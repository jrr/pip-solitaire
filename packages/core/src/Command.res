// The typed-command grammar: `string => Command.t` as a pure parser, plus the
// board-side readers a parsed command needs before it can be run. No session and no
// I/O — feed it a line and it hands back what that line asks for (#273).
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
// **Where the split falls.** `parse` decides everything decidable from the text
// alone; everything that needs a board is answered after it. So `move 8H 5` parses
// all the way to a `Reducer.action` — the reducer is the sole judge of whether it's
// *legal*, but "is this a card, is that a pile" is pure text. `home AS` stops at the
// card: which foundation will take it is a question about the board, so the
// interpreter resolves it into the `Move` the reducer sees. And "deal a game first"
// never appears here at all — whether a session exists is not a property of the line.
//
// Some of those board-shaped questions turn out to be *shared* rather than each front
// end's own: `move 8H 9S` has to land on the same pile in a terminal and in the panel,
// so "which pile is showing the Nine of Spades" is answered here too — by
// `resolveWhere`, which takes the board as an argument rather than pretending to be
// pure. The rule the module keeps is that `parse` never sees one: reading the words and
// reading the board stay two steps, and only the second needs a game.
//
// Malformed input doesn't fail: it parses to `Usage` (a known verb, arguments the
// parser couldn't make sense of) or `Unknown` (no such verb), each carrying prose
// to show. That keeps a scrolling session from ever dead-ending, and it keeps the
// *ordering* of complaints where it belongs — an interpreter with no game dealt can
// still answer "deal a game first" ahead of "that's not a card", because `Usage`
// names the verb it choked on.

open Card

// Where a move sends its cards, as the *text* names it. Only the first shape is
// decidable from the text alone; the other two are answers about a particular board,
// which is why a `move` no longer always parses straight to a `Reducer.action` —
// `resolveWhere` below finishes the job once there's a board to ask.
//
// The three ways to say where, in the order a player reaches for them:
//
//   move 8H 12    `At`   — a pile index (or `table`), the original and still the
//                          only one that needs nothing but the line
//   move 8H T3     `Slot` — the name printed above the column (see `Slot`)
//   move 8H 9S     `Onto` — the card to land on, wherever it happens to be
//
// `Onto` is the one worth explaining. A player looking at the board is thinking "the
// eight goes on the nine", not "the eight goes on pile 12" — the card is the thing
// they can see, and the pile index is a fact about the model they have to count out.
// Naming the card says the move they mean, and it's checked rather than guessed: the
// card has to be the one showing at the top of exactly one pile, or the move is
// refused rather than sent somewhere plausible.
type where =
  | At(Reducer.target)
  | Onto(card)
  | Slot({role: Game.role, ordinal: int})

// What one command line asks for. `Dispatch` is the move-shaped half — the actions
// the reducer takes verbatim — while the rest are session or front-end verbs the
// interpreter answers itself.
type t =
  | Blank // an empty line (or one that was only whitespace)
  | Help
  | Games
  | Print
  | Clear // console-only: wipe the scrollback (#273); a scrolling CLI has none
  // The mirror image of `Clear`: CLI-only, because only an interactive session is
  // something you can *leave*. The panel is closed by the keys on its status line, so
  // it answers this rather than acting on it — and, like `clear` in a terminal, a verb
  // one front end can't act on is still a verb both front ends know.
  | Quit
  // `deal`/`new`. What the argument *means* is the interpreter's: the CLI reads it
  // as a game id (with an optional `Scenario` name after it), the web console as a
  // FreeCell deal number. Absent, it's "deal me something fresh".
  | Deal({game: option<string>, scenario: option<string>})
  // A move the reducer can take as-is: `Move`, `MoveRun` or `MoveColumn`.
  | Dispatch(Reducer.action)
  // A move whose destination only a *board* can resolve — `move 8H 9S` (onto whichever
  // pile is showing the Nine of Spades) or `move 8H T3` (the third tableau column). The
  // cards are the ones a `Dispatch` would have carried: one for a `move`, the whole run
  // for a `moverun`. `resolveWhere` and `moveAction` below turn the pair into that very
  // action, so a resolved move is the same move, not a second kind of one.
  | MoveTo({cards: array<card>, where: where})
  // `home <card>` names a card but no destination — see the module note above.
  | Home({card: card})
  | Finish
  | Undo
  | Redo
  // `redeal`/`restart`: play the *current* deal again from its opening layout — the web
  // menu's Restart button, as a verb. Not a re-shuffle (that's `new`) and not an undo to
  // the start: like the button, it rebuilds the game now on the table, so a session
  // opened at a posed position restarts to that game's real deal rather than the pose.
  | Redeal
  // The driver's own flags (`Options`), read and written: bare `set` shows them, `set
  // <setting> on|off` changes one. A *driver* preference rather than board state, so
  // neither reaches the reducer — but both front ends have the same two flags, so the
  // vocabulary is shared like the rest.
  | Settings
  | Set({setting: Options.setting, on: bool})
  | Unknown({verb: string}) // no such verb
  | Usage({verb: string, message: string}) // this verb, arguments we can't read

