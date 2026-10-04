// Where the solver thinks: a worker thread, so the board keeps painting while it does.
//
// The search behind `autoplay` is a bounded ten seconds (`Solver.interactive`) and
// routinely spends seconds of it. Run on the thread that draws, that is not a pause —
// it is a page that has stopped answering: no frame, no scroll, no pointer, and not
// even the "Thinking…" the menu just wrote, because a render that never reaches a paint
// is a render nobody saw. So the thinking goes elsewhere and the only thing this thread
// does meanwhile is what it always does.
//
// What crosses the boundary is plain data both ways, because a `postMessage` is a
// structured clone (`SolverWorker` is the other end, and owns the protocol). Two things
// follow, and both are load-bearing:
//
//   - **The `Game.t` goes over without its `deal`.** That field is the one function on
//     the type (`Game.res`), and a function cannot be cloned — a board sent whole
//     raises a `DataCloneError` on the way out. Nothing the search touches reads it:
//     `deal` lays out *another* board of this game, where the solver only ever asks
//     about this one. Dropping it is therefore not a lossy send, and sending the id
//     instead would be, since a scenario's board is not `Game.byId`'s to rebuild.
//   - **The answer is `Solver.autoplayed` and stops there.** A `Session.t` could not
//     make the trip, so the worker never builds one; `Session.adoptAutoplay` does that
//     back here, out of what came back.
//
// **One worker per tab, and cancelling is a message.** The worker is spawned on the
// first question and kept: a `stop` is read at its next slice boundary, so the thread
// outlives every question it is asked. Terminating is kept for a worker that has
// stopped answering, which is a build gone wrong rather than anything a player did.
//
// **The search outlives the question too.** The worker holds one board and the search
// grown from it, and this side keeps a copy of which board that is (`held`), so a
// question tells the worker only what has changed since: nothing, when it is asked
// again about the same board — which is how a second ask *continues* the first rather
// than starting over — a `Moved` for the same game in another state, and an `Open` only
// for another game. The board says it has moved (`follow`) on every committed state, so
// the worker hears of a move as it happens; what that re-root costs is paid at the top
// of the next think, on the worker (`docs/solver-next.md` § Re-rooting in the browser).
//
// **It thinks only when asked** — a Solve, an autoplay, a Hint. Nothing is thought about
// between asks: why not, and what it would take, is `docs/solver-next.md` § Thinking
// between asks.

// Whether there is another thread to think on. Workers are baseline everywhere the app
// runs, so what this really asks about is jsdom, where the unit suite has none and wants
// its answer on the spot anyway (`here`, below).
let supported: bool = %raw(`typeof Worker === "function"`)

type worker
type messageEvent = {data: SolverWorker.reply}

// **One raw expression on purpose.** Vite finds a worker to bundle by matching
// `new Worker(new URL(<literal>, import.meta.url), …)` in the emitted module. Split the
// URL out into a binding of its own and the match fails: the file is then copied as a
// plain asset, `core`'s modules never travel with it, and the worker dies on its first
// import — in the built site only, where no unit test is looking.
let spawn: unit => worker = %raw(`
  () => new Worker(new URL("./SolverWorker.res.mjs", import.meta.url), { type: "module" })
`)

@send external terminate: worker => unit = "terminate"
@send external tell: (worker, SolverWorker.request) => unit = "postMessage"
@set external onMessage: (worker, messageEvent => unit) => unit = "onmessage"
// Takes no argument on purpose: what went wrong is the build's problem, not this
// module's, and the fallback below is the same whatever the event would have said.
@set external onError: (worker, unit => unit) => unit = "onerror"

@val external setTimeout: (unit => unit, int) => int = "setTimeout"
@val external clearTimeout: int => unit = "clearTimeout"

// How long a thinking worker may go without a word before it counts as gone. It posts
// after every slice, and a slice is a third of a second on the heaviest board
// (`docs/solver.md`); the first question also waits on the worker's own module loading.
// So this is not a tight bound — it is far enough past any slow device that only a
// thread that has really stopped answering trips it, because what tripping it costs is
// the whole wait spent on this thread instead.
let silence = 10_000

// How much a search may hold here: the tier `Device` settled on at load, or the one the
// memory setting chose since. Read at each question, so a change lands on the next.
let tier: ref<Solver.tier> = ref(Solver.Medium)

