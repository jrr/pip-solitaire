// The reducer driver, as a *pure* command interpreter (#84). This is the CLI's
// brain: it holds a `GameState.t` and folds text commands into the very same
// `core` reducer the web app dispatches into — dealing a game, moving a card,
// printing the board — with no stdin/stdout or pointer plumbing of its own. That
// keeps the whole loop headless and scriptable: `Cli.res` wires it to a terminal
// (see there), while tests drive `run` over a canned script and assert the echo.
//
// The command surface, deliberately small and leaving room for `undo` (#-next):
//   deal <game>          start (or restart) a game — GameState.initial
//   move <card> <pile>   dispatch a Move onto pile <index>, printing the result
//   move <card> table    dispatch a Move loose onto the table (free games only)
//   print                re-print the current board
//   games                list the available games
//   help                 show this command surface
//
// A card is addressed by its compact identity (`AS`, `TH`, `KD` — see
// `CardText`), a pile by its index, and the table by the word `table`.

open Card

// What the driver is doing right now: which game is in play and where every card
// rests. `None` before the first `deal`.
type session = {game: Game.t, state: GameState.t}

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
  | Reducer.LooseNotAllowed => `Rejected: this game keeps cards in piles — no loose drops.`
  | Reducer.NoSuchPile => `Rejected: no such pile.`
  | Reducer.CardNotFound => `Rejected: ${CardText.format(card)} isn't in play.`
  }

let gamesList = () => Game.all->Array.map(g => `  ${g.id}  —  ${g.name}`)->Array.join("\n")

let help = () =>
  `Commands:
  deal <game>          start (or restart) a game
  move <card> <pile>   move a card onto pile <index> (e.g. move AS 0)
  move <card> table    move a card loose onto the table (free games only)
  print                re-print the current board
  games                list the available games
  help                 show this help

Cards are named by identity (AS, TH, KD); piles by index.

Games:
${gamesList()}`

// The board for a live session — the shared renderer over its snapshot.
let renderBoard = (s: session): string => Render.stateBoard(~game=s.game, s.state)

// Start (or restart) a game by id: a fresh `GameState.initial`, printed.
let deal = (id: string): (option<session>, string) =>
  switch Game.all->Array.find(g => g.id == id) {
  | Some(game) =>
    let s = {game, state: GameState.initial(game)}
    (Some(s), renderBoard(s))
  | None => (None, `Unknown game: ${id}\n\n${help()}`)
  }

// Dispatch one `move card target` against the current session, printing the new
// board on `Ok` or the reason on `Error`. The reducer is the sole judge of
// legality — this only translates text to an `action` and back.
let move = (s: session, cardTok: string, targetTok: string): (option<session>, string) =>
  switch (CardText.parse(cardTok), parseTarget(targetTok)) {
  | (None, _) => (Some(s), `Not a card: "${cardTok}" (try AS, TH, KD).`)
  | (_, None) => (Some(s), `Not a pile: "${targetTok}" (an index, or "table").`)
  | (Some(card), Some(target)) =>
    switch Reducer.reduce(~game=s.game, s.state, Move({card, to: target})) {
    | Ok(next) =>
      let s' = {...s, state: next}
      (Some(s'), renderBoard(s'))
    | Error(err) => (Some(s), describeError(err, card))
    }
  }

// Interpret one command line against the current session, returning the updated
// session and the text to show. Pure: no I/O — `Cli.res` prints the text and
// carries the session forward. Unknown or malformed lines answer with guidance
// rather than failing, so a scrolling session never dead-ends.
let step = (session: option<session>, line: string): (option<session>, string) => {
  let toks = tokenize(line)
  let verb = toks->Array.get(0)->Option.map(String.toLowerCase)
  switch (verb, session) {
  | (None, _) => (session, "") // blank line: nothing to do
  | (Some("help"), _) => (session, help())
  | (Some("games"), _) | (Some("list"), _) => (session, gamesList())
  | (Some("deal"), _) | (Some("new"), _) =>
    switch toks->Array.get(1) {
    | Some(id) => deal(id)
    | None => (session, "Usage: deal <game>\n\n" ++ gamesList())
    }
  // `undo` isn't implemented yet (next issue); recognise it so the verb is
  // reserved and users get a clear answer rather than "unknown command".
  | (Some("undo"), _) => (session, "Undo isn't available yet.")
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
    | (Some(cardTok), Some(targetTok)) => move(s, cardTok, targetTok)
    | _ => (session, "Usage: move <card> <pile>   (e.g. move AS 0, or move AS table)")
    }
  | (Some(other), _) => (session, `Unknown command: ${other}. Type "help" for the commands.`)
  }
}

// Fold a whole script of command lines into a single transcript: each non-blank
// line is echoed behind a prompt, followed by its output. This is what tests
// assert against — the reducer loop exercised end-to-end with no terminal.
let run = (lines: array<string>): string => {
  let session = ref(None)
  let out = []
  lines->Array.forEach(line => {
    let trimmed = String.trim(line)
    if trimmed != "" {
      let (next, text) = step(session.contents, line)
      session := next
      out->Array.push(`sleight> ${trimmed}`)
      if text != "" {
        out->Array.push(text)
      }
    }
  })
  out->Array.join("\n\n")
}
