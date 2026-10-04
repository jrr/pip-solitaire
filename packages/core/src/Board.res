// A `Position` the search plays forward and back **in place** — play a move, hash
// and weigh the result, take the move back, and no copy made along the way. The search
// grows every node on one (`Solver.Search.think`) and the graph reads a node back onto
// one (`Graph.standOn`); `Position.applyMove` would copy the whole board for every
// child instead, and what that cost is `docs/solver.md` § On making this faster.
//
// **`Position` is its oracle.** Every function over the board below is a
// re-reading of the `Position` function of the same name on a different layout,
// and `Board_test` walks random games through both and demands they agree at every
// step. The card-level predicates (`follows`, `afterLifting`, the card numbering)
// aren't re-read at all: they know nothing of the layout, so they are `Position`'s
// own, called from here.

// --- The layout --------------------------------------------------------------
//
// The columns share one flat array, `cap` slots each, with a height per column —
// so a card moved is two ints written, not an array spliced. `cap` is the whole
// pack, the most one column could ever hold. The stock never changes order, only
// shortens from its top, so it is the loaded array plus a count of what is left.
//
// **Every write goes through the journal.** Each one logs what it overwrote as
// three ints — a kind, an index, the old value — and `play` marks where its writes
// begin, so `takeBack` undoes a move by replaying its writes backwards. That is
// what makes unmake exact however much a move's settle did: several cards sent
// home, two runs lifted, the face-down card each one turned over. Nothing has to
// know what a move *did* to take it back, only what it wrote.
type t = {
  law: Position.law,
  pack: Position.pack,
  cap: int,
  cells: array<int>,
  found: array<int>,
  cards: array<int>, // column `c`, bottom-first, at `c * cap` up to its height
  height: array<int>,
  down: array<int>,
  stock: array<int>,
  mutable undealt: int,
  // Fold the columns even while there is a stock: the same piles in another column order
  // taken for one position, as they are once the stock is out. Not true of a board that
  // deals, so a search that folds can find a line but can't prove there is none —
  // `Solver.Search` folds to look and keeps the order to prove.
  fold: bool,
  journal: array<int>,
  frames: array<int>, // the journal's length at the start of each move still played
  // Scratch for `canFinish` and `heuristic`, which ask after every generated move.
  drainFound: array<int>,
  drainCells: array<int>,
  drainHeight: array<int>,
  wanted: array<bool>,
}

let columns = (b: t): int => Array.length(b.height)

// Whether which column holds a pile is part of the position: while there is a stock to
// deal onto them, unless the board was loaded to `fold`.
let keepsOrder = (b: t): bool => b.undealt > 0 && !b.fold

let cardAt = (b: t, ~col: int, ~i: int): int => b.cards->Array.getUnsafe(col * b.cap + i)

let topOf = (b: t, col: int): int => {
  let h = b.height->Array.getUnsafe(col)
  h == 0 ? -1 : cardAt(b, ~col, ~i=h - 1)
}

let load = (~fold: bool=false, s: Position.t): t => {
  let cap = Math.Int.max(s.pack.size, 1)
  let n = Array.length(s.casc)
  let cards = Array.make(~length=n * cap, 0)
  s.casc->Array.forEachWithIndex((pile, col) =>
    pile->Array.forEachWithIndex((card, i) => cards->Array.setUnsafe(col * cap + i, card))
  )
  {
    law: s.law,
    pack: s.pack,
    cap,
    cells: s.cells->Array.copy,
    found: s.found->Array.copy,
    cards,
    height: s.casc->Array.map(Array.length),
    down: s.down->Array.copy,
    stock: s.stock->Array.copy,
    undealt: Array.length(s.stock),
    fold,
    journal: [],
    frames: [],
    drainFound: s.found->Array.copy,
    drainCells: s.cells->Array.copy,
    drainHeight: Array.make(~length=n, 0),
    wanted: Array.make(~length=52, false),
  }
}

// Let go of every move in play, keeping the board as it stands: nothing is left to
// take back. For a caller about to overwrite the whole board — `reload`, or one reading
// a layout of its own into it.
@set external truncate: (array<int>, @as(0) _) => unit = "length"

let forget = (b: t) => {
  b.journal->truncate
  b.frames->truncate
}

