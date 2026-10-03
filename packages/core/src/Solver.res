// A best-first solver over `Position` — the "brain" a driver plays with, for either
// of the two games `Position.law` names.
//
// **The contract, the benchmark record and the heuristic are in `docs/solver.md`.**
// Read that before retuning; `mise run solve -- --quiet 1-1000` is how a change
// here is measured, and the doc holds the run to beat.

// --- The heuristic -----------------------------------------------------------

// Heuristic term weights, kept nameable so they can be measured rather than
// guessed — `search` takes them as an argument, which is how these were chosen
// and how a new tuning is compared against them. What each term charges for, and
// why the two mobility terms are load-bearing, is in `docs/solver.md`.
type weights = Board.weights = {
  remaining: int,
  buried: int,
  seam: int,
  cell: int,
  emptyColumn: int,
  stock: int,
}

let freecellWeights = {remaining: 2, buried: 2, seam: 1, cell: 3, emptyColumn: 3, stock: 0}

// The same terms under Simple Simon, where there are no cells to charge for,
// a seam is a break in a *same-suit* run — the join the game is really about — and
// `remaining` has nothing to steer (a run is collected the moment it forms, never
// by choice), so it is zero rather than a number that measured as no number at all.
let simonWeights = {remaining: 0, buried: 1, seam: 2, cell: 0, emptyColumn: 4, stock: 0}

// Simple Simon's again, for a board that deals. **Only `stock` differs, and it is not
// a rounding term** — without it the search never deals at all: a row lands seven
// cards across seven columns and every one of them is a fresh seam, so a deal looks
// like pure damage next to any tidying move, and the search spends its whole budget
// tidying a board it can only win by dealing. Charging for the undealt cards is what
// makes "get the row down" worth the mess it makes.
let spideretteWeights = {...simonWeights, stock: 5}

// Which of the three a board is weighed by. The law picks two of them; the third is
// picked by whether there is a stock to deal from, which is a fact about the *board*
// and not about its rules — Spiderette between deals is Simple Simon. So a Spiderette
// position whose stock is out is weighed as what it has become.
let weightsFor = (s: Position.t): weights =>
  switch s.law {
  | Position.FreeCell => freecellWeights
  | Position.SimpleSimon => Array.length(s.stock) > 0 ? spideretteWeights : simonWeights
  }

// The cards the game is waiting on, as a flag per card number — scratch for
// `heuristic`, filled afresh each call rather than allocated each call. 52 long
// whatever the pack: card numbers are `Position`'s, and a short deck uses the same
// numbering with gaps in it.
let wanted = Array.make(~length=52, false)

// Distance-to-go estimate: one term per way a position can be bad, each scaled by
// its weight. The terms are named in the comments below and tabulated in
// `docs/solver.md`; two of them read differently under each law, and the reading
// is said where it happens.
let heuristic = (s: Position.t, w: weights): int => {
  let h = ref((s.pack.size - Position.foundationTotal(s)) * w.remaining)

  // Which cards are *wanted* — the ones whose burial costs. Under FreeCell, the
  // next card each foundation needs. Under Simple Simon, for every run on the
  // tableau, the same-suit card one rank above its bottom: the card the run has to
  // be carried onto next. (A run founded by the pack's highest card wants nothing;
  // it is the base.)
  wanted->Array.fill(false, ~start=0, ~end=52)
  switch s.law {
  | Position.FreeCell =>
    for i in 0 to Array.length(s.pack.suits) - 1 {
      let suit = s.pack.suits->Array.getUnsafe(i)
      let home = s.found->Array.getUnsafe(suit)
      if home < s.pack.ranks {
        wanted->Array.setUnsafe(suit * 13 + home, true)
      }
    }
  | Position.SimpleSimon =>
    for col in 0 to Array.length(s.casc) - 1 {
      let pile = s.casc->Array.getUnsafe(col)
      for i in 0 to Array.length(pile) - 1 {
        let card = pile->Array.getUnsafe(i)
        let founds =
          i == 0 || !Position.follows(s.law, ~below=pile->Array.getUnsafe(i - 1), ~above=card)
        if founds && Position.rankOf(card) < s.pack.ranks {
          wanted->Array.setUnsafe(card + 1, true) // the same suit, one rank up
        }
      }
    }
  }

  for col in 0 to Array.length(s.casc) - 1 {
    let pile = s.casc->Array.getUnsafe(col)
    let depth = Array.length(pile)
    if depth == 0 {
      h := h.contents - w.emptyColumn // room to manoeuvre
    }
    for i in 0 to depth - 1 {
      let card = pile->Array.getUnsafe(i)

      // Buried where the game wants it: every card above it must move first.
      if wanted->Array.getUnsafe(card) {
        h := h.contents + (depth - 1 - i) * w.buried
      }

      // A break in the run a hand could lift is a seam that has to be undone.
      if i > 0 && !Position.follows(s.law, ~below=pile->Array.getUnsafe(i - 1), ~above=card) {
        h := h.contents + w.seam
      }
    }
  }
  // A card parked in a cell is a card in the way.
  h := h.contents + (Array.length(s.cells) - Position.emptyCells(s)) * w.cell

  // A card still in the stock is a card the game hasn't reached yet. `remaining`
  // charges for cards off the foundations and this charges for the ones not even on
  // the table; under Simple Simon's law, where `remaining` is zero, it is the only
  // term that makes progress through the pack worth anything at all.
  h.contents + Array.length(s.stock) * w.stock
}

