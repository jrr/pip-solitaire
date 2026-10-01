// The positions a search has generated, as records in typed arrays rather than an
// object apiece — the graph `Solver.Search` grows. What each part is for is
// `docs/solver-next.md` § The graph; what it measures, `docs/solver.md` § The search.
//
// **A node is a position, and an index.** Its parent, the move that reached it from
// there, its depth `g`, its heuristic `h` and its hash are one slot each in a column of
// their own. A node is *open* until the search grows it and *closed* after. Only some
// closed nodes' positions are kept — packed into `arena`, one byte per card — and every
// other position is read back by playing moves down from the nearest node that was.
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
  mutable start: Position.t, // the root's position, as the player's board lays it out
  // The longest stock any node has had. Every position of one deal holds a prefix of it,
  // so a stored position keeps only its length; a re-root after an undo of a deal can
  // stand on a longer one than `start` first had (`widen`).
  mutable stock: array<int>,
  mutable board: Board.t, // scratch for hashing, reloaded for every position asked about
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
  // Whether a re-root has kept anything, after which a node's layout need not be its
  // parent's with its move played (`lineTo`).
  mutable relaid: bool,
}

// Empty, and holding nothing until something is added: a search whose start already
// finishes never grows, and says so by holding no bytes.
let make = (start: Position.t): t => {
  let nodes = 0
  {
    start,
    stock: start.stock,
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
    relaid: false,
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

// `stored` says three things: -1 is an open node, -2 a closed one whose position is
// not kept, and anything else where a closed one's position begins in `arena`.
let isOpen = -1
let unkept = -2

let isClosed = (graph: t, node: int): bool => graph.stored->at(node) != isOpen

// How many closed nodes in a row may go without a position of their own. Each one
// kept costs a whole board in `arena`, more than all its columns besides; each one
// skipped costs a move replayed whenever it is read back. Measured in
// `docs/solver.md` § The search.
let keepEvery = 4

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
  graph.stored->put(node, isOpen)
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

// Pack a closed node's position into the arena.
let keep = (graph: t, node: int, s: Position.t) => {
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

// Close a node, now that it is being grown — keeping its position if the last
// `keepEvery - 1` closed nodes above it all went without.
let close = (graph: t, node: int, s: Position.t) => {
  let run = ref(0)
  let above = ref(graph.parent->at(node))
  while above.contents >= 0 && graph.stored->at(above.contents) == unkept {
    run := run.contents + 1
    above := graph.parent->at(above.contents)
  }
  if above.contents >= 0 && run.contents < keepEvery - 1 {
    graph.stored->put(node, unkept)
  } else {
    keep(graph, node, s)
  }
}

// The position a kept node was grown from, read back out of the arena.
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
    stock: graph.stock->Array.slice(~start=0, ~end=undealt),
  }
}

// Any node's position: a kept one's from the arena, any other's by playing its move
// on its parent's — a few moves at most, since a parent is always closed and a run of
// closed nodes is broken by a kept one every `keepEvery`. The root, open, is the start.
let rec positionOf = (graph: t, node: int): Position.t =>
  if graph.stored->at(node) >= 0 {
    unpack(graph, node)
  } else {
    let parent = graph.parent->at(node)
    parent < 0
      ? graph.start
      : Position.applyMove(positionOf(graph, parent), Board.toMove(graph.move->at(node)))
  }

// A move recorded against one layout of a position, said against another layout of the
// same position: the same cards, from and to the cells and columns that hold what the
// first layout's did. Only a re-rooted graph needs it (`lineTo`, below).
let translate = (move: Position.move, ~from: Position.t, ~onto: Position.t): Position.move =>
  switch move {
  | Position.Deal => move
  | Position.Play({n, card, source, destination}) =>
    // Each of `from`'s columns to the first column of `onto` laid out just like it that
    // no other has claimed — identical columns are interchangeable, empty ones included.
    let claimed = onto.casc->Array.map(_ => false)
    let columns = from.casc->Array.mapWithIndex((pile, i) => {
      let j =
        onto.casc->Array.findIndexWithIndex((other, j) =>
          !(claimed->Array.getUnsafe(j)) &&
          onto.down->Array.getUnsafe(j) == from.down->Array.getUnsafe(i) &&
          other == pile
        )
      claimed->Array.setUnsafe(j, true)
      j
    })
    Position.Play({
      n,
      card,
      source: switch source {
      | Position.FromCell(i) =>
        Position.FromCell(onto.cells->Array.indexOf(from.cells->Array.getUnsafe(i)))
      | Position.FromColumn(i) => Position.FromColumn(columns->Array.getUnsafe(i))
      },
      destination: switch destination {
      | Position.ToFoundation => destination
      | Position.ToCell(_) => Position.ToCell(onto.cells->Array.indexOf(-1))
      | Position.ToColumn(i) => Position.ToColumn(columns->Array.getUnsafe(i))
      },
    })
  }

// The moves from the root to a node, oldest first — and then `last`, a move from the
// node itself, if there is one. Said against the root's position as `start` lays it
// out, which is the player's board.
//
// **A node's layout need not be its parent's with its move played.** A re-root keeps a
// closed node whose way down was discarded by storing its position and hanging it from
// a new parent (`collect`), and the new parent's move may lay the same position out in
// another column order. Its children's moves name its own columns, so the line is
// replayed alongside, and a move is translated wherever the two layouts part.
let lineTo = (graph: t, node: int, ~last: option<int>=?): array<Position.move> => {
  let chain = []
  let cursor = ref(node)
  while graph.parent->at(cursor.contents) >= 0 {
    chain->Array.push(cursor.contents)
    cursor := graph.parent->at(cursor.contents)
  }
  chain->Array.reverse
  let recorded = chain->Array.map(child => Board.toMove(graph.move->at(child)))
  last->Option.forEach(move => recorded->Array.push(Board.toMove(move)))
  if !graph.relaid {
    recorded
  } else {
    // The two layouts can only part where the recorded one is read from the arena — at
    // the root, or at a stored node — so `own` is only needed once they have.
    let real = ref(graph.start) // the layout the line is said in
    let own = ref(positionOf(graph, cursor.contents)) // the layout the next move was recorded in
    let parted = ref(own.contents != real.contents)
    recorded->Array.mapWithIndex((move, i) => {
      let said = parted.contents ? translate(move, ~from=own.contents, ~onto=real.contents) : move
      real := Position.applyMove(real.contents, said)
      switch chain->Array.get(i) {
      | Some(child) if graph.stored->at(child) >= 0 =>
        own := unpack(graph, child)
        parted := own.contents != real.contents
      | Some(_) if parted.contents => own := Position.applyMove(own.contents, move)
      | Some(_) | None => ()
      }
      said
    })
  }
}

// The move from `from` that leads to a position `alike` `to` — in `from`'s own layout,
// which is what a node's recorded move has to be in. `None` when there is none.
let moveBetween = (from: Position.t, to: Position.t): option<int> =>
  Position.legalMoves(from)
  ->Array.find(move => Position.alike(Position.applyMove(from, move), to))
  ->Option.map(Board.ofMove)

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
  if graph.tableCount * 10 > TypedArray.length(graph.table) * 8 {
    rehash(graph)
  }
}