// `load` again, into a board already made — no allocation, for a caller that stands
// it on a position at every node it grows. **Only a position of the same deal**: the
// same pack and columns, and a stock that is a prefix of the one first loaded, which
// every position a search reaches from its start is. Whatever was in play is let go of.
let reload = (b: t, s: Position.t) => {
  forget(b)
  for i in 0 to Array.length(s.cells) - 1 {
    b.cells->Array.setUnsafe(i, s.cells->Array.getUnsafe(i))
  }
  for i in 0 to Array.length(s.found) - 1 {
    b.found->Array.setUnsafe(i, s.found->Array.getUnsafe(i))
  }
  s.casc->Array.forEachWithIndex((pile, col) => {
    pile->Array.forEachWithIndex((card, i) => b.cards->Array.setUnsafe(col * b.cap + i, card))
    b.height->Array.setUnsafe(col, Array.length(pile))
    b.down->Array.setUnsafe(col, s.down->Array.getUnsafe(col))
  })
  b.undealt = Array.length(s.stock)
}

let toPosition = (b: t): Position.t => {
  law: b.law,
  pack: b.pack,
  cells: b.cells->Array.copy,
  found: b.found->Array.copy,
  casc: b.height->Array.mapWithIndex((h, col) =>
    Array.fromInitializer(~length=h, i => cardAt(b, ~col, ~i))
  ),
  down: b.down->Array.copy,
  stock: b.stock->Array.slice(~start=0, ~end=b.undealt),
}

// `Position.alike`, on two boards of one deal: the same foundations and stock length,
// the cells the same *multiset*, and the columns too — in the same order while `a`
// `keepsOrder`. What a search asks to be sure a hash that matched meant the same position.
let alike = (a: t, b: t): bool => {
  let columnsEqual = (x: t, i: int, y: t, j: int): bool => {
    let n = x.height->Array.getUnsafe(i)
    x.down->Array.getUnsafe(i) == y.down->Array.getUnsafe(j) &&
    n == y.height->Array.getUnsafe(j) && {
      let k = ref(0)
      while k.contents < n && cardAt(x, ~col=i, ~i=k.contents) == cardAt(y, ~col=j, ~i=k.contents) {
        k := k.contents + 1
      }
      k.contents == n
    }
  }
  // Each column of `a` as often in `a` as in `b` — with as many columns on each side,
  // that is the two multisets equal.
  let sameColumns = () => {
    let n = columns(a)
    let ok = ref(true)
    let i = ref(0)
    while ok.contents && i.contents < n {
      let inA = ref(0)
      let inB = ref(0)
      for j in 0 to n - 1 {
        if columnsEqual(a, i.contents, a, j) {
          inA := inA.contents + 1
        }
        if columnsEqual(a, i.contents, b, j) {
          inB := inB.contents + 1
        }
      }
      ok := inA.contents == inB.contents
      i := i.contents + 1
    }
    ok.contents
  }
  // The cells likewise, counting empties as a value like any other.
  let sameCells = () => {
    let n = Array.length(a.cells)
    let ok = ref(true)
    let i = ref(0)
    while ok.contents && i.contents < n {
      let card = a.cells->Array.getUnsafe(i.contents)
      let inA = ref(0)
      let inB = ref(0)
      for j in 0 to n - 1 {
        if a.cells->Array.getUnsafe(j) == card {
          inA := inA.contents + 1
        }
        if b.cells->Array.getUnsafe(j) == card {
          inB := inB.contents + 1
        }
      }
      ok := inA.contents == inB.contents
      i := i.contents + 1
    }
    ok.contents
  }
  // Each column of `a` the one in the same seat of `b`.
  let sameSeats = () => {
    let i = ref(0)
    while i.contents < columns(a) && columnsEqual(a, i.contents, b, i.contents) {
      i := i.contents + 1
    }
    i.contents == columns(a)
  }
  a.undealt == b.undealt &&
  Array.length(a.cells) == Array.length(b.cells) &&
  columns(a) == columns(b) &&
  a.found->Array.everyWithIndex((n, suit) => b.found->Array.getUnsafe(suit) == n) &&
  sameCells() && (keepsOrder(a) ? sameSeats() : sameColumns())
}

// --- The journal -------------------------------------------------------------

let cellWrite = 0
let foundWrite = 1
let downWrite = 2
let pushed = 3
let popped = 4
let dealtWrite = 5

