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
measured case for making it faster. The code keeps the knobs. The search is a
value that can be grown, left and grown again (§ The search); the rest of what it
is becoming — following the board, budgeted in bytes — is designed in
`docs/solver-next.md`.

## The contract

**The goal isn't a won board — it's `Position.canFinish`.** That's the point
where the app's own Finish button lights up and everything left is a
foundation-only drain. It's the real end of the *thinking* part of a game, and
stopping there keeps the search shallow: no driver needs a plan for the sweep,
because every driver already has one.

Under Simple Simon there is no drain — the foundations are sealed, and a run
reaches one only by being collected — so the only finishable board is the won
one, and the line runs to the win itself. That is why its lines are twice as
long as FreeCell's and its budget is its own. Spiderette is that law with
twenty-four more cards arriving seven at a time, so its lines are longer again
and its budget is its own for the same reason.

**Good enough, not optimal.** It looks for a line that wins, not the shortest
one. Nothing here promises a solution either: both games have deals with no
line, and `solve` returns `None` when the budget runs out rather than pretending
otherwise. A `None` proves nothing about the deal — only that this budget
didn't crack it — *unless* the effort says `Exhausted`: a search that emptied its
frontier grew every position reachable from the start, and none of them
finishes. That is a proof, and `Solver.autoplay` answers it as `Unwinnable`
rather than `NoLine`. It is not a rare answer: about one Simple Simon deal in
twelve is stuck within a few dozen positions of the deal, and the search says so
in a millisecond. The short packs make it commoner still and cheaper still —
eight Mini deals and nineteen Micro ones in the first thousand, none of them
taking longer than the deal it was dealt from.

**No clock of its own.** `Solver.effort` reports positions and moves, and
never an elapsed time: how *long* a solve took is the caller's own measurement,
taken around a call it made. What the solver takes instead is a **`patience`** — a
wait, and the clock to measure it on. A caller that hands over a *stopped* clock,
as every test and every folded transcript does, gets back the plan the node
budgets alone would find, on every machine. That's what lets a plan stay a value
two runs can be expected to agree on — an ordinary `toEqual` in a test, rather
than a timing-shaped hole in one. What handing over a *real* clock buys, and
costs, is the next section.

## What a caller is willing to spend

The budget is in *positions*, and a position is not a unit anyone waits
in. Two hundred thousand of them is a fifth of a second of Mini and most of a
minute of four-suit Spiderette, and the same number again is one wait on a CI
runner and another on a phone. So the budget says how hard to try, and `patience`
says how long the caller will let that take:

```rescript
type patience = {ms: float, clock: unit => float}
```

Two are named in `Solver`, for **who is waiting** rather than for how long:

| | | |
|---|---|---|
| `interactive` | 10 s | a board someone is watching — passed by `TableScene` |
| `patient` | 120 s | a terminal or a script, where the waiting is the point — passed by `Cli` |

`interactive` is a **policy**, and it really does cost answers — § What the
interactive wait costs measures how many, and § Why the unsolved count stands is
the decision that came out of it. `patient` is a **backstop**: it sits above the
worst search any board's budget allows, so it bites only on a machine far slower
than the one the record was measured on.

**Neither front end waits on the thread it draws with.** The terminal has nothing
to draw; the web app sends the board to a worker (`web-app/src/platform/Thinker.res`)
and goes on painting, so `interactive` bounds a spinner rather than a freeze. It is
still a policy about a person's patience and still costs the answers measured below —
what it stopped being is the difference between a page and a hung page.

`mise run solve` passes whatever `--limit` says, and nothing at all by default,
which is what makes the benchmark record a measurement of the budget rather than
of a wait.

**The search keeps no time; the caller cuts it into slices.** `Solver.Search.think`
takes a number of positions and nothing else, and `Solver.solveOn` is the one place a
wait becomes slices of them: resolve the wait into a deadline, grow the search by
`Solver.clockEvery` positions, read the clock, and again, until the search answers or
the deadline passes. A search stopped by the deadline is still in hand, so a caller
that wants to wait longer asks `solveOn` again on the same search and it carries on —
`mise run solve -- --limit 10+10` is that, and a deal out of time after the first ten
seconds and solved in the second is the demonstration.

**The clock is read once every 1,024 positions**, not once per position: a search
grows hundreds of thousands of them and a clock read on each is a cost the answer
doesn't need. What it costs instead is an overshoot of up to those 1,024 positions
— and a position is not a fixed price, because a board with more legal moves grows
more children out of each one. Measured against a ten-second limit, the worst deal
of each board came back at 10,073 ms (Simple Simon), 10,130 ms (four-suit
Spiderette) and 10,326 ms (two-suit). **So a wait under about a second is not a
wait this can keep**; both named ones are far above that.

**Lowering `interactive` is a change to what the browser suite can play.**
`browser-tests/spiderette.spec.mjs` types `autoplay` on all three Spiderette packs
at `seed=1` and waits for the win overlay, so those three searches have to finish
inside it. They are not close to it — 69 ms, 907 ms and 771 ms on a loaded
four-core sandbox — but they are the floor, and the failure they'd give is a
missing overlay rather than anything that says "time".

### The three ways to come back with nothing

`Solver.effort` carries an `ending`, and only one of its refusals is a statement
about the board:

| `ending` | what happened | `autoplay` says |
|---|---|---|
| `Exhausted` | the frontier emptied: every reachable position was seen, and none finishes | `Unwinnable` — a proof |
| `OutOfNodes` | the search grew its `maxNodes` with positions still waiting | `NoLine` |
| `OutOfTime` | the caller's `patience` ran out, with the budget not yet spent | `OutOfPatience` |

They are `Search.answer`'s four with a clock read against it: `Full` is `OutOfNodes`,
and `Paused` — a slice spent with the frontier not — is `OutOfTime` once the deadline
has passed, and simply the next slice before then.