// --- Re-rooting ---------------------------------------------------------------
// The graph made to follow the board: everything reachable from a new root kept,
// everything else let go. The rule, why the proof survives it, and the three repairs it
// makes on the way are `docs/solver-next.md` § Re-rooting; what it costs is
// `docs/solver.md` § Re-rooting.

// Make room for a position of the same deal with more of the stock still to come than
// any the graph has held — the board an undo of a deal goes back to — before anything
// reads it back or hashes it.
let widen = (graph: t, s: Position.t) =>
  if Array.length(s.stock) > Array.length(graph.stock) {
    graph.stock = s.stock
    graph.board = Board.load(s)
  }

// What a walk from a root found: which nodes it reached, the kept closed node each was
// first reached from, and every child of a kept closed node the graph has no node for —
// a position, and the node it hangs from. A search that found its line stopped growing
// the node it found it from, so that node's children after the finishing one are the
// strays there usually are; the finishing child is a stray too.
type walked = {
  kept: ints, // 1 for a node reached from the root
  arrival: ints, // the node a kept one was first reached from; -1 for the root
  order: ints, // when a kept node was first reached: 0 for the root, and up
  strays: array<(int, Position.t)>,
  reached: int,
}

// Whether two positions `alike` are the same game from here on: with a stock left to
// deal, only if their columns are in the same order, since a deal lands one card on each
// column in turn. `docs/solver-next.md` § Re-rooting has what that costs the walk.
let dealsAlike = (a: Position.t, b: Position.t): bool =>
  Array.length(a.stock) == 0 || (a.casc == b.casc && a.down == b.down)

