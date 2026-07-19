// The reducer driver, as a *pure* command interpreter (#84). This is the CLI's
// brain: it holds a `GameState.t` and folds text commands into the very same
// `core` reducer the web app dispatches into — dealing a game, moving a card,
// printing the board — with no stdin/stdout or pointer plumbing of its own. That
// keeps the whole loop headless and scriptable: `Cli.res` wires it to a terminal
// (see there), while tests drive `run` over a canned script and assert the echo.
//
// The command surface, deliberately small:
//   deal <game>          start (or restart) a game — GameState.initial
//   move <card> <pile>   dispatch a Move onto pile <index>, printing the result
//   move <card> table    dispatch a Move loose onto the table (free games only)
//   undo / redo          step back / forward through the accepted-move history (#85)
//   print                re-print the current board
//   games                list the available games
//   help                 show this command surface
//
// A card is addressed by its compact identity (`AS`, `TH`, `KD` — see
// `CardText`), a pile by its index, and the table by the word `table`.
//
// A line whose first non-space character is `#` is a comment: it's skipped
// entirely (not echoed, not run), so a piped script can document itself — see
// `packages/cli/examples/`. Blank lines are skipped too.

open Card

// What the driver is doing right now: which game is in play and the *history* of
// where every card rests (#85). The live board is `History.present(history)`; the
// prior states behind it are what `undo` steps back through. `None` before the
// first `deal`.
type session = {game: Game.t, history: History.t<GameState.t>}

// The live board of a session — the present state its history holds.
let stateOf = (s: session): GameState.t => History.present(s.history)

// Split a command line into whitespace-separated tokens, dropping the empties
// that repeated or trailing spaces would leave.
let tokenize = (line: string): array<string> =>
  line->String.trim->String.split(" ")->Array.filter(t => t != "")

// A move target from its text: a pile index, or the table by name.
let parseTarget = (token: string): option<Reducer.target> =>
  switch token->String.toLowerCase {
  | "table" | "loose" | "t" => Some(Reducer.ToTable)
  | s =>
    switch Int.fromString(s) {
    | Some(i) => Some(Reducer.ToPile(i))
    | None => None
    }
  }

// Prose for a rejected move, so a driver user learns *why* the card bounced —
// the whole point of the reducer returning a typed `moveError` rather than a
// swallowed no-op.
let describeError = (err: Reducer.moveError, card: card): string =>
  switch err {
  | Reducer.Rejected => `Rejected: ${CardText.format(card)} can't stack there.`
  | Reducer.PileFull => `Rejected: that pile is full.`
  | Reducer.LooseNotAllowed => `Rejected: this game keeps cards in piles — no loose drops.`
  | Reducer.NoSuchPile => `Rejected: no such pile.`
  | Reducer.CardNotFound => `Rejected: ${CardText.format(card)} isn't in play.`
  | Reducer.NotARun => `Rejected: those cards aren't an ordered run.`
  | Reducer.RunTooLong => `Rejected: that run is longer than the free cells and empty columns allow.`
  }

let gamesList = () => Game.all->Array.map(g => `  ${g.id}  —  ${g.name}`)->Array.join("\n")

let help = () =>
  `Commands:
  deal <game> [scenario]  start (or restart) a game, optionally at a named position
  move <card> <pile>   move a card onto pile <index> (e.g. move AS 0)
  move <card> table    move a card loose onto the table (free games only)
  moverun <card>… <pile>  supermove an ordered run, cards bottom-first (e.g. moverun 8H 7S 6H 5)
  home <card>          send a card to its foundation, if one will take it (e.g. home AS)
  undo                 step back to the board before the last move
  redo                 replay a move you undid
  print                re-print the current board
  games                list the available games
  help                 show this help

Cards are named by identity (AS, TH, KD); piles by index.

Games:
${gamesList()}`

// The board for a live session — the shared renderer over its present snapshot.
let renderBoard = (s: session): string => Render.stateBoard(~game=s.game, stateOf(s))

// After an accepted move, run safe auto-collect (#125) when the option is on,
// returning the settled state to record; `autoCollect: false` returns the reducer's
// result untouched — the exact no-op path. Shared by `move` and `moveRun`, and
// applied *before* the win check so a collection that plays the final cards still
// trips the win line (#121). The settled state is what the caller records into
// history, so a move and the collection it triggered undo together as one unit.
let settle = (~options: Options.t, ~game: Game.t, state: GameState.t): GameState.t =>
  if options.autoCollect {
    let (collected, _moved) = Reducer.autoCollect(~game, state)
    collected
  } else {
    state
  }

