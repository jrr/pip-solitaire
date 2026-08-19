// The reducer driver, as a *pure command interpreter* (#84). This is the CLI's
// brain: it holds a `GameState.t` and folds text commands into the very same
// `core` reducer the web app dispatches into — dealing a game, moving a card,
// printing the board — with no stdin/stdout or pointer plumbing of its own. That
// keeps the whole loop headless and scriptable: `Cli.res` wires it to a terminal
// (see there), while tests drive `run` over a canned script and assert the echo.
//
// There are *two* loops over this module now, because `cli play` reads a terminal and
// a pipe alike: a live prompt line-at-a-time, and the batch fold `run` below. They
// share `consider` — one pure "what does this line ask for" — so the only thing the
// interactive shape adds is readline plumbing, and the shape that can't be tested
// without a pty decides nothing.
//
// The *grammar* isn't here any more (#273): `Command.parse` in `core` turns a line
// into a `Command.t`, and this module is what runs one against a session. The split
// is the point — the web app's debug console types the same commands at the same
// reducer, so `move 8H 5` had better mean one thing rather than two. What's left
// here is everything that needs a session: which game is in play, the history to
// undo over, the board to print, and the house rules to consult.
//
// The command surface, deliberately small:
//   deal <n>             deal FreeCell game number <n>
//   deal <game> [pos]    a game `core` knows, at one of its named positions if given
//   new                  a fresh board, from a seed the driver invents
//   redeal / restart     play the current deal again from its opening layout
//   move <card> <where>  dispatch a Move onto a slot, a card, or a pile index
//   mv / m               the same verb, for the command you type most
//   move <card> table    dispatch a Move loose onto the table (free games only)
//   movecol <from> <to>  reorder the cascade columns — insert-and-shift (#159)
//   autoplay             let the solver play the rest of the game (#291)
//   undo / redo          step back and forth over the history of accepted moves (#85)
//   print                re-print the current board
//   set [<setting> on|off]  show the driver's flags, or change one
//   games                list the available games
//   help                 show this command surface
//   quit / exit          end an interactive session (Ctrl-D does it too)
//
// A card is addressed by its compact identity (`AS`, `TH`, `KD` — see `CardText`).
// A *destination* is said three ways (see `Command.where`): the slot name printed above
// the column (`T3`, `C1`, `F2` — see `Slot`), the card to land on (`move 2H 3C`), or the
// absolute pile index. The table is the word `table`.
//
// A line whose first non-space character is `#` is a comment: it's skipped
// entirely (not echoed, not run), so a piped script can document itself — see
// `packages/cli/examples/`. Blank lines are skipped too.

open Card

// What the driver is doing right now: which game is in play and the *history* of
// states it has passed through (#85), so `undo`/`redo` can step over them. The
// live position is `History.present(history)`; `None` before the first `deal`.
//
// `seed` is the deal number this board is showing, kept beside the game because the two
// can disagree: a posed position (`Scenario`) sits on a game whose own seed didn't
// produce it, so it reports the deal it has been *proved* to descend from — usually
// none. It's the same fact, and the same rule, the web app reports through `~onDeal`.
type session = {game: Game.t, seed: option<int>, history: History.t<GameState.t>}

// The live snapshot for a session — the present of its history. Every read below
// goes through this rather than a stored field, so the history stays the single
// source of truth for "where every card rests right now".
let present = (s: session): GameState.t => History.present(s.history)

// Prose for a rejected move, so a driver user learns *why* the card bounced. Shared
// with the web console (#273), which says the same thing to the same rejection.
let describeError = Command.describeError

let gamesList = Command.gamesList

let help = () =>
  `Commands:
${Command.renderHelp(
      Array.concat(
        Array.concat(Array.concat(Command.dealHelp, Command.boardHelp), Command.driverHelp),
        [
          ("print", "re-print the current board"),
          ("games", "list the available games"),
          ("help", "show this help"),
          ("quit", "end an interactive session (Ctrl-D does it too)"),
        ],
      ),
    )}

${Command.cardNote}

Games:
${gamesList()}`