let log = (b: t, kind: int, index: int, old: int) => {
  b.journal->Array.push(kind)
  b.journal->Array.push(index)
  b.journal->Array.push(old)
}

let setCell = (b: t, i: int, card: int) => {
  log(b, cellWrite, i, b.cells->Array.getUnsafe(i))
  b.cells->Array.setUnsafe(i, card)
}

let setFound = (b: t, suit: int, n: int) => {
  log(b, foundWrite, suit, b.found->Array.getUnsafe(suit))
  b.found->Array.setUnsafe(suit, n)
}

let setDown = (b: t, col: int, n: int) => {
  log(b, downWrite, col, b.down->Array.getUnsafe(col))
  b.down->Array.setUnsafe(col, n)
}

let push = (b: t, col: int, card: int) => {
  let h = b.height->Array.getUnsafe(col)
  log(b, pushed, col, 0)
  b.cards->Array.setUnsafe(col * b.cap + h, card)
  b.height->Array.setUnsafe(col, h + 1)
}

let pop = (b: t, col: int): int => {
  let h = b.height->Array.getUnsafe(col) - 1
  let card = cardAt(b, ~col, ~i=h)
  log(b, popped, col, card)
  b.height->Array.setUnsafe(col, h)
  card
}

// Take `n` cards off a column's top, turning over whatever that uncovers —
// `Position`'s splice-then-`afterLifting`, the one way a card leaves a column.
let lift = (b: t, col: int, n: int) => {
  let depth = b.height->Array.getUnsafe(col)
  for _i in 1 to n {
    pop(b, col)->ignore
  }
  let down = b.down->Array.getUnsafe(col)
  let after = Position.afterLifting(~down, ~depth, ~n)
  if after != down {
    setDown(b, col, after)
  }
}

// Undo every write since the journal was `mark` long, newest first.
let rewind = (b: t, mark: int) => {
  while Array.length(b.journal) > mark {
    let old = b.journal->Array.pop->Option.getUnsafe
    let index = b.journal->Array.pop->Option.getUnsafe
    let kind = b.journal->Array.pop->Option.getUnsafe
    if kind == cellWrite {
      b.cells->Array.setUnsafe(index, old)
    } else if kind == foundWrite {
      b.found->Array.setUnsafe(index, old)
    } else if kind == downWrite {
      b.down->Array.setUnsafe(index, old)
    } else if kind == pushed {
      b.height->Array.setUnsafe(index, b.height->Array.getUnsafe(index) - 1)
    } else if kind == popped {
      let h = b.height->Array.getUnsafe(index)
      b.cards->Array.setUnsafe(index * b.cap + h, old)
      b.height->Array.setUnsafe(index, h + 1)
    } else {
      b.undealt = old
    }
  }
}

// --- The rules, read off this layout -----------------------------------------
// Each is `Position`'s function of the same name; what it mirrors in
// `Rules`/`Reducer` is said there, once.

let emptyCells = (b: t): int => {
  let n = ref(0)
  for i in 0 to Array.length(b.cells) - 1 {
    if b.cells->Array.getUnsafe(i) < 0 {
      n := n.contents + 1
    }
  }
  n.contents
}

let foundationTotal = (b: t): int => {
  let n = ref(0)
  for i in 0 to Array.length(b.found) - 1 {
    n := n.contents + b.found->Array.getUnsafe(i)
  }
  n.contents
}

let hasWon = (b: t): bool => foundationTotal(b) == b.pack.size

let cascadeAccepts = (b: t, ~col: int, ~card: int): bool => {
  let top = topOf(b, col)
  top < 0 ||
    (Position.rankOf(top) == Position.rankOf(card) + 1 &&
      switch b.law {
      | FreeCell => Position.isRed(top) != Position.isRed(card)
      | SimpleSimon => true
      })
}

let foundationAccepts = (b: t, card: int): bool =>
  switch b.law {
  | FreeCell => b.found->Array.getUnsafe(Position.suitOf(card)) == Position.rankOf(card) - 1
  | SimpleSimon => false
  }