// --- A binary heap of node indices -------------------------------------------
// Its own little module rather than a sorted array — `docs/solver.md` § The search
// has what that is worth. It holds indices into a `Graph`, not entries: a priority is
// read off the node whenever two are compared, so a node's place in the heap is all it
// costs — four bytes for the slot, four for `where`.
//
// **A node is in a heap at most once.** A node reached again more cheaply has its
// priority lowered where it stands (`push` of an item already in), which is what `where`
// is for: the slot each node occupies, or -1.

module Heap = {
  type t = {mutable items: Graph.ints, mutable size: int, mutable where: Graph.ints}

  let make = (): t => {
    items: Int32Array.fromLength(0),
    size: 0,
    where: Int32Array.fromLength(0),
  }
  let size = (heap: t): int => heap.size

  // Empty again, and holding nothing.
  let clear = (heap: t) => {
    heap.items = Int32Array.fromLength(0)
    heap.size = 0
    heap.where = Int32Array.fromLength(0)
  }
  let bytes = (heap: t): int =>
    TypedArray.byteLength(heap.items) + TypedArray.byteLength(heap.where)

  let place = (heap: t, i: int, item: int) => {
    heap.items->Graph.put(i, item)
    heap.where->Graph.put(item, i)
  }

  // The item at `i` up towards the root, past every parent it now outranks.
  let siftUp = (heap: t, i: int, ~priority: int => float) => {
    let item = heap.items->Graph.at(i)
    let rank = priority(item)
    let i = ref(i)
    let sifting = ref(true)
    while sifting.contents && i.contents > 0 {
      let parent = (i.contents - 1) / 2
      let above = heap.items->Graph.at(parent)
      if priority(above) <= rank {
        sifting := false
      } else {
        place(heap, i.contents, above)
        i := parent
      }
    }
    place(heap, i.contents, item)
  }

  // Into the heap, or — for an item already in it whose priority has fallen — up to
  // where it now belongs. A priority only ever falls: a node is reached again only when
  // it is reached more cheaply.
  let push = (heap: t, item: int, ~priority: int => float) => {
    if item >= TypedArray.length(heap.where) {
      let old = TypedArray.length(heap.where)
      heap.where = Graph.widened(heap.where, Int32Array.fromLength, Graph.grow(item))
      heap.where->Graph.fillFrom(-1, ~start=old)
    }
    let at = heap.where->Graph.at(item)
    if at >= 0 {
      siftUp(heap, at, ~priority)
    } else {
      if heap.size == TypedArray.length(heap.items) {
        heap.items = Graph.widened(heap.items, Int32Array.fromLength, Graph.grow(heap.size))
      }
      heap.items->Graph.put(heap.size, item)
      heap.size = heap.size + 1
      siftUp(heap, heap.size - 1, ~priority)
    }
  }

  // The item of least priority, taken off — or -1 from an empty heap.
  let pop = (heap: t, ~priority: int => float): int =>
    if heap.size == 0 {
      -1
    } else {
      let items = heap.items
      let top = items->Graph.at(0)
      heap.where->Graph.put(top, -1)
      heap.size = heap.size - 1
      let size = heap.size
      if size > 0 {
        let item = items->Graph.at(size)
        let rank = priority(item)
        let i = ref(0)
        let sifting = ref(true)
        while sifting.contents {
          let left = 2 * i.contents + 1
          let right = left + 1
          let smallest = ref(i.contents)
          let least = ref(rank)
          if left < size {
            let p = priority(items->Graph.at(left))
            if p < least.contents {
              smallest := left
              least := p
            }
          }
          if right < size && priority(items->Graph.at(right)) < least.contents {
            smallest := right
          }
          if smallest.contents == i.contents {
            sifting := false
          } else {
            place(heap, i.contents, items->Graph.at(smallest.contents))
            i := smallest.contents
          }
        }
        place(heap, i.contents, item)
      }
      top
    }
}

// --- What a caller is willing to spend ---------------------------------------

// How much a search may hold, in three sizes of device. **The three numbers are here and
// nowhere else**: a tier is chosen once per load by whoever knows the device (the web
// app's `Device`), and a caller that knows nothing about it — the CLI, `mise run solve`,
// a test — gets `Medium`. What each holds in positions on each board, and the device each
// was tried on: `docs/solver.md` § Memory tiers.
type tier =
  | Small
  | Medium
  | Large

let capOf = (tier: tier): int =>
  switch tier {
  | Small => 128_000_000
  | Medium => 256_000_000
  | Large => 768_000_000
  }

// The tier below, for a device that has shown it can't hold this one. `Small` is the floor.
let lower = (tier: tier): tier =>
  switch tier {
  | Large => Medium
  | Medium | Small => Small
  }

let tierName = (tier: tier): string =>
  switch tier {
  | Small => "small"
  | Medium => "medium"
  | Large => "large"
  }

let parseTier = (token: string): option<tier> =>
  switch token->String.toLowerCase {
  | "small" => Some(Small)
  | "medium" => Some(Medium)
  | "large" => Some(Large)
  | _ => None
  }

