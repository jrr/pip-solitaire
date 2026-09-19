# The solver

`core/src/Solver.res` is a best-first search over `core/src/Position.res` — the
"brain" every driver in the repo plays with. A hint button, the `autoplay`
command in both front ends, the browser harness that plays a deal end to end,
and the tests that need a game played through all reach the same two modules.

It plays two *laws* over more boards than two. A position carries a `law` —
`FreeCell` or `SimpleSimon` — that says whose rules it is the packed reading of,
and every predicate in `Position` and both terms of the heuristic that differ
are read under it. The search itself is the same code for both.

It also carries a `pack`: which suits are in play, how far the ranks run, and how
many cards that is altogether. That is what lets one law cover boards of
different sizes — Mini FreeCell's twenty cards over four columns and Micro's
sixteen in two suits are FreeCell's law at another size, not another game.

And it carries a `stock`, which is how Spiderette fits: it plays Simple Simon's
law between deals, so the law is not what makes it a different game — the
twenty-four cards still to come are. **A deal is a move like any other**, and
the search takes one when it chooses to, not when it may.

This page carries the contract, the benchmark record, the heuristic, and the
measured case for making it faster. The code keeps the knobs.

## The contract

**The goal isn't a won board — it's `Position.canFinish`.** That's the point
where the app's own Finish button lights up and everything left is a
foundation-only drain. It's the real end of the *thinking* part of a game, and
stopping there keeps the search shallow: no driver needs a plan for the sweep,
because every driver already has one.

Under Simple Simon there is no drain — the foundations are sealed, and a run
reaches one only by being collected — so the only finishable board is the won
one, and the line runs to the win itself. That is why its lines are twice as
long as FreeCell's and its ladder is its own. Spiderette is that law with
twenty-four more cards arriving seven at a time, so its lines are longer again
and its ladder is its own for the same reason.

**Good enough, not optimal.** It looks for a line that wins, not the shortest
one. Nothing here promises a solution either: both games have deals with no
line, and `solve` returns `None` when the ladder runs out rather than pretending
otherwise. A `None` proves nothing about the deal — only that these rungs
didn't crack it — *unless* the effort says `exhausted`: a rung that emptied its
frontier saw every position reachable from the start, and none of them
finishes. That is a proof, and `Solver.autoplay` answers it as `Unwinnable`
rather than `NoLine`. It is not a rare answer: about one Simple Simon deal in
twelve is stuck within a few dozen positions of the deal, and the search says so
in a millisecond. The short packs make it commoner still and cheaper still —
eight Mini deals and nineteen Micro ones in the first thousand, none of them
taking longer than the deal it was dealt from.

**No clock.** `Solver.effort` reports positions, moves and passes; how *long* a
solve took is the caller's own measurement, taken around a call it made. That's
what lets a plan stay a value two runs can be expected to agree on — an ordinary
`toEqual` in a test, rather than a timing-shaped hole in one.

## What the solver sees

**It peeks.** A Klondike-dealt board lies partly face down, and `GameState`
holds those cards' identities, so the packed position carries them too and the
search reads them like any other card. What the face-down count buys is the one
thing turning a card over actually changes: a hand takes hold only of what lies
above the boundary, so a run reads up to it and stops (`Position.runLength`,
`Reducer.isSpan`), and a move that uncovers a card leaves it face up, because the
reducer turns it over as part of that move. The alternative is a different
program — a search under uncertainty, where `Position.key` no longer identifies a
board and a plan can be invalidated by the card it turns over — and nothing in
`Solver` is shaped for that. What peeking costs is not technical but
player-facing: **a hint that peeks is a hint that knows where the Ace is.**
Whether the game may offer a hint, or autoplay, on a board with cards face down
is therefore the front end's question and is still open; `mise run solve`, the
harness and the tests all want the solver that sees everything, and that is the
one they get.

## Measuring it

```
mise run solve                    # deal 1, with the line printed
mise run solve -- 24680           # a particular deal
mise run solve -- --quiet 1-1000  # a soak: just the summary line
mise run solve -- --game simplesimon 1-1000 --quiet   # the other law
mise run solve -- --game mini --quiet 1-1000          # the short packs
mise run solve -- --game spiderette4 --quiet 1-200    # the board that deals
```

