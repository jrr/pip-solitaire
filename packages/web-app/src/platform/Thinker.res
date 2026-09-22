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
// structured clone (`SolverWorker` is the other end). Two things follow, and both are
// load-bearing:
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
// **Cancelling means terminating.** The search is one synchronous call on the far side
// and never looks at its message queue, so there is no polite way to ask it to stop.
// That is fine, and it is more than the old inline search could offer: a board that has
// moved on — a card played, a new deal, the stop gesture — kills the thread outright.

// Whether there is another thread to think on. Workers are baseline everywhere the app
// runs, so what this really asks about is jsdom, where the unit suite has none and wants
// its answer on the spot anyway (`here`, below).
let supported: bool = %raw(`typeof Worker === "function"`)

type worker
type messageEvent = {data: Solver.autoplayed}

// **One raw expression on purpose.** Vite finds a worker to bundle by matching
// `new Worker(new URL(<literal>, import.meta.url), …)` in the emitted module. Split the
// URL out into a binding of its own and the match fails: the file is then copied as a
// plain asset, `core`'s modules never travel with it, and the worker dies on its first
// import — in the built site only, where no unit test is looking.
let spawn: unit => worker = %raw(`
  () => new Worker(new URL("./SolverWorker.res.mjs", import.meta.url), { type: "module" })
`)

@send external terminate: worker => unit = "terminate"
@send external ask: (worker, SolverWorker.request) => unit = "postMessage"
@set external onMessage: (worker, messageEvent => unit) => unit = "onmessage"
// Takes no argument on purpose: what went wrong is the build's problem, not this
// module's, and the fallback below is the same whatever the event would have said.
@set external onError: (worker, unit => unit) => unit = "onerror"

// The thread in flight, `Some` exactly while a search is running on it. One at a time:
// a second question replaces the first rather than racing it, which is the same rule
// the board plays a second `autoplay` by.
let live: ref<option<worker>> = ref(None)

let cancel = () =>
  switch live.contents {
  | Some(worker) =>
    live := None
    // Dropped before the terminate, not after: an answer already queued from a search
    // that finished in the gap must not reach a caller that has stopped caring.
    worker->onMessage(_ => ())
    worker->onError(_ => ())
    terminate(worker)
  | None => ()
  }

// Solve right here, on this thread, holding it for as long as it takes. The answer to
// "what if there is no worker" — and to a worker that failed to load, which is a build
// gone wrong rather than anything a player did, and better answered slowly than not at
// all. It reads the wait off the same clock the far side would (`SolverWorker.clock`),
// so a ten-second patience means ten seconds wherever the thinking ends up happening.
let here = (~game: Game.t, ~state: GameState.t, ~patience: option<float>): Solver.autoplayed => {
  let limit = patience->Option.map((ms): Solver.patience => {ms, clock: SolverWorker.clock})
  Solver.autoplay(~game, ~patience=?limit, state)
}

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
    let worker = spawn()
    live := Some(worker)
    let finish = (answer: Solver.autoplayed) =>
      // Only from the thread still on the books: a late message from one already
      // cancelled is an answer about a board that has moved on.
      switch live.contents {
      | Some(current) if current === worker =>
        cancel()
        onAnswer(answer)
      | _ => ()
      }
    worker->onMessage(event => finish(event.data))
    worker->onError(() => finish(here(~game, ~state, ~patience)))
    worker->ask({game: {...game, deal: None}, state, patience})
  }