// How hard a search leans on the heuristic, and how much it may hold. `heaps` is one
// weight per open list — each scales the heuristic against depth, and a search with
// more than one takes turns between them over a single graph (`Search`, below).
// `maxBytes` is what it may hold (`Search.bytes`) before it answers `Full`: the search
// lets go of nothing it has grown but what a re-root leaves behind, so this is the
// bound on a search asked again and again, or kept open all game.
//
// **The cap is a tier's, and the time a default search takes follows from it**: at the
// 60 to 600 bytes a position the boards cost, `Medium` is a few hundred thousand to a
// million and a half positions — up to about thirty seconds on a cloud sandbox. A caller
// who will wait longer, or has more room, passes a budget of its own (`solve.mjs --mb`).
// Why each pair of heaps: `docs/solver.md` § The budget.
type budget = {heaps: array<float>, maxBytes: int}

// The first weight on each board is the one almost every deal falls to; the second is
// the one that catches most of what the first misses.
let freecellHeaps = [2., 1.]
let simonHeaps = [1., 0.3]
let spideretteHeaps = [2., 1.]

// The budget a board gets on a device of `tier` — its heaps picked the same way its
// weights are, and for the same reason: a stock is a longer game, not another law.
let budgetFor = (~tier: tier=Medium, s: Position.t): budget => {
  heaps: switch s.law {
  | Position.FreeCell => freecellHeaps
  | Position.SimpleSimon => Array.length(s.stock) > 0 ? spideretteHeaps : simonHeaps
  },
  maxBytes: capOf(tier),
}

// How long the caller is willing to wait, and the clock to measure it on. **The solver
// still keeps no clock of its own** — it is handed one, the way `Session` is handed the
// clock a win is stamped with, and for the same reason: hand it a stopped clock and the
// answer is the one the node budget alone would find, on every run and every machine.
//
// What a real one buys and what it costs: `docs/solver.md` § What a caller is willing
// to spend. Read that before changing either number below.
type patience = {ms: float, clock: unit => float}

// The two waits the drivers use, named here so neither front end invents its own —
// `interactive` for a board someone is watching, `patient` for a terminal or a script.
// Thirty seconds is the most anything waits by default; longer is a caller's to ask for.
let interactive = 10_000.
let patient = 30_000.

// The most a board is thought about *unasked*: what a front end that thinks between asks
// (the web app's `Thinker`) may spend on one board before anyone presses Solve, in short
// chunks while the board is still. Not a wait — nobody is watching it — but a cost paid
// in battery by someone who never asked for it, which is why it is measured rather than
// reasoned: `docs/solver.md` § What thinking unasked costs.
let unasked = 20_000.

// `patience` resolved against the clock once, at the moment the caller asked.
type deadline = {at: float, clock: unit => float}

let deadlineFor = (patience: option<patience>): option<deadline> =>
  patience->Option.map(({ms, clock}) => {at: clock() +. ms, clock})

let past = (deadline: option<deadline>): bool =>
  switch deadline {
  | None => false
  | Some({at, clock}) => clock() >= at
  }

// How many positions a search grows between two looks at the clock — the slice a wait
// is cut into. A search grows hundreds of thousands of positions, and a clock read on
// each is a cost the answer doesn't need. The price is an overshoot of up to this many
// positions, which on the heaviest board is a third of a second: **a wait under about a
// second is not one this can keep.** Measured, per board, in `docs/solver.md`.
let clockEvery = 1024

// --- The search --------------------------------------------------------------

// Weighted best-first search from a start to the first position that
// `Position.canFinish` — as a value rather than a call. **It keeps its frontier and its
// visited set between `think`s**, so a caller can grow it for a while, look, and grow it
// again, and nothing it has seen is seen twice. That is the whole of what resuming is:
// `think(a)` then `think(b)` reaches the graph `think(a + b)` does.
//
// It takes node budgets only. Time is the caller's to turn into slices — `solveOn`
// below is that, for the callers who hold a `patience`.
//
// **Several heaps, one graph.** Each weight in the budget has its own open list, and
// they take turns growing one position each. Every child is pushed to all of them, and a
// node is grown once, by whichever pops it first — so an empty set of heaps still means
// every reachable position was grown, and `Exhausted` is still a proof. What a second
// heap buys, and on which boards: `docs/solver.md` § The budget.
//
// What it grows into is a `Graph`: a node per position, in typed arrays, and a
// visited set that answers by hash and checks the answer.
//
// **On a board that deals it looks with the columns folded and proves with them kept.**
// A fold takes the same piles in another column order for one position, which they
// aren't while a deal is still to land on them — so a line found under it is a line, and
// an emptied frontier under it is not a proof. That frontier is answered by searching
// again from the root with column order kept, and only *that* search can say
// `Exhausted`. Why both, and what each costs: `docs/solver.md` § The search.
module Search = {
  // How a `think` came back. **Three of these mean "no line", and only one of them
  // means "there is none".**
  //
  //   `Found`     — `line` has the moves from the root: the start, or the board it
  //                 was last `moved` to.
  //   `Exhausted` — the frontier is empty: every position reachable from the root was
  //                 grown, with column order kept, and none finishes. A proof.
  //   `Paused`    — this call's slice is spent and the frontier is not. Ask again.
  //   `Full`      — the search holds its `maxBytes` with positions still
  //                 waiting. It proves nothing about the deal, and asking again changes
  //                 nothing until the board moves or the cap is raised.
  type answer =
    | Found
    | Exhausted
    | Paused
    | Full

