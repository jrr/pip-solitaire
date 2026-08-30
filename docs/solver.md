# The solver

`core/src/Solver.res` is a best-first search over `core/src/Position.res` — the
"brain" every driver in the repo plays with. A hint button, the `autoplay`
command in both front ends, the browser harness that plays a deal end to end,
and the tests that need a game played through all reach the same two modules.

This page carries the contract, the benchmark record, the heuristic, and the
measured case for making it faster. The code keeps the knobs.

## The contract

**The goal isn't a won board — it's `Position.canFinish`.** That's the point
where the app's own Finish button lights up and everything left is a
foundation-only drain. It's the real end of the *thinking* part of a game, and
stopping there keeps the search shallow: no driver needs a plan for the sweep,
because every driver already has one.

**Good enough, not optimal.** It looks for a line that wins, not the shortest
one. Nothing here promises a solution either: FreeCell has unsolvable deals, and
`solve` returns `None` when the ladder runs out rather than pretending
otherwise. A `None` proves nothing about the deal — only that these four rungs
didn't crack it.

**No clock.** `Solver.effort` reports positions, moves and passes; how *long* a
solve took is the caller's own measurement, taken around a call it made. That's
what lets a plan stay a value two runs can be expected to agree on — an ordinary
`toEqual` in a test, rather than a timing-shaped hole in one.

## Measuring it

```
mise run solve                    # deal 1, with the line printed
mise run solve -- 24680           # a particular deal
mise run solve -- --quiet 1-1000  # a soak: just the summary line
```

`mise run solve` is the solver with nothing attached — no browser, no bundle, no
drags. `mise run autoplay` is the same brain playing the real app through the
DOM and takes about a minute a deal; this takes milliseconds. **It's what you
measure a heuristic change with**, and how you find out whether a deal is one
the ladder can't crack. It exits non-zero if any deal goes unsolved.

## The benchmark record

Deals are dealt by `Game.freecellDeal`, so this is core's own shuffle, not
Microsoft's numbering. "Moves" counts moves to the *finishable* board, not to a
won one.

| Date | Deals | Solved | Mean | Mean moves | Worst | Environment |
|---|---|---|---|---|---|---|
| 2026-08-29 | 1–1000 | 1000/1000 | 101 ms | 54 | #582 at 7.2 s | Node v26.7.0, CI runner |

Method: `mise run solve -- --quiet 1-1000`, one process, timed per deal by
`solve.mjs` around its own `Solver.planSteps` call. The mean hides a long tail —
most deals fall to the first rung of the ladder in well under 100 ms, and the
handful that don't are what the wider rungs and the whole worst-case number are
about.

Add a row rather than editing one. Two runs on different machines are two
different facts, and a heuristic change is worth a soak beside the run it
replaces.

## The heuristic

A distance-to-go estimate. Four things make a position bad:

| Term | Weight | What it charges for |
|---|---|---|
| `remaining` | 2 | every card still off the foundations |
| `buried` | 2 | each card sitting on top of one a foundation is waiting for |
| `seam` | 1 | each break in a column's descending alternating run |
| `cell` | 3 | each loaded free cell — a card parked is a card in the way |
| `emptyColumn` | 3 | *credited*, not charged: room to manoeuvre |

The weights are a named record (`Solver.weights`) that `search` takes as an
argument, which is how they were chosen — measured rather than guessed.

**The two that earned their keep are the mobility terms**, `cell` and
`emptyColumn`. Without them the search cheerfully plays itself into positions
with nowhere to move, and the stubborn deals cost tens of seconds instead of
under one. If you're tempted to simplify the heuristic down to "cards not yet
home", that's the experiment that has already been run.

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
- **Two prunings in `legalMoves`** that only ever cost time: a card may go to the
  *first* empty free cell (the other empty cells are the same move), and a whole
  column may not move into an empty one (that only renames the column).

### The ladder

`solve` escalates until a rung gives, or the rungs run out:

| Pass | `weight` | `maxNodes` |
|---|---|---|
| 1 | 2.0 | 60,000 |
| 2 | 1.0 | 150,000 |
| 3 | 4.0 | 150,000 |
| 4 | 0.5 | 400,000 |

A high `weight` is greedy and dives; a low one searches wider and costs more per
answer. The first pass is mildly greedy because almost every deal falls to it.

**The rungs are capped deliberately.** A rung that can't find a line inside its
budget is usually a rung that never will, and the wasted nodes were most of the
old worst case. Raising a cap is the obvious knob and mostly buys nothing —
measure it over a soak before believing otherwise.

## The packed position

`GameState.t` is the game's real snapshot and stays the source of truth.
`Position.t` is the same board squeezed into ints — four free cells, four
foundation ranks, eight columns of card numbers, each card `suit * 13 + (rank −
1)` in 0…51.

The packing exists for one reason: **a search asks "and then what?" hundreds of
thousands of times per deal**, and the honest `GameState` transition — which
searches every pile for a card by identity and rebuilds sixteen arrays per move
— is far too slow to be asked that often.

**Nothing in `Position` is a second set of rules.** Every predicate is the packed
reading of one in `Rules`/`Reducer`, and `Position_test` pins them together by
playing a solved game through both:

| `Position` | mirrors | and it matters because |
|---|---|---|
| `cascadeAccepts` / `foundationAccepts` | `Rules.cascade` / `Rules.foundation` | a planned move has to be one the board takes |
| `maxSupermove` | `Reducer.maxSupermove` — `(1 + emptyCells) × 2^emptyCascades`, destination excluded | a planned run move is one the reducer will actually take |
| `autoCollect` / `isSafeToCollect` | `Reducer.autoCollect` — on by `Options.default` | the board *after* a move usually isn't just that move applied |
| `canFinish` | `Reducer.canFinish` | it's the goal, and where the drivers stand aside |

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

- **Soak it.** `mise run solve -- --quiet 1-1000` and add a row to the table
  above. A change that helps the mean and doubles the worst case is not an
  improvement.
- **Check the mirror.** If you touched `Position`, `Position_test` plays a solved
  game through both models — that's the test that catches a predicate drifting
  from the `Rules`/`Reducer` it mirrors.
- **Weights are arguments, not constants.** `search` takes them, so a new tuning
  can be measured against `defaultWeights` without editing anything.
- **Play one for real.** `mise run autoplay -- <deal>` runs the plan through the
  actual app, which is the only thing that checks `Position.toAction` still lands
  where the plan meant.
