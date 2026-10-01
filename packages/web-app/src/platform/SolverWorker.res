// The solver, on a thread of its own: the far end of `Thinker`, and the protocol the
// two speak.
//
// It owns no DOM and imports none — `core`'s search and nothing else — which is what
// makes it loadable as a module worker. Everything it is asked and everything it
// answers is plain data, because a `postMessage` is a structured clone: the board
// arrives as a `Game.t` and a `GameState.t` rather than a `Session.t`, and the reply is
// `Solver.autoplayed`, which has no function anywhere in it. `Thinker` owns *why* the
// `Game.t` arrives without its `deal`.
//
// **One per tab, held open, and a service rather than a call.** The operations and why
// they are these five are `docs/solver-next.md` § The worker, as a service. What is
// this module's own is how `think` keeps the inbox in reach: the wait is cut into
// slices of `Solver.clockEvery` positions against this thread's clock, and between two
// slices the thread goes back to its event loop, so a `stop` — or any message that
// changes the board — is read at the next slice boundary and the search ends there.
// Nothing here ever needs the thread terminated to stop thinking.

// `Date.now`, like the board's own clock (`TableScene.clock`) — the wait it bounds is
// ten seconds and the solver reads it once a slice, so nothing here wants a monotonic
// one.
let clock = () => Date.now()

// What the far side may say. `ask` numbers a `think` so its `progress` and its `answer`
// can be told from those of a think that was stopped: a stop is read at a slice
// boundary, so a slice already finished can still post about a question its asker has
// let go of, and the asker is the one who knows which question is current.
//
//   `Open`   — the board to think about, replacing any other along with its search.
//   `Moved`  — the same game, a different state: the search behind it is re-rooted
//              there at the next think, keeping what is reachable from it.
//   `Think`  — spend up to `ms` on the open board (`None`: until it answers), resuming
//              whatever search an earlier think left.
//   `Stop`   — end the think in progress at the next slice boundary, answering nothing.
//   `Forget` — let go of the board and everything grown from it.
type request =
  | Open({game: Game.t, state: GameState.t})
  | Moved({state: GameState.t})
  | Think({ask: int, ms: option<float>})
  | Stop
  | Forget

// `Progress` goes out after every slice that leaves the search still going — for a
// spinner that can say something, and as the heartbeat that tells `Thinker` this thread
// is still answering. `Answer` goes out once per think that is not stopped first.
type reply =
  | Progress({ask: int, positions: int, frontier: int, bytes: int})
  | Answer({ask: int, autoplayed: Solver.autoplayed})

type messageEvent = {data: request}

@val @scope("self")
external listen: (string, messageEvent => unit) => unit = "addEventListener"
@val @scope("self") external say: reply => unit = "postMessage"

// Run `next` as a task of its own, behind whatever is already waiting in the inbox. A
// `MessageChannel` rather than `setTimeout(_, 0)`: nested timeouts are clamped to 4ms,
// and a ten-second wait is several hundred slices, so the clamp alone would cost a
// visible share of the wait.
let makeYield: unit => (unit => unit) => unit = %raw(`
  () => {
    const queue = []
    const channel = new MessageChannel()
    channel.port1.onmessage = () => queue.shift()()
    return (next) => {
      queue.push(next)
      channel.port2.postMessage(null)
    }
  }
`)

// The board held open. `search` is grown from it on the first `think` and kept for the
// next, so a second think carries on where the first left off; a `Moved` hands it the
// new board, and a board it can't read drops it.
type held = {game: Game.t, state: GameState.t, mutable search: option<Solver.Search.t>}

let serve = () => {
  let yieldThen = makeYield()
  let held: ref<option<held>> = ref(None)
  // The ask being thought about, `Some` exactly while a think is between slices. A
  // continuation that finds a different number here has been stopped or replaced, and
  // ends without a word.
  let thinking: ref<option<int>> = ref(None)

  let answer = (ask, autoplayed) => {
    thinking := None
    say(Answer({ask, autoplayed}))
  }

  let rec slice = (ask: int, board: held, search: Solver.Search.t, deadline) =>
    if thinking.contents == Some(ask) {
      let found = Solver.Search.think(search, ~nodes=Solver.clockEvery)
      if found == Solver.Search.Paused && !Solver.past(deadline) {
        say(
          Progress({
            ask,
            positions: search.grown,
            frontier: Solver.Search.frontier(search),
            bytes: Solver.Search.bytes(search),
          }),
        )
        yieldThen(() => slice(ask, board, search, deadline))
      } else {
        conclude(ask, board, search, found)
      }
    }
  and conclude = (ask, board, search, found) =>
    answer(
      ask,
      Solver.autoplayedOf(
        ~game=board.game,
        board.state,
        ~line=Solver.Search.line(search),
        ~effort=Solver.effortOf(search, found),
      ),
    )

  let think = (ask: int, ms: option<float>) => {
    thinking := Some(ask)
    switch held.contents {
    // Asked about no board at all: the same refusal as a board the solver can't read,
    // because there is equally nothing here to think about.
    | None => answer(ask, Solver.UnknownBoard)
    | Some(board) =>
      let search = switch board.search {
      | Some(search) => Some(search)
      | None =>
        Position.ofGameState(~game=board.game, board.state)->Option.map(position => {
          let search = Solver.Search.make(position)
          board.search = Some(search)
          search
        })
      }
      switch search {
      | None => answer(ask, Solver.UnknownBoard)
      | Some(search) =>
        // The deadline is fixed as the ask is read, and checked before the first slice
        // as before every other — the same order `Solver.solveOn` keeps, so a wait of
        // nothing is told so without being charged a slice.
        let deadline = Solver.deadlineFor(ms->Option.map((ms): Solver.patience => {ms, clock}))
        let found = Solver.Search.answer(search)
        if found == Solver.Search.Paused && !Solver.past(deadline) {
          slice(ask, board, search, deadline)
        } else {
          conclude(ask, board, search, found)
        }
      }
    }
  }

  listen("message", event =>
    switch event.data {
    | Open({game, state}) =>
      thinking := None
      held := Some({game, state, search: None})
    | Moved({state}) =>
      thinking := None
      held :=
        held.contents->Option.map(board => {
          let search = switch (board.search, Position.ofGameState(~game=board.game, state)) {
          | (Some(search), Some(position)) =>
            Solver.Search.moved(search, position)
            Some(search)
          | _ => None
          }
          {...board, state, search}
        })
    | Think({ask, ms}) => think(ask, ms)
    | Stop => thinking := None
    | Forget =>
      thinking := None
      held := None
    }
  )
}

// **Only where this module *is* the thread.** `Thinker` imports it for its types and
// `clock`, so it is evaluated on the main thread too — where `self` is the window, and
// a listener registered there would answer window messages by solving on the very
// thread this whole arrangement exists to keep free. `WorkerGlobalScope` is defined in
// a worker and nowhere else, which is the one question that separates the two.
let serving: bool = %raw(`typeof WorkerGlobalScope !== "undefined"`)

if serving {
  serve()
}