  // `grown` counts the positions taken off the frontier and grown; `tried` the moves
  // played out to see where they led, which is the bigger number and the one most of the
  // time goes into (every one of them is a `Board.play`, a hash, a lookup and a
  // `canFinish`, and a `takeBack`). Both
  // count from `make`, across every `think` and every re-root. `closed` is the grown
  // positions the graph still holds — `grown` until a re-root lets some go.
  //
  // `budget` is mutable for its `maxBytes` alone: a device found to hold less than it
  // was thought to (`limit`, below) caps a search already grown. Its `heaps` are the
  // frontiers' and never change.
  type t = {
    weights: weights,
    mutable budget: budget,
    graph: Graph.t,
    frontiers: array<Heap.t>,
    priorities: array<int => float>, // each heap's order, read off the graph
    mutable turn: int, // the heap that grows the next position
    mutable grown: int,
    mutable tried: int,
    mutable closed: int,
    mutable line: option<array<Position.move>>,
    mutable moved: option<Position.t>, // a board to re-root on at the next `think`
  }

  // Whether a search from `start` folds: whenever there is a stock, since without one a
  // fold changes nothing.
  let foldsFrom = (start: Position.t): bool => Array.length(start.stock) > 0

  // A node onto every heap, each at its own weight.
  let push = (search: t, node: int) =>
    search.frontiers->Array.forEachWithIndex((frontier, i) =>
      frontier->Heap.push(node, ~priority=search.priorities->Array.getUnsafe(i))
    )

  let waiting = (search: t): bool =>
    search.frontiers->Array.some(frontier => Heap.size(frontier) > 0)

  // The next node still open, from the heap whose turn it is — or from the next one that
  // has anything, when that one is empty. Nodes another heap already grew are dropped on
  // the way. -1 when every heap is empty.
  let next = (search: t): int => {
    let found = ref(-1)
    while found.contents < 0 && waiting(search) {
      let i = search.turn
      search.turn = mod(search.turn + 1, Array.length(search.frontiers))
      let node =
        search.frontiers
        ->Array.getUnsafe(i)
        ->Heap.pop(~priority=search.priorities->Array.getUnsafe(i))
      if node >= 0 && !Graph.isClosed(search.graph, node) {
        found := node
      }
    }
    found.contents
  }

  // A graph of one open node, `start` — or of none, with the line already known, when
  // `start` already finishes.
  let plant = (search: t, start: Position.t) =>
    if Position.canFinish(start) {
      search.line = Some([])
    } else {
      let graph = search.graph
      let board = Graph.load(graph, start)
      let hash = Graph.hash(board)
      let slot = Graph.slotOf(graph, board, ~hash)
      let root =
        graph->Graph.add(~parent=-1, ~move=0, ~depth=0, ~h=heuristic(start, search.weights), ~hash)
      graph->Graph.file(slot, root)
      search->push(root)
    }

  let make = (start: Position.t, ~budget: option<budget>=?, ~weights: option<weights>=?): t => {
    let budget = budget->Option.getOr(budgetFor(start))
    let weights = weights->Option.getOr(weightsFor(start))
    let graph = Graph.make(~fold=foldsFrom(start), start)
    let search = {
      weights,
      budget,
      graph,
      frontiers: budget.heaps->Array.map(_ => Heap.make()),
      priorities: budget.heaps->Array.map(weight =>
        node =>
          Int.toFloat(graph.depth->Graph.at(node)) +. Int.toFloat(graph.h->Graph.at(node)) *. weight
      ),
      turn: 0,
      grown: 0,
      tried: 0,
      closed: 0,
      line: None,
      moved: None,
    }
    search->plant(start)
    search
  }

  // --- Re-rooting --------------------------------------------------------------
  // The board is now `position`: the next `think` makes it the root and keeps only what
  // is reachable from there. Nothing happens until then, so a board moved twice between
  // asks is re-rooted once. The one rule it follows for a move, an undo, a deal or a new
  // game is `docs/solver-next.md` § Re-rooting.
  let moved = (search: t, position: Position.t) => search.moved = Some(position)

  // Everything let go of, and `start` planted — `make` again, keeping the effort. Folded as
  // `make` would, unless told to keep column order.
  let restart = (~fold: option<bool>=?, search: t, start: Position.t) => {
    Graph.clear(search.graph, ~fold=fold->Option.getOr(foldsFrom(start)), start)
    search.frontiers->Array.forEach(Heap.clear)
    search.turn = 0
    search.closed = 0
    search.line = None
    search->plant(start)
  }

  // The nodes the graph already holds for children of `s`.
  let known = (search: t, s: Position.t): array<int> => {
    let graph = search.graph
    let board = Graph.load(graph, s)
    Board.legalMoves(board)->Array.filterMap(move => {
      Board.play(board, move)
      let node = Graph.nodeAt(graph, Graph.slotOf(graph, board, ~hash=Graph.hash(board)))
      Board.takeBack(board)
      node >= 0 ? Some(node) : None
    })
  }

