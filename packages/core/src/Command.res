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

// Which pile a move picks its cards *up* from, as the text names it. The mirror of the
// two board-shaped `where`s above, and board-shaped for the same reason: a label names
// a place, and only a board knows what is lying there.
type place =
  | AtPile(int) // `move 12 F1` — the absolute index, as `where` takes one
  | InSlot({role: Game.role, ordinal: int}) // `move C1 F1` — the label above the column

// What a move lifts. Naming the cards is the original grammar and still the precise one;
// naming the *place* is the one a player looking at the board reaches for, because the
// board prints `C1` over the cell and prints nothing at all over "the Ten of Clubs, which
// is the card currently in it".
//
// `Top` and `Run` are the same reading at two lengths, one per verb: `move C1 F1` takes
// the single card showing there, `moverun T6 T2` takes the whole ordered run showing
// there. Neither guesses at *more* than the verb asked for — a `move` never lifts a run
// behind the player's back, and a `moverun` off a slot lifts what a player would grab if
// they took hold of the deepest card that still heads a run.
type from =
  | Cards(array<card>) // named by identity: move 8H 9S, moverun 8H 7S 6H T3
  | Top(place) // the card showing there: move C1 F1
  | Run(place) // the run showing there: moverun T6 T2

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
  // A move with a half only a *board* can resolve: a destination said as a card or a
  // label (`move 8H 9S`, `move 8H T3`), a source said as a place (`move C1 F1`), or
  // both. `resolveFrom`/`resolveWhere` read the pair against a board and `moveAction`
  // turns what comes back into the action a `Dispatch` would have carried, so a resolved
  // move is the same move, not a second kind of one.
  | MoveTo({from: from, where: where})
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
  // A prefix that fits more than one verb (`h` is `help` and `home`) — refused by name
  // rather than resolved to whichever came first in the table. See `resolveVerb`.
  | Ambiguous({verb: string, matches: array<string>})
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

// A source token: a pile index, a slot label, or a card named outright. Indices and
// labels first, in `parseWhere`'s order and for its reason — the three grammars don't
// overlap (a card is rank-then-suit, a label is letter-then-digits, an index is neither),
// so the order is only ever a matter of which test is cheapest.
let parsePlace = (token: string): option<place> =>
  switch digits(token) {
  | Some(i) => Some(AtPile(i))
  | None => Slot.parse(token)->Option.map(((role, ordinal)) => InSlot({role, ordinal}))
  }

// Read a move's source. `~run` is the verb asking: `move` lifts the card showing at a
// place, `moverun` the run showing there — the same place, read at the length its verb
// moves.
let parseFrom = (~run: bool, token: string): option<from> =>
  switch CardText.parse(token) {
  | Some(card) => Some(Cards([card]))
  | None => parsePlace(token)->Option.map(place => run ? Run(place) : Top(place))
  }

let notACard = (token: string) => `Not a card: "${token}" (try AS, TH, KD).`
let notASource = (token: string) =>
  `Not a card or a place to move from: "${token}" (a card like AS, a column like T3 or C1, or a pile index).`
let notAPile = (token: string) =>
  `Not a place to move to: "${token}" (a pile index, a column like T3, the card to land on like 9S, or "table").`

let settingNames = () => Options.all->Array.map(Options.name)->Array.join(", ")
let notASetting = (token: string) => `Not a setting: "${token}" (${settingNames()}).`
let notAFlag = (token: string) => `Not on or off: "${token}".`

