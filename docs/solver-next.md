# The next solver: a search that follows the player

A design for replacing the search in `core/src/Solver.res` with one that can be
paused and resumed, that keeps what it has learned when the board changes, and
that knows how much memory it is holding. `docs/solver.md` describes the solver
this replaces and the record it has to match. This page is the mechanism; the
plan that builds it — the steps, their order, what is out of scope and what is
still open — is issue #497, and is not repeated here.

## Why

Three things a player can't do today, and one thing the app can't know.

- **"Try for ten more seconds."** A watched board gets `Solver.interactive`, ten
  seconds, and a stubborn deal comes back `OutOfPatience`. The search that ran
  out is gone the moment it answers: there is nothing to continue, so the only
  offer is to start again from nothing and spend the same ten seconds reaching
  the same place.
- **Keep what was learned when the board moves.** A player who asks, plays a
  move, and asks again starts the solver from scratch, though most of what it
  found a moment ago is still true. Undo is the sharpest case: the position the
  player returns to has a handful of moves, and one of them was just searched
  to exhaustion or to a line.
- **Say how big it is.** The search holds a JavaScript object per frontier node
  and a string per position seen. The "Held" column in `docs/solver.md` is what
  that comes to: the worst uncapped deal holds 334 MB on FreeCell, 533 MB on
  Simple Simon and 963 MB on two-suit Spiderette, and ten seconds of Spider holds
  400 MB and more — which iOS answers by killing the tab. The solver cannot report
  what it holds, so nothing can budget it.
- **The ladder throws work away.** Each rung starts with an empty frontier and an
  empty visited set. A four-suit Spiderette deal that beats both rungs pays for
  700,000 positions, and at ten seconds a player gets the first rung entire and
  a fraction of the second.

The first two are one mechanism, not two features, and the third is what makes
the mechanism safe to ship on a phone. The fourth falls out of the first.

## What stays

The parts of the present design that were right, and that this keeps on
purpose:

- **`Position.res` is the mirror of the rules**, held against `Reducer` by
  `Position_test`, and every predicate the search needs is the packed reading
  of one in `Rules`/`Reducer`. Nothing here is a second set of rules.
- **Three refusals, and one of them is a proof.** `Exhausted` means every
  position reachable from the start was seen and none finishes. It stays a
  proof, which constrains everything below: nothing may be pruned that wasn't
  seen, and a lookup that says "seen" has to be exact.
- **No clock of its own.** Determinism with a stopped clock is what lets a test
  pin a plan; the new search keeps it, and strengthens it (§ Budgets and time).
- **The goal is `Position.canFinish`**, a plan is a plan for a game played with
  auto-collect on, and `Solver.autoplay` does the settling.
- **Plain data across the worker seam**, a `Game.t` without its `deal`, and the
  answer `Solver.autoplayed` with `Session.adoptAutoplay` on the near side.
- **Every board the picker offers**: FreeCell, Mini, Micro, Simple Simon, the
  three Spiderettes and the three Spiders all read into the same position and
  search under the same loop. A law, a pack and a stock are data on the
  position, never a branch on a game id.

## The shape

The search stops being a call and becomes a **value**: a graph of positions the
solver has seen, rooted at the board the player is standing on, that can be
asked to grow for a while and asked again later. One instance lives for as long
as a game does.

Its interface, in `core`, is five operations:

| | |
|---|---|
| `open(position)` | a fresh graph rooted here |
| `moved(position)` | the board is now this; nothing else happens yet |
| `think(~nodes)` | re-root if the board moved, then grow the graph by up to that many expansions |
| `line()` | the moves from the current root to a finishable board, if one is known |
| `effort()` | what has been spent so far, and what is held |

`think` answers one of four ways:

| answer | meaning | today's equivalent |
|---|---|---|
| `Found` | `line()` has the moves from the current root | `Found` |
| `Exhausted` | the frontier is empty: every position reachable from the root is closed and none finishes. A proof. | `Exhausted` |
| `Paused` | this call's budget is spent and the frontier is not | `OutOfTime`, from the driver's point of view |
| `Full` | the memory cap is reached with positions still waiting | `OutOfNodes` |