// The board for a live session — `core`'s text renderer over its present snapshot, in
// colour, because this one is going to a terminal (the web console asks the same
// renderer for the same board without it).
let renderBoard = (s: session): string =>
  Render.stateBoard(~game=s.game, ~deal=?s.seed, ~color=true, present(s))

// Settle an accepted move: run safe auto-collect (#125) when the option is on,
// returning the settled state; `autoCollect: false` (or a finishable board)
// leaves the state exactly as the reducer returned it — the exact no-op path.
// Applied *before* the win check so a collection that plays the final cards still
// trips the win line (#121).
// Once the board is finishable (#132) safe auto-collect steps aside — the
// `finish` verb owns the end-game sweep, so auto-collect doesn't race it to the
// win and rob the player of the trigger.
//
// This settles a *state*, not a session: the caller records the settled result
// into the session's history as a single undoable step (#85), so a move and the
// collection it triggered undo together.
let afterMove = (~game: Game.t, ~options: Options.t, state: GameState.t): GameState.t =>
  if options.autoCollect && !Reducer.canFinish(~game, state) {
    let (collected, _moved) = Reducer.autoCollect(~game, state)
    collected
  } else {
    state
  }

// Adopt a settled state as the session's new present, recording it as one
// undoable step. Only accepted transitions ever reach here, so a rejected move
// leaves the history untouched (#85). A lawful *no-op* — dropping a card back
// where it already rests, or a `MoveColumn` with `from == to` — reduces to `Ok`
// but changes nothing, so it records no step either (#215): there's nothing to
// undo back to.
let commit = (s: session, next: GameState.t): session =>
  GameState.equal(next, present(s)) ? s : {...s, history: History.record(s.history, next)}

// The win line shown beneath a board once every foundation is complete (#121).
let boardText = (s: session): string => {
  let board = renderBoard(s)
  GameState.hasWon(s.game, present(s))
    ? `${board}\n\n🎉 You win! Every foundation is complete. \`deal\` to play again.`
    : board
}

// Open a session on a state, printed. A deal starts a clean history — there's nothing
// before the opening position to undo back to (#85).
let session = (~seed: option<int>, game: Game.t, state: GameState.t): (option<session>, string) => {
  let s = {game, seed, history: History.make(state)}
  (Some(s), renderBoard(s))
}

// Act on a `deal` argument the shared resolver has already read (`Command.resolveDeal`),
// so the terminal and the panel agree on what the words mean and differ only in what
// they *do* about them. All four readings land somewhere here:
//
//   deal                     a fresh board, from the seed the caller supplies
//   deal 12345               that FreeCell deal, by number
//   deal freecell [midgame]  a game `core` knows, at a named position if asked
//
// The named positions are the same vocabulary the web app's `?state=` exposes (#123), so
// a mid-game board — a movable run, a near-won position — is one command away here too.
// A game or position we don't have is reported, with the list of what we do.
let deal = (
  ~newSeed: unit => int,
  ~current: option<session>,
  game: option<string>,
  scenario: option<string>,
): (option<session>, string) =>
  switch Command.resolveDeal(~game, ~scenario) {
  // A dealt board reports the number that dealt it (`Game.freecellDeal` records it), a
  // named game its own, and a posed position the deal it descends from — which for all
  // but `almost-won` is none, so the board says nothing rather than naming a deal it
  // didn't come from.
  | Command.Fresh =>
    let dealt = Game.freecellDeal(~seed=newSeed())
    session(~seed=dealt.seed, dealt, GameState.initial(dealt))
  | Command.Numbered({seed}) =>
    let dealt = Game.freecellDeal(~seed)
    session(~seed=dealt.seed, dealt, GameState.initial(dealt))
  | Command.Named({game, position: None}) => session(~seed=game.seed, game, GameState.initial(game))
  | Command.Named({game, position: Some(position)}) =>
    session(~seed=position.seed, game, position.build(game))
  // A refusal hands `current` straight back, so a mistyped `deal` doesn't cost you the
  // game you were playing — it just says what it couldn't read. (It used to drop the
  // session, which made a typo the most destructive thing you could enter.)
  | Command.NoSuchGame({id}) => (current, Command.describeNoSuchGame(id))
  | Command.NoSuchScenario({game, name}) => (current, Command.describeNoSuchScenario(~game, ~name))
  }

