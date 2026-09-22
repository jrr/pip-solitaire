// The solver, on a thread of its own: the far end of `Thinker`, and the protocol the
// two speak.
//
// It owns no DOM and imports none — `core`'s search and nothing else — which is what
// makes it loadable as a module worker. Everything it is asked and everything it
// answers is plain data, because a `postMessage` is a structured clone: the request
// carries a board rather than a `Session.t`, and the reply is `Solver.autoplayed`,
// which has no function anywhere in it. `Thinker` owns *why* the `Game.t` arrives
// without its `deal`.
//
// **The thread is the cancel.** Nothing here ever checks for a second message: the
// search is one synchronous call and nothing it does looks at the queue, so a caller
// that wants it stopped terminates the worker. That is `Thinker.cancel`, and it is the
// only stop there is.

// `Date.now`, like the board's own clock (`TableScene.clock`) — the wait it bounds is
// ten seconds and the solver reads it once every 1,024 positions, so nothing here wants
// a monotonic one.
let clock = () => Date.now()

// Everything the search needs about the board it is thinking about. `patience` is the
// wait in milliseconds, resolved into a deadline *here* rather than on the other
// thread: the clock that matters is the one the search is measured on.
type request = {game: Game.t, state: GameState.t, patience: option<float>}

type messageEvent = {data: request}

@val @scope("self")
external listen: (string, messageEvent => unit) => unit = "addEventListener"
@val @scope("self") external answer: Solver.autoplayed => unit = "postMessage"

// **Only where this module *is* the thread.** `Thinker` imports it for `request` and
// `clock`, so it is evaluated on the main thread too — where `self` is the window, and
// a listener registered there would answer window messages by solving on the very
// thread this whole arrangement exists to keep free. `WorkerGlobalScope` is defined in
// a worker and nowhere else, which is the one question that separates the two.
let serving: bool = %raw(`typeof WorkerGlobalScope !== "undefined"`)

if serving {
  listen("message", event => {
    let {game, state, patience} = event.data
    let limit = patience->Option.map((ms): Solver.patience => {ms, clock})
    answer(Solver.autoplay(~game, ~patience=?limit, state))
  })
}