`mise run solve` is the solver with nothing attached — no browser, no bundle, no
drags. `mise run autoplay` is the same brain playing the real app through the
DOM and takes about a minute a deal; this takes milliseconds. **It's what you
measure a heuristic change with**, and how you find out whether a deal is one
the ladder can't crack. It exits non-zero if any deal goes unsolved — a deal
proved unwinnable is answered, not unsolved, and the summary line counts the two
apart.

## The benchmark record

Deals are dealt by `Game.freecellDeal` and `Game.simpleSimonDeal`, so this is
core's own shuffle, not Microsoft's numbering. "Moves" counts moves to the
*finishable* board — for Simple Simon, the won one.

**FreeCell**

| Date | Deals | Solved | Mean | Mean moves | Worst | Environment |
|---|---|---|---|---|---|---|
| 2026-08-29 | 1–1000 | 1000/1000 | 101 ms | 54 | #582 at 7.2 s | Node v26.7.0, CI runner |
| 2026-09-10 | 1–1000 | 1000/1000 | 62 ms | 54 | #582 at 4.6 s | Node v26.7.0, Apple Silicon laptop |

**Simple Simon.** "Unwinnable" is the deals the search *proved* have no line
(`exhausted`); "unsolved" is the ones the ladder gave up on, which is the number
a heuristic change is trying to reduce.

| Date | Deals | Solved | Unwinnable | Unsolved | Mean | Mean moves | Worst | Environment |
|---|---|---|---|---|---|---|---|---|
| 2026-09-10 | 1–1000 | 941/1000 | 54 | 5 | 458 ms | 85 | #964 at 13.2 s | Node v26.7.0, Apple Silicon laptop |

**Mini and Micro**, under FreeCell's law and its weights. Every deal is
*answered* — the ladder's first rung either finds a line or empties its frontier
— so the number to watch here is "unsolved", and it is zero.

| Date | Board | Deals | Solved | Unwinnable | Unsolved | Mean | Mean moves | Worst | Environment |
|---|---|---|---|---|---|---|---|---|---|
| 2026-09-17 | Mini | 1–1000 | 992/1000 | 8 | 0 | <1 ms | 11 | #10 at 49 ms | Node v26.7.0, CI runner |
| 2026-09-17 | Micro | 1–1000 | 981/1000 | 19 | 0 | <1 ms | 10 | #699 at 8 ms | Node v26.7.0, CI runner |

Over deals 1–200 that is 198 and 196 solved — the same counts `Game.res` records
from an exhaustive single-card search when it chose two free cells for each
board, arrived at by a different method. A soak of a short pack costs about two
seconds for the thousand, so it is worth running beside the other two.

Method: `mise run solve -- --quiet 1-1000` (with `--game simplesimon` for the
second table), one process, timed per deal by `solve.mjs` around its own
`Solver.solveWithEffort` call. The mean hides a long tail — most deals fall to
the first rung of the ladder in well under 100 ms, and the handful that don't
are what the wider rungs and the whole worst-case number are about. The
FreeCell row of 2026-09-10 is the same ladder and weights as the row before it,
on a faster machine and with the third pruning (a run to the first empty column
only); it finds a line on every deal the earlier run did.