  // A child of a kept closed node the graph had no node for (`Graph.walked`): the line,
  // if it finishes, and otherwise an open node like any other a growth would have added.
  let adopt = (search: t, node: int, s: Position.t) => {
    let graph = search.graph
    let move =
      Graph.moveBetween(Graph.positionOf(graph, node), s)->Option.getOrThrow(
        ~message="a stray is not a child of the node it was found under",
      )
    search.tried = search.tried + 1
    if Position.canFinish(s) {
      if Option.isNone(search.line) {
        search.line = Some(Graph.lineTo(graph, node, ~last=move))
      }
    } else {
      let board = Graph.load(graph, s)
      let hash = Graph.hash(board)
      let slot = Graph.slotOf(graph, board, ~hash)
      if Graph.nodeAt(graph, slot) < 0 {
        let child =
          graph->Graph.add(
            ~parent=node,
            ~move,
            ~depth=graph.depth->Graph.at(node) + 1,
            ~h=heuristic(s, search.weights),
            ~hash,
          )
        graph->Graph.file(slot, child)
        search->push(child)
      }
    }
  }

  // Make `s` the root. Found in the graph, it is the root; missing, it is grown as a new
  // closed node above whatever of its children the graph holds, so an undo finds the root
  // it left as a child — and missing with none of them held, nothing survives and the
  // search starts again from `s`, as `make` would. Then everything reachable is kept
  // (`Graph.walk`, `Graph.collect`), both heaps are filled again from the kept open
  // nodes, and any line is found again from the new root: the line known before ran from
  // the old one.
  let reroot = (search: t, s: Position.t) => {
    let graph = search.graph
    Graph.widen(graph, s)
    let board = Graph.load(graph, s)
    let hash = Graph.hash(board)
    let found = Graph.nodeAt(graph, Graph.slotOf(graph, board, ~hash))
    let children = found >= 0 ? [] : known(search, s)
    if Position.canFinish(s) || (found < 0 && Array.length(children) == 0) {
      search->restart(s)
    } else {
      let root = if found >= 0 {
        found
      } else {
        // A depth one less than the shallowest child it holds, which may be negative:
        // depth only orders the frontier, so comparable is all it needs to be.
        let depth =
          children->Array.reduce(graph.depth->Graph.at(children->Array.getUnsafe(0)), (
            least,
            node,
          ) => Math.Int.min(least, graph.depth->Graph.at(node))) - 1
        let root =
          graph->Graph.add(~parent=-1, ~move=0, ~depth, ~h=heuristic(s, search.weights), ~hash)
        let board = Graph.load(graph, s)
        graph->Graph.file(Graph.slotOf(graph, board, ~hash), root)
        Graph.keep(graph, root, board)
        search.grown = search.grown + 1
        root
      }
      // A found root grown in another column order, on a board with a stock, was dealt to
      // that order (`Graph.dealsAlike`): what is under it is not what is under `s`, and it
      // is grown again from `s`.
      let reopened = Uint8Array.fromLength(graph.size)
      if Graph.isClosed(graph, root) && !Graph.dealsAlike(Graph.positionOf(graph, root), s) {
        reopened->Graph.put(root, 1)
      }
      // Walked again for as long as `collect` reopens something, which changes what the
      // walk reaches.
      let rec reach = () => {
        let walked = Graph.walk(graph, ~root, ~board=Board.load(~fold=graph.fold, s), ~reopened)
        switch Graph.collect(graph, ~root, walked, ~reopened) {
        | None => reach()
        | Some(renumbered) => (walked, renumbered)
        }
      }
      let (walked, renumbered) = reach()
      graph.start = s
      search.frontiers->Array.forEach(Heap.clear)
      search.closed = 0
      for node in 0 to graph.size - 1 {
        if Graph.isClosed(graph, node) {
          search.closed = search.closed + 1
        } else {
          search->push(node)
        }
      }
      search.line = None
      walked.strays->Array.forEach(((node, child)) =>
        search->adopt(renumbered->Graph.at(node), child)
      )
    }
  }

  // A folded search whose frontier has emptied with no line, grown again from its root
  // with column order kept — the search whose emptied frontier is a proof. A folded root
  // with no stock left is already that search: with nothing to deal, a fold changes
  // nothing.
  let confirm = (search: t) =>
    if search.graph.fold && Option.isNone(search.line) && !waiting(search) {
      let start = search.graph.start
      if Array.length(start.stock) > 0 {
        search->restart(start, ~fold=false)
      }
    }

  // The board `moved` named, made the root — if there is one waiting.
  let follow = (search: t) =>
    switch search.moved {
    | None => ()
    | Some(s) =>
      search.moved = None
      search->reroot(s)
    }

  // What the search holds, in bytes: its graph and its heaps, read off the arrays.
  let bytes = (search: t): int =>
    search.frontiers->Array.reduce(Graph.bytes(search.graph), (sum, frontier) =>
      sum + Heap.bytes(frontier)
    )

  // A cap of `maxBytes` from here on, for a search grown under another. Lowered below
  // what it holds, the next `think` answers `Full` without growing anything.
  let limit = (search: t, ~maxBytes: int) => search.budget = {...search.budget, maxBytes}

  // Positions found and not yet grown: every node in the graph is one or the other.
  let frontier = (search: t): int => search.graph.size - search.closed

  // What the search knows now, without growing it — the answer a `think` of nothing
  // gives, re-root included. An emptied frontier is a proof whatever else was running
  // out, so it is read before either budget.
  let answer = (search: t): answer => {
    search->follow
    search->confirm
    if Option.isSome(search.line) {
      Found
    } else if !waiting(search) {
      Exhausted
    } else if bytes(search) >= search.budget.maxBytes {
      Full
    } else {
      Paused
    }
  }