// Play the current deal again from its opening layout (`redeal`/`restart`), printed. The
// web menu's Restart button, verbatim: it rebuilds the game *now on the table*, so the
// board is the same one and the history starts clean — and a session opened at a posed
// position restarts to that game's real deal rather than the pose, which is exactly what
// the button does (see `TableScene`'s `publishRestart`).
// The board it rebuilds is the game's opening deal, so the number it reports is the
// game's own — a restart from a posed position lands on a board that really is that deal.
let redeal = (s: session): (option<session>, string) =>
  session(~seed=s.game.seed, s.game, GameState.initial(s.game))

// Dispatch one parsed `Reducer.action` — a `Move`, a `MoveRun` (#123) or a
// `MoveColumn` (#159) — against the current session, printing the new board on `Ok`
// or the reason on `Error`. The reducer is the sole judge of legality; `Command`
// already turned the text into the action, so all that's left here is the house-rule
// gate, settling the accepted result, and rendering the outcome.
let dispatch = (~options: Options.t, s: session, action: Reducer.action): (
  option<session>,
  string,
) =>
  switch action {
  // The column-reorder house rule (#159) is gated *before* the reducer: with it off
  // the driver never dispatches, so the command is an exact no-op that only reports
  // the rule is disabled — no `MoveColumn` reaches the reducer, no history step
  // recorded.
  | Reducer.MoveColumn(_) if !options.allowColumnReorder => (
      Some(s),
      "Column reordering is off for this game.",
    )
  | _ =>
    switch Reducer.reduce(~game=s.game, present(s), action) {
    | Ok(next) =>
      // Settle (auto-collect) then record the settled state as one undoable step,
      // so a move and its collection undo together (#85). A reorder is purely
      // organizational — nothing has been played anywhere new — so it skips the
      // collection and commits as it stands.
      let settled = switch action {
      | Reducer.MoveColumn(_) => next
      | _ => afterMove(~game=s.game, ~options, next)
      }
      let s' = commit(s, settled)
      (Some(s'), boardText(s'))
    | Error(err) => (Some(s), Command.describeRejection(err, ~action))
    }
  }

// Dispatch one `home card` against the current session: send the named card to
// the foundation that will take it, if any (#122). The target foundation is found
// by `Reducer.foundationTarget` — the same shared legality the web double-click
// uses — and the send-home itself routes through `dispatch`, so it's the ordinary
// `Move` onto that pile: a card that completes the board still wins exactly as a
// dragged one would, and a named card that isn't in play still reports so. A card
// no foundation is ready for is reported rather than moved.
let home = (~options: Options.t, s: session, card: card): (option<session>, string) =>
  switch Reducer.foundationTarget(~game=s.game, present(s), card) {
  | Some(i) => dispatch(~options, s, Reducer.Move({card, to: Reducer.ToPile(i)}))
  | None => (Some(s), `No foundation is ready for ${CardText.format(card)}.`)
  }

// Dispatch `finish` against the current session (#132): when the board can be
// drained to a win by foundation moves alone (`Reducer.canFinish`), play the
// finishing sweep home and print the won board; otherwise report it's not yet
// finishable. The sweep is the very drain `canFinish` proves, so a `finish`
// that's offered always completes — and, like a hand-played final card, trips the
// win line (#121). It never blocks manual play: `home`/`move` still work
// card-by-card, this is only the shortcut.
let finish = (s: session): (option<session>, string) =>
  if Reducer.canFinish(~game=s.game, present(s)) {
    let (settled, _moved) = Reducer.finishSequence(~game=s.game, present(s))
    // The whole sweep is one undoable step (#85): undo after a `finish` steps back
    // to the position the sweep started from.
    let s' = commit(s, settled)
    (Some(s'), boardText(s'))
  } else {
    (Some(s), "Not finishable yet — some cards still need a tableau move first.")
  }

