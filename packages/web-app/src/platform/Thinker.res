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
// **And it thinks between asks, when the board is still.** A board that has sat still
// for `settle` after its last commit — no card held, nothing flying, the tab in view —
// gets a short unasked think, and another after each that comes back still going, until
// the search answers or the board has had `Solver.unasked` of them. Each is an ask of
// its own number, so a Solve pressed meanwhile replaces it like any other question and
// continues the search it grew. The policy and why it is this one are
// `docs/solver-next.md` § Thinking between asks.

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

// The board on the table, as the board last said (`follow`), and what thinking about it
// unasked has cost so far. `spent` is wall-clock time from each unasked think going out
// to its answer, re-root and all, because that is what the worker spent; `settled` is a
// search that has answered about this board — a line, a proof, a full budget — which no
// more thinking changes. `grew` is the positions every think about it added, asked or
// not: 0 for a board the re-root alone answered. `line` is the winning line from here,
// when one is known, which is what `known` offers.
type table = {
  game: Game.t,
  state: GameState.t,
  mutable spent: float,
  mutable settled: bool,
  mutable grew: int,
  mutable line: array<Solver.played>,
}

// The question in flight, `Some` exactly while one is being thought about. One at a
// time: a second question replaces the first rather than racing it, which is the same
// rule the board plays a second `autoplay` by.
type asked = {
  ask: int,
  onAnswer: Solver.autoplayed => unit,
  // The same question, answered on this thread — for a worker that stops answering. An
  // unasked think has none: nobody is waiting on it, and the thread this module exists
  // to keep free is the last place to spend it.
  fallback: option<unit => Solver.autoplayed>,
  // The board an unasked think is charged to, `None` for a question someone asked.
  unasked: option<table>,
  // The board on the table this question is about, asked or not — `None` for a Solve on
  // a board that isn't the one the table last said it is.
  about: option<table>,
  sent: float,
  mutable watchdog: int,
}

// What thinking unasked is doing, for whoever wants to watch it (`reports`): the Debug
// screen's indicator and the debug log. A report is said at a change, not per chunk.
//
//   `Thinking` — an unasked think has gone out about the board on the table, `ms` of
//                its allowance spent before it.
//   `Answered` — the board is settled: the `verdict`, the unasked time it took, the
//                search's positions by then and how many of them this board `grew`.
//                `asked` when a Solve settled it.
//   `Spent`    — the board's whole `Solver.unasked` went by without an answer.
//   `Stopped`  — an unasked think was let go of, and `why`.
//   `Idle`     — a new board, not yet thought about.
type verdict =
  | Winnable
  | Unwinnable
  | OutOfRoom
  | Unreadable

type report =
  | Thinking({ms: float})
  | Answered({verdict: verdict, ms: float, positions: int, grew: int, asked: bool})
  | Spent({ms: float, positions: int, grew: int})
  | Stopped({why: string})
  | Idle

let reports: ref<report => unit> = ref(_ => ())

// The search's positions as the question in flight last said them — at each `Progress`,
// and finally in its `Answer` — for a report on a think that ends without a line.
let grown = ref(0)

// What an answer says about the board. `OutOfPatience` is no verdict and never reaches
// here: it leaves the board unsettled.
let verdictOf = (found: Solver.autoplayed): verdict =>
  switch found {
  | Solver.Played(_) => Winnable
  | Unwinnable => Unwinnable
  | OutOfRoom(_) | OutOfPatience => OutOfRoom
  | UnknownBoard => Unreadable
  }

let positionsIn = (found: Solver.autoplayed, ~otherwise: int): int =>
  switch found {
  | Solver.Played({effort}) => effort.positions
  | _ => otherwise
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
// A worker has been abandoned on this page. Asked questions spawn another and fall back
// if it fails too; nothing unasked is worth a second try at a build that has gone wrong.
let failed = ref(false)

// The next move of a known winning line from the board on the table, or `None` when there
// is none — for the Hint button. Said whenever that changes: a line found, a new board.
// A board already finishable has an empty line and so no hint: the Finish button is that.
let known: ref<option<Reducer.action> => unit> = ref(_ => ())

let offer = (board: table) => known.contents(board.line->Array.get(0)->Option.map(s => s.action))

// An answer about `board`, kept: a line becomes what `known` offers, while the board is
// still the one on the table.
let keep = (board: table, found: Solver.autoplayed) =>
  switch found {
  | Solver.Played({steps}) =>
    board.line = steps
    switch table.contents {
    | Some(current) if current === board => offer(board)
    | _ => ()
    }
  | _ => ()
  }

// A question is over — answered, let go of, or abandoned. An unasked one is charged to
// its board for the time it ran.
let release = (question: asked) => {
  live := None
  Device.ended()
  clearTimeout(question.watchdog)
  question.unasked->Option.forEach(board =>
    board.spent = board.spent +. (SolverWorker.clock() -. question.sent)
  )
}

// Let go of the question in flight without answering it. The worker is told so, and
// anything it still says about this ask is ignored by number when it arrives.
let cancel = (~why: string) =>
  switch live.contents {
  | Some(question) =>
    release(question)
    thread.contents->Option.forEach(worker => worker->tell(Stop))
    if Option.isSome(question.unasked) {
      reports.contents(Stopped({why: why}))
    }
  | None => ()
  }

// The worker has failed to load, thrown, or gone quiet. Said on the console because
// nothing a player did gets here: it is the build, and the fallback below would
// otherwise hide it behind a page that merely got slow.
let abandon = (worker: worker) => {
  Console.error("[pip] the solver's worker stopped answering; solving on the main thread")
  failed := true
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
    question.fallback->Option.forEach(fallback => {
      Device.started()
      let answered = fallback()
      Device.ended()
      question.onAnswer(answered)
    })
  | None => ()
  }
}