The five Simple Simon deals the ladder gives up on (#314, #320, #805, #957,
#964) are the record to beat: each costs the whole ladder, nine to thirteen
seconds, and none is known to be winnable. A proof of unwinnability is cheap by
comparison — the slowest of the 54 took 6.6 s, and most take a millisecond.

Add a row rather than editing one. Two runs on different machines are two
different facts, and a heuristic change is worth a soak beside the run it
replaces.

## The heuristic

A distance-to-go estimate: the same five terms under both laws, two of them
read differently.

| Term | FreeCell | Simple Simon | Spiderette | What it charges for |
|---|---|---|---|---|
| `remaining` | 2 | 0 | 0 | every card still off the foundations |
| `buried` | 2 | 1 | 1 | each card sitting on top of a *wanted* card |
| `seam` | 1 | 2 | 2 | each break in the run a hand could lift |
| `cell` | 3 | — | — | each loaded free cell — a card parked is a card in the way |
| `emptyColumn` | 3 | 4 | 4 | *credited*, not charged: room to manoeuvre |
| `stock` | — | — | 5 | every card still undealt |

What's *wanted* is the reading that differs. Under FreeCell it's the next card
each foundation needs. Under Simple Simon it's, for every run on the tableau,
the same-suit card one rank above the run's bottom — the card that run has to be
carried onto next; a run founded by a King wants nothing. And a *seam* is a
break in whatever holds a lifted run together: alternating colour under
FreeCell, one suit under Simple Simon — so a Seven lawfully dropped on an
Eight of another suit is a seam there, which is the whole game.

`stock` is the one term a board can be weighed by without its law changing.
Spiderette's record is Simple Simon's with that one number in it, and
`Solver.weightsFor` picks it by asking whether the board has a stock left to deal
from — a fact about the board, not its rules, so a Spiderette position whose
stock is out is weighed as the Simple Simon board it has become.

**`stock` is not a rounding term.** On the opening of deal #1, dealing a row
costs 46 under Simple Simon's weights — seven cards land on seven columns and
land mostly as seams, so by every other term the board just got worse. A search
weighed that way never deals at all: it spends its whole budget tidying a board
it can only win by dealing. Charging 5 a card pays back 35 of the 46, which is
what makes "get the row down" worth the mess it makes.

The weights are three named records (`Solver.freecellWeights`,
`Solver.simonWeights`, `Solver.spideretteWeights`) that `search` takes as an
argument, which is how they were chosen — measured rather than guessed. Three,
not five: the short packs were tuned on nothing, because they left nothing to
tune. Under FreeCell's own weights the first rung answers every Mini and Micro
deal in the first thousand, so a record of their own could only make a fast,
complete answer differently fast.

**The two that earned their keep are the mobility terms**, `cell` and
`emptyColumn`. Without them the search cheerfully plays itself into positions
with nowhere to move, and the stubborn deals cost tens of seconds instead of
under one. If you're tempted to simplify the heuristic down to "cards not yet
home", that's the experiment that has already been run.

Simple Simon's `remaining` is zero because it has nothing to steer: a run is
collected the moment it forms, never by choice, so the cards home never differ
between two moves the search is choosing between. Measured — the weight made no
difference to a single node over sixty deals — and set to zero so the table
says so. Its other three were the best of a first sweep of seven settings; none
of the seven moved the count of solved deals by more than two in sixty, and the
ladder's first rung turned out to matter far more (below).

## The search

Weighted best-first, from the start position to the first one that
`canFinish`. Priority is `g + weight · h`, where `g` is the path length.

- **The open list is a binary heap** (`Solver.Heap`), not a sorted array: it's
  pushed and popped hundreds of thousands of times per deal, and re-sorting it
  that often is the whole cost of the search.
- **The visited set is keyed by `Position.key`**, which sorts the cells and the
  columns first — two positions that differ only in *which* free cell or *which*
  column holds what are the same position. A position reached no more cheaply
  than before teaches nothing new and is dropped.
- **Three prunings in `legalMoves`** that only ever cost time, all of them
  symmetries the key already collapses: a card may go to the *first* empty free
  cell and a run to the *first* empty column (the other empties are the same
  move), and a whole column may not move into an empty one (that only renames
  the column). Nothing is pruned on a hunch — that would make `exhausted` a lie.

### The ladder

`solve` escalates until a rung gives, the rungs run out, or a rung *exhausts*
the position — after which no wider rung is climbed, since it would only search
the same finite space again. `Solver.ladderFor` picks one the same way
`weightsFor` does: the law, and then whether the board deals.

| FreeCell | `weight` | `maxNodes` | | Simple Simon | `weight` | `maxNodes` | | Spiderette | `weight` | `maxNodes` |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2.0 | 60,000 | | 1 | 1.0 | 100,000 | | 1 | 2.0 | 200,000 |
| 2 | 1.0 | 150,000 | | 2 | 2.0 | 150,000 | | 2 | 1.0 | 500,000 |
| 3 | 4.0 | 150,000 | | 3 | 0.5 | 400,000 | | | | |
| 4 | 0.5 | 400,000 | | | | | | | | |

A high `weight` is greedy and dives; a low one searches wider and costs more per
answer. FreeCell's first pass is mildly greedy because almost every deal falls to
it. Simple Simon's is *not*: over sixty deals, a first rung at 1.0 solved more
than one at 2.0 with two thirds of the nodes and shorter lines, and every
greedier setting solved fewer. The rungs above it are there for the handful the
first misses. Six whole ladders were then run over deals 1–100; this one was the
only one to leave nothing unsolved, and did it on the fewest nodes — a wider
final rung (0.5 at 400,000) caught the two deals every 0.7-at-300,000 ladder
gave up on, and a smaller first rung cost nothing.

Spiderette's is **budgeted rather than inherited**, which is the whole of why it
is two rungs and not three. A board with twenty-four cards to come is not
searched wide cheaply, so the first rung is greedy where Simple Simon's is not,
and the second is the whole of the extra effort it gets. A deal that beats
neither costs its full budget twice — that is the worst case in the table above,
and the price of a third rung would be paid on every one of them.

**The rungs are capped deliberately.** A rung that can't find a line inside its
budget is usually a rung that never will, and the wasted nodes were most of the
old worst case. Raising a cap is the obvious knob and mostly buys nothing —
measure it over a soak before believing otherwise.

## The packed position

`GameState.t` is the game's real snapshot and stays the source of truth.
`Position.t` is the same board squeezed into ints — the `law`, the `pack`, the
free cells, how many of each suit are home, the columns of card numbers, each
card `suit * 13 + (rank − 1)` in 0…51, how many of each column's cards lie
face down, and the `stock` still to be dealt (bottom-first, so the card the next
deal drops first is the last of them).

**The 13 there is the numbering, not the deck.** A short pack is numbered the
same way and simply leaves gaps: Micro's sixteen cards are ♠A…♠8 at 0…7 and
♥A…♥8 at 13…20. That keeps `isRed` a single range test, `suitOf` a division, and
`found` and the heuristic's scratch array four and fifty-two wide whatever the
board — sparse ids cost a few bytes and leave every predicate alone. A denser
numbering breaks all three at once.

`Position.lawOf` reads a `Game.t`'s law off its rules — the cascade rule, the
run limit, the collect policy, whether the foundations are sealed — and
`ofGameState` then reads the board: **the counts are the board's own**, and the
deck it carries is the pack. What is still refused is only what the packing
genuinely can't say — a second stock (`Reducer.stockOf` deals from the first and
the rest would sit there unplayable), a card loose on the table, a second copy of
a card (two copies pack to one int), ranks that don't run up from the Ace (a
foundation's *length* is read as the rank it has climbed to), fewer foundations
than the deck has suits, and a card face down anywhere but in a column or the
stock (a hidden card in a cell, or a column with nothing showing, is a board
whose top card no predicate could name). Spiderette · 4 suits is refused on
none of it; its one- and two-suit variants are refused on the repeated cards,
which is a different step. Mini and Micro are refused on none either.