  // Grow the search by up to `nodes` more positions, and say where that left it.
  let think = (search: t, ~nodes: int): answer => {
    search->follow
    let {weights, budget: {maxBytes}, graph} = search
    let until = search.grown + nodes
    while (
      {
        search->confirm
        Option.isNone(search.line)
      } &&
      waiting(search) &&
      bytes(search) < maxBytes &&
      search.grown < until
    ) {
      let node = next(search)
      if node >= 0 {
        // The node is stood on once, and each child is the one board with a move played
        // on it and taken back — nothing copied per child.
        let board = graph.board
        Graph.standOn(graph, node, board)
        Graph.close(graph, node, board)
        search.grown = search.grown + 1
        search.closed = search.closed + 1
        let g = graph.depth->Graph.at(node) + 1
        let moves = Board.legalMoves(board)
        let i = ref(0)
        while Option.isNone(search.line) && i.contents < Array.length(moves) {
          let move = moves->Array.getUnsafe(i.contents)
          Board.play(board, move)
          search.tried = search.tried + 1
          let hash = Graph.hash(board)
          let slot = Graph.slotOf(graph, board, ~hash)
          let prior = Graph.nodeAt(graph, slot)
          if prior >= 0 {
            // Seen. A closed position stays as it was grown; an open one reached more
            // cheaply takes the cheaper way, and moves up every heap to match. A
            // position reached no more cheaply than before teaches nothing new.
            if !Graph.isClosed(graph, prior) && graph.depth->Graph.at(prior) > g {
              graph->Graph.reparent(prior, ~parent=node, ~move, ~depth=g)
              search->push(prior)
            }
          } else if Board.canFinish(board) {
            search.line = Some(Graph.lineTo(graph, node, ~last=move))
          } else {
            let child =
              graph->Graph.add(
                ~parent=node,
                ~move,
                ~depth=g,
                ~h=Board.heuristic(board, weights),
                ~hash,
              )
            graph->Graph.file(slot, child)
            search->push(child)
          }
          Board.takeBack(board)
          i := i.contents + 1
        }
      }
    }
    answer(search)
  }

  // The moves from the start to a finishable board, once one is known.
  let line = (search: t): option<array<Position.move>> => search.line
}

// How a solve came to a stop, for the callers above the search — `Search.answer` with
// a clock read against it. **Three of these mean "no line", and only one of them means
// "there is none".**
//
//   `Found`      — a line.
//   `Exhausted`  — the search proved there is none, and what `autoplay` answers
//                  `Unwinnable` from.
//   `Full`       — the search holds all its budget lets it. It proves nothing about
//                  the deal.
//   `OutOfTime`  — the caller's `patience` ran out with the search still `Paused`. It
//                  proves nothing about the deal *or about the budget*, and it isn't
//                  folded into `Full` because it is the one refusal a more patient
//                  caller might turn into an answer.
type ending =
  | Found
  | Exhausted
  | Full
  | OutOfTime

// What a solve cost, for a front end that wants to say how hard the answer was to find,
// and not only what it was — counted from the search's start, so a search asked twice
// reports both asks together.
//
//   `positions` — boards taken off the frontier and grown.
//   `moves`     — moves played out to see where they led (the "and then what?"
//                 count; several per position, and the bigger number by far).
//   `ending`    — how the last ask stopped. The three kinds of "no" are told apart
//                 there rather than here.
//   `bytes`     — what the search holds, read off its own arrays (`Search.bytes`). A
//                 search lets go of nothing but what a re-root leaves behind, so since
//                 the last one this is also the most it held.
//   `unasked`   — how many of `positions` were grown by thinks nobody asked for, before
//                 this ask. The search can't tell one think from another, so this is
//                 always 0 here and the caller that does the asking fills it in
//                 (`SolverWorker`).
//
// **Deliberately no elapsed time.** `patience` is a limit handed in, not a clock the
// solver keeps, and nothing here reports how long anything took: a caller times its own
// call, the way `solve.mjs` and `Session.autoplay` do. What that buys:
// `docs/solver.md` § The contract.
type effort = {positions: int, moves: int, ending: ending, bytes: int, unasked: int}

// The two readings of `ending` a driver outside ReScript needs: `solve.mjs` counts its
// deals by them and gates its exit code on the first. *Asked* rather than compared,
// because how the compiler spells a constructor in the JavaScript it emits is its own
// business — the same bargain `stepFor` strikes for a move.
// What a search has cost so far, and how `answer` — its last — left it.
let effortOf = (search: Search.t, answer: Search.answer): effort => {
  positions: search.grown,
  moves: search.tried,
  ending: switch answer {
  | Search.Found => Found
  | Search.Exhausted => Exhausted
  | Search.Full => Full
  | Search.Paused => OutOfTime
  },
  bytes: Search.bytes(search),
  unasked: 0,
}

let provedUnwinnable = (e: effort): bool => e.ending == Exhausted
let ranOutOfTime = (e: effort): bool => e.ending == OutOfTime

// Think on a search for as long as the caller will wait: a slice of `clockEvery`
// positions, a look at the clock, and again — until the search answers or the wait is
// over. The clock is read once as the wait begins and once before each slice, so a
// caller already out of time is told so without being charged for a slice, and a search
// that already knows its answer gives it without reading the clock at all.
//
// It can be called again on the same search, and carries on from where the last call
// left it.
let solveOn = (search: Search.t, ~patience: option<patience>=?): (
  option<array<Position.move>>,
  effort,
) => {
  let deadline = deadlineFor(patience)
  let answer = ref(Search.answer(search))
  while answer.contents == Search.Paused && !past(deadline) {
    answer := Search.think(search, ~nodes=clockEvery)
  }
  (Search.line(search), effortOf(search, answer.contents))
}