let runLength = (b: t, col: int): int => {
  let depth = b.height->Array.getUnsafe(col)
  let seen = depth - b.down->Array.getUnsafe(col)
  let n = ref(0)
  let i = ref(depth - 1)
  let running = ref(depth > 0 && seen > 0)
  while running.contents {
    n := n.contents + 1
    if i.contents == 0 || n.contents >= seen {
      running := false
    } else {
      let above = cardAt(b, ~col, ~i=i.contents)
      let below = cardAt(b, ~col, ~i=i.contents - 1)
      if Position.follows(b.law, ~below, ~above) {
        i := i.contents - 1
      } else {
        running := false
      }
    }
  }
  n.contents
}

let maxSupermove = (b: t, ~ignoring: int): int => {
  let empties = ref(0)
  for i in 0 to columns(b) - 1 {
    if i != ignoring && b.height->Array.getUnsafe(i) == 0 {
      empties := empties.contents + 1
    }
  }
  (1 + emptyCells(b)) * Int.shiftLeft(1, empties.contents)
}

let liftLimit = (b: t, ~ignoring: int): int =>
  switch b.law {
  | FreeCell => maxSupermove(b, ~ignoring)
  | SimpleSimon => b.pack.size
  }

let isSafeToCollect = (b: t, card: int): bool =>
  foundationAccepts(b, card) && {
    let r = Position.rankOf(card)
    r <= 2 || {
        let red = Position.isRed(card)
        let safe = ref(true)
        for i in 0 to Array.length(b.pack.suits) - 1 {
          let suit = b.pack.suits->Array.getUnsafe(i)
          if Position.isRedSuit(suit) != red && b.found->Array.getUnsafe(suit) < r - 1 {
            safe := false
          }
        }
        safe.contents
      }
  }

let collectSafeCards = (b: t) => {
  let progressed = ref(true)
  while progressed.contents {
    progressed := false
    let cell = ref(0)
    while !progressed.contents && cell.contents < Array.length(b.cells) {
      let card = b.cells->Array.getUnsafe(cell.contents)
      if card >= 0 && isSafeToCollect(b, card) {
        setFound(b, Position.suitOf(card), Position.rankOf(card))
        setCell(b, cell.contents, -1)
        progressed := true
      }
      cell := cell.contents + 1
    }
    let col = ref(0)
    while !progressed.contents && col.contents < columns(b) {
      let card = topOf(b, col.contents)
      if card >= 0 && isSafeToCollect(b, card) {
        setFound(b, Position.suitOf(card), Position.rankOf(card))
        lift(b, col.contents, 1)
        progressed := true
      }
      col := col.contents + 1
    }
  }
}

let topsCompleteRun = (b: t, col: int): bool => {
  let ranks = b.pack.ranks
  let depth = b.height->Array.getUnsafe(col)
  depth >= ranks &&
  Position.rankOf(cardAt(b, ~col, ~i=depth - ranks)) == ranks && {
    let ok = ref(true)
    let i = ref(depth - ranks + 1)
    while ok.contents && i.contents < depth {
      ok :=
        Position.follows(
          Position.SimpleSimon,
          ~below=cardAt(b, ~col, ~i=i.contents - 1),
          ~above=cardAt(b, ~col, ~i=i.contents),
        )
      i := i.contents + 1
    }
    ok.contents
  }
}

let collectRuns = (b: t) => {
  let ranks = b.pack.ranks
  let progressed = ref(true)
  while progressed.contents {
    progressed := false
    for col in 0 to columns(b) - 1 {
      if topsCompleteRun(b, col) {
        let suit = Position.suitOf(cardAt(b, ~col, ~i=b.height->Array.getUnsafe(col) - ranks))
        setFound(b, suit, b.found->Array.getUnsafe(suit) + ranks)
        lift(b, col, ranks)
        progressed := true
      }
    }
  }
}

let autoCollect = (b: t) =>
  switch b.law {
  | FreeCell => collectSafeCards(b)
  | SimpleSimon => collectRuns(b)
  }

let couldFinish = (b: t): bool => {
  let seen = b.drainFound // four wide, and refilled before `canFinish` reads it
  let ok = ref(true)
  let col = ref(0)
  while ok.contents && col.contents < columns(b) {
    seen->Array.fill(0, ~start=0, ~end=4)
    let i = ref(b.height->Array.getUnsafe(col.contents) - 1)
    while ok.contents && i.contents >= 0 {
      let card = cardAt(b, ~col=col.contents, ~i=i.contents)
      let suit = Position.suitOf(card)
      let rank = Position.rankOf(card)
      let deeper = seen->Array.getUnsafe(suit)
      if deeper > 0 && rank < deeper {
        ok := false
      } else {
        seen->Array.setUnsafe(suit, rank)
        i := i.contents - 1
      }
    }
    col := col.contents + 1
  }
  ok.contents
}

