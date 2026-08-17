// The typed-command grammar, as a *pure parser*: `string => Command.t`, and
// nothing else. No session, no board, no I/O — feed it a line and it hands back
// what that line asks for (#273).
//
// It lives in `core` because two front ends type the same commands at the same
// reducer and neither owns the vocabulary:
//
//   - the **CLI's reducer driver** (#84/#91) — `Repl.res` folds a script of these
//     into a `GameState`, and `packages/cli/examples/*.txt` are its transcripts;
//   - the **web app's debug console** (#273) — the panel's input line parses a
//     typed command here and pushes the resulting `Reducer.action` through the very
//     `dispatch` a pointer drop uses, so a typed move and a dragged one are the same
//     move.
//
// A second grammar for the second front end was the thing to avoid: `move 8H 5`
// must mean the same thing in a terminal and in the panel, or the console is a
// separate game that merely looks like this one. (#148's TUI is the third caller
// waiting on this.)
//
// **Where the split falls.** Everything decidable from the text alone is here;
// everything that needs a board is the interpreter's. So `move 8H 5` parses all the
// way to a `Reducer.action` — the reducer is the sole judge of whether it's *legal*,
// but "is this a card, is that a pile" is pure text. `home AS` stops at the card:
// which foundation will take it is a question about the board, so the interpreter
// resolves it into the `Move` the reducer sees. And "deal a game first" never
// appears here at all — whether a session exists is not a property of the line.
//
// Malformed input doesn't fail: it parses to `Usage` (a known verb, arguments the
// parser couldn't make sense of) or `Unknown` (no such verb), each carrying prose
// to show. That keeps a scrolling session from ever dead-ending, and it keeps the
// *ordering* of complaints where it belongs — an interpreter with no game dealt can
// still answer "deal a game first" ahead of "that's not a card", because `Usage`
// names the verb it choked on.

open Card

// What one command line asks for. `Dispatch` is the move-shaped half — the actions
// the reducer takes verbatim — while the rest are session or front-end verbs the
// interpreter answers itself.
type t =
  | Blank // an empty line (or one that was only whitespace)
  | Help
  | Games
  | Print
  | Clear // console-only: wipe the scrollback (#273); a scrolling CLI has none
  // `deal`/`new`. What the argument *means* is the interpreter's: the CLI reads it
  // as a game id (with an optional `Scenario` name after it), the web console as a
  // FreeCell deal number. Absent, it's "deal me something fresh".
  | Deal({game: option<string>, scenario: option<string>})
  // A move the reducer can take as-is: `Move`, `MoveRun` or `MoveColumn`.
  | Dispatch(Reducer.action)
  // `home <card>` names a card but no destination — see the module note above.
  | Home({card: card})
  | Finish
  | Undo
  | Redo
  | Unknown({verb: string}) // no such verb
  | Usage({verb: string, message: string}) // this verb, arguments we can't read

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

let notACard = (token: string) => `Not a card: "${token}" (try AS, TH, KD).`
let notAPile = (token: string) => `Not a pile: "${token}" (an index, or "table").`

// Parse one command line. Total: every line yields a `t`, malformed ones included.
let parse = (line: string): t => {
  let toks = tokenize(line)
  let arg = i => toks->Array.get(i)
  switch toks->Array.get(0)->Option.map(String.toLowerCase) {
  | None => Blank
  | Some("help") => Help
  | Some("games") | Some("list") => Games
  | Some("print") | Some("board") | Some("show") => Print
  | Some("clear") | Some("cls") => Clear
  | Some("undo") => Undo
  | Some("redo") => Redo
  | Some("finish") => Finish
  | Some("deal") | Some("new") => Deal({game: arg(1), scenario: arg(2)})
  | Some("move") =>
    // Arity before content, so `move AS` asks for the usage line rather than
    // complaining about a target that isn't there.
    switch (arg(1), arg(2)) {
    | (Some(cardTok), Some(targetTok)) =>
      switch (CardText.parse(cardTok), parseTarget(targetTok)) {
      | (None, _) => Usage({verb: "move", message: notACard(cardTok)})
      | (_, None) => Usage({verb: "move", message: notAPile(targetTok)})
      | (Some(card), Some(to)) => Dispatch(Reducer.Move({card, to}))
      }
    | _ =>
      Usage({
        verb: "move",
        message: "Usage: move <card> <pile>   (e.g. move AS 0, or move AS table)",
      })
    }
  | Some("home") =>
    switch arg(1) {
    | Some(cardTok) =>
      switch CardText.parse(cardTok) {
      | Some(card) => Home({card: card})
      | None => Usage({verb: "home", message: notACard(cardTok)})
      }
    | None => Usage({verb: "home", message: "Usage: home <card>   (e.g. home AS)"})
    }
  | Some("moverun") =>
    // Everything after the verb is the run's cards, bottom-first, then the target.
    let rest = toks->Array.slice(~start=1, ~end=Array.length(toks))
    if Array.length(rest) >= 2 {
      let targetTok = rest->Array.getUnsafe(Array.length(rest) - 1)
      let parsed =
        rest->Array.slice(~start=0, ~end=Array.length(rest) - 1)->Array.map(CardText.parse)
      switch (parsed->Array.some(Option.isNone), parseTarget(targetTok)) {
      | (true, _) =>
        Usage({verb: "moverun", message: `Not all of those are cards (try AS, TH, KD).`})
      | (_, None) => Usage({verb: "moverun", message: notAPile(targetTok)})
      | (false, Some(to)) => Dispatch(Reducer.MoveRun({cards: parsed->Array.filterMap(c => c), to}))
      }
    } else {
      Usage({
        verb: "moverun",
        message: "Usage: moverun <card>… <pile>   (e.g. moverun 8H 7S 6H 5)",
      })
    }
  | Some("movecol") =>
    switch (arg(1), arg(2)) {
    | (Some(fromTok), Some(toTok)) =>
      switch (Int.fromString(fromTok), Int.fromString(toTok)) {
      | (Some(from), Some(to)) => Dispatch(Reducer.MoveColumn({from, to}))
      | _ =>
        Usage({verb: "movecol", message: `Not a pile index (try two indices, e.g. movecol 8 15).`})
      }
    | _ =>
      Usage({
        verb: "movecol",
        message: "Usage: movecol <from> <to>   (pile indices, e.g. movecol 8 15)",
      })
    }
  | Some(other) => Unknown({verb: other})
  }
}