// Solve right here, on this thread, holding it for as long as it takes. The answer to
// "what if there is no worker" — and to a worker that has stopped answering, which is
// better answered slowly than not at all. It reads the wait off the same clock the far
// side would (`SolverWorker.clock`), so a ten-second patience means ten seconds wherever
// the thinking ends up happening.
let here = (~game: Game.t, ~state: GameState.t, ~patience: option<float>): Solver.autoplayed => {
  let limit = patience->Option.map((ms): Solver.patience => {ms, clock: SolverWorker.clock})
  Solver.autoplay(~game, ~patience=?limit, ~tier=tier.contents, state)
}

// The board on the table, as the board last said (`follow`), and the winning line from
// it when an answer about it has found one — which is what `known` offers. `None` is no
// line known; `Some([])` is a board already finishable, where there was nothing to find.
type table = {
  game: Game.t,
  state: GameState.t,
  mutable line: option<array<Solver.played>>,
}

// The question in flight, `Some` exactly while one is being thought about. One at a
// time: a second question replaces the first rather than racing it, which is the same
// rule the board plays a second `autoplay` by.
type asked = {
  ask: int,
  onAnswer: Solver.autoplayed => unit,
  // Said instead of `onAnswer` when the question is let go of — the board moved, another
  // question replaced it, the board left the table — so a caller showing that it is
  // waiting can stop.
  onLetGo: unit => unit,
  // The same question, answered on this thread — for a worker that stops answering.
  fallback: unit => Solver.autoplayed,
  // The board on the table this question is about — `None` for a question about a board
  // that isn't the one the table last said it is.
  about: option<table>,
  mutable watchdog: int,
}

// The board the worker holds, as this side last told it. `game` is the caller's own
// value rather than the copy sent without its `deal`, because *which* game is asked by
// identity: a session keeps its `Game.t` for as long as it is played, and a new deal is
// a new one (`Game.dealt`), so a move or an undo is a `Moved` and a new deal, another
// game or a scenario's board an `Open`.
type held = {game: Game.t, state: GameState.t}

let thread: ref<option<worker>> = ref(None)
let live: ref<option<asked>> = ref(None)
let held: ref<option<held>> = ref(None)
let table: ref<option<table>> = ref(None)
let asks = ref(0)

// The line known from this board, if the table is on it and one is: what a Hint shows
// without asking again.
let known = (~game: Game.t, ~state: GameState.t): option<array<Solver.played>> =>
  switch table.contents {
  | Some(board) if board.game === game && board.state == state => board.line
  | _ => None
  }

// An answer about `board`, kept: a line is what `known` offers from it from now on.
let keep = (about: option<table>, found: Solver.autoplayed) =>
  switch (about, found) {
  | (Some(board), Solver.Played({steps})) => board.line = Some(steps)
  | _ => ()
  }

// A question is over — answered, let go of, or abandoned.
let release = (question: asked) => {
  live := None
  Device.ended()
  clearTimeout(question.watchdog)
}

// Let go of the question in flight without answering it. The worker is told so, and
// anything it still says about this ask is ignored by number when it arrives.
let letGo = () =>
  switch live.contents {
  | Some(question) =>
    release(question)
    thread.contents->Option.forEach(worker => worker->tell(Stop))
    question.onLetGo()
  | None => ()
  }

// The worker has failed to load, thrown, or gone quiet. Said on the console because
// nothing a player did gets here: it is the build, and the fallback below would
// otherwise hide it behind a page that merely got slow.
let abandon = (worker: worker, ~why: string) => {
  Console.error(`[pip] the solver's worker ${why}; solving on the main thread`)
  worker->onMessage(_ => ())
  worker->onError(_ => ())
  terminate(worker)
  switch thread.contents {
  | Some(current) if current === worker =>
    thread := None
    held := None
  | _ => ()
  }
  switch live.contents {
  | Some(question) =>
    release(question)
    Device.started()
    let answered = question.fallback()
    Device.ended()
    question.onAnswer(answered)
  | None => ()
  }
}

let watch = (worker: worker, question: asked) => {
  clearTimeout(question.watchdog)
  question.watchdog = setTimeout(
    () => abandon(worker, ~why=`said nothing for ${Int.toString(silence / 1000)} s`),
    silence,
  )
}

