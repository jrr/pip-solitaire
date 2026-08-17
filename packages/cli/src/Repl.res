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
//   deal <game>          start (or restart) a game — GameState.initial
//   move <card> <pile>   dispatch a Move onto pile <index>, printing the result
//   move <card> table    dispatch a Move loose onto the table (free games only)
//   movecol <from> <to>  reorder the cascade columns — insert-and-shift (#159)
//   undo / redo          step back and forth over the history of accepted moves (#85)
//   print                re-print the current board
//   games                list the available games
//   help                 show this command surface
//   quit / exit          end an interactive session (Ctrl-D does it too)
//
// A card is addressed by its compact identity (`AS`, `TH`, `KD` — see
// `CardText`), a pile by its index, and the table by the word `table`.
//
// A line whose first non-space character is `#` is a comment: it's skipped
// entirely (not echoed, not run), so a piped script can document itself — see
// `packages/cli/examples/`. Blank lines are skipped too.

open Card

// What the driver is doing right now: which game is in play and the *history* of
// states it has passed through (#85), so `undo`/`redo` can step over them. The
// live position is `History.present(history)`; `None` before the first `deal`.
type session = {game: Game.t, history: History.t<GameState.t>}

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
        Array.concat(
          [("deal <game> [scenario]", "start (or restart) a game, optionally at a named position")],
          Command.boardHelp,
        ),
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

// The board for a live session — the shared renderer over its present snapshot.
let renderBoard = (s: session): string => Render.stateBoard(~game=s.game, present(s))

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

// Start (or restart) a game by id, printed. With an optional scenario name, open
// that named starting position (`Scenario.forName`) instead of the fresh deal —
// the same vocabulary the web app's `?state=` exposes, so a mid-game position (a
// movable run, a near-won board) is reachable from the CLI too (#123). An unknown
// scenario for the game is reported rather than silently ignored.
let deal = (id: string, scenario: option<string>): (option<session>, string) =>
  switch Game.all->Array.find(g => g.id == id) {
  | Some(game) =>
    // A fresh deal starts a clean history — nothing before the opening position
    // to undo back to (#85).
    switch scenario {
    | None =>
      let s = {game, history: History.make(GameState.initial(game))}
      (Some(s), renderBoard(s))
    | Some(name) =>
      switch Scenario.forName(game, name) {
      | Some(state) =>
        let s = {game, history: History.make(state)}
        (Some(s), renderBoard(s))
      | None => (None, `Unknown scenario "${name}" for ${id}.`)
      }
    }
  | None => (None, `Unknown game: ${id}\n\n${help()}`)
  }

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
  | Command.Undo | Command.Redo | Command.Print | Command.Dispatch(Reducer.Move(_)) =>
    Some("stacking")
  | Command.Dispatch(Reducer.MoveRun(_))
  | Command.Dispatch(Reducer.MoveColumn(_))
  | Command.Home(_)
  | Command.Finish =>
    Some("freecell")
  | Command.Usage({verb: "move"}) => Some("stacking")
  | Command.Usage(_) => Some("freecell")
  | _ => None
  }

// Interpret one already-parsed command against the current session, returning the
// updated session and the text to show. Pure: no I/O — the caller prints the text and
// carries the session forward. Unknown or malformed lines answer with guidance rather
// than failing, so a scrolling session never dead-ends.
let stepCommand = (~options: Options.t, session: option<session>, command: Command.t): (
  option<session>,
  string,
) => {
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
  | Command.Unknown({verb}) => (session, Command.describeUnknown(verb))
  | Command.Deal({game: Some(id), scenario}) => deal(id, scenario)
  | Command.Deal({game: None}) => (session, "Usage: deal <game> [scenario]\n\n" ++ gamesList())
  | Command.Usage({message}) => onBoard(_ => (session, message))
  | Command.Print => onBoard(s => (session, renderBoard(s)))
  | Command.Undo => onBoard(undo)
  | Command.Redo => onBoard(redo)
  | Command.Finish => onBoard(finish)
  | Command.Home({card}) => onBoard(s => home(~options, s, card))
  | Command.Dispatch(action) => onBoard(s => dispatch(~options, s, action))
  }
}

// The same, from raw text: parse the line, then run it. The line-based entry point
// most callers (and every test) want.
let step = (~options: Options.t, session: option<session>, line: string): (
  option<session>,
  string,
) => stepCommand(~options, session, Command.parse(line))

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
  | Ran({session: option<session>, output: string})
  | Ended // `quit`/`exit`: the session is over

// Decide one line. `#` comments and blanks are dropped *before* parsing, because a
// comment isn't part of the grammar at all (`# note` would otherwise read as an
// unknown verb) — which is what lets a piped example script annotate itself, and what
// lets a whole such script be pasted into a live prompt and simply play.
let consider = (~options: Options.t, session: option<session>, line: string): outcome => {
  let trimmed = String.trim(line)
  if trimmed == "" || String.startsWith(trimmed, "#") {
    Skipped
  } else {
    switch Command.parse(line) {
    | Command.Quit => Ended
    | command =>
      let (next, output) = stepCommand(~options, session, command)
      Ran({session: next, output})
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
let run = (~options: Options.t=Options.default, lines: array<string>): string => {
  let session = ref(None)
  let out = []
  let ended = ref(false)
  lines->Array.forEach(line =>
    if !ended.contents {
      switch consider(~options, session.contents, line) {
      | Skipped => ()
      | Ended =>
        out->Array.push(prompt ++ String.trim(line))
        ended := true
      | Ran({session: next, output}) =>
        session := next
        out->Array.push(prompt ++ String.trim(line))
        if output != "" {
          out->Array.push(output)
        }
      }
    }
  )
  out->Array.join("\n\n")
}
