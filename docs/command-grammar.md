# The typed-command grammar

One line of text, typed at a prompt, becomes a move on the board. Two front
ends take those lines — the CLI's `play` loop and the web app's debug console —
and they take the *same* ones: `move 8H 9S` has to mean one thing in a terminal
and in the panel, or the console is a second game that merely looks like this
one.

So the grammar lives in `core`, not in either front end:

| Module | What it owns |
|---|---|
| `core/src/Command.res` | the grammar — parsing, the board-side readers, and every refusal's prose |
| `core/src/CardText.res` | how a card is named (`AS`, `TH`, `KD`) |
| `core/src/Slot.res` | how a column is named (`T3`, `C1`, `F2`) |
| `core/src/Session.res` | `step`, the shared interpreter for the board verbs |
| `cli/src/Repl.res` | the terminal's chrome verbs, painting, the two loops |
| `web-app/src/debug/DebugConsole.res` + `Main.res` | the panel's chrome verbs and its runner |

This page carries the grammar itself: the vocabularies, the shapes, the verb
table, and the refusal policy. The code keeps the local rules a reader could
break. `packages/cli/README.md` is the player-facing command listing.

## The three steps

```
  "move 8H 9S"
        │
        │  Command.parse            pure. No board, no session, no I/O.
        ▼
  Command.t                         MoveTo({from: Cards([8H]), where: Onto(9S)})
        │
        │  Session.step             the board verbs, once, for both front ends.
        │    └─ Command.resolveFrom / resolveWhere   ← reads *this* board
        ▼
  Reducer.action                    Move({card: 8H, to: ToPile(12)})
        │
        │  Reducer.reduce           the sole judge of whether it is *legal*
        ▼
  a new GameState, or a typed moveError
```

**`parse` never sees a board.** That is the rule the module keeps, and it's what
makes the grammar testable from a string alone: reading the words and reading
the board are two steps, and only the second needs a game. So "is `8H` a card,
is `12` a pile" is settled by `parse`; "which pile is showing the Nine of
Spades" is settled after it; and "deal a game first" never appears in either,
because whether a session exists is not a property of the line.

Some board-shaped questions are nevertheless *shared* rather than each front
end's own — `move 8H 9S` must land on the same pile in both — so
`resolveFrom`/`resolveWhere` live in `Command` too, taking the board as an
argument rather than pretending to be pure.

Three verbs each front end answers for itself, because the answer is genuinely
its own: `help` (each has a few verbs of its own), `clear`/`quit` (a scrollback
and a session to leave), `set`, and `deal` — where a terminal opens a session
and the panel rebuilds a DOM board. Everything board-shaped goes to
`Session.step`, which reports a verb it doesn't play rather than swallowing it,
so a front end that forwards too much finds out.

## Three vocabularies that can't collide

A move's two argument positions each accept three kinds of token. They are
readable in any order because no token is two of them at once:

| Kind | Shape | Example |
|---|---|---|
| a card | rank then suit | `AS`, `TH` (or `10H`), `KD` |
| a slot label | role letter then a 1-based ordinal | `T3`, `C1`, `F2` |
| a pile index | digits, and nothing else | `0`, `11` |

**`Slot`'s letter-first scheme is what buys the disambiguation.** A card is
rank-then-suit, so a digit-first `3C` would be both the Three of Clubs and the
third free cell in the one place both can appear. `C3` can only ever be the
cell. Nothing else needs to be arranged: the parser tries indices, then labels,
then cards, and the order is only ever a matter of which test is cheapest.

The ordinal counts within its role, not across the board — `T1` is pile 8 on a
FreeCell board. Indices are what the reducer speaks; labels are the kinder way
to say one, and `Render` prints them above the columns so the move you can see
is the move you can type.

## Saying *where*

`Command.where`, in the order a player reaches for them:

```
move 8H 12    At    a pile index (the original, and the only one that needs
                    nothing but the line)
move 8H T3    Slot  the name printed above the column
move 8H 9S    Onto  the card to land on, wherever it happens to be
```