The rest of this page is what it takes to make those five operations true.

## The graph

Every position the search has generated is a **node**. A node is *open* while it
sits on the frontier and *closed* once it has been expanded, and the invariant
the whole design rests on is:

> **A closed node's children are all in the graph.** Every one of them is a node,
> open or closed.

That is what makes an empty frontier a proof: if every reachable position is
closed and none finishes, none can. It is also what re-rooting has to preserve.

**Nodes are records in typed arrays, not objects** (`core/src/Graph.res`). Each
node carries its parent's index, the move that reached it from that parent, its
depth `g`, its heuristic `h`, where its position is kept (which doubles as the
status flag: open, closed, closed and kept), and its hash — twenty bytes. An open
node stores no position, because its position is its parent's with one move
played, and open nodes outnumber closed ones three to seven to one on a Spider
board. Nor does every closed node: one in four is packed into a separate arena,
one byte per card, and the rest replay the moves down from the nearest one that
was. This is the same trade the earlier search made with `parent` and `trail`,
made in bytes instead of objects, and taken one step further. **A node is a
position**: one reached again more cheaply while open takes the cheaper parent and
moves up each heap where it stands, and one already closed is left as it was
grown, because its children's moves name the columns of the layout it was grown
in.

**Lookup is by hash, membership is exact.** A hash table maps the first 32-bit
lane of `Board.hash` to a node index. A hit is *verified* by rebuilding the
node's position and comparing card for card (`Position.alike`, which agrees with
`Position.key` without spelling it). The second lane would only spare a
comparison the table almost never makes, since every true match is compared
anyway, so it is not filed. Correctness never depends on the hash, which is how
the visited set costs a few bytes per position rather than a string, while "seen"
still means seen.

**The canonical form is today's.** Cells sorted, columns sorted, the face-down
count on the column it belongs to, the stock as its length. Two positions that
differ only in which cell or which column holds what are one node.

**The frontier is a binary heap of node indices** ordered by `g + weight · h`,
read off the node whenever two are compared. There may be more than one heap over
the one graph (§ The ladder, replaced); a node popped from a heap after it has
already been closed by another is skipped. Each heap keeps where each node sits in
it, so a node reached more cheaply is moved up rather than pushed twice.

**Measured cost.** A search holds about 60 bytes per node — its twenty, both heaps'
slot and position, and the table's share — plus a quarter of a board per closed
node. Ten seconds of a Spider search holds 6 to 50 MB where it held 54 to 471
(§ What the interactive wait costs in `docs/solver.md`), and every board's bytes
are reported beside its Held.

## Re-rooting

`moved` records the board; the next `think` makes it the root. The rule is one
rule whatever moved the board:

1. Canonicalise the new board and look it up.
2. **Found:** it becomes the root.
   **Missing:** it is inserted as a new closed node, its children generated and
   looked up; any child already present keeps everything under it, and the rest
   join the frontier as open nodes.
3. Walk the graph from the root and keep what is reachable; discard the rest.

Every event the board can produce goes through that door, and undo is not a
special case:

| the player… | lookup | what survives |
|---|---|---|
| plays the move the line said | found | almost everything |
| plays a move the search ranked low | found | whatever that branch had explored |
| plays a move the search never generates (the second empty column) | found — the canonical form is the same | as above |
| deals, on a Spiderette | found — a deal is a move | as above |
| undoes or redoes | missing, then one child is the old root | everything under the old root, untouched |
| starts a new game, or loads a link | missing, no child found | nothing |
| plays with auto-collect off, onto an unsettled board | missing | nothing — the search only ever visits settled positions |