// --- Verbs, and how little of one you have to type ----------------------------
// A console is typed at over and over, and what gets typed is nearly always the same
// handful of words. `move` earned its `m` early (see the `move` branch below) and
// nothing else did, which left `p` an unknown command in a panel where `m` worked — a
// half-rule you have to memorise rather than guess.
//
// So the verbs are a table, and **any unambiguous prefix of one is that verb**: `p`
// prints, `u` undoes, `de 12345` deals. Two rules keep that honest:
//
//   - a whole word always wins over a prefix, so no verb can be shadowed by a longer
//     one that happens to begin the same way (`set` is `set`, never `settings`-ish);
//   - a prefix that fits two verbs is **refused by name** — `h` says it could be `help`
//     or `home` — rather than resolved to whichever sits first in the table. A console
//     that guesses is one you can't trust a one-letter command with, and the refusal
//     teaches the next letter to type.
//
// The pinned aliases are a second tier, consulted only when nothing canonical matched:
// `m` stays `move` though three verbs begin with it, `new`/`list`/`board` keep working,
// and so does `n`, which no canonical verb claims. Canonical names having first say is
// what keeps `s` on `set` rather than on `show`.
let verbs = [
  "help",
  "games",
  "print",
  "clear",
  "quit",
  "undo",
  "redo",
  "redeal",
  "finish",
  "deal",
  "move",
  "moverun",
  "movecol",
  "home",
  "set",
]

// The pinned spellings, each with the verb it *is*. Two kinds live here: the shorthands
// a prefix rule can't give (`m` fits three verbs) and the second names a verb has always
// answered to (`new`, `restart`, `board`).
let aliases = [
  ("m", "move"),
  ("mv", "move"),
  ("list", "games"),
  ("board", "print"),
  ("show", "print"),
  ("cls", "clear"),
  ("exit", "quit"),
  ("new", "deal"),
  ("restart", "redeal"),
]

type resolvedVerb =
  | Verb(string) // the canonical name, whatever was typed
  | AmbiguousVerb(array<string>) // the verbs a prefix fit, in table order
  | NoSuchVerb

// The distinct verbs a token is a prefix of, in table order — `moverun` and `mv` both
// answering "move" is one match, not two.
let prefixMatches = (table: array<(string, string)>, token: string): array<string> =>
  table
  ->Array.filter(((name, _)) => name->String.startsWith(token))
  ->Array.reduce([], (found, (_, verb)) =>
    found->Array.includes(verb) ? found : Array.concat(found, [verb])
  )

let resolveVerb = (token: string): resolvedVerb => {
  let t = token->String.toLowerCase
  let canonical = verbs->Array.map(v => (v, v))
  switch (verbs->Array.find(v => v == t), aliases->Array.find(((a, _)) => a == t)) {
  | (Some(v), _) => Verb(v)
  | (None, Some((_, v))) => Verb(v)
  | (None, None) =>
    switch prefixMatches(canonical, t) {
    | [v] => Verb(v)
    | [] =>
      switch prefixMatches(aliases, t) {
      | [v] => Verb(v)
      | [] => NoSuchVerb
      | many => AmbiguousVerb(many)
      }
    | many => AmbiguousVerb(many)
    }
  }
}

