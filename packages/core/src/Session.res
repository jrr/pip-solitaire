// A *session*: everything a front end has to know about a game in progress, and the
// one place a `Command.t` is run against one.
//
// `Reducer.reduce` is the single way a card moves; this is the layer around it — the
// game in play, the history to undo over, the tallies beside it, the post-move
// auto-collect, and the settle-record-check-win sequence every place a card can move
// runs through. It lives here rather than in each front end so that **a front end
// can't opt out**: a session that owns `Stats` and `Timing` means every front end has
// them, and they ride in the save envelope for free.
//
// What's here is the **board half** of the command surface: the verbs that need a
// dealt game to mean anything. `help`, `games`, `clear`, `quit`, `set` and `deal`
// itself stay with each front end, because those genuinely differ — `help` in a
// terminal lists a terminal's commands, `deal` in the web app tears down a DOM board.
//
// Nothing here does I/O. The two impure things a session needs — the clock a win is
// stamped with, the seed a fresh deal invents — are passed in.

open Card

// `seed` is kept beside the game because the two can disagree: a posed position sits
// on a game whose own seed didn't produce it, so it reports the deal it has been
// *proved* to descend from, usually none.
//
// `options` lives *in* the session because every house rule is consulted while playing
// a card, and a session handed them per call is a session that can be asked to play
// the same board two different ways. Both front ends keep options that outlive a board,
// so opening a new session carries the old one's forward (see `deal`, `redeal`).
type t = {
  game: Game.t,
  seed: option<int>,
  history: History.t<GameState.t>,
  stats: Stats.t,
  timing: Timing.t,
  options: Options.t,
}

// Carrying the whole *session* per step — not just the state — is what lets one
// implementation serve both front ends. A terminal plays a line in one call and wants
// the last; the web app plays it a move at a time with a flight between each, adopting
// `session` as each lands and stopping when the player interrupts. An interrupted run
// is then just an earlier session, with nothing to unwind.
type played = {action: Reducer.action, moved: array<card>, session: t}

// What a command did, split by **how a front end has to react** — the only thing a
// caller needs a variant for. A board with cards on it flies the named cards for a
// `Settled`, staggers a `Swept`, re-derives a `Restored` *without* animating (a step
// through history isn't a move, and easing cards along a path they never took would
// misreport what happened), and rebuilds for a `Dealt`.
//
// `moved` and `action` are named rather than left to be worked out, because the front
// end that needs them can't recover them: a board settled by auto-collect has cards
// resting somewhere the command never mentioned, and a narrator has to say *which*
// move in `Render.action`'s words when the interpreting happened in here.
type change =
  | Unchanged // a verb with nothing to do — "nothing to undo", a lawful no-op
  | Shown // `print`: nothing moved, but the caller asked to see the board
  | Blocked({reason: string}) // a house rule refused it before the reducer saw it
  | Rejected({action: Reducer.action, error: Reducer.moveError}) // the reducer refused it
  // `moved` is what the action named, `collected` whatever safe auto-collect swept up
  // behind it. Apart, because a narrator says two different things about them — the
  // move is what you did, the collection is what the board did back — while a caller
  // that animates flies them as one gesture.
  | Settled({action: Reducer.action, moved: array<card>, collected: array<card>})
  | Swept({moved: array<card>}) // the end-game finish sequence
  | Restored // undo/redo: a position the board already held
  | Dealt // a different board entirely (`redeal`)
  // `reached` is the session the moment the player reached for the solver — the tally
  // already counting the reach, no move played yet — which is what a caller that plays
  // the line itself starts from. A caller that only wants the result ignores all three.
  | Played({reached: t, trail: array<played>, swept: array<card>})

// **The board is deliberately not in here.** A terminal prints it, a web app has it on
// screen already, and a reply carrying it would be a document one of them throws away
// after every move. `reply` is only what neither can derive: why a move bounced, that
// there was nothing to undo, how long the solver thought.
//
// A document rather than text, for the reason `Render` splits the two: a terminal
// paints red suits in ANSI and a panel in CSS, and neither should be reading the
// other's alphabet out of a string.
type outcome = {change: change, reply: array<Render.line>}

// Every read goes through the history rather than a stored field, so it stays the
// single source of truth for where every card rests right now.
let present = (s: t): GameState.t => History.present(s.history)

let hasWon = (s: t): bool => GameState.hasWon(s.game, present(s))

let canUndo = (s: t): bool => History.canUndo(s.history)
let canRedo = (s: t): bool => History.canRedo(s.history)