let canFinish = (b: t): bool =>
  switch b.law {
  | SimpleSimon => hasWon(b)
  | FreeCell =>
    couldFinish(b) && {
      let found = b.drainFound
      let cells = b.drainCells
      let depth = b.drainHeight
      for i in 0 to 3 {
        found->Array.setUnsafe(i, b.found->Array.getUnsafe(i))
      }
      for i in 0 to Array.length(cells) - 1 {
        cells->Array.setUnsafe(i, b.cells->Array.getUnsafe(i))
      }
      for i in 0 to Array.length(depth) - 1 {
        depth->Array.setUnsafe(i, b.height->Array.getUnsafe(i))
      }
      let remaining = ref(b.pack.size - foundationTotal(b))
      let progressed = ref(true)
      while progressed.contents {
        progressed := false
        for i in 0 to Array.length(cells) - 1 {
          let card = cells->Array.getUnsafe(i)
          if (
            card >= 0 && found->Array.getUnsafe(Position.suitOf(card)) == Position.rankOf(card) - 1
          ) {
            found->Array.setUnsafe(Position.suitOf(card), Position.rankOf(card))
            cells->Array.setUnsafe(i, -1)
            remaining := remaining.contents - 1
            progressed := true
          }
        }
        for i in 0 to Array.length(depth) - 1 {
          let draining = ref(true)
          while draining.contents && depth->Array.getUnsafe(i) > 0 {
            let card = cardAt(b, ~col=i, ~i=depth->Array.getUnsafe(i) - 1)
            if found->Array.getUnsafe(Position.suitOf(card)) != Position.rankOf(card) - 1 {
              draining := false
            } else {
              found->Array.setUnsafe(Position.suitOf(card), Position.rankOf(card))
              depth->Array.setUnsafe(i, depth->Array.getUnsafe(i) - 1)
              remaining := remaining.contents - 1
              progressed := true
            }
          }
        }
      }
      remaining.contents == 0
    }
  }

let canDeal = (b: t): bool => b.undealt > 0 && !(b.height->Array.includes(0))

let dealRow = (b: t) => {
  let n = Math.Int.min(b.undealt, columns(b))
  log(b, dealtWrite, 0, b.undealt)
  for col in 0 to n - 1 {
    b.undealt = b.undealt - 1
    push(b, col, b.stock->Array.getUnsafe(b.undealt))
  }
}

// --- Moves, as ints ----------------------------------------------------------
// A `Position.move` packed into one int, so listing a node's moves allocates one
// array of numbers rather than a record per move. Low bits up: the card (6), how
// many cards (7), the source (a cell flag and an index of 5), the destination (a
// kind of 2 and an index of 5). A deal is `-1`, which no packed play can be.

type move = int

let deal: move = -1

let ofMove = (move: Position.move): move =>
  switch move {
  | Deal => deal
  | Play({n, source, destination, card}) =>
    let source = switch source {
    | FromCell(i) => 32 + i
    | FromColumn(i) => i
    }
    let destination = switch destination {
    | ToFoundation => 0
    | ToCell(i) => 1 + i * 4
    | ToColumn(i) => 2 + i * 4
    }
    card + n * 64 + source * 8192 + destination * 524288
  }

let toMove = (move: move): Position.move =>
  if move == deal {
    Position.Deal
  } else {
    let card = mod(move, 64)
    let n = mod(move / 64, 128)
    let source = mod(move / 8192, 64)
    let destination = move / 524288
    let index = destination / 4
    Position.Play({
      n,
      card,
      source: source >= 32 ? Position.FromCell(source - 32) : Position.FromColumn(source),
      destination: switch mod(destination, 4) {
      | 0 => Position.ToFoundation
      | 1 => Position.ToCell(index)
      | _ => Position.ToColumn(index)
      },
    })
  }

