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
rather than `OutOfRoom`. It is not a rare answer: about one Simple Simon deal in
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
in. A million of them is half a minute of four-suit Spiderette on a cloud sandbox,
more than Mini ever needs, and the same number again is one wait on a CI runner and
another on a phone. So the budget says how hard to try, and `patience`
says how long the caller will let that take:

```rescript
type patience = {ms: float, clock: unit => float}
```

Two are named in `Solver`, for **who is waiting** rather than for how long:

| | | |
|---|---|---|
| `interactive` | 10 s | a board someone is watching — passed by `TableScene` |
| `patient` | 30 s | a terminal or a script, where the waiting is the point — passed by `Cli` and the autoplay harness |

A third is not a wait at all. `unasked` (20 s) is the most a board is thought about
with nobody having asked — what the web app's `Thinker` spends between asks, in short
chunks while the board is still (`docs/solver-next.md` § Thinking between asks).
Nobody watches it, so it bounds battery rather than patience, and § What thinking
unasked costs is what it comes to over a game.

`interactive` is a **policy**, and it really does cost answers — § What the
interactive wait costs measures how many, and § Why the unsolved count stands is
the decision that came out of it. `patient` is a **backstop**: it sits at the worst
search any board's budget allows, so it bites only on a machine slower than the one
the record was measured on.

**Nothing a player or a script waits on runs longer than thirty seconds by default.**
The CLI's `autoplay` and the browser harness pass `patient`, and a watched board
`interactive`, so each gives up by then whatever it was asked. The budget is a cap in
*bytes* (§ Memory tiers), and how long a search takes to fill it depends on the board:
`mise run solve` with no flags searches to the medium tier with no wait, which on a
cloud sandbox is seconds for most deals and minutes for the stubborn ones on the
boards whose positions are cheap. That is the benchmark's to spend, not a caller's.
Waiting longer is something a caller asks for: `--tier` and `--mb` raise `mise run
solve`'s cap, and `--limit` sets its wait.

**Neither front end waits on the thread it draws with.** The terminal has nothing
to draw; the web app sends the board to a worker (`web-app/src/platform/Thinker.res`)
and goes on painting, so `interactive` bounds a spinner rather than a freeze. It is
still a policy about a person's patience and still costs the answers measured below —
what it stopped being is the difference between a page and a hung page.

`mise run solve` passes whatever `--limit` says, and nothing at all by default,
which is what makes the benchmark record a measurement of the budget rather than
of a wait. A row measured with `--mb` or another `--tier` says so.

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
`browser-tests/spiderette.spec.mjs` types `autoplay` on all three Spiderette packs,
on one fixed deal each, and waits for the win overlay, so those three searches have
to finish inside it. They are not close to it — a few hundred milliseconds each on a
loaded four-core sandbox — but they are the floor, and the failure they'd give is a
missing overlay rather than anything that says "time". A change that grows the
search can push a deal past the wait, which is why the spec names its deals rather
than taking the first of each.

### The three ways to come back with nothing

`Solver.effort` carries an `ending`, and only one of its refusals is a statement
about the board:

| `ending` | what happened | `autoplay` says |
|---|---|---|
| `Exhausted` | the frontier emptied: every reachable position was seen, and none finishes | `Unwinnable` — a proof |
| `Full` | the search holds its budget's `maxBytes` with positions still waiting | `OutOfRoom` |
| `OutOfTime` | the caller's `patience` ran out, with the budget not yet spent | `OutOfPatience` |

They are `Search.answer`'s four with a clock read against it: `Full` is `Full`,
and `Paused` — a slice spent with the frontier not — is `OutOfTime` once the deadline
has passed, and simply the next slice before then.

**The last two are not one answer in two moods.** `Full` means the budget was
spent and gave up, which is the most this solver has to say about a deal — and it is
said as an answer about the budget, in megabytes, rather than about the board
(`Command.autoplayOutOfRoom`).
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
player-facing: **a hint that peeks is a hint that knows where the Ace is** — and
that is accepted. The game offers its hint, and autoplay, on a board with cards
face down exactly as on one without, so a front end has no reason to hide either
there. `mise run solve`, the harness and the tests want the same solver that sees
everything, and that is the one they get.

## Measuring it