// What the `finish` verb and the button offering it both ask.
let canFinish = (s: t): bool => Reducer.canFinish(~game=s.game, present(s))

// Ink but no colour: the caller's alphabet decides that.
let boardLines = (s: t): array<Render.line> =>
  Render.stateLines(~game=s.game, ~deal=?s.seed, present(s))

// How the flags a driver carries reach the session that consults them; see `t`.
let withOptions = (s: t, options: Options.t): t => {...s, options}

// One rule, applied after every change: a won board records when it was won, and a
// board that isn't won has no won-at. `Timing.won` keeps the first stamp, so a resumed
// victory reports the game's own length rather than how long ago it was played.
let stamp = (~clock: unit => float, s: t): t => {
  ...s,
  timing: hasWon(s) ? Timing.won(s.timing, ~at=clock()) : Timing.unwon(s.timing),
}

// A deal starts a clean history — there is nothing before the opening position to undo
// back to — a zero tally, and a running clock.
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

// The envelope holds the history, the tally and the clock; the game, the deal number
// and the house rules come from whoever knew which board this save was of.
//
// **`saved.gameId` is deliberately not consulted.** It's how a *reader* works out which
// board a loose blob is of, before there is a session to restore into; by the time a
// save reaches here the caller is handing over the game it already resolved, so reading
// it again could only disagree with the board being opened.
let restore = (~seed: option<int>, ~options: Options.t, game: Game.t, saved: SaveState.t): t => {
  game,
  seed,
  history: saved.history,
  stats: saved.stats,
  timing: saved.timing,
  options,
}

// …and what to write back out. `seed` and `options` stay out of the envelope: the
// first is how the save was found, and the second is the driver's rather than the
// board's.
//
// The game *is* in it, as its id, and has to be. "That's how it was found" holds for
// `localStorage`, whose key names the game, and not for the other thing this envelope
// is — a share link is found by nothing at all, so one carrying no id arrives naming no
// board. This is the only place a save is written from a session, which is the only
// thing that knows.
let save = (s: t): SaveState.t => {
  history: s.history,
  stats: s.stats,
  timing: s.timing,
  gameId: Some(s.game.id),
}

// Runs *before* the win check, so a collection playing the final cards still trips the
// win line — and steps aside once the board is finishable, so it doesn't race the
// `finish` verb to the win and rob the player of the trigger.
//
// Settles a *state*, not a session: the caller records the result as one undoable step,
// so a move and the collection it triggered undo together. The swept cards come back
// because the caller that animates flies them with the move, as one gesture.
let settle = (~game: Game.t, ~options: Options.t, state: GameState.t): (GameState.t, array<card>) =>
  if options.autoCollect && !Reducer.canFinish(~game, state) {
    Reducer.autoCollect(~game, state)
  } else {
    (state, [])
  }

// **One recorded step is one move made**, counted here rather than at each verb, so
// every way to play a move agrees by construction — a drop, a typed command, a solver
// step, and the finish sweep, which records itself as a single step.
//
// A lawful *no-op* reduces to `Ok` but changes nothing, so it records no step and
// counts no move: there is nothing to undo back to, and nothing was played.
let commit = (~clock: unit => float, s: t, next: GameState.t): t =>
  GameState.equal(next, present(s))
    ? s
    : stamp(~clock, {...s, history: History.record(s.history, next), stats: Stats.move(s.stats)})

// --- Playing a card ------------------------------------------------------------
// The one path a card moves along, whatever asked. A typed `move 8H 5`, a pointer
// drop, a double-tapped send-home and a solver's step all arrive as a `Reducer.action`
// and all get the same treatment: the house-rule gate, the reducer's verdict, the
// settle, the undoable step, the tally and the clock.

// The one house rule answered *before* the reducer rather than by it: with reordering
// off nothing is dispatched at all, so the command is an exact no-op. Said here so both
// front ends say it the same way.
let columnReorderOff = "Column reordering is off for this game."

// The reducer is the sole judge of legality; what's left here is the gate, the
// settling and the bookkeeping.
//
// A column reorder skips the settling — organizational rather than played, so nothing
// has been put down anywhere new for auto-collect to consider.
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

// The prose is built here, beside the action, because that's the only place it can be:
// `describeRejection` names the card that bounced, and a `change` alone doesn't carry
// one. Nothing is said about an *accepted* move — the board is the answer, and the
// caller is the one drawing it.
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

// Routes through `dispatch`, so a send-home is the ordinary `Move` onto that pile and
// a card that completes the board wins exactly as a dragged one would.
//
// This is the *destination* test, not a movability one: a buried card is dispatched and
// refused by the reducer, so it's told it's buried rather than told no foundation wants
// it — which is very often untrue of a buried card.
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