The packing exists for one reason: **a search asks "and then what?" hundreds of
thousands of times per deal**, and the honest `GameState` transition — which
searches every pile for a card by identity and rebuilds sixteen arrays per move
— is far too slow to be asked that often.

**Nothing in `Position` is a second set of rules.** Every predicate is the packed
reading of one in `Rules`/`Reducer`, and `Position_test` pins them together by
playing a solved game through both:

| `Position` | mirrors | and it matters because |
|---|---|---|
| `cascadeAccepts` / `foundationAccepts` | `Rules.accepts` under `Rules.cascade` or `Rules.spiderCascade`; `Rules.foundation`, or `Sealed` | a planned move has to be one the board takes |
| `follows` / `runLength` | `Rules.isRun` — alternating colour, or one suit | what a grab lifts is what the plan said it would |
| `runLength`'s boundary, and `afterLifting` | `Reducer.isSpan`, which refuses a span reaching below a pile's face-down count, and `liftCard`, which turns over the card a move uncovers | a plan that lifted what no hand can see, or left a card face down that the board has turned over, comes apart on the next move |
| `liftLimit` / `maxSupermove` | `Reducer.withinRunLimit` — `(1 + emptyCells) × 2^emptyCascades` with the destination excluded, or unlimited | a planned run move is one the reducer will actually take |
| `autoCollect` — `collectSafeCards` / `collectRuns` | `Reducer.autoCollect` — on by `Options.default` | the board *after* a move usually isn't just that move applied |
| `isSafeToCollect`'s opposite colours | `Reducer.oppositeColorSuits` — read off the deck | Micro's ♠♥ pack has *one* suit of the other colour, and naming two stalls the collect above the Twos |
| `canDeal` / `dealRow` | `Reducer.dealRefusal` — no stock, stock empty, a cascade standing empty — and `Reducer.dealRow`, which lands one card per cascade left to right | a deal is a branch, not a formality: a search that deals whenever it may misses every line that makes room first |
| `canFinish` | `Reducer.canFinish` — the drain, or (with sealed foundations) the win itself | it's the goal, and where the drivers stand aside |

