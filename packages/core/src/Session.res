// A *session*: everything a front end has to know about a game in progress, and
// the one place a `Command.t` is run against one (#298).
//
// `Reducer.reduce` was already the single way a card moves, and both front ends went
// through it. The layer wrapped *around* it wasn't: which game is in play, the history
// to undo over, the tallies beside it, the post-move auto-collect, and "run this
// command" existed three times — once in `Repl.res` and twice more inside
// `TableScene.res`, which repeated the settle-record-check-win sequence at every place
// a card could move (a drop, a double-tap send-home, a typed command).
//
// The drift that shape produced was the point of the issue: `Stats` (#289) and
// `Timing` (#302) both landed in `core`, both ride in the `SaveState` envelope, and
// both were wired into the web app only — because that is where the wiring lived. A
// session that owns them means a front end can't *not* have them.
//
// What's here is the board half of the command surface: the verbs that need a dealt
// game to mean anything. The rest — `help`, `games`, `clear`, `quit`, `set`, and
// `deal` itself — stays with each front end, because those genuinely differ: `help` in
// a terminal lists a terminal's commands, `deal` in the web app tears down a DOM board
// and builds another, and neither is a question about the cards on the table. That
// seam isn't invented here; it's the one both front ends already drew.
//
// Nothing in this module does I/O. The two impure things a session needs — the clock
// a win is stamped with, and the seed a fresh deal invents — are passed in, the way
// `Repl` has always passed `~newSeed`.

open Card

// The whole of a game in progress.
//
// `seed` is the deal number this board is showing, kept beside the game because the
// two can disagree: a posed position (`Scenario`) sits on a game whose own seed didn't
// produce it, so it reports the deal it has been *proved* to descend from — usually
// none.
//
// `options` is the house rules in force. They live here rather than beside the session
// because every one of them is consulted *while playing a card* — auto-collect after a
// move, column reorder before one — and a session that had to be handed them at each
// call is a session that can be asked to play the same board two different ways. Both
// front ends keep options that outlive any one board (a terminal's flags survive
// `deal`, the web app's switches survive a New Game), so opening a new session carries
// the old one's options forward; see `deal` and `redeal`.
type t = {
  game: Game.t,
  seed: option<int>,
  history: History.t<GameState.t>,
  stats: Stats.t,
  timing: Timing.t,
  options: Options.t,
}

// One move of a line the solver played, and the session it left behind.
//
// Carrying the whole *session* per step — not just the state — is what lets one
// implementation serve both front ends. A terminal plays a line in a single call and
// wants the last one; the web app plays it a move at a time with a card flight between
// each, adopting `session` as each flight lands, and stops adopting when the player
// interrupts. An interrupted run is then just an earlier session: a real position with
// a real history and a real tally behind it, with nothing to unwind.
type played = {action: Reducer.action, moved: array<card>, session: t}

// What a command did to the board — enough for a caller to show it, and no more.
//
// The split is by *how a front end has to react*, which is the only thing a caller
// needs a variant for: a scrolling driver reprints the board for every case that put
// different cards on the table, while a board with cards on it flies the named cards
// for a `Settled`, staggers a `Swept`, re-derives a `Restored` without animating (a step
// through history isn't a move, and easing cards along a path they never took would
// misreport what happened), and rebuilds for a `Dealt`.
//
// The moved cards are named rather than left to be worked out from the two states,
// because the one front end that needs them can't recover them: `moved` is what
// *travelled*, and a board settled by auto-collect has cards resting somewhere new
// that the command never mentioned.
//
// The `action` rides along for the same sort of reason. A caller that narrates a move
// (the web app's debug console, #213) needs to say *which* move, in `Render.action`'s
// words — and once the interpreting happens in here, a command's action is something it
// never saw. Handing it back is what lets one narrator serve a drop, a typed command and
// a solver's step alike.
type change =
  | Unchanged // a verb with nothing to do — "nothing to undo", a lawful no-op
  | Shown // `print`: nothing moved, but the caller asked to see the board
  | Blocked({reason: string}) // a house rule refused it before the reducer saw it
  | Rejected({action: Reducer.action, error: Reducer.moveError}) // the reducer refused it
  // An accepted move: `moved` is what the action named, `collected` whatever safe
  // auto-collect swept up behind it (#125). Kept apart because a caller that narrates
  // says two different things about them — the move is what you did, the collection is
  // what the board did back — while a caller that animates flies them as one gesture.
  | Settled({action: Reducer.action, moved: array<card>, collected: array<card>})
  | Swept({moved: array<card>}) // the end-game finish sequence (#132)
  | Restored // undo/redo: a position the board already held
  | Dealt // a different board entirely (`redeal`)
  // A solver line (#291). `reached` is the session the moment the player reached for
  // the solver — the tally already counting the reach, no move played yet — and it's
  // what a caller that plays the line itself starts from. A caller that just wants the
  // result takes the session returned beside this outcome and ignores all three.
  | Played({reached: t, trail: array<played>, swept: array<card>})