// Split a command line into whitespace-separated tokens, dropping the empties
// that repeated or trailing spaces would leave.
let tokenize = (line: string): array<string> =>
  line->String.trim->String.split(" ")->Array.filter(t => t != "")

// A whole number, and nothing else. `Int.fromString` is `parseInt` underneath, so it
// reads "4D" as 4 and "12abc" as 12 — which is merely untidy while a number is the only
// thing a token could be, and a bug the moment a card can be one too: `move 8H 4D` would
// quietly aim at pile 4 rather than at the Four of Diamonds. Both readers of a numeric
// token go through here (`dealNumber` below is the same rule for a deal).
let digits = (token: string): option<int> =>
  token != "" && token->String.split("")->Array.every(c => c >= "0" && c <= "9")
    ? Int.fromString(token)
    : None

// A move target from its text: a pile index, or the table by name.
let parseTarget = (token: string): option<Reducer.target> =>
  switch token->String.toLowerCase {
  | "table" | "loose" | "t" => Some(Reducer.ToTable)
  | s =>
    switch digits(s) {
    | Some(i) => Some(Reducer.ToPile(i))
    | None => None
    }
  }

// Read a destination token. Indices first (a bare number has always been one), then a
// slot label, then a card identity — the three grammars don't overlap, because a label
// is letter-then-digits and a card is rank-then-suit with no suit letter that a role
// letter shares (see `Slot`).
let parseWhere = (token: string): option<where> =>
  switch parseTarget(token) {
  | Some(target) => Some(At(target))
  | None =>
    switch Slot.parse(token) {
    | Some((role, ordinal)) => Some(Slot({role, ordinal}))
    | None => CardText.parse(token)->Option.map(card => Onto(card))
    }
  }

let notACard = (token: string) => `Not a card: "${token}" (try AS, TH, KD).`
let notAPile = (token: string) =>
  `Not a place to move to: "${token}" (a pile index, a column like T3, the card to land on like 9S, or "table").`