**The walk.** A depth-first traversal from the root over closed nodes, with one
mutable board played forward and back along the way. At each closed node the
moves are generated, each child looked up, and each child not yet reached in this
walk is marked kept and, if closed, descended into. Open nodes are leaves. When
the walk is done, kept nodes are copied into a fresh arena, the hash table is
rebuilt over them, and the heaps are rebuilt from the kept open nodes — a copying
collection with the root as its only root, which is also how the memory actually
comes back. Regenerating a closed node's moves costs about what expanding it
cost, without the heuristic or the heap; storing child links to avoid it is a
trade of memory for time to make once the walk has been measured, not before.

**Transpositions need one repair.** A kept node may have been discovered first
through a branch that is now being discarded, so its parent is gone. When the
walk reaches a node whose parent is not kept, it re-parents the node to the node
it arrived from. The line reconstructed through the new parent is a different
route and still a valid one.

**Depth is relative, and that is fine.** A new root inserted above an existing
child takes that child's `g` less one, which may be negative; a search that never
promised the shortest line uses `g` only to order the frontier and to drop a
position reached no more cheaply than before, and both of those want `g` values
comparable to each other, not to zero.

**The proof survives.** Every kept closed node's children were in the graph when
it was closed and are reachable from it, so they are kept too: the invariant
holds after the walk, and an empty frontier from the new root is a proof about
the new root. What would break it is evicting an open node to make room, so the
first version never does — § Memory.

**What it buys beyond reuse.** A subgraph under a move that emptied its frontier
is a move proved to lead nowhere, and after an undo the search never re-enters
it; the app could say so. A line found from the position after a move is, after
the undo, that line with one move in front of it, known at once.

### Re-rooting as built

`Solver.Search.moved` and the re-root at the top of the next `think` (or `answer`),
over `Graph.walk` and `Graph.collect`. The rule above holds; these are the places it
had to be more careful than the table says.

- **Missing with no child held is `make` again**, exactly — same graph, same heaps,
  `turn` back to the first — and so is a board that already finishes. Only `grown`,
  `tried` and the bytes carry over, because the effort is the search's and not the
  graph's.
- **The cap counts what is held.** `maxNodes` is checked against the grown nodes the
  graph still holds (`closed`), not against `grown`, which counts every position
  grown since `make`. A search a player keeps open all game would otherwise answer
  `Full` on a board it holds little of.
- **The walk replays, and mostly doesn't compare.** Each closed node's moves are
  generated on a `Board` and each child looked up by hash. A child that was grown
  from this node by this very move is that position by construction, so it is taken
  without `Position.alike`; any other match is compared, as growing it was. What is
  left is the comparisons on transpositions, and on a transposition-heavy board that
  is most of the walk (`docs/solver.md` § Re-rooting).
- **A new parent never makes a cycle.** A kept node whose parent was let go of hangs
  from the node it was first reached from. That node can lie under it in the old
  graph, so the new parents are followed up to the root, and wherever they loop the
  loop is broken at a node whose old parent was reached after it — which every loop
  has, since the node a child was reached from was always reached first.
- **Strays are adopted.** A child of a kept closed node with no node of its own is
  added as an open node — or, if it finishes, is the line. They come from the node a
  search found its line under, which it stopped growing at the finishing move; so a
  line survives a re-root whenever the node it ran through does, and a re-root after
  the line was abandoned leaves that node's other children waiting rather than lost.
- **A line is said in the player's layout.** A re-parented closed node keeps its own
  layout (its position stored, as above), so a line through it is replayed alongside
  the moves recorded against it, and each move from the first node whose layout parts
  from the replayed one is said against the replayed one instead (`Graph.translate`):
  the same cards, to and from the cells and columns that hold them there. Until a
  re-root has kept anything, layouts can't part and `lineTo` is what it was.
- **An undo of a deal stands on a longer stock** than any node had. A stored position
  keeps only its stock's length and reads the cards back off a stock the graph holds,
  so that stock is widened to the longest seen before anything is read.