`Onto` is the one worth explaining. A player looking at the board is thinking
"the eight goes on the nine", not "the eight goes on pile 12" — the card is the
thing they can see, and the pile index is a fact about the model they have to
count out.

**It is checked rather than guessed.** `resolveWhere` accepts an `Onto` only
when *exactly one* pile is showing that card as its top card. Nought and more
than one are both refusals:

- not in play — `AS isn't in play.`
- lying loose on the table — not on a pile at all
- buried — only the card on top of a pile can be moved onto
- showing on several piles — named, with their labels, and "name the column
  instead"

A standard deck can't show the same card twice, so the ambiguous case is a guard
on the games that could — but it is the guard that lets the rule be stated
simply. A move that lands somewhere the player didn't name is worse than one
that doesn't happen.

## Saying *what*

`Command.from`, and its `place` half:

```
move 8H T3        Cards  named by identity — the original grammar, and still the
moverun 8H 7S 6H 5       precise one
move C1 F1        Top    the single card showing at that place
moverun T6 T2     Run    the whole ordered run showing at that place
```

Naming the *place* is what a player looking at the board reaches for, because
the board prints `C1` over the cell and prints nothing at all over "the Ten of
Clubs, which is the card currently in it".

**`Top` and `Run` are the same reading at two lengths, one per verb.** A `move`
never lifts a run behind the player's back; a `moverun` off a place lifts what a
player would grab if they took hold of the deepest card that still heads a run.

Two rules keep `Run` honest:

- The run is read under that pile's **own** rule (`Rules.isRun`), so a game whose
  cascades stack differently is answered in its own terms rather than in
  FreeCell's.
- It stops at what **is** a run, not at what may legally move. Whether the run is
  longer than the free cells and empty columns allow is the reducer's verdict
  (`RunTooLong`) — second-guessing it here would refuse moves the reducer would
  have taken.

`moverun` takes its cards bottom-first, then the destination. A *lone* source
token that isn't a card is read as a place; `moverun T6 T7 T2` names two places
and no run, so it's refused rather than guessed at.

## Verbs, and how little of one you have to type

The verbs are a table, and **any unambiguous prefix of one is that verb**: `p`
prints, `u` undoes, `de 12345` deals.

```
help  games  print  clear  quit  undo  redo  redeal
finish  autoplay  deal  move  moverun  movecol  home  set
```

Two rules keep the prefix rule honest:

1. **A whole word always wins over a prefix**, so no verb can be shadowed by a
   longer one that begins the same way — `set` is `set`, never `settings`-ish.
2. **A prefix that fits two verbs is refused by name.** `h` says it could be
   `help` or `home`, rather than resolving to whichever sits first in the table.
   A console that guesses is one you can't trust a one-letter command with, and
   the refusal teaches the next letter to type.

The pinned aliases are a **second tier**, consulted only when nothing canonical
matched:

| Alias | Verb | | Alias | Verb |
|---|---|---|---|---|
| `m`, `mv` | `move` | | `cls` | `clear` |
| `list` | `games` | | `exit` | `quit` |
| `board`, `show` | `print` | | `new` | `deal` |
| | | | `restart` | `redeal` |

Two kinds live there: the shorthands the prefix rule can't give (`m` fits three
verbs, so it has to be pinned) and the second names a verb has always answered
to. Canonical names having first say is what keeps `s` on `set` rather than on
`show`.

**Adding a name to `verbs` changes what every existing prefix means.** A second
`re…` verb makes `re` ambiguous for everyone who had been typing it.

Downstream of the table, everything says the canonical verb — the `Usage`
complaints and the front ends' "deal a game first" hint all key off it, so a
shorthand can't drift into a second command with its own messages.

## `deal`, and what its argument names

`parse` hands a `deal` argument through untouched, because *acting* on a deal
needs a front end. **Reading** it does not, and `Command.resolveDeal` is where
that reading happens — once, for both:

| Line | `dealt` |
|---|---|
| `deal` / `new` | `Fresh` — something new, from a seed the caller invents |
| `deal 12345` | `Numbered({seed})` — a FreeCell deal by number |
| `deal freecell` | `Named({game, position: None})` |
| `deal freecell midgame` | `Named({game, position: Some(_)})` |
| `deal nonesuch` | `NoSuchGame` — answered with the games list |
| `deal freecell nope` | `NoSuchScenario` — answered with that game's positions |

A deal number is **all** digits. `Int.fromString` is `parseInt` underneath and
would read `12abc` as 12, opening a board nobody asked for — which is why both
readers of a numeric token go through `Command.digits`. The same trap is what
makes `move 8H 4D` a real bug rather than an untidiness: a bare `Int.fromString`
would aim it at pile 4 instead of the Four of Diamonds.

Read a `deal` argument through `resolveDeal`, never in a front end. One resolver
is what lets the panel deal the games its own `games` command has always listed.

## Nothing fails; things are refused

**`parse` is total.** Every line yields a `Command.t`, malformed ones included,
which is what keeps a scrolling session from ever dead-ending. There are three
refusals, and each carries the prose to show:

| | When | Says |
|---|---|---|
| `Unknown({verb})` | no such verb | `Unknown command: frob. Type "help" for the commands.` |
| `Ambiguous({verb, matches})` | a prefix fitting several | `Ambiguous command: "h" could be help or home. Type enough to tell them apart.` |
| `Usage({verb, message})` | a known verb, arguments it couldn't read | the usage line, or what the offending token isn't |

**Arity before content.** `move AS` asks for the usage line rather than
complaining about a target that isn't there; `set autocollect` likewise. And
because `Usage` names the *verb* it choked on, an interpreter with no game dealt
can still answer "deal a game first" ahead of "that's not a card" — the ordering
of complaints stays where it belongs.

Every refusal's prose lives in `Command`, so the same half-typed word reads the
same in a terminal and in the panel.

### Two spellings of a rejection

A move the reducer refuses comes back as a typed `Reducer.moveError`, and there
are two ways to say one:

- **`Command.reason`** — the phrase alone, no subject and no full stop
  (`can't stack there`). For a caller whose line above already said *which* move
  this is: the web console prints `move 10♣ → F1 ✗` and then the reason, and
  repeating the card in the second line would say it twice, in two spellings, one
  line apart.
- **`Command.describeError` / `describeRejection`** — a sentence that stands on
  its own (`Rejected: 10♣ can't stack there.`), naming the card in the cases that
  read better for it. What a terminal says, where there is no line above to lean
  on.

The second is built from the first, so the two front ends can't drift apart on
what a refusal means.

## What each front end still owns

Shared help *rows* (`Command.boardHelp`, `dealHelp`, `driverHelp`) rendered by a
shared `renderHelp`, so the two listings can't disagree on what `moverun` does —
but each front end composes its own listing around them, because each has a few
verbs of its own:

- **the terminal** has `print` and `games`, `quit`/`exit` (only an interactive
  session is something you can leave), ANSI colour, and `#` comments in a piped
  script;
- **the panel** has `clear` (a terminal scrolls; the panel has a scrollback to
  empty), and answers `quit` with "press ` or esc to close the console" rather
  than acting on it.

That last one is the pattern: **a verb one front end can't act on is still a verb
both front ends know.** It answers rather than reporting an unknown command.

## Before you add a verb

1. **Does the reading need a board?** If not, it belongs in `parse`. If it does
   and both front ends need the same answer, it belongs beside
   `resolveWhere`/`resolveFrom` — not in a front end.
2. **Check what the new name does to the prefix table.** A second verb sharing a
   prefix makes that prefix ambiguous for everyone.
3. **Put the help row in `Command`** if both front ends offer the verb. A row in
   a front end is a row the other one will drift from.
4. **Write the refusal in `Command` too**, and key it off the canonical verb, not
   off what was typed.
5. **Arity before content**, so a half-typed line gets the usage line rather than
   a complaint about an argument that isn't there.
6. **Refuse rather than guess.** Every ambiguity in this grammar is answered by
   naming the alternatives.