let watch = (worker: worker, question: asked) => {
  clearTimeout(question.watchdog)
  question.watchdog = setTimeout(() => abandon(worker), silence)
}

let heard = (worker: worker, reply: SolverWorker.reply) =>
  switch (live.contents, reply) {
  | (Some(question), Progress({ask, positions})) if ask == question.ask =>
    grown := positions
    watch(worker, question)
  | (Some(question), Answer({ask, autoplayed, grew, positions})) if ask == question.ask =>
    grown := positions
    question.about->Option.forEach(board => board.grew = board.grew + grew)
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
    cancel(~why="the board moved")
    held := Some({game, state})
    worker->tell(Moved({state: state}))
  | _ =>
    cancel(~why="another game")
    held := Some({game, state})
    worker->tell(Open({game: {...game, deal: None}, state}))
  }

// --- Thinking unasked ---------------------------------------------------------

// How long the board has to have been still since its last commit before an unasked
// think goes out. A player moving quickly never gets one: the first thing a think does
// after a move is the re-root, which on a big graph is seconds of worker time a `Stop`
// or the next `Moved` waits behind — so only a pause pays for it.
let settle = 1_500

// One unasked think: short, so a Solve or a move is never queued behind much of one.
// The worker reads its inbox at every slice boundary, so this bounds the growing, not
// the re-root at its top.
let chunk = 250.

// Between one unasked think and the next, so the board's stillness is asked again.
let breath = 50

// What the page says about itself. A worker-less runtime (jsdom) has neither question
// worth answering, since nothing unasked runs there.
let hidden: unit => bool = %raw(`() => typeof document !== "undefined" && document.hidden`)
@val external addWindowListener: (string, unit => unit) => unit = "addEventListener"
@val @scope("document")
external addDocumentListener: (string, unit => unit) => unit = "addEventListener"

// Whether it is switched on (Beta features, through `allow`); whether the page
// is being put away (`pagehide`, until a `pageshow` brings it back); and whether the
// board is still — no card held, nothing flying, no line being played — which only the
// board can say, so it installs the answer here (`TableScene`).
let allowed = ref(false)
let parked = ref(false)
let still: ref<unit => bool> = ref(() => true)

let timer: ref<option<int>> = ref(None)

let disarm = () => {
  timer.contents->Option.forEach(clearTimeout)
  timer := None
}

// An unasked think in flight, let go of; a question someone asked is left alone.
let quiet = (~why: string) => {
  disarm()
  switch live.contents {
  | Some({unasked: Some(_)}) => cancel(~why)
  | _ => ()
  }
}

let rec arm = (ms: int) => {
  disarm()
  if supported && allowed.contents {
    timer := Some(setTimeout(wake, ms))
  }
}
and wake = () => {
  timer := None
  switch table.contents {
  | Some(board)
    if allowed.contents &&
    !failed.contents &&
    !parked.contents &&
    !hidden() &&
    Option.isNone(live.contents) &&
    !board.settled &&
    board.spent < Solver.unasked =>
    if still.contents() {
      wonder(board)
    } else {
      arm(settle)
    }
  | _ => ()
  }
}
// One unasked think about the board on the table, and the next one booked when it comes
// back still going. Any other answer is the search having said all it will about this
// board, so it settles it.
and wonder = (board: table) => {
  let worker = worker()
  worker->tellBoard(~game=board.game, ~state=board.state)
  asks := asks.contents + 1
  grown := 0
  reports.contents(Thinking({ms: board.spent}))
  let question = {
    ask: asks.contents,
    onAnswer: found =>
      switch found {
      | Solver.OutOfPatience =>
        if board.spent >= Solver.unasked {
          reports.contents(Spent({ms: board.spent, positions: grown.contents, grew: board.grew}))
        } else {
          arm(breath)
        }
      | _ =>
        board.settled = true
        keep(board, found)
        reports.contents(
          Answered({
            verdict: verdictOf(found),
            ms: board.spent,
            positions: positionsIn(found, ~otherwise=grown.contents),
            grew: board.grew,
            asked: false,
          }),
        )
      },
    fallback: None,
    unasked: Some(board),
    about: Some(board),
    sent: SolverWorker.clock(),
    watchdog: 0,
  }
  live := Some(question)
  watch(worker, question)
  // A think nobody asked for is still a search holding this tab's memory, so it is
  // marked like any other (`Device.recover`).
  Device.started()
  worker->tell(
    Think({
      ask: question.ask,
      ms: Some(Math.min(chunk, Solver.unasked -. board.spent)),
      maxBytes: Solver.capOf(tier.contents),
      unasked: true,
    }),
  )
}