// Solve to the finishable position — or `None` when the budget runs out or the caller's
// patience does, neither of which proves anything about the deal unless the effort says
// `Exhausted`. Reports what the search cost alongside the line.
let solveWithEffort = (
  start: Position.t,
  ~budget: option<budget>=?,
  ~patience: option<patience>=?,
): (option<array<Position.move>>, effort) => solveOn(Search.make(start, ~budget?), ~patience?)

// The line alone, for the callers that only ever wanted that.
let solve = (start: Position.t, ~budget: option<budget>=?, ~patience: option<patience>=?): option<
  array<Position.move>,
> => Pair.first(solveWithEffort(start, ~budget?, ~patience?))

// Wanting this faster? It has been profiled, and the answer isn't the one it looks
// like — read `docs/solver.md` § On making this faster first.

// --- Playing the plan on a real board ----------------------------------------

// The moves to a finishable board from a real `GameState` — the game-facing entry
// point (a hint button, a demo that plays itself, a test that needs a game played
// through). `None` when the board isn't one the solver models or the search found no
// line within its budget or the caller's patience.
//
// **A plan is a plan for a game played with auto-collect on** — the warning is on
// `Position.applyMove`, which is where the settling happens.
let plan = (~game: Game.t, ~patience: option<patience>=?, state: GameState.t): option<
  array<Position.move>,
> => Position.ofGameState(~game, state)->Option.flatMap(position => solve(position, ~patience?))

// The next move to play, as the action a driver dispatches — the smallest useful
// thing to ask the solver, and the one the game itself will want first.
let hint = (~game: Game.t, ~patience: option<patience>=?, state: GameState.t): option<
  Reducer.action,
> =>
  plan(~game, ~patience?, state)
  ->Option.flatMap(moves => moves->Array.get(0))
  ->Option.flatMap(move => Position.toAction(~game, state, move))

// --- Autoplay: the plan, played out ------------------------------------
// `plan` says which moves win from here and `Position.toAction` says one of them in
// the reducer's terms. What's left — running them one after another against a real
// `GameState` and keeping the board in step — is the part *both* front ends would
// otherwise write for themselves, so it's written here once and they play the same
// game (the rule the shared `Command` grammar exists for).
//
// **The settling is done here, not by the caller**, and that is the load-bearing
// bit — the reason is the last row of `docs/solver.md` § The packed position.
//
// It stops where the search stops, at the first position `Reducer.canFinish` clears.
// Sweeping the board home from there is the finish both drivers already have, so
// autoplay doesn't grow a second copy of it — it thinks, and hands over.

// One planned move, played: the move said in the reducer's own vocabulary, and the
// settled board it leaves behind. Enough for a driver to record one undoable step per
// move without re-deriving a position the plan already knows — and the `action` is
// what lets it *say* what it played, in the same words a typed move is logged in.
//
// `moved` is what a driver that *animates* the line needs: the cards this step
// displaces, in the order they moved — the ones the action names, then whatever the
// settle swept up behind them. It's core's to report for the same reason the settling
// is core's to do: the collection happens in here, so a driver reading only `state`
// would have to re-derive which cards it took to get there.
type played = {
  action: Reducer.action,
  state: GameState.t,
  moved: array<Card.card>,
}

// What autoplay found. The four refusals answer four different questions and read as
// four different sentences (`Command.autoplayUnknownBoard` / `autoplayOutOfRoom` /
// `autoplayUnwinnable` / `autoplayOutOfPatience`): a board the solver doesn't
// understand, one it filled its memory on without a win, one it has proved can't be won,
// and one nobody finished looking at. A `Played` with no steps is none of them — it's a
// board already finishable, where there was nothing left to think about.
//
// `Played` carries what the search cost alongside the line it found (`effort`), so a
// front end can say how hard the answer was to come by. It travels with the steps
// rather than being asked for separately because it's a fact about *this* answer —
// ask again and you'd be timing a second search.
type autoplayed =
  | Played({steps: array<played>, effort: effort})
  | UnknownBoard // not a board `Position.ofGameState` can read — neither game, or a shape of one it doesn't model
  // The search holds all its budget lets it, `bytes` of it, with positions still waiting:
  // an answer about the budget, which proves nothing about the deal.
  | OutOfRoom({bytes: int})
  | Unwinnable // every reachable position was searched and none wins (`ending` says `Exhausted`)
  // The caller's own `patience` ran out with the search still going — an answer about the
  // wait that was asked for, not about the board. It reads as its own refusal because it
  // is the only one where asking again, somewhere more patient, is worth anything.
  | OutOfPatience

// The post-move settle the plan assumes: safe auto-collect, standing aside once the
// board is finishable — `Position.applyMove`'s own rule, said against a real state.
// Reports the cards it sent home along with the settled board, so a step can say
// everything that moved and not just where the board ended up.
let settle = (~game: Game.t, state: GameState.t): (GameState.t, array<Card.card>) =>
  if Reducer.canFinish(~game, state) {
    (state, [])
  } else {
    Reducer.autoCollect(~game, state)
  }