**The last two are not one answer in two moods.** `OutOfNodes` means the budget was
spent and gave up, which is the most this solver has to say about a deal.
`OutOfTime` means nobody finished looking — so it's the one refusal a more patient
caller might turn into an answer, and the front end says *that* rather than
reporting a verdict the search never reached (`Command.autoplayOutOfPatience`).
A proof outranks both: a frontier that empties on the last position before the
deadline is still a proof.

For a driver outside ReScript, `Solver.provedUnwinnable` and `Solver.ranOutOfTime`
ask the two questions worth asking, so that nothing outside the language depends on
how the compiler spells a constructor in the JavaScript it emits; `solve.mjs` counts
its deals by them.

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
mise run solve -- --game spiderette1 --quiet 1-200    # …and its repeated packs
mise run solve -- --game spiderette --quiet 1-200
mise run solve -- --game spider --limit 10 --quiet 1-5   # two packs: a probe, not a record
mise run solve -- --limit 10 --game spiderette4 --quiet 1-200   # …as a player waits for it
mise run solve -- --limit 10+10 --game spiderette4 147          # …and asks for ten more
```

`--limit` is a wait in seconds — the `patience` a driver would impose, so a soak can
be run the way a front end actually calls the solver. It is also how the expensive
boards are soaked in an evening rather than half a day, since a deal that beats the
budget stops costing the budget. Leave it off for anything destined for the benchmark
record: that table is a measurement of the budget, and a capped run measures the cap.
Several waits joined by `+` are asked one after another of the same search, each
carrying on from where the last stopped; the deal's time, effort and Held are all of
them together, and a deal that answers after the first says which ask it was.

`mise run solve` is the solver with nothing attached — no browser, no bundle, no
drags. `mise run autoplay` is the same brain playing the real app through the
DOM and takes about a minute a deal; this takes milliseconds. **It's what you
measure a heuristic change with**, and how you find out whether a deal is one
the budget can't crack. It exits non-zero if any deal goes unsolved — a deal
proved unwinnable is answered, not unsolved, and the summary line counts the two
apart. A deal that ran out of a `--limit` is unsolved like any other — the limit is
what the caller chose to spend, not a verdict on the board — and the summary says how
many of the unsolved were that.

**Every deal is also weighed.** Beside its time, each deal reports what the search
*held*, and the summary gives the mean over the range and the deal that held most —
the "Held" column in every table below. It is the live JavaScript heap with the search
still in hand once it has answered, less what was live before it was made — the heap
*and* the backing stores of typed arrays, which live outside it and are where the
search keeps its graph. **A search never releases what it has grown**, so that moment
is its largest; `solve.mjs` holds the search as a value, so it can run the collector
there, after the timed asks, and keep the collection out of the time. So the task runs
Node with `--expose-gc`, and collects until two readings agree: a column outgrown
just before the search stopped can linger in the count for a collection or two.

Beside each Held, in brackets, is what the search says it holds: `effort.bytes`,
summed from its own arrays' lengths (`Solver.Search.bytes`). The two agree to within a
megabyte on every deal, and the difference is what the arrays don't count — the
scratch board, the line, the search record itself.

Rows before 2026-09-30 are the restart ladder that search replaced, and were measured
differently to the same end: a rung that spent its budget was released for the next,
so each deal was solved twice, the repeat replaying the timed run's clock to collect
at the last read of every rung. The ladder re-run with its own script on the
2026-09-30 machine gave FreeCell's 2026-09-29 figures back exactly (4 MB, #582 at
334 MB), so the column reads across the change.

What it counts: every position, frontier entry and map key the search can still
reach. What it doesn't: the garbage made along the way (the collector's time shows in
the milliseconds instead) and anything a larger heap costs a process beyond the heap
itself. It is in megabytes of a million bytes.

It is the same *kind* of number as the 379 MB in § On making this faster — V8's live
heap after a full collection — but not the same measurement: that was a browser heap
snapshot over a fixed 100,000 nodes of one Spider position, and this is a whole deal's
search in Node.

## The benchmark record

Deals are dealt by `Game.freecellDeal` and `Game.simpleSimonDeal`, so this is
core's own shuffle, not Microsoft's numbering. "Moves" counts moves to the
*finishable* board — for Simple Simon, the won one.

**FreeCell**

| Date | Deals | Solved | Mean | Mean moves | Worst | Held | Environment |
|---|---|---|---|---|---|---|---|
| 2026-08-29 | 1–1000 | 1000/1000 | 101 ms | 54 | #582 at 7.2 s | — | Node v26.7.0, CI runner |
| 2026-09-10 | 1–1000 | 1000/1000 | 62 ms | 54 | #582 at 4.6 s | — | Node v26.7.0, Apple Silicon laptop |
| 2026-09-19 | 1–1000 | 1000/1000 | 107 ms | 54 | #582 at 7.4 s | — | Node v26.7.0, CI runner |
| 2026-09-20 | 1–1000 | 1000/1000 | 123 ms | 54 | #582 at 8.5 s | — | Node v26.9.0, cloud sandbox |
| 2026-09-29 | 1–1000 | 1000/1000 | 85 ms | 54 | #403 at 6.7 s | 4 MB, #582 at 334 MB | Node v26.9.0, cloud sandbox, two soaks at once |
| 2026-09-30 | 1–1000 | 1000/1000 | 126 ms | 54 | #403 at 8.7 s | 4 MB, #582 at 334 MB | Node v26.9.0, cloud sandbox, up to four soaks at once; the ladder, re-run beside the row below |
| 2026-09-30 | 1–1000 | 1000/1000 | 124 ms | 52 | #403 at 8.4 s | 6 MB, #963 at 331 MB | Node v26.9.0, cloud sandbox, up to four soaks at once |
| 2026-09-30 | 1–1000 | 1000/1000 | 73 ms | 52 | #658 at 5.9 s | <1 MB, #150 at 25 MB | Node v26.9.0, cloud sandbox, up to four soaks at once; the graph in typed arrays |

**Simple Simon.** "Unwinnable" is the deals the search *proved* have no line
(`exhausted`); "unsolved" is the ones the budget gave up on, which is the number
a heuristic change is trying to reduce.

| Date | Deals | Solved | Unwinnable | Unsolved | Mean | Mean moves | Worst | Held | Environment |
|---|---|---|---|---|---|---|---|---|---|
| 2026-09-10 | 1–1000 | 941/1000 | 54 | 5 | 458 ms | 85 | #964 at 13.2 s | — | Node v26.7.0, Apple Silicon laptop |
| 2026-09-19 | 1–1000 | 941/1000 | 54 | 5 | 732 ms | 85 | #964 at 20.8 s | — | Node v26.7.0, CI runner |
| 2026-09-20 | 1–1000 | 941/1000 | 54 | 5 | 855 ms | 85 | #964 at 25.1 s | — | Node v26.9.0, cloud sandbox |
| 2026-09-29 | 1–1000 | 941/1000 | 54 | 5 | 628 ms | 85 | #964 at 19.2 s | 21 MB, #964 at 533 MB | Node v26.9.0, cloud sandbox, two soaks at once |
| 2026-09-30 | 1–1000 | 931/1000 | 54 | 15 | 407 ms | 80 | #60 at 9.7 s | 21 MB, #60 at 447 MB | Node v26.9.0, cloud sandbox, up to four soaks at once |
| 2026-09-30 | 1–1000 | 944/1000 | 56 | 0 | 791 ms | 80 | #766 at 100.9 s | 2 MB, #766 at 164 MB | Node v26.9.0, cloud sandbox, up to four soaks at once; the graph in typed arrays |

**Spiderette · 4 suits**, over 1–200 rather than the thousand: a deal the search
gives up on costs it the whole budget, so this soak is half an hour where Simple
Simon's is twenty minutes. The unsolved count is not zero and is not a target —
`mise run solve` exits non-zero on this board today, and on the two-suit pack
below it. Why it stands: § Why the unsolved count stands.

| Date | Deals | Solved | Unwinnable | Unsolved | Mean | Mean moves | Worst | Held | Environment |
|---|---|---|---|---|---|---|---|---|---|
| 2026-09-19 | 1–200 | 159/200 | 8 | 33 | 5.4 s | 105 | #147 at 38.6 s | — | Node v26.7.0, CI runner |
| 2026-09-20 | 1–200 | 159/200 | 8 | 33 | 5.9 s | 105 | #147 at 30.2 s | — | Node v26.9.0, cloud sandbox |
| 2026-09-29 | 1–200 | 159/200 | 8 | 33 | 4.3 s | 105 | #147 at 22.2 s | 188 MB, #162 at 897 MB | Node v26.9.0, cloud sandbox, two soaks at once |
| 2026-09-30 | 1–200 | 150/200 | 7 | 43 | 3.2 s | 100 | #71 at 13.4 s | 156 MB, #41 at 619 MB | Node v26.9.0, cloud sandbox, up to four soaks at once |
S4_ROW

**Spiderette · 1 suit and · 2 suits**, over the same 1–200. The same law, budget
and weights on a cheaper deck — these are the repeated packs, where `found`
counts a suit's runs rather than naming one (§ The packed position). One suit
has nothing to build wrong, so every deal is answered and the soak is about a
minute; two suits sits between it and the four-suit board — a quarter-hour soak,
and an unsolved count of its own.

| Date | Board | Deals | Solved | Unwinnable | Unsolved | Mean | Mean moves | Worst | Held | Environment |
|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-19 | 1 suit | 1–200 | 198/200 | 2 | 0 | 252 ms | 71 | #143 at 17.7 s | — | Node v26.9.0, cloud sandbox |
| 2026-09-19 | 2 suits | 1–200 | 183/200 | 5 | 12 | 2.8 s | 86 | #42 at 38.3 s | — | Node v26.9.0, cloud sandbox |
| 2026-09-20 | 1 suit | 1–200 | 198/200 | 2 | 0 | 262 ms | 71 | #143 at 17.8 s | — | Node v26.9.0, cloud sandbox |
| 2026-09-20 | 2 suits | 1–200 | 183/200 | 5 | 12 | 3.0 s | 86 | #42 at 40.2 s | — | Node v26.9.0, cloud sandbox |
| 2026-09-29 | 1 suit | 1–200 | 198/200 | 2 | 0 | 178 ms | 71 | #143 at 12.5 s | 8 MB, #143 at 472 MB | Node v26.9.0, cloud sandbox, two soaks at once |
| 2026-09-29 | 2 suits | 1–200 | 183/200 | 5 | 12 | 2.2 s | 86 | #42 at 30.0 s | 86 MB, #100 at 963 MB | Node v26.9.0, cloud sandbox, two soaks at once |
| 2026-09-30 | 1 suit | 1–200 | 198/200 | 2 | 0 | 293 ms | 70 | #143 at 11.7 s | 11 MB, #143 at 425 MB | Node v26.9.0, cloud sandbox, up to four soaks at once |
| 2026-09-30 | 2 suits | 1–200 | 181/200 | 4 | 15 | 1.9 s | 84 | #94 at 21.6 s | 82 MB, #94 at 795 MB | Node v26.9.0, cloud sandbox, up to four soaks at once |
| 2026-09-30 | 1 suit | 1–200 | 198/200 | 2 | 0 | 221 ms | 71 | #143 at 6.5 s | <1 MB, #143 at 11 MB | Node v26.9.0, cloud sandbox, up to four soaks at once; the graph in typed arrays |
S2_ROW

**Mini and Micro**, under FreeCell's law and its weights. Every deal is
*answered* — the search either finds a line or empties its frontier long before
its budget — so the number to watch here is "unsolved", and it is zero.

| Date | Board | Deals | Solved | Unwinnable | Unsolved | Mean | Mean moves | Worst | Held | Environment |
|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-17 | Mini | 1–1000 | 992/1000 | 8 | 0 | <1 ms | 11 | #10 at 49 ms | — | Node v26.7.0, CI runner |
| 2026-09-17 | Micro | 1–1000 | 981/1000 | 19 | 0 | <1 ms | 10 | #699 at 8 ms | — | Node v26.7.0, CI runner |
| 2026-09-19 | Mini | 1–1000 | 992/1000 | 8 | 0 | <1 ms | 11 | #10 at 38 ms | — | Node v26.7.0, CI runner |
| 2026-09-19 | Micro | 1–1000 | 981/1000 | 19 | 0 | <1 ms | 10 | #699 at 7 ms | — | Node v26.7.0, CI runner |
| 2026-09-20 | Mini | 1–1000 | 992/1000 | 8 | 0 | <1 ms | 11 | #10 at 35 ms | — | Node v26.9.0, cloud sandbox |
| 2026-09-20 | Micro | 1–1000 | 981/1000 | 19 | 0 | <1 ms | 10 | #699 at 8 ms | — | Node v26.9.0, cloud sandbox |
| 2026-09-29 | Mini | 1–1000 | 992/1000 | 8 | 0 | <1 ms | 11 | #10 at 39 ms | <1 MB | Node v26.9.0, cloud sandbox, two soaks at once |
| 2026-09-29 | Micro | 1–1000 | 981/1000 | 19 | 0 | <1 ms | 10 | #699 at 13 ms | <1 MB | Node v26.9.0, cloud sandbox, two soaks at once |
| 2026-09-30 | Mini | 1–1000 | 992/1000 | 8 | 0 | 1 ms | 11 | #10 at 74 ms | <1 MB | Node v26.9.0, cloud sandbox, up to four soaks at once |
| 2026-09-30 | Micro | 1–1000 | 981/1000 | 19 | 0 | 1 ms | 9 | #699 at 15 ms | <1 MB | Node v26.9.0, cloud sandbox, up to four soaks at once |
| 2026-09-30 | Mini | 1–1000 | 992/1000 | 8 | 0 | 2 ms | 11 | #10 at 101 ms | <1 MB | Node v26.9.0, cloud sandbox, up to four soaks at once; the graph in typed arrays |
| 2026-09-30 | Micro | 1–1000 | 981/1000 | 19 | 0 | 1 ms | 9 | #519 at 25 ms | <1 MB | Node v26.9.0, cloud sandbox, up to four soaks at once; the graph in typed arrays |

Over deals 1–200 that is 198 and 196 solved — the same counts `Game.res` records
from an exhaustive single-card search when it chose two free cells for each
board, arrived at by a different method. A soak of a short pack costs a few
seconds for the thousand, so it is worth running beside the other two.

Method: `mise run solve -- --quiet 1-1000` (with `--game simplesimon` for the
second table), one process, timed per deal by `solve.mjs` around its own
`Solver.solveOn` asks. The mean hides a long tail — most deals fall to the
board's first weight in well under 100 ms, and the handful that don't are what the
second heap and the whole worst-case number are about. Rows before 2026-09-30 are
the restart ladder § The budget describes; the first 2026-09-30 FreeCell row is that
ladder run again beside the continuous search, so the two compare in time as well
as in counts. The
FreeCell row of 2026-09-10 is the same ladder and weights as the row before it,
on a faster machine and with the third pruning (a run to the first empty column
only); it finds a line on every deal the earlier run did.

The five Simple Simon deals the ladder gave up on (#314, #320, #805, #957,
#964) are the record to beat: none is known to be winnable, and the continuous
search gives up on them too. A proof of unwinnability is cheap by comparison — the
slowest of the 54 took 6.6 s, and most take a millisecond.

### What the continuous search costs

The 2026-09-30 rows are the first of the search that keeps what it grows (§ The
budget), and each board's cap was set so that the most any deal holds stays under
the ladder's. Read against the 2026-09-29 rows, that cost:

| Board | Solved | Unwinnable | Most held | Mean held |
|---|---|---|---|---|
| FreeCell | same | — | 331 MB, was 334 | **6 MB, was 4** |
| Simple Simon | **10 fewer** | same | 447 MB, was 533 | same |
| Spiderette · 1 suit | same | same | 425 MB, was 472 | **11 MB, was 8** |
| Spiderette · 2 suits | **2 fewer** | **1 fewer** | 795 MB, was 963 | 82 MB, was 86 |
| Spiderette · 4 suits | **9 fewer** | **1 fewer** | 619 MB, was 897 | 156 MB, was 188 |
| Mini, Micro | same | same | under 1 MB | under 1 MB |

The deals are ones a later rung of the ladder used to reach and a cap that keeps the
memory level can't: Simple Simon's ten are #60, #102, #132, #152, #174, #557, #620,
#866, #880 and #961, and the two lost proofs (two-suit #105, and one four-suit) are
searches that emptied their frontier only past 300,000 positions. **The means rise
where the second heap is paid by easy deals**: a deal that falls to the first weight
in a few hundred positions now grows about as many again on the second, which on
FreeCell and one-suit Spiderette — boards where nearly every deal is easy — moves the
mean. Lines got shorter on every board that has a line to shorten, and the worst
deal faster on every board but the short packs, whose worst is tens of milliseconds
either way. Mean time is level with the ladder on FreeCell, the one board re-run
beside it; across machines it reads lower on Simple Simon and the multi-suit
Spiderettes and higher on one suit, which is as much the load as the search.

Under the interactive wait the comparison is different, and § What the interactive
wait costs has it.

### What the graph in typed arrays bought

The last 2026-09-30 row of each table is the search holding its graph in typed arrays
(§ The search), with the caps raised as § The budget describes. It got there in three
steps, each soaked on every board at the caps the one before it used:

| Board | 2026-09-30, objects | Typed arrays | One node per position | Caps raised |
|---|---|---|---|---|
| FreeCell | 1000 · 331 MB | 1000 · 37 MB | 1000 · 28 MB | 1000 · 25 MB |
| Simple Simon | 931 + 54 · 447 MB | 931 + 54 · 44 MB | 932 + 54 · 43 MB | 944 + 56 · 164 MB |
| Spiderette · 1 suit | 198 + 2 · 425 MB | 198 + 2 · 47 MB | 198 + 2 · 16 MB | 198 + 2 · 11 MB |
| Spiderette · 2 suits | 181 + 4 · 795 MB | 181 + 4 · 86 MB | 185 + 5 · 67 MB | S2_CELL |
| Spiderette · 4 suits | 150 + 7 · 619 MB | 150 + 7 · 73 MB | 157 + 8 · 59 MB | S4_CELL |

Each cell is solved + proved unwinnable, and the most any deal held.

- **Typed arrays, nothing else changed.** A node was still one per push, so the search
  was the same search: the identical line on every deal of 1–40 on five boards, and
  the same counts on every board — the bar the parent-pointer change met before it.
  What changed is only what it held, a tenth.
- **One node per position.** A position reached again more cheaply used to be pushed
  as a second node, and the stale first one was grown too when its turn came — a third
  of all nodes on four-suit Spiderette, and a quarter of what it grew. Moving the
  cheaper node up its heaps instead, and leaving a grown one as it was, grows those
  positions once, which is both less held and more reached inside the same cap.
  Lines are no longer the ones the earlier rows found, but no shorter or longer on the
  mean.
- **Caps raised**, and every fourth closed position kept rather than every one, which
  halved what the largest deals held again (§ The search, § The budget).

### What the interactive wait costs

Every row above is the ladder with nothing in its way, and that is what those
tables are for. This is the same ladder under `Solver.interactive` — the ten
seconds a watched board gets — over the same ranges, each capped row beside the
uncapped one it should be read against. Each date's six rows were measured in one
sitting on one machine, so within a date the times compare as well as the counts;
read across dates, or any other pair of rows in this page, and only the counts do —
and under a cap not even those, since a faster machine gets further in ten seconds.

| Date | Board | Deals | Wait | Solved | Unwinnable | Unsolved | Mean | Worst | Held |
|---|---|---|---|---|---|---|---|---|---|
| 2026-09-20 | Simple Simon | 1–1000 | none | 941 | 54 | 5 | 855 ms | #964 at 25.1 s | — |
| 2026-09-20 | Simple Simon | 1–1000 | 10 s | 914 | 53 | 33 | 714 ms | #34 at 10.1 s | — |
| 2026-09-20 | Spiderette · 2 suits | 1–200 | none | 183 | 5 | 12 | 3.0 s | #42 at 40.2 s | — |
| 2026-09-20 | Spiderette · 2 suits | 1–200 | 10 s | 175 | 4 | 21 | 1.7 s | #120 at 10.3 s | — |
| 2026-09-20 | Spiderette · 4 suits | 1–200 | none | 159 | 8 | 33 | 5.9 s | #147 at 30.2 s | — |
| 2026-09-20 | Spiderette · 4 suits | 1–200 | 10 s | 149 | 7 | 44 | 3.6 s | #141 at 10.1 s | — |
| 2026-09-29 | Simple Simon | 1–1000 | none | 941 | 54 | 5 | 628 ms | #964 at 19.2 s | 21 MB, #964 at 533 MB |
| 2026-09-29 | Simple Simon | 1–1000 | 10 s | 930 | 54 | 16 | 588 ms | #686 at 10.1 s | 20 MB, #103 at 352 MB |
| 2026-09-29 | Spiderette · 2 suits | 1–200 | none | 183 | 5 | 12 | 2.2 s | #42 at 30.0 s | 86 MB, #100 at 963 MB |
| 2026-09-29 | Spiderette · 2 suits | 1–200 | 10 s | 178 | 4 | 18 | 1.5 s | #42 at 10.0 s | 62 MB, #94 at 517 MB |
| 2026-09-29 | Spiderette · 4 suits | 1–200 | none | 159 | 8 | 33 | 4.3 s | #147 at 22.2 s | 188 MB, #162 at 897 MB |
| 2026-09-29 | Spiderette · 4 suits | 1–200 | 10 s | 155 | 7 | 38 | 3.1 s | #107 at 10.4 s | 136 MB, #6 at 565 MB |
| 2026-09-30 | Simple Simon | 1–1000 | none | 931 | 54 | 15 | 407 ms | #60 at 9.7 s | 21 MB, #60 at 447 MB |
| 2026-09-30 | Simple Simon | 1–1000 | 10 s | 931 | 54 | 15 | 384 ms | #60 at 9.2 s | 21 MB, #60 at 447 MB |
| 2026-09-30 | Spiderette · 2 suits | 1–200 | none | 181 | 4 | 15 | 1.9 s | #94 at 21.6 s | 82 MB, #94 at 795 MB |
| 2026-09-30 | Spiderette · 2 suits | 1–200 | 10 s | 179 | 4 | 17 | 1.7 s | #94 at 10.1 s | 74 MB, #167 at 512 MB |
| 2026-09-30 | Spiderette · 4 suits | 1–200 | none | 150 | 7 | 43 | 3.2 s | #71 at 13.4 s | 156 MB, #41 at 619 MB |
| 2026-09-30 | Spiderette · 4 suits | 1–200 | 10 s | 150 | 7 | 43 | 3.0 s | #157 at 10.0 s | 153 MB, #162 at 568 MB |
| 2026-09-30 | Simple Simon | 1–1000 | none | 944 | 56 | 0 | 791 ms | #766 at 100.9 s | 2 MB, #766 at 164 MB |
| 2026-09-30 | Simple Simon | 1–1000 | 10 s | 933 | 54 | 13 | 431 ms | #102 at 10.1 s | 1 MB, #946 at 32 MB |
S2_NONE
| 2026-09-30 | Spiderette · 2 suits | 1–200 | 10 s | 184 | 5 | 11 | 1.4 s | #94 at 10.1 s | 4 MB, #184 at 53 MB |
S4_NONE
| 2026-09-30 | Spiderette · 4 suits | 1–200 | 10 s | 156 | 8 | 36 | 2.9 s | #166 at 10.0 s | 10 MB, #184 at 51 MB |

So the wait costs **twenty-seven Simple Simon deals in the thousand, and eight
two-suit and ten four-suit in the two hundred** on the 2026-09-20 machine — and one
proof on each board, because a rung that would have emptied its frontier is stopped
before it does. The faster 2026-09-29 machine lost eleven, five and four, and kept
Simple Simon's proof: what a cap costs is a fact about the machine as much as the
board.
That is what not making someone watch a still board for forty seconds is worth,
and it is the number to argue with if `interactive` should be five seconds or
twenty.

**FreeCell is the board to watch here, not Spiderette.** It is missing from the
table because the wait costs it nothing — but its worst deal, #403, takes 8.4 s on
a cloud sandbox, which is close enough to ten that a
slower machine loses it. Spiderette's stubborn deals are already lost either way;
FreeCell's worst is the one a smaller `interactive` would take first.

**The 2026-09-30 rows are the continuous search, and the wait matters much less to
it.** Its whole budget fits in about ten seconds on this machine for Simple Simon and
four-suit Spiderette, so the capped row is the uncapped one: the wait costs Simple
Simon nothing, and two two-suit deals. Against the ladder under the same wait it
answers one more Simple Simon deal and one more two-suit, and five fewer four-suit.

**The wait was also a ceiling on memory, and now the cap is.** Under the ladder, ten
seconds kept every deal on these boards under 565 MB, because the rung that grew past
half a gigabyte was the one a watched board rarely reached. The continuous search
never releases what it grew, so what bounds it is its node cap (§ The budget), and a
watched board holds what an unwatched one does: 568 MB at most on four-suit
Spiderette, and 447 MB on Simple Simon where the ladder held 352 under the wait.

**The last six rows are the graph in typed arrays, and under the wait they hold a
tenth of anything above them.** Ten seconds reaches 53 MB at most on any of the three
boards, where every earlier search held 350 MB and more; and in those ten seconds it
answers more than the ladder did under the same wait — three Simple Simon deals, six
two-suit and one four-suit — and every proof the ladder found with no wait at all. The node caps are
far past what ten seconds reaches, so the capped rows are the ones a player sees, and
the uncapped ones say what a patient caller could have.

The 2026-09-20 rows: Node v26.9.0, cloud sandbox. The 2026-09-29 rows: Node
v26.9.0, cloud sandbox, two soaks at once. The 2026-09-30 rows: Node v26.9.0, cloud
sandbox, up to four soaks at once — the uncapped typed-array rows as chunks of the
range side by side, their means weighted back together. The capped half of each with
`--limit 10`.

**Spider has no row here, and a probe is why.** `Position.ofGameState` reads all
three packs — nothing in the model assumes one pack or four foundations — so the
search runs on 104 cards without an edit. What it does *not* do is answer: at the
interactive ten seconds, four of the first five two-suit deals come back out of time,
and the one that solves takes 173 moves. Under the object graph each of the four held
397 to 471 MB when the limit stopped it (2026-09-30, the command in § Measuring it,
re-run beside the row below) — a heap a phone may not give a tab. The graph in typed
arrays holds 38 MB at most and 26 on the mean over the same five, with as many
positions grown in the ten seconds. Five deals is a probe, not a record, and the
honest reading is only that the numbers above do not carry over — a board twice the
size is not the same search at the same cap. Whoever measures it properly owes a range
and a row; until then the Debug screen's Solve row on a Spider board is ten seconds of
thinking and then a refusal, which is the designed path (`Solver.ranOutOfTime`) and
not a wait anyone should be asked to like.

### Why the unsolved count stands

Four-suit Spiderette leaves 43 of 200 deals unanswered and the two-suit pack 15,
where every other board the solver models answers all of them. **Those numbers
are the record, not a target**, and this is the argument for leaving them alone
rather than tuning the heuristic or widening the budget to move them.

**The cost that made them a defect is gone.** What was wrong with an unanswered
deal was never the gap in the table — it was that reaching it took the whole
restart ladder, nearly forty seconds, wherever `autoplay` had been typed. A player now
waits ten (§ What a caller is willing to spend), on a page that is still a page
while they do. The deal is still unanswered and the board still can't say whether
it is winnable, but neither of those is something anyone sits through.

**And the answer they give is now true.** These deals used to come back
"couldn't find a way to win from here", which reads as a verdict on the board.
Under a wait they come back `OutOfTime`, which says what actually happened:
nobody finished looking. Part of what made the count feel like a defect was a
sentence claiming more than the search had earned.

**Nobody knows the count is too high.** Eight of the 200 four-suit deals were
*proved* unwinnable by the ladder; the rest of the 43 were not proved either way. A
deal with no line is not a deal the solver failed on, and no one has established how
many of the 43 have lines at all. "Answer more of them" is only a goal for the ones that can be
answered, and that number is unknown.

**A longer search is the wrong knob, and now for a second reason.** The budget is
capped deliberately, and § The budget has the measured case: a search never releases
what it grows, so every position a stubborn deal is allowed is memory a phone pays
for, and it is the stubborn deals that spend all of it. The bounded wait sharpens
that. On three stubborn four-suit deals — #3, #141, #147 — the old ladder spent all
700,000 of its positions and took 21 to 31 s, and ten seconds bought 217,000 to
357,000 of them. A search a player would never finish is tuning for `mise run solve`
and the CLI — worth doing only if those are who it is for, which should be said out
loud rather than assumed.

**What would actually help is a cheaper proof.** A search that empties its frontier
answers a deal in milliseconds, which is well inside any wait; that is how Mini
and Micro answer every deal in the first thousand. Converting some of the 43 into
`Exhausted` would raise the answered count *within* the ten seconds, where a
longer search cannot. That is a different piece of work from tuning weights, and
it is the direction to take if this is picked up again.

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
weighed that way barely deals at all: it spends its whole budget tidying a board
it can only win by dealing. Charging 5 a card pays back 35 of the 46, which is
what makes "get the row down" worth the mess it makes.

Measured rather than argued: with the term at zero, deals 1–5 come back 1 solved
and 4 given up on at 16 s each; with it at 5 the same five come back 4 solved,
and the one that doesn't (#3) is one the whole restart ladder the search then ran
couldn't crack either way.

The weights are three named records (`Solver.freecellWeights`,
`Solver.simonWeights`, `Solver.spideretteWeights`) that `Search.make` takes as an
argument, which is how they were chosen — measured rather than guessed. Three,
not five: the short packs were tuned on nothing, because they left nothing to
tune. Under FreeCell's own weights a greedy search answers every Mini and Micro
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
search's own weight turned out to matter far more (§ The budget).

## The search

Weighted best-first, from the start position to the first one that
`canFinish`. Priority is `g + weight · h`, where `g` is the path length.

**It is a value, not a call.** `Solver.Search.make` opens one at a position,
`think(~nodes)` grows it by up to that many positions and says where that left it
(`Found`, `Exhausted`, `Paused`, `Full`), and `line` reads the answer once there is
one. The frontier and the visited set live in the value between `think`s, so nothing
is grown twice, and **`think(a)` then `think(b)` reaches exactly the graph
`think(a + b)` does** — `Solver_test` pins it. That is the whole of what carrying on
means, and it is what `solveOn` leans on to turn a wait into slices.

**Several heaps, one graph.** A budget names one weight per open list, and the
lists take turns growing a position each. Every child is pushed to all of them, and a
node is grown once — by whichever list pops it first; the others drop it when they
reach it. So a search with an empty set of lists has still grown every position it
could reach, and `Exhausted` is still a proof. Why each board has two, and what the
second buys: § The budget.

- **The graph is typed arrays, not objects** (`Graph.res`). A node is an index: its
  parent, the move from there, its depth, its heuristic and its hash are a slot each
  in a column of their own, about twenty bytes. Only a *grown* node's position is
  kept, packed one byte per card into an arena; an open node's is its parent's with
  its move played again, the trade `parent` and `trail` objects used to make. What
  that holds per board is § The budget's to say.
- **The open list is a binary heap** (`Solver.Heap`) of node indices, not a sorted
  array: it's pushed and popped hundreds of thousands of times per deal, and
  re-sorting it that often is the whole cost of the search. A priority is read off
  the node when two are compared, so a heap stores nothing but the index and where
  each node sits in it.
- **The visited set is a hash table, and a hit is checked.** It files each node by
  `Board.hash`, which agrees with `Position.key` — two positions that differ only in
  *which* free cell or *which* column holds what are the same position — and a hash
  that matches counts as seen only once the node's position, rebuilt, is
  `Position.alike` the one asked about. A collision taken for "seen" would prune a
  position nobody visited, and `Exhausted` would stop being a proof. No string is
  built for a position anywhere on this path.
- **One node per position, and `closed` is on the node.** A position reached no more
  cheaply than before teaches nothing new and is dropped. One reached more cheaply
  while still open takes the cheaper parent and moves up each heap where it stands;
  one already grown is left as it was grown, because its children's moves name
  the columns of the layout it was grown in.
- **Three prunings in `legalMoves`** that only ever cost time, all of them
  symmetries the key already collapses: a card may go to the *first* empty free
  cell and a run to the *first* empty column (the other empties are the same
  move), and a whole column may not move into an empty one (that only renames
  the column). Nothing is pruned on a hunch — that would make `exhausted` a lie.

### The budget

Each board gets **two heaps over one search**, and a cap on the positions it grows.
`Solver.budgetFor` picks one the same way `weightsFor` does: the law, and then whether
the board deals.

| Board | `heaps` | `maxNodes` |
|---|---|---|
| FreeCell, Mini, Micro | 2.0, 1.0 | 2,000,000 |
| Simple Simon | 1.0, 0.3 | 1,600,000 |
| Spiderette, every pack | 2.0, 1.0 | 6,000,000 |

A high weight is greedy and dives; a low one searches wider and costs more per answer.
The first weight on each board is the one almost every deal falls to — FreeCell's is
mildly greedy, and Simple Simon's is *not*: over sixty deals, 1.0 solved more than 2.0
with two thirds of the nodes and shorter lines, and every greedier setting solved
fewer. The second is what catches the deals the first misses.

**What the budget replaced.** Until 2026-09-30 a board climbed a *ladder*: a search at
one weight and cap, then — if it spent its cap — a fresh search at another, from
nothing. FreeCell's was 2.0 at 60,000, 1.0 at 150,000, 4.0 at 150,000 and 0.5 at
400,000; Simple Simon's 1.0 at 100,000, 2.0 at 150,000 and 0.5 at 400,000;
Spiderette's 2.0 at 200,000 and 1.0 at 500,000. A restart cannot be resumed — "ten more
seconds" has no meaning across one — so one continuous search took its place, and the
different weights that used to take turns *in time* take turns *in a graph* instead.

**The cap is a memory ceiling, and that is what sets each one.** The ladder was a
ceiling as well as a restart: a rung that spent its budget released its frontier
before the next began, so a deal held at most what its biggest rung did. A search that
only grows has no such release. So **each cap is the most that board can grow without
its soak's Held column rising above the ladder's 2026-09-29 figure** — 334 MB on
FreeCell, 533 on Simple Simon, 963 and 897 on the two- and four-suit Spiderettes.

What a position costs is what moved the caps. The first continuous search held about
3 KB per position grown, an object per open node and a string per position seen, and
that put the caps at 200,000, 150,000 and 300,000 — below the ladder's reach, which is
where the 2026-09-30 rows lost ten Simple Simon deals, eleven Spiderette deals and two
proofs. The graph in typed arrays (§ The search) holds 60 to 150 bytes per position
grown, which is what let the caps go back up:

- **FreeCell** solves every deal in the thousand well inside 200,000, so its cap costs
  nothing and changes nothing; 2,000,000 is where a deal at the cap would still hold
  under 334 MB. #150 holds the most, 25 MB.
- **Simple Simon** answers every deal in the thousand at 1,600,000 — 944 solved and 56
  proved, where the ladder gave up on five. #766 is the longest and holds the most,
  164 MB in 101 s; the cap was set when a Simple Simon position cost a third more, and
  is where a deal that spent it would still hold under 533 MB.
- **Spiderette** is the one board where deals still spend the cap, so its cap is the
  one the ceiling binds: 6,000,000 is where the four-suit deals that spend it hold
  most of the 897 MB they are allowed. SPIDERETTE_CAP_RESULT

**A bigger cap is still paid for in memory** by every deal that spends it, which is
every deal that goes unanswered — and now in time as well, since a deal that spends six
million positions takes minutes. A watched board never gets there: § What the
interactive wait costs has what ten seconds reaches, and how little it holds.

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

**A repeated pack collapses onto the same numbering, on purpose.** Spiderette · 1
suit is ♠ taken four times, so both Sevens of Spades are the int 6 — and two
boards differing only in which of them sits where *are* the same position, which
is the same thing `Position.key` says when it sorts the cells and the columns.
What the collapse would lose is one fact and the packing keeps it two ways:
`pack.copies` says how many runs there are to send home (so `pack.size` is
`suits × ranks × copies`), and `found` **counts cards home** rather than naming a
rank, so `collectRuns` adds a run's worth to a suit's entry instead of assigning
one. Where a copy genuinely has to be told from its twin is on the real board, and
`toAction` gets there by carrying the cards a move lifts out of the live pile
rather than rebuilding them from the int.

`Position.lawOf` reads a `Game.t`'s law off its rules — the cascade rule, the
run limit, the collect policy, whether the foundations are sealed — and
`ofGameState` then reads the board: **the counts are the board's own**, and the
deck it carries is the pack. What is still refused is only what the packing
genuinely can't say — a second stock (`Reducer.stockOf` deals from the first and
the rest would sit there unplayable), a card loose on the table, a repeated pack
*under FreeCell's law* (`found` is a rank there, and a second copy would carry it
past the King), ranks that don't run up from the Ace (a foundation's *length* is
read as the rank it has climbed to), fewer foundations than the deck has runs to
send home, and a card face down anywhere but in a column or the stock (a hidden
card in a cell, or a column with nothing showing, is a board whose top card no
predicate could name). All three Spiderettes are refused on none of it, and
neither are Mini and Micro.

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

`Board` is the same position laid out for a search to play forward and back in
place — `play`, `takeBack`, and a hash in place of `key` — rather than copied per
move as `applyMove` does. It re-reads every row above on its own layout, and
`Board_test` holds it against `Position` the way `Position_test` holds `Position`
against `Reducer`: random walks on every board the picker offers, every legal move
played and taken back at every step.

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
line on every one of them.

**Parent pointers went in, for memory rather than speed** — along with the frontier
holding each node's *parent* and replaying its last move when it is taken off, and a
key spelled one character per card. On a Spider board a pass generates fifteen
positions for every one it grows, and holding each of those whole, with its own copy
of a two-hundred-move path, took ten seconds of `Solver.interactive` past a gigabyte —
which iOS answers by killing the tab, worker and all, and reloading it. The three
together measured 1,518 MB → 379 MB of live heap over 100,000 nodes of a Spider
position, a little faster, and the identical line on every deal of 1–40 on five
boards. **The key went next, and the objects with it** (§ The search): nodes as typed
arrays and a visited set that files by hash and checks every match, which is how a
hash can be smaller without a collision ever pruning a position — `Exhausted` is only
a proof while nothing is pruned that wasn't seen. That too found the identical line on
every deal of 1–40 on five boards before anything else about the search changed.
Re-profiled before it, the collector was still ~23%,
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
  compilation at 4 KB on the main thread — which the web app's worker thread is
  not, so this one has softened since it was written; the CLI still calls
  `Session.autoplay` from inside a command that answers synchronously.

**Deferred deliberately: nothing is waiting on it.** If the budget is ever
wanted, spend it at the cheap end of that list first — and note that the reason
to want it is more likely a *shorter line* than a faster one, which is the trade
`weight` already makes.

## Before you change the solver

- **Soak it — every board.** `mise run solve -- --quiet 1-1000`, and again with
  `--game simplesimon`, `--game mini` and `--game micro`, and add a row to each
  table above. A change that helps the mean and doubles the worst case is not an
  improvement, and a change to the search or a shared term moves every board at
  once. The two short packs take a few seconds each, so there is no excuse.
  Spiderette is the expensive one — `--game spiderette4 --quiet 1-200` is half an
  hour, because the deals it gives up on each cost the whole budget — so soak it
  over 1–200 rather than the thousand, and leave it running. Its repeated packs
  (`spiderette1`, `spiderette`) are the same board with a cheaper deck and are
  worth the same range: the one-suit soak is about a minute, the two-suit one
  a quarter of an hour. **Don't reach for `--limit` to make that cheaper**: a capped run
  measures the cap, and a cap is exactly what would hide a regression in the
  positions it stopped short of.
- **Read the Held column, not only the counts.** The node cap is the only thing
  bounding what a search holds (§ The budget), so a change that solves more by
  growing more is a change a phone pays for. Add a row to § What the interactive
  wait costs as well: that table is where a watched board's memory is measured.
- **Check the mirror.** If you touched `Position`, `Position_test` plays a solved
  game through both models — that's the test that catches a predicate drifting
  from the `Rules`/`Reducer` it mirrors.
- **Weights and budgets are arguments, not constants.** `Search.make` takes both,
  so a new tuning can be measured against the board's own without editing anything.
- **Play one for real.** `mise run autoplay -- <deal>` (and
  `-- --game simplesimon <deal>`) runs the plan through the actual app, which is
  the only thing that checks `Position.toAction` still lands where the plan
  meant. Not Spiderette: that harness reads the board off the rendered page, where
  a face-down card has no name to read and a repeated pack announces two cards by
  the same one, so a board that deals is played by the in-app `autoplay` command
  instead — `mise run cli -- play spiderette4` and the web app's debug console
  (`browser-tests/spiderette.spec.mjs` types it on each of the three packs), both
  of which read the board out of the game.