// The node for the position `board` stands on, -1 if there is none: `slotOf`, for a
// board just played `move` from `node`'s position. A node grown from `node` by `move` is
// that position by construction, so it is taken without the card-for-card comparison
// that membership otherwise needs — which is most of what a walk would spend.
let grownBy = (graph: t, board: Board.t, ~node: int, ~move: int): int => {
  if TypedArray.length(graph.table) == 0 {
    rehash(graph)
  }
  let {table} = graph
  let mask = mask(graph)
  let hash = Pair.first(Board.hash(board))
  let slot = ref(hash->Int.bitwiseAnd(mask))
  let found = ref(-1)
  let s = ref(None)
  while found.contents < 0 && table->at(slot.contents) >= 0 {
    let candidate = table->at(slot.contents)
    if (
      graph.hashes->at(candidate) == hash &&
        ((graph.parent->at(candidate) == node && graph.move->at(candidate) == move) || {
            let position = switch s.contents {
            | Some(position) => position
            | None =>
              let position = Board.toPosition(board)
              s := Some(position)
              position
            }
            Position.alike(positionOf(graph, candidate), position)
          })
    ) {
      found := candidate
    } else {
      slot := (slot.contents + 1)->Int.bitwiseAnd(mask)
    }
  }
  found.contents
}

// Every node reachable from `root`, depth first, with a board — standing on the root's
// position — played forward and back along the way. A closed node's moves are generated
// afresh and each child looked up; an open node is a leaf. The depth is the graph's, so
// the stack is an array rather than the call stack.
//
// **Each closed node is walked in its own layout** while there is a stock
// (`dealsAlike`): a child reached other than by the move it was grown through gets a
// board of its own, loaded from its position. With nothing left to deal, any layout
// generates the same children, and the one board serves throughout. A node marked in
// `reopened` is walked as if open.
//
// **Nothing is changed**, so every `positionOf` the lookups make still reads the chains
// the graph was grown with.
let walk = (graph: t, ~root: int, ~board: Board.t, ~reopened: ints): walked => {
  let kept = Uint8Array.fromLength(graph.size)
  let arrival = Int32Array.fromLength(graph.size)
  arrival->fillWith(-1)
  let order = Int32Array.fromLength(graph.size)
  let strays = []
  let reached = ref(1)
  kept->put(root, 1)
  // The stack, a frame per closed node being walked: its moves, how many are tried, its
  // board, and whether it stands on its parent's board, one move played.
  let nodes = []
  let moves = []
  let tried = []
  let boards = []
  let borrowed = []
  let enter = (node, board, ~borrows) => {
    nodes->Array.push(node)
    moves->Array.push(Board.legalMoves(board))
    tried->Array.push(0)
    boards->Array.push(board)
    borrowed->Array.push(borrows)
  }
  let grown = node => isClosed(graph, node) && reopened->at(node) == 0
  if grown(root) {
    enter(root, board, ~borrows=false)
  }
  while Array.length(nodes) > 0 {
    let top = Array.length(nodes) - 1
    let node = nodes->Array.getUnsafe(top)
    let options = moves->Array.getUnsafe(top)
    let board = boards->Array.getUnsafe(top)
    let i = tried->Array.getUnsafe(top)
    if i == Array.length(options) {
      nodes->Array.pop->ignore
      moves->Array.pop->ignore
      tried->Array.pop->ignore
      boards->Array.pop->ignore
      if borrowed->Array.pop->Option.getOr(false) {
        Board.takeBack(board)
      }
    } else {
      tried->Array.setUnsafe(top, i + 1)
      let move = options->Array.getUnsafe(i)
      Board.play(board, move)
      let child = grownBy(graph, board, ~node, ~move)
      if child < 0 {
        strays->Array.push((node, Board.toPosition(board)))
        Board.takeBack(board)
      } else if kept->at(child) == 1 {
        Board.takeBack(board)
      } else {
        kept->put(child, 1)
        arrival->put(child, node)
        order->put(child, reached.contents)
        reached := reached.contents + 1
        if !grown(child) {
          Board.takeBack(board)
        } else if (
          board.undealt == 0 || (graph.parent->at(child) == node && graph.move->at(child) == move)
        ) {
          enter(child, board, ~borrows=true)
        } else {
          Board.takeBack(board)
          enter(child, Board.load(positionOf(graph, child)), ~borrows=false)
        }
      }
    }
  }
  {kept, arrival, order, strays, reached: reached.contents}
}

