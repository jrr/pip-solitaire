// The positions a search has generated, as records in typed arrays rather than an
// object apiece — the graph `Solver.Search` grows. What each part is for is
// `docs/solver-next.md` § The graph; what it measures, `docs/solver.md` § The search.
//
// **A node is a position, and an index.** Its parent, the move that reached it from
// there, its depth `g`, its heuristic `h` and its hash are one slot each in a column of
// their own. A node is *open* until the search grows it and *closed* after, and only a
// closed node's position is kept — packed into `arena`, one byte per card — because an
// open node's position is its parent's with one move played.
//
// **Membership is by hash and exact.** `table` maps a hash to a node, and a hit counts
// only once the node's position has been rebuilt and found `alike` the one asked about.
// A collision taken for "seen" would prune a position nobody visited, and `Exhausted`
// would stop being a proof.

type ints = TypedArray.t<int>

@get_index external at: (ints, int) => int = ""
@set_index external put: (ints, int, int) => unit = ""
@send external copyFrom: (ints, ints) => unit = "set"
@send external fillWith: (ints, int) => unit = "fill"
@send external fillFrom: (ints, int, ~start: int) => unit = "fill"

// A column the same kind as `old`, `length` long, with `old` copied into its front.
let widened = (old: ints, make: int => ints, length: int): ints => {
  let wider = make(length)
  wider->copyFrom(old)
  wider
}

// How far a full column grows: by a quarter, not double, because the slack a column
// carries after growing is memory a search holds and never uses. The copying that
// costs is a few passes over the column, spread across every node it holds.
let grow = (n: int): int => n + n / 4 + 1024

// --- The arena ----------------------------------------------------------------
// A closed node's position, as bytes: the cells (a card plus one, so an empty cell
// is 0), the foundations, how many cards are still undealt, and then each column as
// its face-down count, its height and its cards. The columns are in the position's
// own order rather than a canonical one, because the moves recorded against a node
// name its columns by index.

type t = {
  start: Position.t,
  board: Board.t, // scratch for hashing, reloaded for every position asked about
  mutable size: int,
  mutable parent: ints,
  mutable move: ints, // `Board.move`, packed
  mutable depth: ints,
  mutable h: ints,
  mutable stored: ints, // where a closed node's position begins in `arena`; -1 while open
  mutable hashes: ints, // the first lane of `Board.hash`, which is all `table` files by
  mutable arena: ints,
  mutable arenaSize: int,
  mutable table: ints, // node indices, open-addressed by `hashes`; -1 is an empty slot
  mutable tableCount: int,
}

// Empty, and holding nothing until something is added: a search whose start already
// finishes never grows, and says so by holding no bytes.
let make = (start: Position.t): t => {
  let nodes = 0
  {
    start,
    board: Board.load(start),
    size: 0,
    parent: Int32Array.fromLength(nodes),
    move: Int32Array.fromLength(nodes),
    depth: Int16Array.fromLength(nodes),
    h: Int16Array.fromLength(nodes),
    stored: Int32Array.fromLength(nodes),
    hashes: Int32Array.fromLength(nodes),
    arena: Uint8Array.fromLength(0),
    arenaSize: 0,
    table: Int32Array.fromLength(0),
    tableCount: 0,
  }
}

// What the graph holds, from the arrays' own lengths — what they have room for, not
// only what they have filled, since the room is what the heap is paying for.
let bytes = (graph: t): int =>
  [
    graph.parent,
    graph.move,
    graph.depth,
    graph.h,
    graph.stored,
    graph.hashes,
    graph.arena,
    graph.table,
  ]->Array.reduce(0, (sum, column) => sum + TypedArray.byteLength(column))

// --- Nodes --------------------------------------------------------------------

let isClosed = (graph: t, node: int): bool => graph.stored->at(node) >= 0

let add = (graph: t, ~parent: int, ~move: int, ~depth: int, ~h: int, ~hash: int): int => {
  let node = graph.size
  if node == TypedArray.length(graph.parent) {
    let length = grow(node)
    graph.parent = widened(graph.parent, Int32Array.fromLength, length)
    graph.move = widened(graph.move, Int32Array.fromLength, length)
    graph.depth = widened(graph.depth, Int16Array.fromLength, length)
    graph.h = widened(graph.h, Int16Array.fromLength, length)
    graph.stored = widened(graph.stored, Int32Array.fromLength, length)
    graph.hashes = widened(graph.hashes, Int32Array.fromLength, length)
  }
  graph.parent->put(node, parent)
  graph.move->put(node, move)
  graph.depth->put(node, depth)
  graph.h->put(node, h)
  graph.stored->put(node, -1)
  graph.hashes->put(node, hash)
  graph.size = node + 1
  node
}

// A shorter way to an open node: the parent and move that reach it, and its depth.
// **Never a closed node** — its children were generated from its position as its own
// parent reached it, and the moves recorded against them name that layout's columns;
// a new parent might lay the same position out in another order.
let reparent = (graph: t, node: int, ~parent: int, ~move: int, ~depth: int) => {
  graph.parent->put(node, parent)
  graph.move->put(node, move)
  graph.depth->put(node, depth)
}