**With a stock, column order is part of the position.** A deal lands one card on each
column in turn, so two boards with the same piles in a different column order are
dealt different cards. The canonical form says they are one position, and the search
grows them as one: whichever layout reached it first is the one its subtree was grown
for. For growing that is a question about the search, not about re-rooting, and it is
left open here — it means a position can be pruned as seen when the board it stands
for is not, which bears on whether `Exhausted` is a proof on a board that still deals.
For re-rooting it is a correctness question, and it is answered:

- a closed node is walked in its own layout while there is a stock, so the walk finds
  the children it was grown with rather than another layout's;
- a closed node that can only be kept by hanging it from a parent whose move lays it
  out in another column order, while there is a stock, is **reopened** instead: it
  becomes an open node in the layout its new parent gives it and is grown again from
  there, and what was under it is kept only if something else reaches it. A found root
  in another column order from the player's board is reopened likewise. `collect`
  says so by declining, and the walk runs again with the reopened nodes as leaves.

On every board without a stock the two layouts generate the same children and
translate move for move, so nothing is ever reopened there.

## The ladder, replaced

A restart cannot be resumed — "ten more seconds" has no meaning across one — so
the rungs of `Solver.ladderFor` go, and one continuous search takes their place.

`docs/solver.md` § The ladder records that different weights catch different
deals: FreeCell's first rung is greedy because almost every deal falls to it, and
Simple Simon's is not because 1.0 solved more than 2.0. If that still holds, the
continuous form is **several heaps over one graph**, one per weight, taking turns
at expansion; a node is closed once, whichever heap popped it first, and its
children are pushed to all of them. Every heap sees every closed node's
children, so the proof property is unchanged.

The first version starts with **one heap at each board's first-rung weight** and
is soaked against the record. A second heap is added where the soak loses deals
the ladder used to find, and not otherwise: each extra heap is one more index and
priority per open node.

Measured: every board wanted the second heap, and none a third to reach its cap.
Which weights, and what each cap costs, is in `docs/solver.md` § The budget.

**The ladder was also a memory ceiling, and a continuous search gives that up.**
A rung that spends its budget releases its frontier before the next begins, which
is why a capped Spiderette deal holds 565 MB at most where an uncapped one holds
963 (`docs/solver.md` § What the interactive wait costs). One graph that only grows
has no such release, so from the day the ladder goes the cap on the graph is the
only thing bounding what a solve holds — and the soak's "Held" column is how a
change to the search is checked against that, not only its counts.

## Budgets and time

The search takes **node budgets only**. Patience — a wait, and the clock to
measure it on — moves out to the caller, who turns time into slices: run
`think(~nodes=1024)`, read the clock, repeat until the answer or the deadline.
That is today's `clockEvery` made explicit at the boundary, and it makes the
determinism property stronger than it was:

> `think(a)` then `think(b)` reaches exactly the graph `think(a + b)` reaches.

Which is the whole of what "resume" means, and a property a test can state.
`solve.mjs` and the tests, holding a stopped clock, get the same plans on every
machine as they do now; the record in `docs/solver.md` remains a measurement of
budgets rather than of waits.

`effort()` accumulates across calls: positions grown, moves tried, and now the
bytes held. `passes` goes with the ladder.

## Memory

The graph has a **cap in bytes**, and reaching it is the answer `Full` — today's
`OutOfNodes`, honestly named. The first version does not evict to stay under it,
because dropping an open node is the one thing that would turn `Exhausted` into a
lie; an eviction policy that marks the proof lost is future work, once there is a
measured reason to want it.

Where the cap comes from, in order:

1. `navigator.deviceMemory` where a browser gives it (Chromium anywhere): under
   4 GB small, 4 to 8 medium, above that large.
2. Otherwise an Apple touch device (a Macintosh or iPhone user agent with more
   than one touch point) is small. It is the platform that kills a tab without
   warning and exposes no memory figure at all.