// The player's switch: on books a think for the board as it stands, off lets go of any
// in flight.
let allow = (on: bool) => {
  allowed := on
  on ? arm(settle) : quiet(~why="switched off")
}

// A hidden tab thinks about nothing, and a page being put away stops at once — the
// battery is the player's, and a page in the back-forward cache is not a page they are
// looking at.
if supported {
  addDocumentListener("visibilitychange", () =>
    hidden() ? quiet(~why="the tab is hidden") : arm(settle)
  )
  addWindowListener("pagehide", () => {
    parked := true
    quiet(~why="the page is going away")
  })
  addWindowListener("pageshow", () => {
    parked := false
    arm(settle)
  })
}

// The board is now this one: every committed state, from every place a board can
// change. A worker that is up is told at once; one that isn't holds no search to keep,
// and the first think will `Open` it. Either way the board's stillness starts counting
// again from here, which is the debounce that keeps a quick player from ever paying for
// an unasked re-root.
//
// A move along the known line keeps the rest of it, so the hint is there at once rather
// than a settle and a re-root later. The board is still thought about as any new one is.
// The rest of a line with no shortcut in it has none either, so what is kept needs no
// pass of its own: the line arrived shortened (`Solver.shortened`).
let follow = (~game: Game.t, ~state: GameState.t) => {
  switch table.contents {
  | Some(board) if board.game === game && board.state == state => ()
  | previous =>
    let line = switch previous {
    | Some(board) if board.game === game =>
      switch board.line->Array.get(0) {
      | Some(step) if step.state == state =>
        board.line->Array.slice(~start=1, ~end=Array.length(board.line))
      | _ => []
      }
    | _ => []
    }
    let board = {game, state, spent: 0., settled: false, grew: 0, line}
    table := Some(board)
    reports.contents(Idle)
    offer(board)
  }
  thread.contents->Option.forEach(worker => worker->tellBoard(~game, ~state))
  arm(settle)
}

// The board has left the table — its scene is gone — so there is nothing to think about
// unasked until another one says it is there.
let leave = () => {
  quiet(~why="the board left the table")
  table := None
  reports.contents(Idle)
  known.contents(None)
}

// Ask for a line, and say so when there is one.
//
// `onAnswer` is a callback rather than a promise because the fallback answers
// *synchronously*, and the board leans on that: a run is started on the tick after the
// command that asked for it, and a promise would put a microtask in front of the tick
// and reorder the two. With a worker the answer lands whenever it lands, which is the
// whole point.
//
// An answer that leaves the search still going books more thinking unasked, and any
// other settles the board, the same as an unasked think's would.
let think = (
  ~game: Game.t,
  ~state: GameState.t,
  ~patience: option<float>,
  ~onAnswer: Solver.autoplayed => unit,
) =>
  if !supported {
    Device.started()
    let answered = here(~game, ~state, ~patience)
    Device.ended()
    onAnswer(answered)
  } else {
    cancel(~why="Solve was asked")
    disarm()
    let worker = worker()
    asks := asks.contents + 1
    grown := 0
    let about = switch table.contents {
    | Some(board) if board.game === game && board.state == state => Some(board)
    | _ => None
    }
    let question = {
      ask: asks.contents,
      onAnswer: found => {
        switch (found, about) {
        | (Solver.OutOfPatience, _) => arm(settle)
        | (_, Some(board)) =>
          board.settled = true
          keep(board, found)
          reports.contents(
            Answered({
              verdict: verdictOf(found),
              ms: board.spent,
              positions: positionsIn(found, ~otherwise=grown.contents),
              grew: board.grew,
              asked: true,
            }),
          )
        | (_, None) => ()
        }
        onAnswer(found)
      },
      fallback: Some(() => here(~game, ~state, ~patience)),
      unasked: None,
      about,
      sent: SolverWorker.clock(),
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

// Let go of the question in flight, as the board does when what it asked about has
// moved on — and start the board's stillness counting again, since nothing else will.
let cancel = () => {
  cancel(~why="the board moved")
  arm(settle)
}