// The prose for an unknown verb — one string, so both front ends say the same thing
// to the same typo.
let describeUnknown = (verb: string): string =>
  `Unknown command: ${verb}. Type "help" for the commands.`

// --- Rejection prose ----------------------------------------------------------
// Why a move bounced, in words, so someone typing learns the *reason* rather than
// watching a card refuse to go — the whole point of the reducer returning a typed
// `moveError` instead of a swallowed no-op.
let describeError = (err: Reducer.moveError, card: card): string =>
  switch err {
  | Reducer.Rejected => `Rejected: ${CardText.format(card)} can't stack there.`
  | Reducer.PileFull => `Rejected: that pile is full.`
  | Reducer.LooseNotAllowed => `Rejected: this game keeps cards in piles — no loose drops.`
  | Reducer.NoSuchPile => `Rejected: no such pile.`
  | Reducer.CardNotFound => `Rejected: ${CardText.format(card)} isn't in play.`
  | Reducer.NotARun => `Rejected: those cards aren't an ordered run.`
  | Reducer.RunTooLong => `Rejected: that run is longer than the free cells and empty columns allow.`
  | Reducer.NotAColumn => `Rejected: that pile isn't a cascade column.`
  }

// The same, for a rejection reported against the *action* that was dispatched: a
// `Move` is named by its card and a `MoveRun` by the bottom card of its run, while
// a `MoveColumn` carries no card at all and so is described on its own terms (it
// can only fail for the two reasons below).
let describeRejection = (err: Reducer.moveError, ~action: Reducer.action): string =>
  switch (action, err) {
  | (Reducer.MoveColumn(_), Reducer.NotAColumn) => "Rejected: that pile isn't a cascade column."
  | (Reducer.MoveColumn(_), _) => "Rejected: no such pile."
  | (Reducer.Move({card}), _) => describeError(err, card)
  | (Reducer.MoveRun({cards}), _) =>
    switch cards->Array.get(0) {
    | Some(card) => describeError(err, card)
    | None => "Rejected: those cards aren't an ordered run."
    }
  }

// --- Help ---------------------------------------------------------------------
// The verbs are shared; the *listing* isn't quite, because each front end has a few
// of its own (`print`/`games` in a terminal, `clear` in the panel) and reads the
// `deal` argument differently. So the shared rows live here and each front end
// composes its own listing around them — one table, rendered by one function, with
// no chance of the two drifting on what `moverun` does.
type helpRow = (string, string)

// The board verbs both front ends offer, in the order they're worth learning.
let boardHelp: array<helpRow> = [
  ("move <card> <pile>", "move a card onto pile <index> (e.g. move AS 0)"),
  ("move <card> table", "move a card loose onto the table (free games only)"),
  (
    "moverun <card>… <pile>",
    "supermove an ordered run, cards bottom-first (e.g. moverun 8H 7S 6H 5)",
  ),
  ("home <card>", "send a card to its foundation, if one will take it (e.g. home AS)"),
  (
    "movecol <from> <to>",
    "reorder cascade columns: pull column <from> and drop it at <to> (e.g. movecol 8 15)",
  ),
  ("finish", "sweep every card home to win, when the board is drainable (#132)"),
  ("undo", "step back one move (works even from a win)"),
  ("redo", "replay a move you undid"),
]

// How a card is addressed, said once for both listings.
let cardNote = "Cards are named by identity (AS, TH, KD); piles by index."

let rec padTo = (s: string, width: int): string =>
  String.length(s) >= width ? s : padTo(s ++ " ", width)

// Render rows into an aligned block: every description starts at the same column, so
// a front end's own verbs and the shared ones read as one table rather than two.
let renderHelp = (rows: array<helpRow>): string => {
  let width = rows->Array.reduce(0, (w, (verb, _)) => {
    let n = String.length(verb)
    n > w ? n : w
  })
  rows->Array.map(((verb, what)) => `  ${padTo(verb, width)}  ${what}`)->Array.join("\n")
}

// The available games, one per line — what `games` prints, and what an unknown game
// id is answered with.
let gamesList = (): string =>
  Game.all->Array.map(g => `  ${g.id}  —  ${g.name}`)->Array.join("\n")