// Start (or restart) a game by id, printed. With an optional scenario name, open
// that named starting position (`Scenario.forName`) instead of the fresh deal —
// the same vocabulary the web app's `?state=` exposes, so a mid-game position (a
// movable run, a near-won board) is reachable from the CLI too (#123). An unknown
// scenario for the game is reported rather than silently ignored.
let deal = (id: string, scenario: option<string>): (option<session>, string) =>
  switch Game.all->Array.find(g => g.id == id) {
  | Some(game) =>
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

// Dispatch one `move card target` against the current session, printing the new
// board on `Ok` or the reason on `Error`. The reducer is the sole judge of
// legality — this only translates text to an `action` and back.
let move = (~options: Options.t, s: session, cardTok: string, targetTok: string): (
  option<session>,
  string,
) =>
  switch (CardText.parse(cardTok), parseTarget(targetTok)) {
  | (None, _) => (Some(s), `Not a card: "${cardTok}" (try AS, TH, KD).`)
  | (_, None) => (Some(s), `Not a pile: "${targetTok}" (an index, or "table").`)
  | (Some(card), Some(target)) =>
    switch Reducer.reduce(~game=s.game, stateOf(s), Move({card, to: target})) {
    | Ok(next) =>
      let settled = settle(~options, ~game=s.game, next)
      let s' = {...s, history: History.record(s.history, settled)}
      let board = renderBoard(s')
      // A move that completes every foundation ends the game (#121): print the win
      // line beneath the board that shows the final card in place.
      let text = GameState.hasWon(s'.game, stateOf(s'))
        ? `${board}\n\n🎉 You win! Every foundation is complete. \`deal\` to play again.`
        : board
      (Some(s'), text)
    | Error(err) => (Some(s), describeError(err, card))
    }
  }

// Dispatch one `moverun card… target` against the current session: an ordered run
// (the cards named bottom-first, deepest first) supermoved onto pile `target`. The
// reducer alone rules on whether the run is legal and within the free-cell/empty-
// column limit (#123) — this only parses the tokens into a `MoveRun` and renders
// the outcome, exactly as `move` does for a single card.
let moveRun = (~options: Options.t, s: session, cardToks: array<string>, targetTok: string): (
  option<session>,
  string,
) => {
  let parsed = cardToks->Array.map(CardText.parse)
  switch (parsed->Array.some(Option.isNone), parseTarget(targetTok)) {
  | (true, _) => (Some(s), `Not all of those are cards (try AS, TH, KD).`)
  | (_, None) => (Some(s), `Not a pile: "${targetTok}" (an index, or "table").`)
  | (false, Some(target)) =>
    let cards = parsed->Array.filterMap(c => c)
    switch Reducer.reduce(~game=s.game, stateOf(s), MoveRun({cards, to: target})) {
    | Ok(next) =>
      let settled = settle(~options, ~game=s.game, next)
      let s' = {...s, history: History.record(s.history, settled)}
      let board = renderBoard(s')
      let text = GameState.hasWon(s'.game, stateOf(s'))
        ? `${board}\n\n🎉 You win! Every foundation is complete. \`deal\` to play again.`
        : board
      (Some(s'), text)
    // The bottom card names the run in any card-specific error prose.
    | Error(err) => (Some(s), describeError(err, cards->Array.getUnsafe(0)))
    }
  }
}

// Dispatch one `home card` against the current session: send the named card to
// the foundation that will take it, if any (#122). The target foundation is found
// by `Reducer.foundationTarget` — the same shared legality the web double-click
// uses — and the send-home itself routes through `move`, so it's the ordinary
// `Move` onto that pile: a card that completes the board still wins exactly as a
// dragged one would, and a named card that isn't in play still reports so. A card
// no foundation is ready for is reported rather than moved.
let home = (~options: Options.t, s: session, cardTok: string): (option<session>, string) =>
  switch CardText.parse(cardTok) {
  | None => (Some(s), `Not a card: "${cardTok}" (try AS, TH, KD).`)
  | Some(card) =>
    switch Reducer.foundationTarget(~game=s.game, stateOf(s), card) {
    | Some(i) => move(~options, s, cardTok, Int.toString(i))
    | None => (Some(s), `No foundation is ready for ${CardText.format(card)}.`)
    }
  }

// Interpret one command line against the current session, returning the updated
// session and the text to show. Pure: no I/O — `Cli.res` prints the text and
// carries the session forward. Unknown or malformed lines answer with guidance
// rather than failing, so a scrolling session never dead-ends.
let step = (~options: Options.t, session: option<session>, line: string): (
  option<session>,
  string,
) => {
  let toks = tokenize(line)
  let verb = toks->Array.get(0)->Option.map(String.toLowerCase)
  switch (verb, session) {
  | (None, _) => (session, "") // blank line: nothing to do
  | (Some("help"), _) => (session, help())
  | (Some("games"), _) | (Some("list"), _) => (session, gamesList())
  | (Some("deal"), _) | (Some("new"), _) =>
    switch toks->Array.get(1) {
    | Some(id) => deal(id, toks->Array.get(2))
    | None => (session, "Usage: deal <game> [scenario]\n\n" ++ gamesList())
    }
  // Step back (or forward) through the history of accepted moves (#85). Undo pops
  // the prior state and re-prints it; redo replays a move undo stepped out of. Both
  // are no-ops at the ends of the history, reported rather than silently ignored.
  | (Some("undo"), Some(s)) =>
    if History.canUndo(s.history) {
      let s' = {...s, history: History.undo(s.history)}
      (Some(s'), renderBoard(s'))
    } else {
      (Some(s), "Nothing to undo.")
    }
  | (Some("undo"), None) => (session, "Deal a game first (try `deal freecell`).")
  | (Some("redo"), Some(s)) =>
    if History.canRedo(s.history) {
      let s' = {...s, history: History.redo(s.history)}
      (Some(s'), renderBoard(s'))
    } else {
      (Some(s), "Nothing to redo.")
    }
  | (Some("redo"), None) => (session, "Deal a game first (try `deal freecell`).")
  | (Some("print"), Some(s)) | (Some("board"), Some(s)) | (Some("show"), Some(s)) => (
      session,
      renderBoard(s),
    )
  | (Some("print"), None) | (Some("board"), None) | (Some("show"), None) => (
      session,
      "Deal a game first (try `deal stacking`).",
    )
  | (Some("move"), None) => (session, "Deal a game first (try `deal stacking`).")
  | (Some("move"), Some(s)) =>
    switch (toks->Array.get(1), toks->Array.get(2)) {
    | (Some(cardTok), Some(targetTok)) => move(~options, s, cardTok, targetTok)
    | _ => (session, "Usage: move <card> <pile>   (e.g. move AS 0, or move AS table)")
    }
  | (Some("home"), None) => (session, "Deal a game first (try `deal freecell`).")
  | (Some("home"), Some(s)) =>
    switch toks->Array.get(1) {
    | Some(cardTok) => home(~options, s, cardTok)
    | None => (session, "Usage: home <card>   (e.g. home AS)")
    }
  | (Some("moverun"), None) => (session, "Deal a game first (try `deal freecell`).")
  | (Some("moverun"), Some(s)) =>
    // Everything after the verb is the run's cards, bottom-first, then the target.
    let rest = toks->Array.slice(~start=1, ~end=Array.length(toks))
    if Array.length(rest) >= 2 {
      let targetTok = rest->Array.getUnsafe(Array.length(rest) - 1)
      let cardToks = rest->Array.slice(~start=0, ~end=Array.length(rest) - 1)
      moveRun(~options, s, cardToks, targetTok)
    } else {
      (session, "Usage: moverun <card>… <pile>   (e.g. moverun 8H 7S 6H 5)")
    }
  | (Some(other), _) => (session, `Unknown command: ${other}. Type "help" for the commands.`)
  }
}

// Fold a whole script of command lines into a single transcript: each non-blank,
// non-comment line is echoed behind a prompt, followed by its output. This is
// what tests assert against — the reducer loop exercised end-to-end with no
// terminal. Blank lines and `#` comments are skipped so a piped example script
// can annotate itself without cluttering the transcript.
let run = (~options: Options.t=Options.default, lines: array<string>): string => {
  let session = ref(None)
  let out = []
  lines->Array.forEach(line => {
    let trimmed = String.trim(line)
    if trimmed != "" && !String.startsWith(trimmed, "#") {
      let (next, text) = step(~options, session.contents, line)
      session := next
      out->Array.push(`sleight> ${trimmed}`)
      if text != "" {
        out->Array.push(text)
      }
    }
  })
  out->Array.join("\n\n")
}
