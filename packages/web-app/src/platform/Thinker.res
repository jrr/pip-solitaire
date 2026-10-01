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

// Solve right here, on this thread, holding it for as long as it takes. The answer to
// "what if there is no worker" — and to a worker that has stopped answering, which is
// better answered slowly than not at all. It reads the wait off the same clock the far
// side would (`SolverWorker.clock`), so a ten-second patience means ten seconds wherever
// the thinking ends up happening.
let here = (~game: Game.t, ~state: GameState.t, ~patience: option<float>): Solver.autoplayed => {
  let limit = patience->Option.map((ms): Solver.patience => {ms, clock: SolverWorker.clock})
  Solver.autoplay(~game, ~patience=?limit, state)
}

// The question in flight, `Some` exactly while one is being thought about. One at a
// time: a second question replaces the first rather than racing it, which is the same
// rule the board plays a second `autoplay` by.
type asked = {
  ask: int,
  onAnswer: Solver.autoplayed => unit,
  // The same question, answered on this thread — for a worker that stops answering.
  fallback: unit => Solver.autoplayed,
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
let asks = ref(0)

// Let go of the question in flight without answering it. The worker is told so, and
// anything it still says about this ask is ignored by number when it arrives.
let cancel = () =>
  switch live.contents {
  | Some(question) =>
    live := None
    clearTimeout(question.watchdog)
    thread.contents->Option.forEach(worker => worker->tell(Stop))
  | None => ()
  }

// The worker has failed to load, thrown, or gone quiet. Said on the console because
// nothing a player did gets here: it is the build, and the fallback below would
// otherwise hide it behind a page that merely got slow.
let abandon = (worker: worker) => {
  Console.error("[pip] the solver's worker stopped answering; solving on the main thread")
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
    live := None
    clearTimeout(question.watchdog)
    question.onAnswer(question.fallback())
  | None => ()
  }
}

let watch = (worker: worker, question: asked) => {
  clearTimeout(question.watchdog)
  question.watchdog = setTimeout(() => abandon(worker), silence)
}

let heard = (worker: worker, reply: SolverWorker.reply) =>
  switch (live.contents, reply) {
  | (Some(question), Progress({ask})) if ask == question.ask => watch(worker, question)
  | (Some(question), Answer({ask, autoplayed})) if ask == question.ask =>
    live := None
    clearTimeout(question.watchdog)
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
    worker->onError(() => abandon(worker))
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
    cancel()
    held := Some({game, state})
    worker->tell(Moved({state: state}))
  | _ =>
    cancel()
    held := Some({game, state})
    worker->tell(Open({game: {...game, deal: None}, state}))
  }

// The board is now this one: every committed state, from every place a board can
// change. Only to a worker that is already up — one that isn't holds no search to keep,
// and the first question will `Open` it.
let follow = (~game: Game.t, ~state: GameState.t) =>
  thread.contents->Option.forEach(worker => worker->tellBoard(~game, ~state))

// Ask for a line, and say so when there is one.
//
// `onAnswer` is a callback rather than a promise because the fallback answers
// *synchronously*, and the board leans on that: a run is started on the tick after the
// command that asked for it, and a promise would put a microtask in front of the tick
// and reorder the two. With a worker the answer lands whenever it lands, which is the
// whole point.
let think = (
  ~game: Game.t,
  ~state: GameState.t,
  ~patience: option<float>,
  ~onAnswer: Solver.autoplayed => unit,
) =>
  if !supported {
    onAnswer(here(~game, ~state, ~patience))
  } else {
    cancel()
    let worker = worker()
    asks := asks.contents + 1
    let question = {
      ask: asks.contents,
      onAnswer,
      fallback: () => here(~game, ~state, ~patience),
      watchdog: 0,
    }
    // The board first — which may be nothing at all, and is, for a second ask on the
    // same board: that one carries on with the search the first grew, and its effort
    // counts both. Then the question, with the watchdog started, since `tellBoard`
    // lets go of any question it finds in flight.
    worker->tellBoard(~game, ~state)
    live := Some(question)
    watch(worker, question)
    worker->tell(Think({ask: question.ask, ms: patience}))
  }