// The cards an action names, bottom-first, which is the order they'd be lifted in.
// A column reorder names none — it moves whole piles rather than cards.
//
// A `Deal` names none either, but it does move cards, and a driver animating the line
// needs them: `Reducer.nextDeal` says which they are and in what order they land, so
// this asks the board it is about to be played on rather than recomputing it. Read
// against the state *before* the deal, which is the only state that still has them.
let namedCards = (~game: Game.t, state: GameState.t, action: Reducer.action): array<Card.card> =>
  switch action {
  | Reducer.Move({card}) => [card]
  | Reducer.MoveRun({cards}) => cards
  | Reducer.Deal => Reducer.nextDeal(~game, state)
  | Reducer.MoveColumn(_) => []
  }

// What a search's line and effort come to on the real board it started from. The half of
// `autoplay` after the thinking, for a caller that does the thinking in slices of its own
// (`SolverWorker`).
let autoplayedOf = (
  ~game: Game.t,
  state: GameState.t,
  ~line: option<array<Position.move>>,
  ~effort: effort,
): autoplayed =>
  switch line {
  | None =>
    switch effort.ending {
    | Exhausted => Unwinnable
    | OutOfTime => OutOfPatience
    | Found | Full => OutOfRoom({bytes: effort.bytes})
    }
  | Some(moves) =>
    let steps = []
    let current = ref(state)
    // A plan generated from these very rules shouldn't come unstuck against them,
    // but a driver handed half a plan and told it was whole would play a board
    // nobody can explain. So a move that won't convert or won't reduce ends the
    // line *here*, and what comes back is the prefix that really was played.
    let stopped = ref(false)
    let i = ref(0)
    while !stopped.contents && i.contents < Array.length(moves) {
      switch Position.toAction(~game, current.contents, moves->Array.getUnsafe(i.contents)) {
      | None => stopped := true
      | Some(action) =>
        switch Reducer.reduce(~game, current.contents, action) {
        | Error(_) => stopped := true
        | Ok(next) =>
          let (settled, collected) = settle(~game, next)
          steps->Array.push({
            action,
            state: settled,
            moved: Array.concat(namedCards(~game, current.contents, action), collected),
          })
          current := settled
        }
      }
      i := i.contents + 1
    }
    Played({steps, effort})
  }

// `~tier` is the device's (`budgetFor`), for a driver that knows it; `Medium` otherwise.
let autoplay = (
  ~game: Game.t,
  ~patience: option<patience>=?,
  ~tier: option<tier>=?,
  state: GameState.t,
): autoplayed =>
  switch Position.ofGameState(~game, state) {
  | None => UnknownBoard
  | Some(position) =>
    let (line, effort) = solveWithEffort(position, ~budget=budgetFor(~tier?, position), ~patience?)
    autoplayedOf(~game, state, ~line, ~effort)
  }

// --- The plan, in the terms a driver outside ReScript plays it in ------------
// The browser autoplay harness (`web-app/scripts/autoplay/`) is JavaScript: it
// reads the board off a rendered page and plays each move as a pointer drag. It
// has no business unpacking a `Position.move`, so a plan is handed to it already
// said in its terms — which card to grab, what that grab should raise, where to
// drop it, and the board the move should leave behind.

// One planned move, ready to drag.
//   `card`        — the card to grab, as a `CardText` code, or `""` for a deal, which
//                   is a tap on the stock and grabs nothing.
//   `lifts`       — every card that grab should raise, bottom-first, so a driver
//                   can check that the board lifted what the plan meant.
//   `target`      — where it lands: "foundation", "cell", "column" — or "deal", the
//                   one step that isn't a drag at all.
//   `column`      — the destination column, or `-1` for the other targets.
//   `description` — the move in words, for a play-by-play.
//   `after`       — the position this move should leave behind, for a driver that
//                   re-reads the board and checks (`Position.key`).
type step = {
  card: string,
  lifts: array<string>,
  target: string,
  column: int,
  description: string,
  after: Position.t,
}

// One move said that way, against the position it's played from — for a driver
// that picked the move itself (playing a single move by hand, see the
// `play-in-browser` skill) rather than taking a whole plan.
let stepFor = (position: Position.t, move: Position.move): step => {
  card: switch move {
  | Position.Deal => ""
  | Position.Play({card}) => Position.code(card)
  },
  lifts: Position.lifted(position, move)->Array.map(Position.code),
  target: switch move {
  | Position.Deal => "deal"
  | Position.Play({destination: Position.ToFoundation}) => "foundation"
  | Position.Play({destination: Position.ToCell(_)}) => "cell"
  | Position.Play({destination: Position.ToColumn(_)}) => "column"
  },
  column: switch move {
  | Position.Play({destination: Position.ToColumn(col)}) => col
  | _ => -1
  },
  description: Position.describeMove(move),
  after: Position.applyMove(position, move),
}

// The plan from `start` as steps: `None` when the budget ran out or the patience did,
// and `Some([])` when the board is already finishable and there's nothing left to think
// about. The patience comes first so a driver outside ReScript passes it positionally
// — the harness hands it `patient`, since the thing waiting there is a script.
let planSteps = (~patience: option<patience>=?, start: Position.t): option<array<step>> =>
  solve(start, ~patience?)->Option.map(moves => {
    let position = ref(start)
    moves->Array.map(move => {
      let step = stepFor(position.contents, move)
      position := step.after
      step
    })
  })