// The whole sweep is one undoable step, so undo after a `finish` steps back to the
// position the sweep started from. Split out from `finish` because `autoplay` hands
// over to the same sweep and needs the cards to say what it did.
let sweepHome = (~clock: unit => float, s: t): (t, array<card>) => {
  let (settled, moved) = Reducer.finishSequence(~game=s.game, present(s))
  (commit(~clock, s, settled), moved)
}

let notFinishable = "Not finishable yet — some cards still need a tableau move first."

// The sweep is the very drain `canFinish` proves, so a `finish` that's offered always
// completes — and, like a hand-played final card, trips the win. It never blocks manual
// play: this is only the shortcut.
let finish = (~clock: unit => float, s: t): (t, outcome) =>
  if canFinish(s) {
    let (s', moved) = sweepHome(~clock, s)
    (s', {change: Swept({moved: moved}), reply: []})
  } else {
    (s, {change: Unchanged, reply: Render.text(notFinishable)})
  }

// Play the line the solver finds, then the finishing sweep it deliberately stops short
// of, so `autoplay` on a solvable deal ends on a won board rather than one with the
// Finish button lit.
//
// Every planned move is committed as its own undoable step, so a game the solver played
// is as long as it looks and undo walks back through it a move at a time. It adopts the
// solver's *states* rather than re-dispatching its actions, because `Solver.autoplay`
// settles each one the way the plan assumes — so a session with auto-collect off still
// plays the line the search actually found.
//
// The reach is counted once, *before* the first step, so the very first save already
// carries "this game was autoplayed" even if a caller stops the run a move later.
let autoplay = (~clock: unit => float, s: t): (t, outcome) => {
  // This session's clock, not the solver's: it times the whole call, search plus
  // replay. The replay is fifty reductions against a search of tens of thousands of
  // positions, so the number describes the thinking.
  let started = clock()
  switch Solver.autoplay(~game=s.game, present(s)) {
  | Solver.NotFreeCell => (s, {change: Unchanged, reply: Render.text(Command.autoplayNotFreeCell)})
  | Solver.NoLine => (s, {change: Unchanged, reply: Render.text(Command.autoplayNoLine)})
  | Solver.Played({steps, effort}) =>
    let ms = clock() -. started
    let reached = {...s, stats: Stats.autoplay(s.stats)}
    // A caller walking this a step at a time is playing the same line returned whole.
    let trail: array<played> = []
    let played = steps->Array.reduce(reached, (carried, step: Solver.played) => {
      let next = commit(~clock, carried, step.state)
      trail->Array.push({action: step.action, moved: step.moved, session: next})
      next
    })
    // The solver stops where the board becomes finishable, so the finish is one further
    // undoable step. A board it couldn't get there stays where the line left it.
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

// Available even from a won position — a victory is just another recorded state — so a
// player can step back out of the win and keep playing, which is what un-stamps the
// clock. Counted as an undo, never as a move, and never taking a move back off the
// tally: the move was still made. Inside the guard, so a press with nothing behind the
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

// …and forward again. A redo puts a move back on the board, so it counts as one — the
// rule that keeps undo-then-redo from being a way to play for free.
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

// Rebuilds the game *now on the table* from its opening layout, so a session opened at
// a posed position restarts to that game's real deal rather than the pose — and reports
// the game's own number, since the board really is that deal now. The house rules carry
// over: restarting isn't changing the rules you're playing under.
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
  // Which game a plain number belongs to is `Game`'s to say, not this interpreter's:
  // this asks `Game.default` for another board rather than naming FreeCell's deal
  // function, so a second seeded game costs nothing here.
  let numbered = seed => {
    let dealt = Game.dealt(Game.default, ~seed)
    opened(~seed=dealt.seed, dealt, GameState.initial(dealt))
  }
  switch Command.resolveDeal(~game, ~scenario) {
  // Each opens reporting the deal it can prove: a dealt board the number that dealt it,
  // a posed position the one it descends from — which for all but `almost-won` is none,
  // so the board says nothing rather than naming a deal it didn't come from.
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

// Pure: the caller shows what comes back and carries the session forward. A verb this
// doesn't play is *reported* rather than silently ignored, so a caller that forwards
// more than the board half finds out.
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
  // A move with a half only a board can read — `move 8H 9S`, `move C1 F1`. `Command`'s
  // readers answer each against this session's board, and what comes back is dispatched
  // through the very path a hand-typed index takes, so every way of saying a move is
  // one move underneath.
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