// Parse one command line. Total: every line yields a `t`, malformed ones included.
let parse = (line: string): t => {
  let toks = tokenize(line)
  let arg = i => toks->Array.get(i)
  switch toks->Array.get(0) {
  | None => Blank
  | Some(token) =>
    switch resolveVerb(token) {
    | NoSuchVerb => Unknown({verb: token->String.toLowerCase})
    | AmbiguousVerb(matches) => Ambiguous({verb: token->String.toLowerCase, matches})
    | Verb(verb) =>
      switch verb {
      | "help" => Help
      | "games" => Games
      | "print" => Print
      | "clear" => Clear
      | "quit" => Quit
      | "undo" => Undo
      | "redo" => Redo
      | "redeal" => Redeal
      | "finish" => Finish
      | "deal" => Deal({game: arg(1), scenario: arg(2)})
      // Everything downstream of the verb table says `move`, whichever of `move`/`mv`/`m`
      // was typed (see `resolveVerb`): the `Usage` complaints and the "deal a game first"
      // hint that keys off the verb all name the canonical one, so a shorthand can't drift
      // into a second command with its own messages.
      | "move" =>
        // Arity before content, so `move AS` asks for the usage line rather than
        // complaining about a target that isn't there.
        switch (arg(1), arg(2)) {
        | (Some(fromTok), Some(whereTok)) =>
          switch (parseFrom(~run=false, fromTok), parseWhere(whereTok)) {
          | (None, _) => Usage({verb: "move", message: notASource(fromTok)})
          | (_, None) => Usage({verb: "move", message: notAPile(whereTok)})
          // A named card sent to a pile index needs no board, so it parses all the way to
          // the action, exactly as it always has; every other combination names something
          // only a board can point at and waits for one.
          | (Some(Cards([card])), Some(At(to))) => Dispatch(Reducer.Move({card, to}))
          | (Some(from), Some(where)) => MoveTo({from, where})
          }
        | _ =>
          Usage({
            verb: "move",
            message: "Usage: move <card|place> <where>   (e.g. move AS 0, move AS T3, move 2H 3C, move C1 F1, or move AS table)",
          })
        }
      // Bare `set` shows the flags; `set <setting> on|off` changes one. Arity before content
      // here too, so `set autocollect` asks for the usage line rather than complaining about
      // a value that isn't there.
      | "set" =>
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
      | "home" =>
        switch arg(1) {
        | Some(cardTok) =>
          switch CardText.parse(cardTok) {
          | Some(card) => Home({card: card})
          | None => Usage({verb: "home", message: notACard(cardTok)})
          }
        | None => Usage({verb: "home", message: "Usage: home <card>   (e.g. home AS)"})
        }
      | "moverun" =>
        // Everything after the verb is the run's cards, bottom-first, then the target —
        // unless the run is named by the *place* it's showing (`moverun T6 T2`), which is one
        // token where the cards would be several.
        let rest = toks->Array.slice(~start=1, ~end=Array.length(toks))
        if Array.length(rest) >= 2 {
          let targetTok = rest->Array.getUnsafe(Array.length(rest) - 1)
          let sourceToks = rest->Array.slice(~start=0, ~end=Array.length(rest) - 1)
          // A lone source token that isn't a card is the place the run is showing in. Only a
          // lone one: `moverun T6 T7 T2` names two places and no run, which is a `Usage`
          // rather than a guess about which of them was meant.
          let place = switch sourceToks {
          | [only] => CardText.parse(only)->Option.isNone ? parsePlace(only) : None
          | _ => None
          }
          let parsed = sourceToks->Array.map(CardText.parse)
          switch (place, parsed->Array.some(Option.isNone), parseWhere(targetTok)) {
          | (Some(_), _, None) | (None, false, None) =>
            Usage({verb: "moverun", message: notAPile(targetTok)})
          | (Some(place), _, Some(where)) => MoveTo({from: Run(place), where})
          | (None, true, _) =>
            Usage({
              verb: "moverun",
              message: `Not all of those are cards or a place to move from (try AS, TH, KD, or a column like T6).`,
            })
          | (None, false, Some(At(to))) =>
            Dispatch(Reducer.MoveRun({cards: parsed->Array.filterMap(c => c), to}))
          // A run takes its destination the same three ways a single card does — there's no
          // reason `moverun 8H 7S 6H T3` should be the one move you have to count piles for.
          | (None, false, Some(where)) =>
            MoveTo({from: Cards(parsed->Array.filterMap(c => c)), where})
          }
        } else {
          Usage({
            verb: "moverun",
            message: "Usage: moverun <card>… <where>   (e.g. moverun 8H 7S 6H 5, or moverun T6 T2)",
          })
        }
      | "movecol" =>
        switch (arg(1), arg(2)) {
        | (Some(fromTok), Some(toTok)) =>
          switch (digits(fromTok), digits(toTok)) {
          | (Some(from), Some(to)) => Dispatch(Reducer.MoveColumn({from, to}))
          | _ =>
            Usage({
              verb: "movecol",
              message: `Not a pile index (try two indices, e.g. movecol 8 15).`,
            })
          }
        | _ =>
          Usage({
            verb: "movecol",
            message: "Usage: movecol <from> <to>   (pile indices, e.g. movecol 8 15)",
          })
        }
      // Unreachable: `resolveVerb` only ever answers with a name from the table above.
      | _ => Unknown({verb: token->String.toLowerCase})
      }
    }
  }
}