3. Otherwise medium.
4. A setting overrides all three.
5. **The reload is the pressure signal.** A flag set when a solve starts and
   cleared when it ends; found still set on load, the last solve killed the tab,
   and the tier drops persistently. It is the only adaptive signal iOS offers.

The three tiers are three numbers in one place. What they should be is measured,
not reasoned: bytes per node from `solve.mjs` in Node, from Chrome on the dev
server, and the small tier tried on an old phone. Until the tiers land the cap is
expressed in nodes, each board's set so the most its soak holds stays under what
the restart ladder held (`docs/solver.md` § The budget).

## The worker, as a service

`Thinker` spawns a worker per question and terminates it to cancel. The graph has
to outlive a question, so the worker becomes **one per tab, held open**, and the
five operations become its protocol:

| to the worker | from the worker |
|---|---|
| `open {game, state}` | `progress {positions, frontier, bytes}` between slices, for a spinner that can say something |
| `moved {state}` | `answer {autoplayed, effort}` |
| `think {ms}` | |
| `stop` | |
| `forget` | |

The worker turns `think {ms}` into slices against its own clock, checks its inbox
between slices, and answers. **Cancel is a message**, honoured at the next slice
boundary; terminating the worker remains the fallback for one that has stopped
answering, and costs the graph. `Thinker.here` stays for a runtime with no
worker: the same five operations on the calling thread, with the whole budget in
one slice, which is what the unit suite under jsdom wants.

`TableScene` sends `moved` on every committed state — a move, an undo, a redo, a
deal, a new game — and nothing happens until someone asks. Whether the app should
*think between requests*, keeping a line warm for a hint that is a lookup, is a
product question the design leaves open and supports.

"Try for ten more seconds" is then `think {ms: 10000}` again: same graph, same
root, ten more seconds of slices, and an `effort` that says what the two asks
cost together.

## The board the search plays on

Expanding a node means playing each of its moves and canonicalising the result,
some fifteen times per node on Spider and hundreds of thousands of times a
search. `Position.applyMove` copies the whole position each time, and the copy
and the string key are, with the collector they feed, most of the runtime
(`docs/solver.md` § On making this faster).

The search therefore expands on **`Board`** (`core/src/Board.res`), the same
position laid out to be played forward and back in place: play a move, hash the
canonical form, look it up, compute `h`, insert, take the move back. No copy per
child; the arena copy happens only when a node is *closed* and its position
stored. Three of its choices matter to the search above it:

- **Unmake is a journal, not an undo record.** Every write logs what it
  overwrote, and `takeBack` replays a move's writes in reverse — so a settle that
  sent several cards home, lifted two runs and turned a card over is undone by the
  same code as a plain move. The re-rooting walk leans on this: it plays and takes
  back arbitrary moves and never has to know what each one did.
- **Moves are packed ints**, so listing a node's moves allocates one array; the
  node record's `move` field is that int.
- **The hash is not exact and says so**, which is why membership verifies.

`Position.res` keeps its job at the seam — `ofGameState`, `toAction`,
`describeMove`, `key` — and has a second one: **the oracle**. `Board_test` walks
every board the picker offers along a solver's line with random excursions off it,
playing and taking back every legal move at every step against
`Position.applyMove`, and demanding the same legal moves, position, `canFinish`,
heuristic and hash. That is a stronger mirror than one solved game replayed, and
it is what would let this board be written in another language later without the
rules coming loose. `Solver.weights` is a re-export of `Board.weights` so the
search can depend on `Board` without a cycle.

## WebAssembly, later

Not part of this effort, and the design keeps the door open rather than
deciding. The compact board and the node arena are exactly the part that ports:
integer loops over typed arrays behind five operations. What a port would add is
the usual factor on those loops, a linear memory whose size is set rather than
inferred and whose `grow` fails where it can be caught, and a state that
snapshots by copying bytes. What it costs is the second toolchain in `mise.toml`
and the rules crossing the seam — which is what the oracle test above is for.
Measure the ReScript engine against the record first; if it falls short, the
interface does not change.