let settingNames = () => Options.all->Array.map(Options.name)->Array.join(", ")
let notASetting = (token: string) => `Not a setting: "${token}" (${settingNames()}).`
let notAFlag = (token: string) => `Not on or off: "${token}".`

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
  | Some("quit") | Some("exit") => Quit
  | Some("undo") => Undo
  | Some("redo") => Redo
  | Some("redeal") | Some("restart") => Redeal
  | Some("finish") => Finish
  | Some("deal") | Some("new") => Deal({game: arg(1), scenario: arg(2)})
  // `mv` and `m` are the same verb: `move` is the one command typed over and over, and
  // a player who has just read a board wants two keystrokes for it, not four. The
  // aliases end here — everything downstream (the `Usage` complaints, the "deal a game
  // first" hint that keys off the verb) still says `move`, so a shorthand can't drift
  // into a second command with its own messages.
  | Some("move") | Some("mv") | Some("m") =>
    // Arity before content, so `move AS` asks for the usage line rather than
    // complaining about a target that isn't there.
    switch (arg(1), arg(2)) {
    | (Some(cardTok), Some(whereTok)) =>
      switch (CardText.parse(cardTok), parseWhere(whereTok)) {
      | (None, _) => Usage({verb: "move", message: notACard(cardTok)})
      | (_, None) => Usage({verb: "move", message: notAPile(whereTok)})
      // A pile index needs no board, so it parses all the way to the action, exactly as
      // it always has; the two board-shaped destinations wait for one.
      | (Some(card), Some(At(to))) => Dispatch(Reducer.Move({card, to}))
      | (Some(card), Some(where)) => MoveTo({cards: [card], where})
      }
    | _ =>
      Usage({
        verb: "move",
        message: "Usage: move <card> <where>   (e.g. move AS 0, move AS T3, move 2H 3C, or move AS table)",
      })
    }
  // Bare `set` shows the flags; `set <setting> on|off` changes one. Arity before content
  // here too, so `set autocollect` asks for the usage line rather than complaining about
  // a value that isn't there.
  | Some("set") =>
    switch (arg(1), arg(2)) {
    | (None, _) => Settings
    | (Some(settingTok), Some(valueTok)) =>
      switch (Options.parse(settingTok), Options.parseFlag(valueTok)) {
      | (None, _) => Usage({verb: "set", message: notASetting(settingTok)})
      | (_, None) => Usage({verb: "set", message: notAFlag(valueTok)})
      | (Some(setting), Some(on)) => Set({setting, on})
      }
    | (Some(_), None) =>
      Usage({
        verb: "set",
        message: `Usage: set <setting> on|off   (e.g. set autocollect off; ${settingNames()})`,
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
      switch (parsed->Array.some(Option.isNone), parseWhere(targetTok)) {
      | (true, _) =>
        Usage({verb: "moverun", message: `Not all of those are cards (try AS, TH, KD).`})
      | (_, None) => Usage({verb: "moverun", message: notAPile(targetTok)})
      | (false, Some(At(to))) =>
        Dispatch(Reducer.MoveRun({cards: parsed->Array.filterMap(c => c), to}))
      // A run takes its destination the same three ways a single card does — there's no
      // reason `moverun 8H 7S 6H T3` should be the one move you have to count piles for.
      | (false, Some(where)) => MoveTo({cards: parsed->Array.filterMap(c => c), where})
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
      switch (digits(fromTok), digits(toTok)) {
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

// --- Resolving a destination against a board ---------------------------------
// The other half of `where`: `parse` reads the words, and this reads the *board* they
// were said about. It lives here rather than in either front end for the reason the
// grammar does — `move 8H 9S` has to pick the same pile in a terminal and in the
// panel, and "which pile is showing the Nine of Spades" is one question with one
// answer, not two implementations of it.

// Every pile currently *showing* `card` — holding it as its top card, the card a
// newcomer would land on. A buried card shows nothing: landing "on" it would really
// land on whatever covers it, which is a different move from the one that was typed.
let showing = (~game: Game.t, state: GameState.t, card: card): array<int> =>
  game.piles
  ->Array.mapWithIndex((_, i) => i)
  ->Array.filter(i =>
    switch GameState.topOf(state, i) {
    | Some(top) => GameState.sameCard(top, card)
    | None => false
    }
  )

// The slot labels for a set of pile indices, for a message that has to point at them.
let labelsOf = (~game: Game.t, indices: array<int>): string =>
  indices->Array.filterMap(i => Slot.labelAt(~game, i))->Array.join(", ")

// Turn a `where` into the target a `Reducer.action` carries, or say why it names no
// single pile on this board. Every refusal is a sentence about the board the player is
// looking at, because that's the only thing that could have made the destination
// unreadable — the words themselves already parsed.
let resolveWhere = (~game: Game.t, state: GameState.t, where: where): result<
  Reducer.target,
  string,
> =>
  switch where {
  | At(target) => Ok(target)
  | Slot({role, ordinal}) =>
    switch Slot.indexOf(~game, ~role, ~ordinal) {
    | Some(i) => Ok(Reducer.ToPile(i))
    | None =>
      let have = Slot.count(~game, role)
      Error(
        have == 0
          ? `This board has no ${Slot.roleNamePlural(role)}.`
          : `No such ${Slot.roleName(role)}: ${Slot.format(
                ~role,
                ~ordinal,
              )} (this board has ${Int.toString(have)}, ${Slot.format(
                ~role,
                ~ordinal=1,
              )}–${Slot.format(~role, ~ordinal=have)}).`,
      )
    }
  // A named card resolves only when *exactly one* pile is showing it. Nought and more
  // than one are both refusals rather than a guess: a move that lands somewhere the
  // player didn't name is worse than one that doesn't happen. (A standard deck can't
  // show the same card twice, so the ambiguous case is a guard on the games that could
  // — but it's the guard that lets the rule be stated simply.)
  | Onto(card) =>
    switch showing(~game, state, card) {
    | [i] => Ok(Reducer.ToPile(i))
    | [] =>
      Error(
        switch GameState.locationOf(state, card) {
        | None => `${CardText.format(card)} isn't in play.`
        | Some(GameState.Loose) =>
          `${CardText.format(card)} is lying loose on the table, not on a pile.`
        | Some(GameState.InPile(_)) =>
          `${CardText.format(card)} is buried — only the card on top of a pile can be moved onto.`
        },
      )
    | many =>
      Error(
        `Ambiguous: ${CardText.format(card)} is showing on ${Int.toString(
            Array.length(many),
          )} piles (${labelsOf(~game, many)}). Name the column instead.`,
      )
    }
  }

// The action that moves `cards` onto a resolved target: one card is a `Move`, several
// are the supermove `MoveRun`. Written once so a resolved `move`/`moverun` dispatches
// the identical action its index-typed twin would have.
let moveAction = (~cards: array<card>, ~to: Reducer.target): Reducer.action =>
  switch cards {
  | [card] => Reducer.Move({card, to})
  | _ => Reducer.MoveRun({cards, to})
  }

// --- What a `deal` argument names --------------------------------------------
// `parse` above hands the argument through untouched, because *acting* on a deal needs a
// front end (a terminal builds a session, the panel rebuilds a board). Reading it does
// not — "is that a deal number, a game, a posed position, or nothing we know?" is
// answered by `Game.all` and `Scenario`, both of which live here. So it's answered here,
// once, and the two front ends act on the same verdict.
//
// That's the whole point: before this, `deal 12345` opened a board in the browser and
// was an unknown game in the terminal, while `deal freecell midgame` did the reverse.
// One resolver means one vocabulary — and it's the reason the panel now deals the games
// its own `games` command has always listed.
type dealt =
  | Fresh // `deal` / `new`: something new, dealt from a seed the caller invents
  | Numbered({seed: int}) // `deal 12345`: a FreeCell deal by number
  // `deal <game> [position]`: a game `core` knows, at its opening layout or at one of
  // its named positions. The `Scenario.named` comes through whole rather than as the
  // state it builds, because a caller may want its `seed` too (the web app reports which
  // deal a posed board descends from).
  | Named({game: Game.t, position: option<Scenario.named>})
  | NoSuchGame({id: string})
  | NoSuchScenario({game: Game.t, name: string})

// A deal number is *all* digits. `Int.fromString` alone would read "12abc" as 12 and
// open a board nobody asked for, so the token has to be nothing but digits to be one.
let dealNumber = digits

let resolveDeal = (~game: option<string>, ~scenario: option<string>): dealt =>
  switch game {
  | None => Fresh
  | Some(token) =>
    switch dealNumber(token) {
    | Some(seed) => Numbered({seed: seed})
    | None =>
      // A game id, then — the numbers are taken, so nothing else can be one.
      switch Game.all->Array.find(g => g.id == token) {
      | None => NoSuchGame({id: token})
      | Some(game) =>
        switch scenario {
        | None => Named({game, position: None})
        | Some(name) =>
          switch Scenario.scenariosFor(game)->Array.find(s => s.name == name) {
          | Some(position) => Named({game, position: Some(position)})
          | None => NoSuchScenario({game, name})
          }
        }
      }
    }
  }

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
  ("move <card> <where>", "move a card (`mv`/`m` for short) — see the destinations below"),
  ("move <card> table", "move a card loose onto the table (free games only)"),
  (
    "moverun <card>… <where>",
    "supermove an ordered run, cards bottom-first (e.g. moverun 8H 7S 6H T3)",
  ),
  ("home <card>", "send a card to its foundation, if one will take it (e.g. home AS)"),
  (
    "movecol <from> <to>",
    "reorder cascade columns: pull column <from> and drop it at <to> (e.g. movecol 8 15)",
  ),
  ("finish", "sweep every card home to win, when the board is drainable (#132)"),
  ("undo", "step back one move (works even from a win)"),
  ("redo", "replay a move you undid"),
  ("redeal", "play the current deal again from the start (the same board)"),
]

// The `deal` family. Shared rows now that both front ends read the argument the same way
// (see `resolveDeal`) — before, each listed its own half of the same verb, which is
// exactly the drift a shared grammar is supposed to prevent.
// The driver's flags (`Options`). Shared for the same reason the board verbs are: the
// two front ends have the same two settings, and one of them — the column-reorder house
// rule — has no other control anywhere.
let driverHelp: array<helpRow> = [
  ("set", "show the driver settings"),
  ("set <setting> on|off", "change one (autocollect, reorder)"),
]

let dealHelp: array<helpRow> = [
  ("deal <n>", "deal FreeCell game number <n> (e.g. deal 12345)"),
  ("deal <game> [position]", "deal a named game, at a named position if given"),
  ("new", "deal a fresh game"),
]

// How a card is addressed and how a destination is said, once for both listings. The
// three ways to name a place are worth spelling out here rather than crowding the
// `move` row: they're the same three for `move` and `moverun`, and two of them are new
// enough that a player won't guess them.
let cardNote = `Cards are named by identity (AS, TH, KD).
A destination is one of:
  a slot name    the label above the column — T3 (tableau), C1 (free cell), F2 (foundation)
  a card         the card to land on, wherever it is — move 2H 3C
  a pile index   the absolute position — move 2H 11
  table          loose on the table (free games only)`

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

// The driver's flags and their values, aligned by the same renderer the help listing
// uses — what a bare `set` shows, in both front ends.
let describeSettings = (options: Options.t): string =>
  `Settings:\n${renderHelp(Options.rows(options))}`

// One changed flag, acknowledged. Short on purpose: it's a confirmation, not a report.
let describeSet = (~setting: Options.setting, ~on: bool): string =>
  `${Options.name(setting)} ${on ? "on" : "off"}`

// The available games, one per line — what `games` prints, and what an unknown game
// id is answered with.
let gamesList = (): string =>
  Game.all->Array.map(g => `  ${g.id}  —  ${g.name}`)->Array.join("\n")

// The named positions a game has, one per line (`Scenario`) — the `games` listing's
// sibling, for the second half of a `deal <game> <position>`.
let positionsList = (game: Game.t): string =>
  switch Scenario.scenariosFor(game) {
  | [] => `  (${game.id} has no named positions)`
  | positions => positions->Array.map(p => `  ${p.name}  —  ${p.label}`)->Array.join("\n")
  }

// What to say when a `deal` argument names nothing we know. One sentence for each case,
// said the same way in a terminal and in the panel — and each ends with what *would*
// have worked, because a refusal that only says "no" sends the reader to the source.
let describeNoSuchGame = (id: string): string =>
  `Unknown game: ${id}. Try a deal number (e.g. deal 12345), or one of:\n${gamesList()}`

let describeNoSuchScenario = (~game: Game.t, ~name: string): string =>
  `Unknown position "${name}" for ${game.id}. Named positions:\n${positionsList(game)}`