// The bytes a stored position takes in the arena, from where it begins.
let storedLength = (graph: t, offset: int): int => {
  let {start, arena} = graph
  let cursor = ref(offset + Array.length(start.cells) + Array.length(start.found) + 1)
  for _ in 1 to Array.length(start.casc) {
    cursor := cursor.contents + 2 + arena->at(cursor.contents + 1)
  }
  cursor.contents - offset
}

// Make `root` the root and keep only what `walked` reached: the copying collection that
// finishes a re-root. Returns where each old node went, -1 for one let go of. `start` is
// the caller's to set after, since an open root's position is read from it.
//
// First, while every old chain still reads, each kept node whose parent is let go of or
// reopened takes the node it was first reached from as its parent — and so does any
// that would otherwise close a cycle — with its move said in that parent's own layout,
// and a closed one so moved, or a closed root, has its position stored. **`None`, with
// nothing let go of, if one of those can't be moved faithfully** (`dealsAlike`): it is
// marked in `reopened`, and the caller walks again.
//
// Then the kept nodes are copied, in their old order, into columns and an arena sized to
// hold them and no more — typed arrays never shrink in place, so a copy is how the memory
// comes back — and the table is built again over them.
let collect = (graph: t, ~root: int, walked: walked, ~reopened: ints): option<ints> => {
  let {kept, arrival, order} = walked
  let size = graph.size
  // Which kept nodes take the node they were reached from as their parent: each whose
  // parent is gone or reopened, to begin with, and then one more for every cycle that
  // leaves. A cycle needs a parent reached after its child, since the node a child was
  // reached from was always reached first, so each one is broken at such a parent.
  let moving = Uint8Array.fromLength(size)
  let above = node =>
    moving->at(node) == 1 ? arrival->at(node) : node == root ? -1 : graph.parent->at(node)
  for node in 0 to size - 1 {
    if kept->at(node) == 1 && node != root {
      let parent = graph.parent->at(node)
      if parent < 0 || kept->at(parent) == 0 || reopened->at(parent) == 1 {
        moving->put(node, 1)
      }
    }
  }
  let state = Uint8Array.fromLength(size) // 1 while on the path being followed, 2 once it reaches the root
  let path = []
  for node in 0 to size - 1 {
    if kept->at(node) == 1 && state->at(node) == 0 {
      let settled = ref(false)
      while !settled.contents {
        let cursor = ref(node)
        while cursor.contents >= 0 && state->at(cursor.contents) == 0 {
          state->put(cursor.contents, 1)
          path->Array.push(cursor.contents)
          cursor := above(cursor.contents)
        }
        if cursor.contents >= 0 && state->at(cursor.contents) == 1 {
          let from = path->Array.indexOf(cursor.contents)
          let late =
            path
            ->Array.slice(~start=from)
            ->Array.find(node =>
              moving->at(node) == 0 && order->at(graph.parent->at(node)) > order->at(node)
            )
            ->Option.getOrThrow(~message="a cycle with no parent reached after its child")
          moving->put(late, 1)
          path->Array.forEach(node => state->put(node, 0))
        } else {
          path->Array.forEach(node => state->put(node, 2))
          settled := true
        }
        path->Array.splice(~start=0, ~remove=Array.length(path), ~insert=[])
      }
    }
  }
  let astray = node => moving->at(node) == 1
  let store = node =>
    if graph.stored->at(node) == unkept {
      keep(graph, node, positionOf(graph, node))
    }
  let moves = Int32Array.fromLength(size)
  let faithful = ref(true)
  for node in 0 to size - 1 {
    if astray(node) {
      let from = positionOf(graph, arrival->at(node))
      let own = positionOf(graph, node)
      let move =
        moveBetween(from, own)->Option.getOrThrow(
          ~message="a kept node is not a child of the node it was reached from",
        )
      if (
        isClosed(graph, node) &&
        reopened->at(node) == 0 &&
        !dealsAlike(Position.applyMove(from, Board.toMove(move)), own)
      ) {
        reopened->put(node, 1)
        faithful := false
      }
      moves->put(node, move)
      store(node)
    }
  }
  if !faithful.contents {
    None
  } else {
    store(root)
    for node in 0 to size - 1 {
      if astray(node) {
        graph.parent->put(node, arrival->at(node))
        graph.move->put(node, moves->at(node))
      }
    }
    graph.parent->put(root, -1)
    graph.move->put(root, 0)
    for node in 0 to size - 1 {
      if kept->at(node) == 1 && reopened->at(node) == 1 {
        graph.stored->put(node, isOpen)
      }
    }

    let count = walked.reached
    let renumbered = Int32Array.fromLength(size)
    let next = ref(0)
    let arenaSize = ref(0)
    for node in 0 to size - 1 {
      if kept->at(node) == 1 {
        renumbered->put(node, next.contents)
        next := next.contents + 1
        let offset = graph.stored->at(node)
        if offset >= 0 {
          arenaSize := arenaSize.contents + storedLength(graph, offset)
        }
      } else {
        renumbered->put(node, -1)
      }
    }
    let parent = Int32Array.fromLength(count)
    let move = Int32Array.fromLength(count)
    let depth = Int16Array.fromLength(count)
    let h = Int16Array.fromLength(count)
    let stored = Int32Array.fromLength(count)
    let hashes = Int32Array.fromLength(count)
    let arena = Uint8Array.fromLength(arenaSize.contents)
    let cursor = ref(0)
    for node in 0 to size - 1 {
      let to = renumbered->at(node)
      if to >= 0 {
        let above = graph.parent->at(node)
        parent->put(to, above < 0 ? -1 : renumbered->at(above))
        move->put(to, graph.move->at(node))
        depth->put(to, graph.depth->at(node))
        h->put(to, graph.h->at(node))
        hashes->put(to, graph.hashes->at(node))
        let offset = graph.stored->at(node)
        if offset >= 0 {
          let length = storedLength(graph, offset)
          for i in 0 to length - 1 {
            arena->put(cursor.contents + i, graph.arena->at(offset + i))
          }
          stored->put(to, cursor.contents)
          cursor := cursor.contents + length
        } else {
          stored->put(to, offset)
        }
      }
    }
    graph.size = count
    graph.parent = parent
    graph.move = move
    graph.depth = depth
    graph.h = h
    graph.stored = stored
    graph.hashes = hashes
    graph.arena = arena
    graph.arenaSize = cursor.contents
    // The smallest table `file` would not rehash at once, holding every node.
    let length = ref(1024)
    while count * 10 > length.contents * 8 {
      length := length.contents * 2
    }
    graph.table = Int32Array.fromLength(0)
    let table = Int32Array.fromLength(length.contents)
    table->fillWith(-1)
    let mask = length.contents - 1
    for node in 0 to count - 1 {
      let slot = ref(hashes->at(node)->Int.bitwiseAnd(mask))
      while table->at(slot.contents) >= 0 {
        slot := (slot.contents + 1)->Int.bitwiseAnd(mask)
      }
      table->put(slot.contents, node)
    }
    graph.table = table
    graph.tableCount = count
    graph.relaid = true
    Some(renumbered)
  }
}

// Let go of everything, and stand on `start` — `make` again, into the graph already
// made, for a search whose closures read this one.
let clear = (graph: t, start: Position.t) => {
  let fresh = make(start)
  graph.start = fresh.start
  graph.stock = fresh.stock
  graph.board = fresh.board
  graph.size = 0
  graph.parent = fresh.parent
  graph.move = fresh.move
  graph.depth = fresh.depth
  graph.h = fresh.h
  graph.stored = fresh.stored
  graph.hashes = fresh.hashes
  graph.arena = fresh.arena
  graph.arenaSize = 0
  graph.table = fresh.table
  graph.tableCount = 0
  graph.relaid = false
}