// What a command did, and what there is to say about it *beyond* the board.
//
// The board itself is deliberately not in here. A terminal prints it, a web app
// already has it on screen, and a reply that carried it would be a document one of
// them has to throw away after every move. What `reply` carries is the part neither
// can derive: why a move bounced, that there was nothing to undo, how long the solver
// thought. A caller draws the board for itself, from the `change` it gets back.
//
// A document (`Render.line`) rather than text, for the reason `Render` splits the two
// (#282): a terminal paints the red suits in ANSI and a panel paints them in CSS, and
// neither should be reading the other's alphabet out of a string.
type outcome = {change: change, reply: array<Render.line>}

// The live snapshot — the present of the history. Every read goes through this rather
// than a stored field, so the history stays the single source of truth for "where
// every card rests right now".
let present = (s: t): GameState.t => History.present(s.history)

let hasWon = (s: t): bool => GameState.hasWon(s.game, present(s))

let canUndo = (s: t): bool => History.canUndo(s.history)
let canRedo = (s: t): bool => History.canRedo(s.history)

// Can the board be drained to a win by foundation moves alone (#132)? What the `finish`
// verb and the button that offers it both ask.
let canFinish = (s: t): bool => Reducer.canFinish(~game=s.game, present(s))

// The board as a document — `core`'s renderer over the present snapshot, reporting the
// deal this board descends from. Ink but no colour: the caller's alphabet decides that.
let boardLines = (s: t): array<Render.line> =>
  Render.stateLines(~game=s.game, ~deal=?s.seed, present(s))

// Adopt the house rules a front end holds. Options outlive any one board in both
// drivers — a terminal's `set` survives `deal`, the web app's switches survive a New
// Game — so this is how the flags a driver carries reach the session that consults
// them.
let withOptions = (s: t, options: Options.t): t => {...s, options}

// Stamp the clock against the board as it now stands (#302). One rule, applied after
// every change: a won board records when it was won, and a board that isn't won has no
// won-at. `Timing.won` keeps the first stamp, so a resumed victory reports the game's
// own length rather than how long ago it was played; stepping back out of a win clears
// it, and winning again stamps afresh — the same stance the tally takes, where undoing
// never gives a move back.
let stamp = (~clock: unit => float, s: t): t => {
  ...s,
  timing: hasWon(s) ? Timing.won(s.timing, ~at=clock()) : Timing.unwon(s.timing),
}

// Open a session on a state. A deal starts a clean history — there's nothing before the
// opening position to undo back to (#85) — a zero tally, and a running clock.
let open_ = (
  ~clock: unit => float,
  ~options: Options.t=Options.default,
  ~seed: option<int>,
  game: Game.t,
  state: GameState.t,
): t => {
  game,
  seed,
  history: History.make(state),
  stats: Stats.zero,
  timing: Timing.dealt(~at=clock()),
  options,
}

// Restore a session from what a save carried (#177/#289/#302). The envelope holds the
// history, the tally and the clock; the game, the deal number and the house rules come
// from whoever knew which board this save was of.
//
// `saved.gameId` is deliberately not consulted (#354). It's how a *reader* works out
// which board a loose blob is of — a `#g=` link's, before there's a session to restore
// into — and by the time a save reaches here that question is answered: the caller is
// handing over the game it resolved. Reading it again here could only disagree with the
// board being opened.
let restore = (~seed: option<int>, ~options: Options.t, game: Game.t, saved: SaveState.t): t => {
  game,
  seed,
  history: saved.history,
  stats: saved.stats,
  timing: saved.timing,
  options,
}