// Hand the board to the solver (#291): play the line `core` finds from here, then
// the finishing sweep it deliberately stops short of, so `autoplay` on a solvable
// deal ends on a won board rather than on a board with the Finish button lit.
//
// Every planned move is committed as its own undoable step, exactly as a typed one
// would be: a game the solver played is as long as it looks, and undo walks back
// through it a move at a time rather than teleporting past the whole thing. The
// moves themselves come from `Solver.autoplay`, which settles each one the way the
// plan assumes — so this driver adopts the states rather than re-dispatching the
// actions, and a session with `autocollect` off still plays the line the search
// actually found.
let autoplay = (s: session): (option<session>, string) => {
  // The clock is the caller's, not the solver's (see `Solver.effort`): what it times
  // is the whole `autoplay` call — the search, plus playing the line it found through
  // the reducer. The second part is fifty reductions against a search that generated
  // tens of thousands of positions, so what the number describes is the thinking.
  let started = Date.now()
  switch Solver.autoplay(~game=s.game, present(s)) {
  | Solver.NotFreeCell => (Some(s), Command.autoplayNotFreeCell)
  | Solver.NoLine => (Some(s), Command.autoplayNoLine)
  | Solver.Played({steps, effort}) =>
    let ms = Date.now() -. started
    let played =
      steps->Array.reduce(s, (carried, step: Solver.played) => commit(carried, step.state))
    // The sweep home is this driver's own `finish`, so an autoplayed win and a
    // hand-played one end the same way — one further undoable step, and the win line
    // beneath the board. A board it couldn't finish (a plan cut short) simply stays
    // where the moves left it.
    let swept = fst(finish(played))->Option.getOr(played)
    let said = Command.describeAutoplay(
      ~moves=Array.length(steps),
      ~ms,
      ~positions=effort.positions,
      ~tried=effort.moves,
      ~passes=effort.passes,
    )
    (Some(swept), `${said}\n\n${boardText(swept)}`)
  }
}

// Step back one move (#85): pop the history to the prior state and re-print the
// restored board, or report there's nothing to undo. Undo is available even from a
// won position — a victory is just another recorded state — so a player can step
// back out of the win and keep playing.
let undo = (s: session): (option<session>, string) =>
  if History.canUndo(s.history) {
    let s' = {...s, history: History.undo(s.history)}
    (Some(s'), boardText(s'))
  } else {
    (Some(s), "Nothing to undo.")
  }

// Step forward one move (#85): replay a state undo stepped back over, or report
// there's nothing to redo. A fresh move after an undo has cleared the future, so
// redo only replays an unbroken back-step chain.
let redo = (s: session): (option<session>, string) =>
  if History.canRedo(s.history) {
    let s' = {...s, history: History.redo(s.history)}
    (Some(s'), boardText(s'))
  } else {
    (Some(s), "Nothing to redo.")
  }

// Which commands address a *dealt board*, and which game each suggests dealing when
// there isn't one yet. Asked before the command runs, so "deal a game first" is
// answered ahead of any complaint about the arguments — that ordering is why
// `Command.Usage` carries the verb it choked on rather than just the prose.
let dealFirstHint = (command: Command.t): option<string> =>
  switch command {
  | Command.Undo
  | Command.Redo
  | Command.Print
  | Command.Dispatch(Reducer.Move(_))
  | Command.MoveTo({from: Command.Cards([_])})
  | Command.MoveTo({from: Command.Top(_)}) =>
    Some("stacking")
  | Command.Dispatch(Reducer.MoveRun(_))
  | Command.Dispatch(Reducer.MoveColumn(_))
  | Command.MoveTo(_)
  | Command.Home(_)
  | Command.Finish
  | Command.Autoplay =>
    Some("freecell")
  | Command.Usage({verb: "move"}) => Some("stacking")
  | Command.Usage(_) => Some("freecell")
  // There's no "current deal" to play again before one has been dealt.
  | Command.Redeal => Some("freecell")
  | _ => None
  }