That last row is the one that bites. **A plan is a plan for a game played with
auto-collect on**, which is how the app ships. `Solver.autoplay` therefore does
the settling itself rather than leaving it to the caller: a driver with the flag
off would leave the board a card behind the plan, and every later move would
bounce off a pile the plan thought was empty. The flag governs what the
*player's* moves trigger, not what the solver's plan means.

## On making this faster — measured, then deferred

Asked in passing: would a WASM module be significantly faster? Profiled rather
than guessed — `node --cpu-prof` over deals 1–60 plus 1848, about thirty seconds
of solving. Self-time:

| | |
|---|---|
| 24.8% | the garbage collector |
| 19.2% | `search` itself — the loop, the visited map, the path array per node |
| 31.3% | `Position.key` — nine strings built and sorted per generated position |
| ~15% | the game: `legalMoves`, `applyMove`, `canFinish`, `autoCollect`, `heuristic` |

**So the arithmetic a rewrite in another language makes faster is about a
seventh of the runtime.** The rest is how a position is *represented*: string
keys, a fresh path array per node (`Array.concat`), and the allocation those two
imply.

Changing only those two — an FNV-1a-per-column numeric key, and parent pointers
instead of copied paths — measured ~1.9× over deals 1–60, finding the identical
line on every one of them. Re-profiled after that, the collector was still ~23%,
now behind `applyMove`'s `copy`; make/unmake against one mutable board would take
most of that too. **Call it 3–4× available without leaving the language, and the
rules untouched by any of it.**

What WASM adds on top is the usual 1.2–2× of integer loops over an optimising
JIT — and it costs the thing having the solver in `core` buys:

- The search asks `legalMoves` / `applyMove` / `canFinish` millions of times a
  deal, so the boundary **can't** sit between the search and the rules. The rules
  move into the module too, in whatever language it's written in, and `Position`
  becomes a mirror no unit test can pin — `Position_test` holds it against
  `Reducer` precisely because both sides are one build.
- It puts a second toolchain in `mise.toml`.
- It makes `Solver.autoplay` async. Browsers cap synchronous WebAssembly
  compilation at 4 KB on the main thread, and both front ends call it from inside
  a command that answers synchronously.

**Deferred deliberately: nothing is waiting on it.** If the budget is ever
wanted, spend it at the cheap end of that list first — and note that the reason
to want it is more likely a *shorter line* than a faster one, which is the trade
`weight` already makes.

## Before you change the solver

- **Soak it — every board.** `mise run solve -- --quiet 1-1000`, and again with
  `--game simplesimon`, `--game mini` and `--game micro`, and add a row to each
  table above. A change that helps the mean and doubles the worst case is not an
  improvement, and a change to the search or a shared term moves every board at
  once. The two short packs take about two seconds each, so there is no excuse.
  Spiderette is the expensive one — `--game spiderette4 --quiet 1-200` is half an
  hour, because the deals it gives up on each cost the whole ladder — so soak it
  over 1–200 rather than the thousand, and leave it running.
- **Check the mirror.** If you touched `Position`, `Position_test` plays a solved
  game through both models — that's the test that catches a predicate drifting
  from the `Rules`/`Reducer` it mirrors.
- **Weights are arguments, not constants.** `search` takes them, so a new tuning
  can be measured against `defaultWeights` without editing anything.
- **Play one for real.** `mise run autoplay -- <deal>` (and
  `-- --game simplesimon <deal>`) runs the plan through the actual app, which is
  the only thing that checks `Position.toAction` still lands where the plan
  meant. Not Spiderette: that harness reads the board off the rendered page and
  a face-down card has no name to read, so a board that deals is played by the
  in-app `autoplay` command instead — `mise run cli -- play spiderette4` and the
  web app's debug console, both of which read the board out of the game.