// The prose for an unknown verb — one string, so both front ends say the same thing
// to the same typo.
let describeUnknown = (verb: string): string =>
  `Unknown command: ${verb}. Type "help" for the commands.`

// "a, b or c" — the tail of the refusal below, and the only place the grammar has to
// say a list in prose.
let orList = (items: array<string>): string =>
  switch items {
  | [] => ""
  | [only] => only
  | many =>
    `${many
      ->Array.slice(~start=0, ~end=Array.length(many) - 1)
      ->Array.join(", ")} or ${many->Array.getUnsafe(Array.length(many) - 1)}`
  }

// A prefix that fit more than one verb, named rather than guessed at — see `resolveVerb`
// for why refusing is the point. Shared prose, like every other complaint here, so the
// same half-typed word reads the same in a terminal and in the panel.
let describeAmbiguous = (~verb: string, ~matches: array<string>): string =>
  `Ambiguous command: "${verb}" could be ${orList(matches)}. Type enough to tell them apart.`

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
// The pile a slot label names on this board, or why it names none. Shared by the two
// halves of a move, because `C1` has to mean the same cell whether cards are coming out
// of it or going into it.
let resolveSlot = (~game: Game.t, ~role: Game.role, ~ordinal: int): result<int, string> =>
  switch Slot.indexOf(~game, ~role, ~ordinal) {
  | Some(i) => Ok(i)
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

let resolveWhere = (~game: Game.t, state: GameState.t, where: where): result<
  Reducer.target,
  string,
> =>
  switch where {
  | At(target) => Ok(target)
  | Slot({role, ordinal}) =>
    switch resolveSlot(~game, ~role, ~ordinal) {
    | Ok(i) => Ok(Reducer.ToPile(i))
    | Error(message) => Error(message)
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

// --- Resolving a source against a board ---------------------------------------
// The same job for the other half of a move. `move C1 F1` says which *place* to lift
// from and lets the board say which card that is — the reading a player does for
// themselves today, and the one thing on a printed board that is genuinely written down
// (the label is over the column; the card's name is not).

// What to call a place in a refusal: its label where the board prints one, and its bare
// index where it doesn't (a loose-table game's piles have no slot names).
let placeLabel = (~game: Game.t, place: place): string =>
  switch place {
  | InSlot({role, ordinal}) => Slot.format(~role, ~ordinal)
  | AtPile(i) => Slot.labelAt(~game, i)->Option.getOr(`pile ${Int.toString(i)}`)
  }

// The pile a place names, or why it names none — `resolveSlot` for a label, a range
// check for a bare index.
let resolvePlace = (~game: Game.t, place: place): result<int, string> =>
  switch place {
  | InSlot({role, ordinal}) => resolveSlot(~game, ~role, ~ordinal)
  | AtPile(i) =>
    switch game.piles->Array.get(i) {
    | Some(_) => Ok(i)
    | None =>
      Error(
        `No such pile: ${Int.toString(i)} (this board has ${Int.toString(
            Array.length(game.piles),
          )}, 0–${Int.toString(Array.length(game.piles) - 1)}).`,
      )
    }
  }

// The longest run showing at the top of a pile: the cards a player would lift if they
// took hold of the deepest card that still heads an ordered run — which is what
// `moverun T6 T2` names. Read under that pile's *own* rule, so a game whose cascades
// stack differently is answered in its own terms rather than in FreeCell's, and it stops
// at what *is* a run rather than at what may legally move: whether the run is too long
// for the free cells is the reducer's verdict (`RunTooLong`), not the reader's.
let runShowing = (~game: Game.t, state: GameState.t, i: int): array<card> =>
  switch game.piles->Array.get(i) {
  | None => []
  | Some(pile) =>
    let cards = GameState.cardsInPile(state, i)
    let count = Array.length(cards)
    let rec longest = (start: int): array<card> =>
      if start <= 0 {
        cards
      } else if Rules.isRun(pile.rule, cards->Array.slice(~start=start - 1, ~end=count)) {
        longest(start - 1)
      } else {
        cards->Array.slice(~start, ~end=count)
      }
    count == 0 ? [] : longest(count - 1)
  }

// Turn a `from` into the cards a move lifts, or say why this board offers none there.
// Cards named outright are handed straight back — the board has no say in what `8H`
// means — which is what keeps the original grammar exactly as it was.
let resolveFrom = (~game: Game.t, state: GameState.t, from: from): result<array<card>, string> => {
  let lift = (place, pick) =>
    switch resolvePlace(~game, place) {
    | Error(message) => Error(message)
    | Ok(i) =>
      switch pick(i) {
      | [] => Error(`${placeLabel(~game, place)} is empty.`)
      | cards => Ok(cards)
      }
    }
  switch from {
  | Cards(cards) => Ok(cards)
  | Top(place) => lift(place, i => GameState.topOf(state, i)->Option.mapOr([], card => [card]))
  | Run(place) => lift(place, i => runShowing(~game, state, i))
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
// The reason alone: a phrase with no subject and no full stop, for a caller whose line
// above already said *which* move this is. The web console's rejection is two lines —
// `move 10♣ → F1 ✗` and then the reason — and repeating the move in the second one would
// say the card twice, in two spellings, one line apart.
let reason = (err: Reducer.moveError): string =>
  switch err {
  | Reducer.Rejected => "can't stack there"
  | Reducer.PileFull => "that pile is full"
  | Reducer.LooseNotAllowed => "this game keeps cards in piles — no loose drops"
  | Reducer.NoSuchPile => "no such pile"
  | Reducer.CardNotFound => "that card isn't in play"
  | Reducer.NotARun => "those cards aren't an ordered run"
  | Reducer.RunTooLong => "that run is longer than the free cells and empty columns allow"
  | Reducer.NotAColumn => "that pile isn't a cascade column"
  | Reducer.CardBuried => "that card is buried — only the card on top of a pile can be moved"
  | Reducer.NotASpan => "those cards aren't lying together at the top of one pile"
  }

// The same, as a sentence that stands on its own: the phrase, prefixed, and naming the
// card in the two cases that read better for it. What a terminal says, where there's no
// line above to lean on — and, being built from `reason`, a refusal the two front ends
// can't drift apart on.
let describeError = (err: Reducer.moveError, card: card): string =>
  switch err {
  | Reducer.Rejected => `Rejected: ${CardText.format(card)} can't stack there.`
  | Reducer.CardNotFound => `Rejected: ${CardText.format(card)} isn't in play.`
  // The mirror of `resolveWhere`'s refusal for a buried *destination*, said about the
  // card being lifted — so "buried" reads the same at either end of a move.
  | Reducer.CardBuried =>
    `Rejected: ${CardText.format(card)} is buried — only the card on top of a pile can be moved.`
  | _ => `Rejected: ${reason(err)}.`
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
  ("move <what> <where>", "move a card (`mv`/`m` for short) — see the two columns below"),
  ("move <card> table", "move a card loose onto the table (free games only)"),
  (
    "moverun <what> <where>",
    "supermove an ordered run: its cards bottom-first, or the column it's showing in (moverun T6 T2)",
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
What to move is one of:
  a card         the card itself, wherever it is — move 8H T3
  a slot name    whatever is showing there — move C1 F1 (the card in the first free cell)
  a pile index   the same, by absolute position — move 11 F1
A destination is one of:
  a slot name    the label above the column — T3 (tableau), C1 (free cell), F2 (foundation)
  a card         the card to land on, wherever it is — move 2H 3C
  a pile index   the absolute position — move 2H 11
  table          loose on the table (free games only)
Any verb may be shortened to an unambiguous prefix: p prints, u undoes, de 12345 deals.`

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