// Interpret one already-parsed command against the current session, returning the
// updated session and the text to show. Pure: no I/O — the caller prints the text and
// carries the session forward. Unknown or malformed lines answer with guidance rather
// than failing, so a scrolling session never dead-ends.
// `~newSeed` is where a *fresh* deal's number comes from: `deal`/`new` names no board, so
// something has to invent one, and inventing is not the interpreter's to do. The default
// keeps a driver (and every test) deterministic; `Cli.res` overrides it with a random one,
// which is the same split the web app draws — `Main.randomSeed` lives in the impure view
// layer, not in `core`'s deal path.
let stepCommand = (
  ~options: Options.t,
  ~newSeed: unit => int=() => Game.freecellSeed,
  session: option<session>,
  command: Command.t,
): (option<session>, string) => {
  // Every board verb funnels through here so the "deal a game first" answer is
  // written once rather than once per verb.
  let onBoard = run =>
    switch session {
    | Some(s) => run(s)
    | None => (
        session,
        `Deal a game first (try \`deal ${dealFirstHint(command)->Option.getOr("stacking")}\`).`,
      )
    }
  switch command {
  | Command.Blank => (session, "") // blank line: nothing to do
  | Command.Help => (session, help())
  | Command.Games => (session, gamesList())
  // The panel's scrollback verb (#273). A scrolling transcript has no screen to
  // wipe, so the CLI takes it as a well-formed no-op rather than an unknown verb —
  // the grammar is shared even where the effect isn't.
  | Command.Clear => (session, "")
  // Leaving a session is the *loop's* business, not the interpreter's: `consider`
  // below intercepts this before it ever reaches here, and both drivers act on the
  // `Ended` it returns. A line that arrives here anyway (a caller stepping a parsed
  // command straight in) changes nothing, which is the only sound answer an
  // interpreter with no loop to stop can give.
  | Command.Quit => (session, "")
  // The driver's flags are the *loop's* state too, for exactly the reason quitting is:
  // `~options` here is one call's value, so a change made through it couldn't outlive the
  // command that made it. `consider` answers both before they reach here; a caller
  // stepping one in directly can still read them, but setting one changes nothing.
  | Command.Settings => (session, Command.describeSettings(options))
  | Command.Set(_) => (session, "")
  | Command.Unknown({verb}) => (session, Command.describeUnknown(verb))
  // A prefix that fit more than one verb (#286-era shorthands): text-level, like an
  // unknown verb, so it's answered before any question about a board.
  | Command.Ambiguous({verb, matches}) => (session, Command.describeAmbiguous(~verb, ~matches))
  // Every shape of `deal` — bare, numbered, named, at a position — reads the same here as
  // it does in the panel, because the reading is `core`'s (see `Command.resolveDeal`).
  | Command.Deal({game, scenario}) => deal(~newSeed, ~current=session, game, scenario)
  // A malformed *board* verb is answered "deal a game first" when there's no game, since
  // that's the more useful complaint — but a malformed `set` is about the driver's own
  // flags, which exist whether or not a board does, so it says what it couldn't read.
  | Command.Usage({verb: "set", message}) => (session, message)
  | Command.Usage({message}) => onBoard(_ => (session, message))
  | Command.Print => onBoard(s => (session, renderBoard(s)))
  | Command.Undo => onBoard(undo)
  | Command.Redo => onBoard(redo)
  | Command.Redeal => onBoard(redeal)
  | Command.Finish => onBoard(finish)
  | Command.Autoplay => onBoard(autoplay)
  | Command.Home({card}) => onBoard(s => home(~options, s, card))
  | Command.Dispatch(action) => onBoard(s => dispatch(~options, s, action))
  // A move with a half only a board can read: a destination named as a card or a column
  // label (`move 8H 9S`, `move 8H T3`), a source named as the place it's showing in
  // (`move C1 F1`, `moverun T6 T2`), or both. `Command`'s readers answer each against
  // this session's board, and what comes back is dispatched through the very path an
  // index typed by hand takes, so every way of saying a move is one move underneath.
  | Command.MoveTo({from, where}) =>
    onBoard(s =>
      switch (
        Command.resolveFrom(~game=s.game, present(s), from),
        Command.resolveWhere(~game=s.game, present(s), where),
      ) {
      | (Ok(cards), Ok(to)) => dispatch(~options, s, Command.moveAction(~cards, ~to))
      // The source first: it's the half that was typed first, and a complaint about
      // where a move lands is beside the point when there's nothing to pick up.
      | (Error(message), _) | (_, Error(message)) => (Some(s), message)
      }
    )
  }
}