// `Position.legalMoves`, in the same order and with the same three prunings — the two
// column ones taken whenever the board doesn't `keepsOrder`, so a board that `fold`s
// prunes them with a stock still to deal.
let legalMoves = (b: t): array<move> => {
  let moves = []
  for cell in 0 to Array.length(b.cells) - 1 {
    let card = b.cells->Array.getUnsafe(cell)
    if card >= 0 {
      if foundationAccepts(b, card) {
        moves->Array.push(card + 64 + (32 + cell) * 8192)
      }
      for col in 0 to columns(b) - 1 {
        if cascadeAccepts(b, ~col, ~card) {
          moves->Array.push(card + 64 + (32 + cell) * 8192 + (2 + col * 4) * 524288)
        }
      }
    }
  }
  let firstEmptyCell = b.cells->Array.indexOf(-1)
  let firstEmptyColumn = b.height->Array.indexOf(0)
  let folds = !keepsOrder(b)
  for src in 0 to columns(b) - 1 {
    let depth = b.height->Array.getUnsafe(src)
    if depth > 0 {
      let top = cardAt(b, ~col=src, ~i=depth - 1)
      if foundationAccepts(b, top) {
        moves->Array.push(top + 64 + src * 8192)
      }
      if firstEmptyCell >= 0 {
        moves->Array.push(top + 64 + src * 8192 + (1 + firstEmptyCell * 4) * 524288)
      }
      let liftable = runLength(b, src)
      for n in 1 to liftable {
        let bottom = cardAt(b, ~col=src, ~i=depth - n)
        for dest in 0 to columns(b) - 1 {
          let intoEmpty = b.height->Array.getUnsafe(dest) == 0
          if (
            dest != src &&
            cascadeAccepts(b, ~col=dest, ~card=bottom) &&
            !(intoEmpty && folds && (dest != firstEmptyColumn || n == depth)) &&
            n <= liftLimit(b, ~ignoring=dest)
          ) {
            moves->Array.push(bottom + n * 64 + src * 8192 + (2 + dest * 4) * 524288)
          }
        }
      }
    }
  }
  if canDeal(b) {
    moves->Array.push(deal)
  }
  moves
}

// --- Make and unmake ---------------------------------------------------------

// Play `move` and settle the board after it — `Position.applyMove`, in place. The
// move has to be one `legalMoves` offered on this board as it stands.
let play = (b: t, move: move) => {
  b.frames->Array.push(Array.length(b.journal))
  if move == deal {
    dealRow(b)
  } else {
    let card = mod(move, 64)
    let n = mod(move / 64, 128)
    let source = mod(move / 8192, 64)
    let destination = move / 524288
    let index = destination / 4
    // The lifted cards land before the source lets go of them: they are still
    // sitting in its slots, so no scratch copy is needed to carry them across.
    switch mod(destination, 4) {
    | 0 => setFound(b, Position.suitOf(card), Position.rankOf(card))
    | 1 => setCell(b, index, card)
    | _ =>
      if source >= 32 {
        push(b, index, card)
      } else {
        let depth = b.height->Array.getUnsafe(source)
        for i in depth - n to depth - 1 {
          push(b, index, cardAt(b, ~col=source, ~i))
        }
      }
    }
    if source >= 32 {
      setCell(b, source - 32, -1)
    } else {
      lift(b, source, n)
    }
  }
  if !canFinish(b) {
    autoCollect(b)
  }
}

// Take back the last move `play` played, settle and all.
let takeBack = (b: t) =>
  switch b.frames->Array.pop {
  | Some(mark) => rewind(b, mark)
  | None => ()
  }

// How many moves are played and not yet taken back.
let played = (b: t): int => Array.length(b.frames)

// --- The canonical hash ------------------------------------------------------
// Two 32-bit hashes of the board `Position.key` spells, so two boards that key
// alike hash alike: the cells are a multiset there (sorted before they're spelled),
// and here each is hashed on its own and the results *summed*, which no order
// changes. The columns are summed the same way unless the board `keepsOrder`; while it
// does, each column's hash takes its index too, as `key` keeps their order. The
// foundations and the stock's length are positional.
//
// **Nothing may depend on it being exact.** A match is where a lookup starts, never
// where it ends — `Exhausted` is only a proof while "seen" means seen, so a caller
// compares the boards themselves before believing it.