let heard = (worker: worker, reply: SolverWorker.reply) =>
  switch (live.contents, reply) {
  | (Some(question), Progress({ask})) if ask == question.ask => watch(worker, question)
  | (Some(question), Answer({ask, autoplayed})) if ask == question.ask =>
    release(question)
    question.onAnswer(autoplayed)
  // About a question already let go of: an answer about a board that has moved on.
  | _ => ()
  }

let worker = (): worker =>
  switch thread.contents {
  | Some(worker) => worker
  | None =>
    let worker = spawn()
    worker->onMessage(event => heard(worker, event.data))
    worker->onError(() => abandon(worker, ~why="raised an error"))
    thread := Some(worker)
    worker
  }

// Bring the worker's board to this one, saying as little as will do it. A different
// board stops whatever it was thinking about, so the question in flight is let go of
// here as well — or its watchdog would wait on an answer the worker will never send.
let tellBoard = (worker: worker, ~game: Game.t, ~state: GameState.t) =>
  switch held.contents {
  | Some(board) if board.game === game && board.state == state => ()
  | Some(board) if board.game === game =>
    letGo()
    held := Some({game, state})
    worker->tell(Moved({state: state}))
  | _ =>
    letGo()
    held := Some({game, state})
    worker->tell(Open({game: {...game, deal: None}, state}))
  }

// The board is now this one: every committed state, from every place a board can
// change. A worker that is up is told at once; one that isn't holds no search to keep,
// and the first question will `Open` it.
//
// A move along the known line keeps the rest of it, so a Hint after it is there at once
// rather than a re-root later. The rest of a line with no shortcut in it has none either,
// so what is kept needs no pass of its own: the line arrived shortened
// (`Solver.shortened`).
let follow = (~game: Game.t, ~state: GameState.t) => {
  switch table.contents {
  | Some(board) if board.game === game && board.state == state => ()
  | previous =>
    let line = switch previous {
    | Some({game: was, line: Some(line)}) if was === game =>
      switch line->Array.get(0) {
      | Some(step) if step.state == state =>
        Some(line->Array.slice(~start=1, ~end=Array.length(line)))
      | _ => None
      }
    | _ => None
    }
    table := Some({game, state, line})
  }
  thread.contents->Option.forEach(worker => worker->tellBoard(~game, ~state))
}

// The board has left the table — its scene is gone — so nothing asked about it is
// wanted any more.
let leave = () => {
  letGo()
  table := None
}

// Ask for a line, and say so when there is one.
//
// `onAnswer` is a callback rather than a promise because the fallback answers
// *synchronously*, and the board leans on that: a run is started on the tick after the
// command that asked for it, and a promise would put a microtask in front of the tick
// and reorder the two. With a worker the answer lands whenever it lands, which is the
// whole point. A question let go of before it answers says `onLetGo` instead.
let think = (
  ~game: Game.t,
  ~state: GameState.t,
  ~patience: option<float>,
  ~onAnswer: Solver.autoplayed => unit,
  ~onLetGo: unit => unit=() => (),
) => {
  let about = switch table.contents {
  | Some(board) if board.game === game && board.state == state => Some(board)
  | _ => None
  }
  let answered = found => {
    keep(about, found)
    onAnswer(found)
  }
  if !supported {
    Device.started()
    let found = here(~game, ~state, ~patience)
    Device.ended()
    answered(found)
  } else {
    letGo()
    let worker = worker()
    asks := asks.contents + 1
    let question = {
      ask: asks.contents,
      onAnswer: answered,
      onLetGo,
      fallback: () => here(~game, ~state, ~patience),
      about,
      watchdog: 0,
    }
    // The board first — which may be nothing at all, and is, for a second ask on the
    // same board: that one carries on with the search the first grew, and its effort
    // counts both. Then the question, with the watchdog started, since `tellBoard`
    // lets go of any question it finds in flight.
    worker->tellBoard(~game, ~state)
    live := Some(question)
    watch(worker, question)
    // Marked as running until it answers or is let go of: a load that finds the mark
    // still set is a tab this search took down (`Device.recover`).
    Device.started()
    worker->tell(
      Think({
        ask: question.ask,
        ms: patience,
        maxBytes: Solver.capOf(tier.contents),
        unasked: false,
      }),
    )
  }
}

// Let go of the question in flight, as the board does when what it asked about has
// moved on.
let cancel = letGo