```
mise run solve                    # deal 1, with the line printed
mise run solve -- 24680           # a particular deal
mise run solve -- --quiet 1-1000  # a soak: just the summary line
mise run solve -- --game simplesimon 1-1000 --quiet   # the other law
mise run solve -- --game minifreecell --quiet 1-1000  # the short packs
mise run solve -- --game spiderette4 --quiet 1-200    # the board that deals
mise run solve -- --game spiderette1 --quiet 1-200    # …and its repeated packs
mise run solve -- --game spiderette2 --quiet 1-200
mise run solve -- --game spider2 --limit 10 --quiet 1-5   # two packs: a probe, not a record
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
| 2026-10-01 | 1–1000 | 1000/1000 | 83 ms | 52 | #658 at 6.5 s | <1 MB, #150 at 25 MB | Node v26.9.0, cloud sandbox, two soaks at once; the graph in typed arrays, re-run beside the row below |
| 2026-10-01 | 1–1000 | 1000/1000 | 46 ms | 52 | #658 at 4.0 s | <1 MB, #150 at 25 MB | Node v26.9.0, cloud sandbox, two soaks at once; grown on a `Board` |
| 2026-10-01 | 1–1000 | 1000/1000 | 28 ms | 52 | #658 at 2.3 s | <1 MB, #150 at 25 MB | Node v26.9.0, CI runner, 8 jobs at once; grown on a `Board` |

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
| 2026-09-30 | 1–1000 | 944/1000 | 56 | 0 | 791 ms | 80 | #766 at 100.9 s | 2 MB, #766 at 164 MB | Node v26.9.0, cloud sandbox, up to four soaks at once; the graph in typed arrays; `--nodes 1600000` |
| 2026-10-01 | 1–1000 | 940/1000 | 55 | 5 | 481 ms | 80 | #314 at 25.3 s | 2 MB, #60 at 74 MB | Node v26.9.0, cloud sandbox, three soaks at once; the graph in typed arrays at the default cap |
| 2026-10-01 | 1–1000 | 940/1000 | 55 | 5 | 593 ms | 80 | #314 at 31.3 s | 2 MB, #60 at 74 MB | Node v26.9.0, cloud sandbox, two soaks at once; the graph in typed arrays, re-run beside the row below |
| 2026-10-01 | 1–1000 | 940/1000 | 55 | 5 | 223 ms | 80 | #957 at 12.1 s | 2 MB, #60 at 74 MB | Node v26.9.0, cloud sandbox, two soaks at once; grown on a `Board` |

**Spiderette · 4 suits**, over 1–200 rather than the thousand: a deal the search
gives up on costs it the whole budget — about forty seconds each at the default cap,
five minutes each at the ceiling — so this soak is half an hour in one process at the
default and over an hour at the ceiling, where Simple Simon's is a quarter of one. The
unsolved count is not zero and is not a target —
`mise run solve` exits non-zero on this board today, and on the two-suit pack
below it. Why it stands: § Why the unsolved count stands.

| Date | Deals | Solved | Unwinnable | Unsolved | Mean | Mean moves | Worst | Held | Environment |
|---|---|---|---|---|---|---|---|---|---|
| 2026-09-19 | 1–200 | 159/200 | 8 | 33 | 5.4 s | 105 | #147 at 38.6 s | — | Node v26.7.0, CI runner |
| 2026-09-20 | 1–200 | 159/200 | 8 | 33 | 5.9 s | 105 | #147 at 30.2 s | — | Node v26.9.0, cloud sandbox |
| 2026-09-29 | 1–200 | 159/200 | 8 | 33 | 4.3 s | 105 | #147 at 22.2 s | 188 MB, #162 at 897 MB | Node v26.9.0, cloud sandbox, two soaks at once |
| 2026-09-30 | 1–200 | 150/200 | 7 | 43 | 3.2 s | 100 | #71 at 13.4 s | 156 MB, #41 at 619 MB | Node v26.9.0, cloud sandbox, up to four soaks at once |
| 2026-09-30 | 1–200 | 180/200 | 8 | 12 | 23.1 s | 102 | #90 at 344.9 s | 55 MB, #199 at 779 MB | Node v26.9.0, cloud sandbox, up to four soaks at once; the graph in typed arrays; `--nodes 5500000` |
| 2026-10-01 | 1–200 | 173/200 | 8 | 19 | 5.2 s | 101 | #3 at 37.7 s | 20 MB, #3 at 143 MB | Node v26.9.0, cloud sandbox, three soaks at once; the graph in typed arrays at the default cap, in two halves |
| 2026-10-01 | 1–200 | 173/200 | 8 | 19 | 7.0 s | 101 | #3 at 51.0 s | 20 MB, #3 at 143 MB | Node v26.9.0, cloud sandbox, two soaks at once; the graph in typed arrays, re-run beside the row below |
| 2026-10-01 | 1–200 | 173/200 | 8 | 19 | 2.9 s | 101 | #171 at 20.0 s | 20 MB, #3 at 143 MB | Node v26.9.0, cloud sandbox, two soaks at once; grown on a `Board` |
| 2026-10-01 | 1–200 | 171/200 | 8 | 21 | 5.0 s | 102 | #200 at 42.4 s | 24 MB, #120 at 188 MB | Node v26.9.0, cloud sandbox, three soaks at once; grown on a `Board`, column order kept |
| 2026-10-01 | 1–200 | 176/200 | 8 | 16 | 5.8 s | 101 | #7 at 59.6 s | 35 MB, #147 at 289 MB | Node v26.9.0, cloud sandbox, three soaks at once; grown on a `Board`, folded to look and column order kept to prove |
| 2026-10-01 | 1–200 | 176/200 | 8 | 16 | 3.3 s | 101 | #7 at 37.4 s | 35 MB, #108 at 289 MB | Node v26.9.0, CI runner, 8 jobs at once; grown on a `Board`, folded to look and column order kept to prove |

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
| 2026-09-30 | 2 suits | 1–200 | 195/200 | 5 | 0 | 4.2 s | 86 | #168 at 182.6 s | 11 MB, #168 at 429 MB | Node v26.9.0, cloud sandbox, up to four soaks at once; the graph in typed arrays; `--nodes 6000000` |
| 2026-10-01 | 2 suits | 1–200 | 190/200 | 5 | 5 | 1.9 s | 85 | #120 at 36.3 s | 7 MB, #120 at 121 MB | Node v26.9.0, cloud sandbox, three soaks at once; the graph in typed arrays at the default cap |
| 2026-10-01 | 1 suit | 1–200 | 198/200 | 2 | 0 | 182 ms | 71 | #143 at 5.0 s | <1 MB, #143 at 11 MB | Node v26.9.0, cloud sandbox, two soaks at once; the graph in typed arrays, re-run beside the row below |
| 2026-10-01 | 1 suit | 1–200 | 198/200 | 2 | 0 | 75 ms | 71 | #143 at 1.7 s | <1 MB, #143 at 11 MB | Node v26.9.0, cloud sandbox, two soaks at once; grown on a `Board` |
| 2026-10-01 | 2 suits | 1–200 | 190/200 | 5 | 5 | 2.3 s | 85 | #120 at 42.8 s | 7 MB, #120 at 121 MB | Node v26.9.0, cloud sandbox, two soaks at once; the graph in typed arrays, re-run beside the row below |
| 2026-10-01 | 2 suits | 1–200 | 190/200 | 5 | 5 | 963 ms | 85 | #120 at 18.2 s | 7 MB, #120 at 121 MB | Node v26.9.0, cloud sandbox, two soaks at once; grown on a `Board` |
| 2026-10-01 | 1 suit | 1–200 | 198/200 | 2 | 0 | 5.2 s | 71 | #179 at 85.8 s | 22 MB, #38 at 221 MB | Node v26.9.0, cloud sandbox, three soaks at once; grown on a `Board`, column order kept |
| 2026-10-01 | 2 suits | 1–200 | 186/200 | 5 | 9 | 6.3 s | 85 | #1 at 159.7 s | 33 MB, #1 at 710 MB | Node v26.9.0, cloud sandbox, three soaks at once; grown on a `Board`, column order kept |
| 2026-10-01 | 1 suit | 1–200 | 198/200 | 2 | 0 | 89 ms | 71 | #93 at 3.2 s | <1 MB, #143 at 11 MB | Node v26.9.0, cloud sandbox, three soaks at once; grown on a `Board`, folded to look and column order kept to prove |
| 2026-10-01 | 2 suits | 1–200 | 193/200 | 5 | 2 | 1.6 s | 85 | #168 at 49.0 s | 9 MB, #168 at 265 MB | Node v26.9.0, cloud sandbox, three soaks at once; grown on a `Board`, folded to look and column order kept to prove |
| 2026-10-01 | 1 suit | 1–200 | 198/200 | 2 | 0 | 62 ms | 71 | #93 at 1.9 s | <1 MB, #143 at 11 MB | Node v26.9.0, CI runner, 8 jobs at once; grown on a `Board`, folded to look and column order kept to prove |
| 2026-10-01 | 2 suits | 1–200 | 193/200 | 5 | 2 | 951 ms | 85 | #168 at 24.4 s | 9 MB, #168 at 264 MB | Node v26.9.0, CI runner, 8 jobs at once; grown on a `Board`, folded to look and column order kept to prove |

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
| 2026-10-01 | Mini | 1–1000 | 992/1000 | 8 | 0 | 1 ms | 11 | #10 at 73 ms | <1 MB | Node v26.9.0, cloud sandbox, two soaks at once; the graph in typed arrays, re-run beside the row below |
| 2026-10-01 | Mini | 1–1000 | 992/1000 | 8 | 0 | 1 ms | 11 | #10 at 58 ms | <1 MB | Node v26.9.0, cloud sandbox, two soaks at once; grown on a `Board` |
| 2026-10-01 | Micro | 1–1000 | 981/1000 | 19 | 0 | 1 ms | 9 | #18 at 17 ms | <1 MB | Node v26.9.0, cloud sandbox, two soaks at once; the graph in typed arrays, re-run beside the row below |
| 2026-10-01 | Micro | 1–1000 | 981/1000 | 19 | 0 | <1 ms | 9 | #18 at 12 ms | <1 MB | Node v26.9.0, cloud sandbox, two soaks at once; grown on a `Board` |

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
| Spiderette · 2 suits | 181 + 4 · 795 MB | 181 + 4 · 86 MB | 185 + 5 · 67 MB | 195 + 5 · 429 MB |
| Spiderette · 4 suits | 150 + 7 · 619 MB | 150 + 7 · 73 MB | 157 + 8 · 59 MB | 180 + 8 · 779 MB |

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

**And at the default caps**, the 2026-10-01 rows: half a million positions answers
Simple Simon 940 + 55, with the ladder's #314, #320, #957 and #964 still unanswered
and #766 beside them, the deal the ceiling cap solved in 101 s; a million answers
two-suit Spiderette 190 + 5 and four-suit 173 + 8 — between the ladder's 159 and the
ceiling's 180 — and no deal on any board holds more than 143 MB. So the thirty-second
default gives up a handful of deals the ceiling reaches, every one of them a deal
that costs minutes, and holds a fifth of what the ladder did doing it.

### What the interactive wait costs

Every row above is the ladder with nothing in its way, and that is what those
tables are for. This is the same ladder under `Solver.interactive` — the ten
seconds a watched board gets — over the same ranges, each capped row beside the
uncapped one it should be read against. Each date's rows were measured in one
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
| 2026-09-30 | Spiderette · 2 suits | 1–200 | none | 195 | 5 | 0 | 4.2 s | #168 at 182.6 s | 11 MB, #168 at 429 MB |
| 2026-09-30 | Spiderette · 2 suits | 1–200 | 10 s | 184 | 5 | 11 | 1.4 s | #94 at 10.1 s | 4 MB, #184 at 53 MB |
| 2026-09-30 | Spiderette · 4 suits | 1–200 | none | 180 | 8 | 12 | 23.1 s | #90 at 344.9 s | 55 MB, #199 at 779 MB |
| 2026-09-30 | Spiderette · 4 suits | 1–200 | 10 s | 156 | 8 | 36 | 2.9 s | #166 at 10.0 s | 10 MB, #184 at 51 MB |
| 2026-10-01 | Simple Simon | 1–1000 | none | 940 | 55 | 5 | 593 ms | #314 at 31.3 s | 2 MB, #60 at 74 MB |
| 2026-10-01 | Simple Simon | 1–1000 | 10 s | 932 | 54 | 14 | 443 ms | #60 at 10.1 s | 1 MB, #60 at 31 MB |
| 2026-10-01 | Spiderette · 2 suits | 1–200 | none | 190 | 5 | 5 | 2.3 s | #120 at 42.8 s | 7 MB, #120 at 121 MB |
| 2026-10-01 | Spiderette · 2 suits | 1–200 | 10 s | 183 | 5 | 12 | 1.4 s | #42 at 10.0 s | 4 MB, #168 at 41 MB |
| 2026-10-01 | Spiderette · 4 suits | 1–200 | none | 173 | 8 | 19 | 7.0 s | #3 at 51.0 s | 20 MB, #3 at 143 MB |
| 2026-10-01 | Spiderette · 4 suits | 1–200 | 10 s | 153 | 8 | 39 | 3.1 s | #4 at 10.1 s | 9 MB, #184 at 38 MB |
| 2026-10-01 | Simple Simon | 1–1000 | none | 940 | 55 | 5 | 223 ms | #957 at 12.1 s | 2 MB, #60 at 74 MB |
| 2026-10-01 | Simple Simon | 1–1000 | 10 s | 939 | 55 | 6 | 213 ms | #766 at 10.0 s | 2 MB, #60 at 64 MB |
| 2026-10-01 | Spiderette · 2 suits | 1–200 | none | 190 | 5 | 5 | 963 ms | #120 at 18.2 s | 7 MB, #120 at 121 MB |
| 2026-10-01 | Spiderette · 2 suits | 1–200 | 10 s | 188 | 5 | 7 | 800 ms | #45 at 10.0 s | 6 MB, #184 at 76 MB |
| 2026-10-01 | Spiderette · 4 suits | 1–200 | none | 173 | 8 | 19 | 2.9 s | #171 at 20.0 s | 20 MB, #3 at 143 MB |
| 2026-10-01 | Spiderette · 4 suits | 1–200 | 10 s | 165 | 8 | 27 | 2.2 s | #200 at 10.0 s | 15 MB, #184 at 78 MB |
| 2026-10-01 | Spiderette · 1 suit | 1–200 | none | 198 | 2 | 0 | 5.2 s | #179 at 85.8 s | 22 MB, #38 at 221 MB |
| 2026-10-01 | Spiderette · 1 suit | 1–200 | 10 s | 159 | 2 | 39 | 3.3 s | #59 at 10.8 s | 14 MB, #137 at 70 MB |
| 2026-10-01 | Spiderette · 2 suits | 1–200 | none | 186 | 5 | 9 | 6.3 s | #1 at 159.7 s | 33 MB, #1 at 710 MB |
| 2026-10-01 | Spiderette · 2 suits | 1–200 | 10 s | 159 | 5 | 36 | 3.0 s | #1 at 10.3 s | 15 MB, #129 at 70 MB |
| 2026-10-01 | Spiderette · 4 suits | 1–200 | none | 171 | 8 | 21 | 5.0 s | #200 at 42.4 s | 24 MB, #120 at 188 MB |
| 2026-10-01 | Spiderette · 4 suits | 1–200 | 10 s | 152 | 8 | 40 | 3.1 s | #95 at 10.2 s | 14 MB, #129 at 68 MB |
| 2026-10-01 | Spiderette · 1 suit | 1–200 | none | 198 | 2 | 0 | 89 ms | #93 at 3.2 s | <1 MB, #143 at 11 MB |
| 2026-10-01 | Spiderette · 1 suit | 1–200 | 10 s | 198 | 2 | 0 | 96 ms | #93 at 3.3 s | <1 MB, #143 at 11 MB |
| 2026-10-01 | Spiderette · 2 suits | 1–200 | none | 193 | 5 | 2 | 1.6 s | #168 at 49.0 s | 9 MB, #168 at 265 MB |
| 2026-10-01 | Spiderette · 2 suits | 1–200 | 10 s | 187 | 5 | 8 | 919 ms | #42 at 10.0 s | 5 MB, #184 at 63 MB |
| 2026-10-01 | Spiderette · 4 suits | 1–200 | none | 176 | 8 | 16 | 5.8 s | #7 at 59.6 s | 35 MB, #147 at 289 MB |
| 2026-10-01 | Spiderette · 4 suits | 1–200 | 10 s | 164 | 8 | 28 | 2.3 s | #84 at 10.0 s | 14 MB, #116 at 75 MB |
| 2026-10-01 | Spiderette · 1 suit | 1–200 | none | 198 | 2 | 0 | 62 ms | #93 at 1.9 s | <1 MB, #143 at 11 MB |
| 2026-10-01 | Spiderette · 2 suits | 1–200 | none | 193 | 5 | 2 | 951 ms | #168 at 24.4 s | 9 MB, #168 at 264 MB |
| 2026-10-01 | Spiderette · 4 suits | 1–200 | none | 176 | 8 | 16 | 3.3 s | #7 at 37.4 s | 35 MB, #108 at 289 MB |

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

**The last twelve are the search grown on a `Board`** (§ On making this faster), the
first six the build before it and the last six the new one, each pair run at the same
moment so the two compare in time. With no wait the counts are identical, because the
search is the same search, and it gets there in under half the time. Under the wait
that time turns into answers: seven more Simple Simon deals and a proof, five more
two-suit and twelve more four-suit — 165 solved, the first ten-second row to pass the
ladder's 159 with no wait at all. What it holds under the wait rises with them, to
78 MB at most, because ten seconds now reaches further into the same graph.

The 2026-09-20 rows: Node v26.9.0, cloud sandbox. The 2026-09-29 rows: Node
v26.9.0, cloud sandbox, two soaks at once. The 2026-09-30 rows: Node v26.9.0, cloud
sandbox, up to four soaks at once — the uncapped typed-array rows as chunks of the
range side by side, their means weighted back together. The 2026-10-01 rows: Node
v26.9.0, cloud sandbox, two soaks at once, the old build's and the new one's. The
capped half of each with `--limit 10`.

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

**The last six rows keep column order while there is a stock** (§ The search), and
the watched board pays for it. Every proof stands: the same 2, 5 and 8 deals come back
unwinnable on the three packs, so none of them leaned on the fold. But a search that
has to tell more boards apart reaches fewer of them in ten seconds — 39 one-suit deals go unanswered under the wait where none did,
and two-suit loses 29 and four-suit 13 against the rows above them. Uncapped, the counts
barely move — two fewer solved on four suits and four fewer on two, with a few deals
trading places — but the one-suit mean goes from under a tenth of a second to five. The time goes on boards with empty columns, where a
run now has every empty seat to go to and a whole column may change seats, and one suit
empties columns most.

**The last six rows look with the columns folded and prove with them kept** (§ The
search), and the watched board gets back what keeping the order cost it: 198 one-suit
deals inside the ten seconds where the six above them answered 159, 187 two-suit where
they answered 159, and 164 four-suit where they answered 152 — each within one of the
fold applied throughout, the 2026-10-01 rows before those six. Every proof stands with
column order kept: the same 2, 5 and 8 deals come back unwinnable, the slowest of them
(two-suit #105) in under seven seconds, so none of them is lost to the wait. Uncapped
it answers more than either: seven more two-suit deals and five more four-suit than
with column order kept throughout, and the one-suit mean back under a tenth of a
second. Measured with three soaks at once, the capped three and then the uncapped.

**The last three are the same uncapped soaks from the `solver-soak` workflow**, each
pack split across eight CI runners: the same counts on all three packs, and the same
worst deal on all three but the 4-suit Held (#108 rather than #147, both at 289 MB).
They are another machine, so they confirm the counts, not the times. Each pack took
under four minutes of wall clock where one process takes over an hour.

### Why the unsolved count stands

Four-suit Spiderette leaves 16 of 200 deals unanswered at the default cap; under the
ten seconds a watched board gets it leaves 28, and the two-suit pack 8 — where every
other board answers all of them. (With columns folded throughout, four suits left 12 at
the most it may be asked to grow; that cap is not yet measured with proofs confirmed
in column order.) **Those numbers are
the record, not a target**, and this is the argument for leaving them alone rather
than tuning the heuristic or widening the budget to move them.

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
*proved* unwinnable by the ladder, and the search proves the same eight — with column
order kept, so without leaning on a fold that a board which deals can't make; the rest were
not proved either way. A deal with no line is not a deal the solver failed on, and no
one has established how many of the 12 have lines at all. "Answer more of them" is only a goal for the ones that can be
answered, and that number is unknown.

**A longer search is the wrong knob, and now for a second reason.** The budget is
capped deliberately, and § The budget has the measured case: a search never releases
what it grows, so every position a stubborn deal is allowed is memory a phone pays
for, and it is the stubborn deals that spend all of it. The bounded wait sharpens
that. On three stubborn four-suit deals — #3, #141, #147 — the old ladder spent all
700,000 of its positions and took 21 to 31 s, and ten seconds bought 217,000 to
357,000 of them. A search a player would never finish is tuning for `mise run solve`
and the CLI — worth doing only if those are who it is for, which should be said out
loud rather than assumed. The caps were raised on 2026-09-30 under exactly that
reading: they answer more for a patient caller, cost a watched board nothing it would
reach in ten seconds, and are held under the memory the ladder already spent.

**What would actually help is a cheaper proof.** A search that empties its frontier
answers a deal in milliseconds, which is well inside any wait; that is how Mini
and Micro answer every deal in the first thousand. Converting some of the 28 into
`Exhausted` would raise the answered count *within* the ten seconds, where a
longer search cannot. That is a different piece of work from tuning weights, and
it is the direction to take if this is picked up again.

Add a row rather than editing one. Two runs on different machines are two
different facts, and a heuristic change is worth a soak beside the run it
replaces.

### What thinking unasked costs

What a tab spends thinking between asks, over a whole played game: `mise run
solve-unasked` replays `Thinker`'s policy without a browser — chunks of 250 ms on
each board until the search answers or the board's `Solver.unasked` is spent, the
re-root a move leaves owing paid in the first. The game played is the line a patient
solve finds, and the player stops on every board long enough for the background to do
all it would, so this is **the most the background is given on a game won by the
solver's own line**; a player who leaves the line pays a fresh search wherever they do.
A deal with no line to play is counted as its opening board alone.

*Per game* is the whole game's unasked thinking; *opening* is the part of it spent on
the deal as laid out, before any move; *whole allowance* counts the boards that spent
all twenty seconds without an answer.

| Date | Board | Deals | Per game | Opening | Worst game | Whole allowance | Environment |
|---|---|---|---|---|---|---|---|
| 2026-10-02 | FreeCell | 1–100 | 606 ms | 20 ms | #14 at 23.8 s | 0 of 5,394 boards | Node v26.9.0, cloud sandbox, up to three soaks at once |
| 2026-10-02 | Mini | 1–100 | 3 ms | 1 ms | #10 at 24 ms | 0 of 1,187 boards | Node v26.9.0, cloud sandbox, up to three soaks at once |
| 2026-10-02 | Micro | 1–100 | 3 ms | <1 ms | #2 at 21 ms | 0 of 1,049 boards | Node v26.9.0, cloud sandbox, up to three soaks at once |
| 2026-10-02 | Simple Simon | 1–50 | 761 ms | 94 ms | #17 at 8.0 s | 0 of 3,799 boards | Node v26.9.0, cloud sandbox, up to three soaks at once |
| 2026-10-02 | Spiderette · 1 suit | 1–50 | 773 ms | 38 ms | #49 at 8.7 s | 0 of 3,627 boards | Node v26.9.0, cloud sandbox, up to three soaks at once |
| 2026-10-02 | Spiderette · 2 suits | 1–30 | 8.1 s | 977 ms | #8 at 47.2 s | 1 of 2,554 boards | Node v26.9.0, cloud sandbox, up to three soaks at once |
| 2026-10-02 | Spiderette · 4 suits | 1–20 | 26.0 s | 3.6 s | #3 at 183.0 s | 5 of 1,845 boards | Node v26.9.0, cloud sandbox, up to three soaks and the browser suite at once |

**Most of it is not the opening board, and none of it is searching.** The opening
board is answered in under a tenth of a second on average everywhere but the two- and
four-suit packs. After that, a move along a line already found grows nothing: the
re-root walks what the graph keeps (§ Re-rooting), meets the finishing position under
the line's last node on the way, and has the line again before a single position is
grown. Followed move by move along the line the search itself holds, FreeCell #14,
#5 and #24680, Simple Simon #17, two-suit #8 and four-suit #3 grew **no positions on
any of their 50–100 moves**; the whole of each game's bill was the walk, from about
15 ms a move on FreeCell #5 to 2.7 s on four-suit #3, whose graph is the biggest. A
move *off* the line is real work — on FreeCell #14 the other opening moves each grew
2,000–35,000 positions before answering. The worst games above are deals whose
opening board went unanswered for a while, so a large graph was grown before the line
was found and then walked on every move: four-suit #3 spent 60 of its 183 seconds on
three boards that used their whole allowance, and the rest walking. Making the walk
cheaper — or skipping it for a move that is the line's next (#524) — is what would bring
the per-game figure down; the allowance only bounds a board.

**Twenty seconds is two interactive asks**: long enough that a board the search can
answer at all is almost always answered unasked first — no FreeCell, Mini, Micro,
Simple Simon or one-suit board in these ranges spent it, and 6 of some 8,000
Spiderette boards did — and short enough that a deal that will never answer costs a
pause twenty seconds and no more. A game is not bounded by it: what bounds a game is
the player, who has to stop on a board for a second and a half before it is thought
about at all.

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
  that holds per board is § Memory tiers' to say.
- **A node is grown on one board, in place** (`Board.res`). It is stood on once —
  read out of the arena, or its nearest kept ancestor's position read and the moves
  down from there played — and then each of its moves is played, hashed, looked up,
  weighed and taken back. No position is copied per child; what that bought is
  § On making this faster.
- **The open list is a binary heap** (`Solver.Heap`) of node indices, not a sorted
  array: it's pushed and popped hundreds of thousands of times per deal, and
  re-sorting it that often is the whole cost of the search. A priority is read off
  the node when two are compared, so a heap stores nothing but the index and where
  each node sits in it.
- **The visited set is a hash table, and a hit is checked.** It files each node by
  `Board.hash`, which agrees with `Position.key` — two positions that differ only in
  *which* free cell holds what are the same position, and so are two that differ only
  in which column holds what, **once the stock is out** — and a hash that matches counts as seen only once the node's position, stood on a second
  board, is `Board.alike` the one asked about. A collision taken for "seen" would prune a
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
- **While there is a stock, column order is part of the position**, and the two
  column prunings wait for it to run out. A deal lands one card on each column in
  turn, so the same piles in another column order are dealt other cards: a run into
  the second empty column is not the move into the first, and a whole column moved
  into an empty one is not a rename. The key, the hash and both `alike`s keep the
  columns in order while `stock` is not empty, and fold them only once it is. A
  board that never deals is untouched by this. Spiderette rows whose Environment
  doesn't say *column order kept* were measured with the fold applied throughout — a
  position could be pruned as seen when the board it stood for was another — so
  their unwinnable deals were proved only under it.
- **But a search on a board that deals looks with the columns folded, and proves with
  them kept.** Keeping the order multiplies the graph by every seat a pile could sit
  in, and a watched board pays for that in answers it doesn't reach in ten seconds.
  The fold costs a line nothing: every node is still a real position its parent's move
  leads to, so a line found under it is a line, played move by move against the
  reducer like any other. What the fold can't give is a proof — a position pruned as
  seen may have been another board — so a folded search whose frontier empties is
  **grown again from its root with column order kept** (`Search.confirm`), and only
  that search can answer `Exhausted`. Proofs under the fold are small, so the second
  search is usually as quick; when it isn't, the deal comes back out of time or out of
  room, never `Unwinnable`. The fold is a flag on the graph and every board it loads
  (`Board.fold`), not a change to `Position`, whose key keeps column order whatever the
  search does. Spiderette rows whose Environment says *folded to look* were measured so.

### The budget

Each board gets **two heaps over one search**, and a cap on what it may hold, in bytes:
the arrays its graph and heaps keep (`Solver.Search.bytes`), which is everything it has
grown until a re-root (§ Re-rooting) lets some go. `Solver.budgetFor` picks the heaps the
same way `weightsFor` does — the law, and then whether the board deals — and the cap from
the device's memory tier (§ Memory tiers).

| Board | `heaps` |
|---|---|
| FreeCell, Mini, Micro | 2.0, 1.0 |
| Simple Simon | 1.0, 0.3 |
| Spiderette, every pack | 2.0, 1.0 |

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

**Then the cap was in positions**, until 2026-10-01: 500,000 grown positions on FreeCell
and Simple Simon and 1,000,000 on Spiderette by default — about thirty seconds of search
each on a cloud sandbox — and up to 2,000,000, 1,600,000 and 5,500,000 for a caller who
would wait (`--nodes`), the most each board could grow while its worst deal held under
what the ladder did: 334 MB on FreeCell, 533 on Simple Simon, 963 and 897 on the two- and
four-suit Spiderettes. The record's rows marked `--nodes`, or with no cap named, before
that date are those caps. A position is not a unit of memory, though — one costs from
60 bytes to 2 KB depending on the board and the deal (§ Memory tiers) — and a search a
player keeps all game is bounded by what it holds, so the cap became bytes.

**The time a default search takes now follows from the cap.** At the medium tier a
search holds 256 MB, which is a million to two million positions on most boards: seconds
for nearly every deal and about a minute for the stubborn Simple Simon ones on a cloud
sandbox, where the 500,000-position cap stopped at thirty seconds. That buys answers —
the medium tier answers every Simple Simon deal in the thousand, where the old default
left five unsolved — and costs nobody a wait: a player's ask is bounded by `interactive`
and a script's by `patient`, and only `mise run solve` with no `--limit` searches to the
cap, because that is what the benchmark measures.

### Memory tiers

The cap is one of three numbers, `Solver.capOf`:

| Tier | Cap | Chosen for |
|---|---|---|
| `Small` | 128 MB | under 4 GB of `deviceMemory`; with none, an iPhone or iPad |
| `Medium` | 256 MB | 4 to 8 GB; with none, anything else — and every caller in Node |
| `Large` | 768 MB | 8 GB, which is as high as `deviceMemory` reads |

How the web app chooses, the setting that overrides it, and the reload that lowers it:
`docs/solver-next.md` § Memory. A search that reaches its cap answers `Full`, and the
player is told it ran out of room in megabytes, an answer about the budget rather than
the board (`Command.autoplayOutOfRoom`). The cap is checked before each position is
grown and an array grows by a quarter at a time, so a search can pass its cap by up to a
quarter of its largest column before it stops.

**What a tier is in positions** depends on the board, and `mise run solve` reports it:
each deal's bytes per position grown, and the figure over the range. Measured on
2026-10-01 (Node v26.9.0, cloud sandbox, five soaks and the browser suite at once — so
read the counts, not the times), over the deals that held at least 10 MB, since a
search's first arrays are sized ahead of what it grows and a deal answered in a few
hundred positions reads as kilobytes each:

| Board | Deals | Wait | Deals over 10 MB | Bytes a position: over them all | median | most | Held, most |
|---|---|---|---|---|---|---|---|
| FreeCell | 1–1000 | none | 5 | 276 | 254 | 681 | #150 at 25 MB |
| Simple Simon | 1–1000 | none | 25 | 117 | 148 | 240 | #766 at 164 MB |
| Spiderette · 4 suits | 1–200 | 10 s | 76 | 122 | 124 | 973 | #199 at 81 MB |
| Spiderette · 2 suits | 1–200 | 10 s | 68 | 274 | 257 | 2,035 | #183 at 96 MB |
| Spiderette · 1 suit | 1–200 | 10 s | 83 | 311 | 302 | 1,743 | #179 at 91 MB |

The figure is a fact about the arrays, not about Node: the browser's worker grows the
same `Graph` in the same typed arrays, and `Search.bytes` reads their lengths, so a
position costs the same in Chrome. The spread is the frontier: a position's children are
held as open nodes until they are grown, and a board with many moves from each position
holds many of them per position grown.

So at the medium tier a search holds about two million Simple Simon or four-suit
positions and about a million on the other boards; the small tier half that. **The small
tier is set by the ten-second ask**: the most any board held in ten seconds here is 96 MB
(two-suit #183), so a single ask fits under 128 MB on every board, and what the tier
bounds is a search asked again and again, or kept open across a game. The counts under
the wait, beside the record's rows in § What the interactive wait costs: 156 four-suit
deals solved and 8 proved, 161 and 5 on two suits, 164 and 2 on one suit, with every
unsolved deal out of time rather than full; and with no wait, FreeCell 1000 of 1000 and
Simple Simon 944 solved and 56 proved — every deal answered.

**Not yet measured: the small tier on an old phone.** It is the number most likely to
be wrong, and the reload that lowers a tier is the backstop for it being too high; a
device named here, and what it held before it was killed, is what would settle it.

### Re-rooting

What a player pays on every move with a search open: `Search.moved`, and the walk the
next `think` starts with to keep what is reachable from the new board and let go of the
rest. The rule and its repairs are `docs/solver-next.md` § Re-rooting; this is what it
costs. `mise run solve -- --reroot` measures it: once a deal's search has answered, the
board moves one move — the line's first — and the search re-roots there, then the move
is taken back and it re-roots again, and each re-root is timed with the nodes it kept.

| Date | Board | Deals | Nodes kept | Per thousand kept | Worst | Environment |
|---|---|---|---|---|---|---|
| 2026-10-01 | FreeCell | 1–200 | 3.3 M | 8.2 ms | #150, 4.8 s to keep 530,000 | Node v26.9.0, cloud sandbox, four runs at once |
| 2026-10-01 | Mini | 1–200 | 27,000 | 18.3 ms | #80, 10 ms to keep 306 | Node v26.9.0, cloud sandbox, four runs at once |
| 2026-10-01 | Simple Simon | 1–100 | 6.5 M | 7.3 ms | #60, 9.7 s to keep 1,354,000 | Node v26.9.0, cloud sandbox, four runs at once |
| 2026-10-01 | Spiderette · 2 suits | 1–40 | 4.8 M | 8.3 ms | #6, 8.4 s to keep 976,000 | Node v26.9.0, cloud sandbox, four runs at once |
| 2026-10-01 | Spiderette · 4 suits | 1–20 | 15.3 M | 7.7 ms | #3, 20.0 s to keep 2,675,000 | Node v26.9.0, cloud sandbox, four runs at once |
| 2026-10-01 | FreeCell | 1–200 | 3.3 M | 6.0 ms | #150, 3.1 s to keep 530,000 | Node v26.9.0, cloud sandbox, five runs at once; grown on a `Board` |
| 2026-10-01 | Mini | 1–200 | 27,000 | 11.9 ms | #2, 10 ms to keep 49 | Node v26.9.0, cloud sandbox, five runs at once; grown on a `Board` |
| 2026-10-01 | Simple Simon | 1–100 | 6.5 M | 5.4 ms | #60, 7.1 s to keep 1,354,000 | Node v26.9.0, cloud sandbox, five runs at once; grown on a `Board` |
| 2026-10-01 | Spiderette · 2 suits | 1–40 | 4.8 M | 6.0 ms | #6, 6.0 s to keep 976,000 | Node v26.9.0, cloud sandbox, five runs at once; grown on a `Board` |
| 2026-10-01 | Spiderette · 4 suits | 1–20 | 15.3 M | 5.9 ms | #3, 15.3 s to keep 2,675,000 | Node v26.9.0, cloud sandbox, five runs at once; grown on a `Board` |
| 2026-10-01 | Spiderette · 1 suit | 1–40 | 465,000 | 6.2 ms | #21, 0.3 s to keep 44,500 | Node v26.9.0, cloud sandbox, three runs at once; folded to look |
| 2026-10-01 | Spiderette · 2 suits | 1–40 | 7.7 M | 6.0 ms | #6, 16.5 s to keep 2,440,000 | Node v26.9.0, cloud sandbox, three runs at once; folded to look |
| 2026-10-01 | Spiderette · 4 suits | 1–20 | 31.1 M | 6.0 ms | #7, 36.7 s to keep 5,111,000 | Node v26.9.0, cloud sandbox, three runs at once; folded to look |

The last three rows are the Spiderette searches folded to look (§ The search), where every
row above them kept column order throughout. **The cost a node is unchanged; the worst
re-root keeps two to three times the nodes it did, and takes that much longer**: a
two-suit #6 or four-suit #7 that ran to the cap re-roots for as long as one interactive
wait, or several. Before the fold could be re-rooted at all, the
two- and four-suit runs stopped on a panic in `Graph.collect`: a folded lookup reaches a
node in the other column order, and no move in its own leads there
(`docs/solver-next.md` § Re-rooting as built).

**About eight microseconds a node, on every board**, open and closed alike — Mini's
higher figure is graphs too small to amortise anything. The walk keeps the same nodes on a
`Board`-grown graph and costs about six microseconds a node — the last five rows —
because a transposition is checked on the second scratch board rather than on a
`Position` built for it. A graph the default cap fills
holds one to three million nodes, open and closed, so a re-root of one costs five to
twenty seconds — the interactive wait itself, or twice it — and a third to a half of
what growing it cost: Simple Simon #60 grew its graph in 24 s and re-roots it in 10,
four-suit Spiderette #3 in 62 s and 20. The time goes on lookups, as
growing did. A child grown from the node being walked by the move being replayed is
found without a comparison; every other child is a transposition, compared card for
card, and on Simple Simon that is most of them.

**That is the number that decides child links.** Storing each closed node's children
would replace those lookups with a read — four bytes an edge, several edges a node, on
a graph that holds about sixty bytes a node today (§ The search). Whether a watched
board's re-root is worth that is the decision this measurement is for, and it is not
taken here.

**What a re-root holds.** `effort.bytes` drops as it should: the kept nodes are copied
into arrays sized to hold them, so moving one move on from two-suit Spiderette #6 at a
300,000 cap took the search from 33 MB to 8. The cap counts the grown positions a
search *holds*, so a re-rooted search that grows back to it holds what a fresh one from
the same board does at the cap, or less — 36 MB against 38 on that deal. Short of the
cap it can hold more on the way to a line: it carries a frontier ordered from where it
was opened, and Simple Simon #60 one move on found its line holding 51 MB where a fresh
search from that board found one at 16. The Held column, the most a deal holds, is
bounded by the cap either way.

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
Re-profiled before it, the collector was still ~23%, now behind `applyMove`'s
`copy`, and the estimate was that make/unmake against one mutable board would take
most of that too: 3–4× available without leaving the language.

**Make/unmake went in last, and bought 1.8–2.7× a deal** — the 2026-10-01 rows, each
soaked beside the build before it. The search grows a node on one `Board`, playing
each move and taking it back (§ The search), and it is the same search: the same
positions grown and the same line on every deal sampled on every board, so the counts
in every table are the ones before it. `Board` had measured 1.8× per child on FreeCell
and 2.4–2.5× on Simple Simon and Spider in isolation, against `applyMove` plus `key`;
in the search the means moved by about that — 1.8× on FreeCell, 2.4× on each
Spiderette, 2.7× on Simple Simon, where reading a node back and checking a hash hit,
both now on a board rather than a fresh `Position`, are a larger share. The short packs
gain least, on deals that take a millisecond either way. **That is the low end of the
estimate, and the collector is not where it came from**: the graph in typed arrays had
already taken it from a quarter of the time to about a twentieth, and it stays there.
What went is the work of making a position per child — the copy, `Position`'s own
array-walking helpers, a position unpacked and replayed for every hash hit — spread
over a dozen functions, none of them large alone.

What is left, profiled the same way over FreeCell 1–60 and a few Simple Simon and
two-suit Spiderette deals at a smaller cap — 10 seconds of solving where the build
before took 25:

| | |
|---|---|
| ~10% | `Board.heuristic` |
| ~15% | checking hash hits — `Board.alike` and the columns it compares |
| ~12% | standing a node on the board — `Graph.standOn` and the arena it reads |
| ~5% | the collector |
| the rest | the game on the board — `play`, `takeBack`, `legalMoves`, `hash`, the collects — and the card predicates it shares with `Position`, `rankOf` alone 7% |

**It is spread thin.** No line of it is the quarter of the runtime the collector or
the string key once was, so the next gains are a few percent each — a cheaper
comparison for the hit that is laid out in the same order, or not standing a node on
the board again when the search dives into a child it has just made — and none of them
changes what the search finds. The rules are untouched by any of it.

**The interface a port would sit behind is now the one the search uses**: `Board`'s
five operations and `Graph`'s typed arrays. What WASM adds on top is the usual 1.2–2×
of integer loops over an optimising JIT — and it costs the thing having the solver in
`core` buys:

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

Three checks, each sized to the question it answers. Which a change owes depends on
what it means to do.

- **A refactor or a speed-up owes the first two, and no soak.** The question is
  whether it is the *same search*, and that has an exact answer:

  ```
  mise run solve-same                            # every board, against main
  mise run solve-same -- --game simplesimon 1-1000   # one board, a range of your own
  mise run solve-same -- --base HEAD~1           # against another commit
  ```

  It builds the base commit's solver (the merge base with `origin/main` unless
  `--base` says otherwise) under `packages/core/.baseline/`, runs it beside this tree
  deal by deal, and compares the positions grown, the moves tried, how the search
  ended and the line it found. A deal that differs is printed and the exit is
  non-zero. Every board is covered, from a sample of each sized to finish in about
  two minutes on four cores; the Spider boards, whose deals nearly all run to the
  budget, are compared under a 48 MB cap (`--mb`). Two searches that grow the same
  positions and try the same moves on a deal make every count the record keeps for
  it the same — so where `solve-same` passes, the record's counts stand. Its times
  could still have moved, and so could Held, which is how the search *stores* what
  it grew: a change to that wants `mise run solve -- --quiet` over a short range of
  each board, beside the same range on main.

  Then **is it faster** — `mise run solve-time -- --game <id> <deals>`, which times
  the base build and this one on each deal in turn, swapping which goes first, and
  prints each one's mean and worst beside the ratio. `--runs 3` for a steadier
  figure on a short range. The pair is the measurement: the two halves were taken
  together under the same load, and compare with each other and nothing else —
  not with the record, and not with a pair taken another day. A speed claim in a PR
  quotes the pair. A board whose deals take seconds wants a short range (Spiderette
  over 1–20 is a few minutes); the cheap boards can take hundreds.

- **A change meant to move the counts** — the heuristic, the weights, the caps, a
  pruning — fails `solve-same` by design, and owes a **soak of every board**, and a
  row in each table above. A change that helps the mean and doubles the worst case is
  not an improvement, and a change to the search or a shared term moves every board
  at once. Soaks run in CI, not in a session: the `solver-soak` workflow (Actions →
  solver-soak → Run workflow, on the PR's branch) takes a board, a range, an optional
  `--mb` cap and a number of jobs, splits the range across them, and prints the
  row for that board's table on the run page — and, for Simple Simon and the
  Spiderettes, its row in § What the interactive wait costs — copy them in and finish
  the Environment cell. At the default eight jobs every board is done in under five
  minutes. The ranges are the record's: 1–1000 for FreeCell, Simple Simon and the two
  short packs, 1–200 for each Spiderette pack. A change to the search wants a row at
  the medium tier, which is what a soak with no `--mb` runs at, and one at `--mb 128`,
  the small tier's cap, when it changes what a position costs (§ Memory tiers). **Don't reach for `--limit` to make that
  cheaper**: a capped run measures the cap, and a cap is exactly what would hide a
  regression in the positions it stopped short of. `mise run solve -- --quiet` is
  still how you soak a range by hand, and `--record <file>` with `mise run
  soak-summary -- <files>` is how the workflow puts its slices back together.
- **Read the Held column, not only the counts.** The tier's cap is the only thing
  bounding what a search holds (§ Memory tiers), so a change that solves more by
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