// Murmur3's finaliser: every input bit reaches every output bit, which is what
// makes a plain sum of the per-column values safe to take.
let mix = (h: int): int => {
  let h = h->Int.bitwiseXor(h->Int.shiftRightUnsigned(16))
  let h = Math.Int.imul(h, 0x85ebca6b)
  let h = h->Int.bitwiseXor(h->Int.shiftRightUnsigned(13))
  let h = Math.Int.imul(h, 0xc2b2ae35)
  h->Int.bitwiseXor(h->Int.shiftRightUnsigned(16))
}

// One FNV-1a step, over a small number rather than a byte.
let step = (h: int, n: int): int => Math.Int.imul(h->Int.bitwiseXor(n), 0x01000193)

let hash = (b: t): (int, int) => {
  let a = ref(0)
  let z = ref(0)
  for i in 0 to Array.length(b.cells) - 1 {
    let card = b.cells->Array.getUnsafe(i)
    if card >= 0 {
      a := (a.contents + mix(card + 0x1000))->Int.bitwiseOr(0)
      z := (z.contents + mix(card + 0x2000))->Int.bitwiseOr(0)
    }
  }
  for col in 0 to columns(b) - 1 {
    let h = b.height->Array.getUnsafe(col)
    let seat = (seed: int): int => keepsOrder(b) ? step(seed, col) : seed
    let ha = ref(step(seat(0x811c9dc5), b.down->Array.getUnsafe(col)))
    let hz = ref(step(seat(0x050c5d1f), b.down->Array.getUnsafe(col) + 64))
    for i in 0 to h - 1 {
      let card = cardAt(b, ~col, ~i)
      ha := step(ha.contents, card)
      hz := step(hz.contents, card + 64)
    }
    a := (a.contents + mix(ha.contents))->Int.bitwiseOr(0)
    z := (z.contents + mix(hz.contents + h))->Int.bitwiseOr(0)
  }
  let fa = ref(a.contents)
  let fz = ref(z.contents)
  for suit in 0 to 3 {
    fa := step(fa.contents, b.found->Array.getUnsafe(suit))
    fz := step(fz.contents, b.found->Array.getUnsafe(suit) + 128)
  }
  (mix(step(fa.contents, b.undealt)), mix(step(fz.contents, b.undealt + 256)))
}

// --- The heuristic -----------------------------------------------------------
// `Solver.heuristic`, term for term; what each term charges for is in
// `docs/solver.md` § The heuristic. The weights are declared here rather than in
// `Solver`, which re-exports them, because a search that weighs this board has to
// depend on it — and the two can't depend on each other.

type weights = {
  remaining: int,
  buried: int,
  seam: int,
  cell: int,
  emptyColumn: int,
  stock: int,
  idle: int,
}

let heuristic = (b: t, w: weights): int => {
  let h = ref((b.pack.size - foundationTotal(b)) * w.remaining)
  let wanted = b.wanted
  wanted->Array.fill(false, ~start=0, ~end=52)
  switch b.law {
  | FreeCell =>
    for i in 0 to Array.length(b.pack.suits) - 1 {
      let suit = b.pack.suits->Array.getUnsafe(i)
      let home = b.found->Array.getUnsafe(suit)
      if home < b.pack.ranks {
        wanted->Array.setUnsafe(suit * 13 + home, true)
      }
    }
  | SimpleSimon =>
    for col in 0 to columns(b) - 1 {
      for i in 0 to b.height->Array.getUnsafe(col) - 1 {
        let card = cardAt(b, ~col, ~i)
        let founds =
          i == 0 || !Position.follows(b.law, ~below=cardAt(b, ~col, ~i=i - 1), ~above=card)
        if founds && Position.rankOf(card) < b.pack.ranks {
          wanted->Array.setUnsafe(card + 1, true)
        }
      }
    }
  }
  for col in 0 to columns(b) - 1 {
    let depth = b.height->Array.getUnsafe(col)
    if depth == 0 {
      h := h.contents - w.emptyColumn
    }
    for i in 0 to depth - 1 {
      let card = cardAt(b, ~col, ~i)
      if wanted->Array.getUnsafe(card) {
        h := h.contents + (depth - 1 - i) * w.buried
      }
      if i > 0 && !Position.follows(b.law, ~below=cardAt(b, ~col, ~i=i - 1), ~above=card) {
        h := h.contents + w.seam
      }
    }
  }
  h := h.contents + (Array.length(b.cells) - emptyCells(b)) * w.cell
  h.contents + b.undealt * w.stock
}