// …and what to write back out. `seed` and `options` are deliberately not in the
// envelope: the first is how the save was found in the first place, and the second is
// the driver's, not the board's.
//
// The game *is* in it, as its id (#354). It used to be left out on the same "that's how
// the save was found" reasoning, which held for `localStorage` — the key names the game
// — and quietly didn't for the other thing this envelope is: a share link, which is
// found by nothing at all and so arrived at the far end naming no board. This is the one
// place a save is written from a session, and the session knows which game it is of, so
// the answer is written down here rather than inferred from whatever scene the blob
// happens to land on.
let save = (s: t): SaveState.t => {
  history: s.history,
  stats: s.stats,
  timing: s.timing,
  gameId: Some(s.game.id),
}

// Settle an accepted move: run safe auto-collect (#125) when the option is on,
// returning the settled state and the cards it sent home. `autoCollect: false` (or a
// finishable board) leaves the state exactly as the reducer returned it — the exact
// no-op path. Applied *before* the win check so a collection that plays the final cards
// still trips the win line (#121).
//
// Once the board is finishable (#132) safe auto-collect steps aside — the `finish` verb
// owns the end-game sweep, so auto-collect doesn't race it to the win and rob the
// player of the trigger.
//
// This settles a *state*, not a session: the caller records the settled result into the
// session's history as a single undoable step (#85), so a move and the collection it
// triggered undo together. The swept cards come back because the one caller that
// animates needs them — a typed or dragged move flies the cards it displaced *and*
// whatever the collection swept up behind them, so the two read as one gesture rather
// than a move and a jump.
let settle = (~game: Game.t, ~options: Options.t, state: GameState.t): (GameState.t, array<card>) =>
  if options.autoCollect && !Reducer.canFinish(~game, state) {
    Reducer.autoCollect(~game, state)
  } else {
    (state, [])
  }

// Adopt a settled state as the session's new present, recording it as one undoable
// step and counting it as one move. Only accepted transitions ever reach here, so a
// rejected move leaves the history untouched (#85). A lawful *no-op* — dropping a card
// back where it already rests, or a `MoveColumn` with `from == to` — reduces to `Ok`
// but changes nothing, so it records no step and counts no move either (#215): there's
// nothing to undo back to, and nothing was played.
//
// One recorded step is one move made (#289). Counting here rather than at each verb
// means every way to play a move agrees by construction — a drop, a typed command, a
// solver's step, and the finish sweep, which records itself as a single step.
let commit = (~clock: unit => float, s: t, next: GameState.t): t =>
  GameState.equal(next, present(s))
    ? s
    : stamp(~clock, {...s, history: History.record(s.history, next), stats: Stats.move(s.stats)})

// --- Playing a card ------------------------------------------------------------
// The one path a card moves along, whatever asked. A typed `move 8H 5`, a pointer
// drop, a double-tapped send-home and a solver's step all arrive here as a
// `Reducer.action`, and all get the same treatment: the house-rule gate, the reducer's
// verdict, the settle, the undoable step, the tally and the clock.

// The house rule that has to be answered before the reducer, not by it: with column
// reordering off, nothing is dispatched at all, so the command is an exact no-op that
// only reports the rule is disabled — no `MoveColumn` reaches the reducer, no history
// step recorded. Said here so both front ends say it the same way.
let columnReorderOff = "Column reordering is off for this game."

// Dispatch one action against a session. The reducer is the sole judge of legality;
// what's left here is the gate, the settling, and the bookkeeping.
//
// A column reorder skips the settling: it's organizational rather than played, so
// nothing has been put down anywhere new for auto-collect to consider and the settled
// state is the reducer's own.
let dispatch = (~clock: unit => float, s: t, action: Reducer.action): (t, change) =>
  switch action {
  | Reducer.MoveColumn(_) if !s.options.allowColumnReorder => (
      s,
      Blocked({reason: columnReorderOff}),
    )
  | _ =>
    switch Reducer.reduce(~game=s.game, present(s), action) {
    | Ok(next) =>
      let (settled, collected) = switch action {
      | Reducer.MoveColumn(_) => (next, [])
      | _ => settle(~game=s.game, ~options=s.options, next)
      }
      let moved = switch action {
      | Reducer.Move({card}) => [card]
      | Reducer.MoveRun({cards}) => cards
      // A reorder moves whole columns rather than named cards, so there's nothing to
      // fly: a caller re-lays the board instead.
      | Reducer.MoveColumn(_) => []
      }
      (commit(~clock, s, settled), Settled({action, moved, collected}))
    | Error(error) => (s, Rejected({action, error}))
    }
  }