// The same, from raw text: parse the line, then run it. The line-based entry point
// most callers (and every test) want.
let step = (
  ~options: Options.t,
  ~newSeed: unit => int=() => Game.freecellSeed,
  session: option<session>,
  line: string,
): (option<session>, string) => stepCommand(~options, ~newSeed, session, Command.parse(line))

// The prompt, in one place: written *before* the read in an interactive session and
// *behind* the line in a batch transcript. Same string either way — that's what makes
// the two shapes of `cli play` print the same thing, so a session on screen and a
// piped transcript of the same commands are indistinguishable (and `examples/*.txt`
// stays readable as a session log).
let prompt = "pip> "

// What a line asks the driver to *do*, decided once for both of them. The two loops
// differ only in when they learn the answer — a terminal a line at a time, a pipe all
// at once — so everything that decides anything lives here, on the pure side, and the
// loops are left holding nothing but I/O.
type outcome =
  | Skipped // a blank line or a `#` comment: neither echoed nor run
  // Everything that ran: the driver's state after it (the session *and* the flags, since
  // `set` changes those) and the text to show. Both come back on every line, changed or
  // not, so a loop adopts the pair rather than deciding which half moved.
  | Ran({session: option<session>, options: Options.t, output: string})
  // `clear`: wipe the screen, if this driver has one. Nothing else changes — which is why
  // it carries no state. A batch fold has no screen and treats it as a well-formed line
  // that prints nothing, exactly as it always did.
  | Cleared
  | Ended // `quit`/`exit`: the session is over

// Decide one line. `#` comments and blanks are dropped *before* parsing, because a
// comment isn't part of the grammar at all (`# note` would otherwise read as an
// unknown verb) — which is what lets a piped example script annotate itself, and what
// lets a whole such script be pasted into a live prompt and simply play.
let consider = (
  ~options: Options.t,
  ~newSeed: unit => int=() => Game.freecellSeed,
  session: option<session>,
  line: string,
): outcome => {
  let trimmed = String.trim(line)
  if trimmed == "" || String.startsWith(trimmed, "#") {
    Skipped
  } else {
    switch Command.parse(line) {
    | Command.Quit => Ended
    | Command.Clear => Cleared
    | Command.Settings => Ran({session, options, output: Command.describeSettings(options)})
    // The one command that changes the *driver* rather than the board. Handed back as
    // part of the state so the loop carries it into the next line — which is what makes
    // a setting stick for the rest of the session.
    | Command.Set({setting, on}) =>
      Ran({
        session,
        options: Options.apply(options, ~setting, ~on),
        output: Command.describeSet(~setting, ~on),
      })
    | command =>
      let (next, output) = stepCommand(~options, ~newSeed, session, command)
      Ran({session: next, options, output})
    }
  }
}

// Fold a whole script of command lines into a single transcript: each non-blank,
// non-comment line is echoed behind the prompt, followed by its output. This is what
// tests assert against — the reducer loop exercised end-to-end with no terminal — and
// what a piped `cli play` prints.
//
// `quit` ends the transcript where it appears, the way `exit` ends a shell script:
// it's echoed (a transcript should say why it stopped) and the rest of the input is
// left unread.
let run = (
  ~options: Options.t=Options.default,
  ~newSeed: unit => int=() => Game.freecellSeed,
  lines: array<string>,
): string => {
  let session = ref(None)
  // `~options` is where the fold *starts*; a `set` line moves it from there.
  let flags = ref(options)
  let out = []
  let ended = ref(false)
  lines->Array.forEach(line =>
    if !ended.contents {
      switch consider(~options=flags.contents, ~newSeed, session.contents, line) {
      | Skipped => ()
      | Ended =>
        out->Array.push(prompt ++ String.trim(line))
        ended := true
      // Nothing to wipe in a transcript, so the line is echoed and says nothing — the
      // shape `clear` has always had here.
      | Cleared => out->Array.push(prompt ++ String.trim(line))
      | Ran({session: next, options: flags', output}) =>
        session := next
        flags := flags'
        out->Array.push(prompt ++ String.trim(line))
        if output != "" {
          out->Array.push(output)
        }
      }
    }
  )
  out->Array.join("\n\n")
}