// Keep a node's position, now that it is being grown.
let close = (graph: t, node: int, s: Position.t) => {
  let need = Array.length(s.cells) + 5 + 2 * Array.length(s.casc) + s.pack.size
  if graph.arenaSize + need > TypedArray.length(graph.arena) {
    graph.arena = widened(
      graph.arena,
      Uint8Array.fromLength,
      grow(TypedArray.length(graph.arena) + need),
    )
  }
  let arena = graph.arena
  let cursor = ref(graph.arenaSize)
  let write = n => {
    arena->put(cursor.contents, n)
    cursor := cursor.contents + 1
  }
  graph.stored->put(node, graph.arenaSize)
  s.cells->Array.forEach(card => write(card + 1))
  s.found->Array.forEach(write)
  write(Array.length(s.stock))
  s.casc->Array.forEachWithIndex((pile, col) => {
    write(s.down->Array.getUnsafe(col))
    write(Array.length(pile))
    pile->Array.forEach(write)
  })
  graph.arenaSize = cursor.contents
}

// The position a closed node was grown from, read back out of the arena.
let unpack = (graph: t, node: int): Position.t => {
  let {start, arena} = graph
  let cursor = ref(graph.stored->at(node))
  let read = () => {
    let n = arena->at(cursor.contents)
    cursor := cursor.contents + 1
    n
  }
  let cells = start.cells->Array.map(_ => read() - 1)
  let found = start.found->Array.map(_ => read())
  let undealt = read()
  let down = []
  let casc = start.casc->Array.map(_ => {
    down->Array.push(read())
    Array.fromInitializer(~length=read(), _ => read())
  })
  {
    law: start.law,
    pack: start.pack,
    cells,
    found,
    casc,
    down,
    stock: start.stock->Array.slice(~start=0, ~end=undealt),
  }
}

// Any node's position: a closed one's from the arena, an open one's by playing its
// move on its parent's. The root, open, is the start.
let positionOf = (graph: t, node: int): Position.t =>
  if isClosed(graph, node) {
    unpack(graph, node)
  } else {
    let parent = graph.parent->at(node)
    parent < 0
      ? graph.start
      : Position.applyMove(unpack(graph, parent), Board.toMove(graph.move->at(node)))
  }

// The moves from the root to a node, oldest first.
let lineTo = (graph: t, node: int): array<Position.move> => {
  let line = []
  let cursor = ref(node)
  while graph.parent->at(cursor.contents) >= 0 {
    line->Array.push(Board.toMove(graph.move->at(cursor.contents)))
    cursor := graph.parent->at(cursor.contents)
  }
  line->Array.reverse
  line
}

// --- Lookup -------------------------------------------------------------------

// `Board.hash` of a position, by way of the scratch board — its first lane alone. The
// second would only spare a comparison the table almost never makes: a match is
// compared card for card whatever the hash says, and a 32-bit match on a different
// position is about one probe in four billion.
let hash = (graph: t, s: Position.t): int => {
  Board.reload(graph.board, s)
  Pair.first(Board.hash(graph.board))
}

let mask = (graph: t) => TypedArray.length(graph.table) - 1

// Twice the room — or a first room — and every node filed again by its hash.
let rehash = (graph: t) => {
  let old = graph.table
  let table = Int32Array.fromLength(Math.Int.max(2 * TypedArray.length(old), 1024))
  table->fillWith(-1)
  graph.table = table
  let mask = mask(graph)
  for i in 0 to TypedArray.length(old) - 1 {
    let node = old->at(i)
    if node >= 0 {
      let slot = ref(graph.hashes->at(node)->Int.bitwiseAnd(mask))
      while table->at(slot.contents) >= 0 {
        slot := (slot.contents + 1)->Int.bitwiseAnd(mask)
      }
      table->put(slot.contents, node)
    }
  }
}

// The slot a position is filed under: holding its node if it has one, or the empty
// slot it would go in if it hasn't. Read it with `nodeAt`, fill it with `file`.
let slotOf = (graph: t, s: Position.t, ~hash: int): int => {
  if TypedArray.length(graph.table) == 0 {
    rehash(graph)
  }
  let {table} = graph
  let mask = mask(graph)
  let slot = ref(hash->Int.bitwiseAnd(mask))
  let found = ref(false)
  while !found.contents && table->at(slot.contents) >= 0 {
    let node = table->at(slot.contents)
    if graph.hashes->at(node) == hash && Position.alike(positionOf(graph, node), s) {
      found := true
    } else {
      slot := (slot.contents + 1)->Int.bitwiseAnd(mask)
    }
  }
  slot.contents
}

let nodeAt = (graph: t, slot: int): int => graph.table->at(slot)

// File a node under the slot `slotOf` gave for its position — replacing the node
// that was there, if there was one. The slot is spent: the table may move.
let file = (graph: t, slot: int, node: int) => {
  if graph.table->at(slot) < 0 {
    graph.tableCount = graph.tableCount + 1
  }
  graph.table->put(slot, node)
  if graph.tableCount * 10 > TypedArray.length(graph.table) * 7 {
    rehash(graph)
  }
}