// Dispatch an action and say what there is to say about it. The prose is built here,
// beside the action, because that's the only place it can be: `Command.describeRejection`
// names the card that bounced, and a `change` alone doesn't carry one.
//
// Nothing is said about an *accepted* move. The board itself is the answer, and the
// caller is the one drawing it — a sentence here would only repeat what the cards
// already show.
let dispatched = (~clock: unit => float, s: t, action: Reducer.action): (t, outcome) => {
  let (s', change) = dispatch(~clock, s, action)
  (
    s',
    {
      change,
      reply: switch change {
      | Blocked({reason}) => Render.text(reason)
      | Rejected({error}) => Render.text(Command.describeRejection(error, ~action))
      | _ => []
      },
    },
  )
}

// Send the named card to the foundation that will take it, if any (#122). The target is
// found by `Reducer.foundationTarget` — the shared legality behind the drop itself — and
// the send-home routes through `dispatch`, so it's the ordinary `Move` onto that pile: a
// card that completes the board still wins exactly as a dragged one would. A card no
// foundation is ready for is reported rather than moved.
//
// Note this is the *destination* test, not a movability test: a card that's buried is
// dispatched and refused by the reducer, so it's told it's buried rather than told no
// foundation wants it — which is very often untrue of a buried card. (The web app's
// send-home reads `validMoves` instead and so answers the buried case with the weaker
// sentence; that's for it to adopt when it comes through here.)
let home = (~clock: unit => float, s: t, card: card): (t, outcome) =>
  switch Reducer.foundationTarget(~game=s.game, present(s), card) {
  | Some(i) => dispatched(~clock, s, Reducer.Move({card, to: Reducer.ToPile(i)}))
  | None => (
      s,
      {
        change: Unchanged,
        reply: Render.text(`No foundation is ready for ${CardText.format(card)}.`),
      },
    )
  }

// The finishing sweep (#132), without the reply that wraps it: the settled session and
// the cards it sent home. The whole sweep is one undoable step (#85), so undo after a
// `finish` steps back to the position the sweep started from.
//
// Split out because `autoplay` hands over to this same sweep and wants to *say* what it
// did, which needs the cards — and running the sequence twice to find them out would be
// a second answer to a question already answered.
let sweepHome = (~clock: unit => float, s: t): (t, array<card>) => {
  let (settled, moved) = Reducer.finishSequence(~game=s.game, present(s))
  (commit(~clock, s, settled), moved)
}

let notFinishable = "Not finishable yet — some cards still need a tableau move first."

// Play the finishing sweep when the board can be drained to a win by foundation moves
// alone (`Reducer.canFinish`); otherwise report it's not yet finishable. The sweep is
// the very drain `canFinish` proves, so a `finish` that's offered always completes —
// and, like a hand-played final card, trips the win (#121). It never blocks manual
// play: `home`/`move` still work card-by-card, this is only the shortcut.
let finish = (~clock: unit => float, s: t): (t, outcome) =>
  if canFinish(s) {
    let (s', moved) = sweepHome(~clock, s)
    (s', {change: Swept({moved: moved}), reply: []})
  } else {
    (s, {change: Unchanged, reply: Render.text(notFinishable)})
  }

// Hand the board to the solver (#291): play the line `core` finds from here, then the
// finishing sweep it deliberately stops short of, so `autoplay` on a solvable deal ends
// on a won board rather than on a board with the Finish button lit.
//
// Every planned move is committed as its own undoable step, exactly as a typed one
// would be: a game the solver played is as long as it looks, and undo walks back
// through it a move at a time rather than teleporting past the whole thing. The moves
// themselves come from `Solver.autoplay`, which settles each one the way the plan
// assumes — so this adopts the states rather than re-dispatching the actions, and a
// session with `autocollect` off still plays the line the search actually found.
//
// The reach is counted once, not once per move: the moves the solver plays are counted
// as moves by `commit`, like any other. Counted *before* the first step is recorded, so
// the very first save this produces already carries "this game was autoplayed" — and
// counted even if a caller stops the run a move later, because it was still reached for.
let autoplay = (~clock: unit => float, s: t): (t, outcome) => {
  // The clock is this session's, not the solver's (see `Solver.effort`): what it times
  // is the whole call — the search, plus playing the line it found through the reducer.
  // The second part is fifty reductions against a search that generated tens of
  // thousands of positions, so what the number describes is the thinking.
  let started = clock()
  switch Solver.autoplay(~game=s.game, present(s)) {
  | Solver.NotFreeCell => (s, {change: Unchanged, reply: Render.text(Command.autoplayNotFreeCell)})
  | Solver.NoLine => (s, {change: Unchanged, reply: Render.text(Command.autoplayNoLine)})
  | Solver.Played({steps, effort}) =>
    let ms = clock() -. started
    let reached = {...s, stats: Stats.autoplay(s.stats)}
    // The trail: one entry per planned move, each carrying the session that move left
    // behind. A caller walking it a step at a time is playing the same line this
    // returns whole.
    let trail: array<played> = []
    let played = steps->Array.reduce(reached, (carried, step: Solver.played) => {
      let next = commit(~clock, carried, step.state)
      trail->Array.push({action: step.action, moved: step.moved, session: next})
      next
    })
    // Where the line ends: the solver stops where the board becomes finishable, so
    // finishing is the sweep's own — one further undoable step. A board it couldn't get
    // all the way there stays where the line left it, with nothing swept to report.
    let (finished, swept) = canFinish(played) ? sweepHome(~clock, played) : (played, [])
    (
      finished,
      {
        change: Played({reached, trail, swept}),
        reply: Render.text(
          Command.describeAutoplay(
            ~moves=Array.length(steps),
            ~ms,
            ~positions=effort.positions,
            ~tried=effort.moves,
            ~passes=effort.passes,
          ),
        ),
      },
    )
  }
}

// --- Stepping through history --------------------------------------------------

// Step back one move (#85): pop the history to the prior state, or report there's
// nothing to undo. Undo is available even from a won position — a victory is just
// another recorded state — so a player can step back out of the win and keep playing,
// which is what un-stamps the clock (see `stamp`).
//
// Counted as an undo, never as a move, and it never takes a move back off the tally
// (#289): the move was still made. Inside the guard, so a press with nothing behind the
// present isn't counted as one.
let undo = (~clock: unit => float, s: t): (t, outcome) =>
  if canUndo(s) {
    (
      stamp(~clock, {...s, history: History.undo(s.history), stats: Stats.undo(s.stats)}),
      {change: Restored, reply: []},
    )
  } else {
    (s, {change: Unchanged, reply: Render.text("Nothing to undo.")})
  }

// …and forward again. A fresh move after an undo has cleared the future, so redo only
// replays an unbroken back-step chain. A redo puts a move back on the board, so it
// counts as one (#289) — the only rule that keeps undo-then-redo from being a way to
// play for free.
let redo = (~clock: unit => float, s: t): (t, outcome) =>
  if canRedo(s) {
    (
      stamp(~clock, {...s, history: History.redo(s.history), stats: Stats.redo(s.stats)}),
      {change: Restored, reply: []},
    )
  } else {
    (s, {change: Unchanged, reply: Render.text("Nothing to redo.")})
  }

// --- Opening a board -----------------------------------------------------------

// Play the current deal again from its opening layout (`redeal`/`restart`). The web
// menu's Restart button, verbatim: it rebuilds the game *now on the table*, so the
// board is the same one and the history starts clean — and a session opened at a posed
// position restarts to that game's real deal rather than the pose, which is exactly
// what the button does.
//
// The board it rebuilds is the game's opening deal, so the number it reports is the
// game's own: a restart from a posed position lands on a board that really is that
// deal. The house rules carry over — restarting a game isn't changing the rules you're
// playing it under.
let redeal = (~clock: unit => float, s: t): (t, outcome) => (
  open_(~clock, ~options=s.options, ~seed=s.game.seed, s.game, GameState.initial(s.game)),
  {change: Dealt, reply: []},
)

// Open a session on a `deal` argument the shared resolver has already read
// (`Command.resolveDeal`), so every front end agrees on what the words mean and differs
// only in what it *does* about them. All four readings land somewhere here:
//
//   deal                     a fresh board, from the seed the caller supplies
//   deal 12345               that FreeCell deal, by number
//   deal freecell [midgame]  a game `core` knows, at a named position if asked
//
// A refusal returns no session, so a caller hands the player back the game they were
// playing rather than making a typo the most destructive thing they can enter.
let deal = (
  ~clock: unit => float,
  ~newSeed: unit => int,
  ~options: Options.t,
  game: option<string>,
  scenario: option<string>,
): (option<t>, outcome) => {
  let opened = (~seed, game, state) => (
    Some(open_(~clock, ~options, ~seed, game, state)),
    {change: Dealt, reply: []},
  )
  // The two readings that name a number but no game — a bare `deal` (a number invented
  // for it) and `deal 12345` — both lay out that deal of the default game (#349). Which
  // game a plain number belongs to is `Game`'s to say, not this interpreter's: it asks
  // `Game.default` for another board rather than naming FreeCell's deal function, so a
  // second seeded game costs nothing here.
  let numbered = seed => {
    let dealt = Game.dealt(Game.default, ~seed)
    opened(~seed=dealt.seed, dealt, GameState.initial(dealt))
  }
  switch Command.resolveDeal(~game, ~scenario) {
  // A dealt board reports the number that dealt it (`Game.t`'s `seed` records it), a
  // named game its own, and a posed position the deal it descends from — which for all
  // but `almost-won` is none, so the board says nothing rather than naming a deal it
  // didn't come from.
  | Command.Fresh => numbered(newSeed())
  | Command.Numbered({seed}) => numbered(seed)
  | Command.Named({game, position: None}) => opened(~seed=game.seed, game, GameState.initial(game))
  | Command.Named({game, position: Some(position)}) =>
    opened(~seed=position.seed, game, position.build(game))
  | Command.NoSuchGame({id}) => (
      None,
      {change: Unchanged, reply: Render.text(Command.describeNoSuchGame(id))},
    )
  | Command.NoSuchScenario({game, name}) => (
      None,
      {change: Unchanged, reply: Render.text(Command.describeNoSuchScenario(~game, ~name))},
    )
  }
}

// --- The interpreter -----------------------------------------------------------

// Run one parsed command against a session. Pure: no I/O — the caller shows what comes
// back and carries the session forward.
//
// This is the *board* half of the command surface. A caller answers the rest itself
// (`help`, `games`, `clear`, `quit`, `set`, `deal`) and forwards everything else here;
// a verb this doesn't play is reported rather than silently ignored, so a caller that
// forwards too much finds out.
let step = (~clock: unit => float, s: t, command: Command.t): (t, outcome) =>
  switch command {
  | Command.Print => (s, {change: Shown, reply: []})
  | Command.Undo => undo(~clock, s)
  | Command.Redo => redo(~clock, s)
  | Command.Redeal => redeal(~clock, s)
  | Command.Finish => finish(~clock, s)
  | Command.Autoplay => autoplay(~clock, s)
  | Command.Home({card}) => home(~clock, s, card)
  | Command.Dispatch(action) => dispatched(~clock, s, action)
  // A move with a half only a board can read: a destination named as a card or a column
  // label (`move 8H 9S`, `move 8H T3`), a source named as the place it's showing in
  // (`move C1 F1`, `moverun T6 T2`), or both. `Command`'s readers answer each against
  // this session's board, and what comes back is dispatched through the very path an
  // index typed by hand takes, so every way of saying a move is one move underneath.
  | Command.MoveTo({from, where}) =>
    switch (
      Command.resolveFrom(~game=s.game, present(s), from),
      Command.resolveWhere(~game=s.game, present(s), where),
    ) {
    | (Ok(cards), Ok(to)) => dispatched(~clock, s, Command.moveAction(~cards, ~to))
    // The source first: it's the half that was typed first, and a complaint about where
    // a move lands is beside the point when there's nothing to pick up.
    | (Error(message), _) | (_, Error(message)) => (
        s,
        {change: Unchanged, reply: Render.text(message)},
      )
    }
  | _ => (s, {change: Unchanged, reply: Render.text("That isn't something the board can do.")})
  }
