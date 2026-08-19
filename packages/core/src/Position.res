// A FreeCell position packed small enough to **think** with — the board as the
// solver searches it (see `Solver`).
//
// `GameState.t` is the game's real snapshot and stays the source of truth. This is
// the same position squeezed into ints: four free cells, four foundation ranks,
// eight columns of card numbers. Nothing here is a second set of rules — every
// predicate below is the packed reading of one in `Rules`/`Reducer`, and
// `Position_test` pins them together by playing a solved game through both. The
// packing exists for one reason: a search asks "and then what?" hundreds of
// thousands of times per deal, and the honest `GameState` transition — which
// searches every pile for a card by identity and rebuilds sixteen arrays per move
// — is far too slow to be asked that often.
//
// What it mirrors, and why each is load-bearing for a plan that survives contact
// with the app:
//   - `Rules.cascade` / `Rules.foundation` — what a pile accepts.
//   - `Reducer.maxSupermove` — `(1 + emptyCells) × 2 ^ emptyCascades`, with the
//     destination excluded from the tally, so a planned run move is one the
//     reducer will actually take.
//   - `Reducer.autoCollect` / `isSafeToCollect` — on by `Options.default`, so the
//     board *after* a move usually isn't just that move applied.
//   - `Reducer.canFinish` — once it flips true the drivers stand aside and the
//     Finish button owns the sweep, which changes what the next board looks like.
//     It's also the solver's goal: from there the game is won.
//
// This is the JavaScript mirror that used to live in `web-app/scripts/autoplay/`
// (#269), brought into `core` as ReScript (#290) — so the model and the rules it
// mirrors are now one language, one build, and checked against each other by the
// ordinary test suite rather than only by a browser run.

open Card

// --- A card as an int --------------------------------------------------------
// `suit * 13 + (rank - 1)`, so every card is one small int in 0…51 and a whole
// column is a compact array of them. The suit numbering is this module's own (it
// only has to be consistent with itself), chosen so the two red suits sit in the
// middle and `isRed` is a single range test.

let suitIndex = (suit: suit): int =>
  switch suit {
  | Spades => 0
  | Hearts => 1
  | Diamonds => 2
  | Clubs => 3
  }

let suitAt = (i: int): suit =>
  switch i {
  | 1 => Hearts
  | 2 => Diamonds
  | 3 => Clubs
  | _ => Spades
  }

let rankAt = (r: int): rank =>
  switch r {
  | 2 => Two
  | 3 => Three
  | 4 => Four
  | 5 => Five
  | 6 => Six
  | 7 => Seven
  | 8 => Eight
  | 9 => Nine
  | 10 => Ten
  | 11 => Jack
  | 12 => Queen
  | 13 => King
  | _ => Ace
  }

// The card number of a `Card.card`, and back again — the two directions of the
// packing, checked against each other over the whole deck in `Position_test`.
let idOf = (card: card): int => suitIndex(card.suit) * 13 + Rules.rankValue(card.rank) - 1
let cardOf = (id: int): card => {suit: suitAt(id / 13), rank: rankAt(mod(id, 13) + 1)}

// The three things the rules ask of a card number, without unpacking it.
let suitOf = (id: int): int => id / 13
let rankOf = (id: int): int => mod(id, 13) + 1
let isRed = (id: int): bool => {
  let s = suitOf(id)
  s == 1 || s == 2
}

// A card number as the text identity everything else in the repo names cards by
// (`CardText`), and back — how a driver outside ReScript says which card it means.
let code = (id: int): string => CardText.format(cardOf(id))
let idOfCode = (token: string): option<int> => CardText.parse(token)->Option.map(idOf)

// --- The position ------------------------------------------------------------

// `cells` — the four free cells, `-1` for an empty one.
// `found` — how far each suit's foundation has climbed, indexed by `suitOf`, `0`
//   for a suit with no Ace home yet. (A foundation is an ascending same-suit run,
//   so its top rank *is* its contents.)
// `casc` — the eight columns, each bottom-first like `GameState.cardsInPile`.
//
// A plain record of arrays, deliberately: it is also the shape a JavaScript
// driver builds by hand (`{cells, found, casc}`) when it reads a board off a
// rendered page — see `web-app/scripts/autoplay/read-board.mjs`.
type t = {
  cells: array<int>,
  found: array<int>,
  casc: array<array<int>>,
}

let cellCount = 4
let foundationCount = 4
let columnCount = 8

// A position of one's own: every array copied, so a caller can mutate the result
// without reaching back into the original. The search leans on this — `applyMove`
// works in place on a copy rather than rebuilding immutably, which is most of why
// it can afford to be called a hundred thousand times.
let copy = (s: t): t => {
  cells: s.cells->Array.copy,
  found: s.found->Array.copy,
  casc: s.casc->Array.map(pile => pile->Array.copy),
}

let emptyCells = (s: t): int => {
  let n = ref(0)
  for i in 0 to Array.length(s.cells) - 1 {
    if s.cells->Array.getUnsafe(i) < 0 {
      n := n.contents + 1
    }
  }
  n.contents
}

// How many cards are home — the game's progress, and `52` exactly when it's won.
let foundationTotal = (s: t): int => {
  let n = ref(0)
  for i in 0 to Array.length(s.found) - 1 {
    n := n.contents + s.found->Array.getUnsafe(i)
  }
  n.contents
}

let hasWon = (s: t): bool => foundationTotal(s) == 52

// `Rules.cascade`: build down in alternating colour, any card founding an empty
// column.
let cascadeAccepts = (s: t, ~col: int, ~card: int): bool => {
  let pile = s.casc->Array.getUnsafe(col)
  switch pile->Array.last {
  | None => true
  | Some(top) => rankOf(top) == rankOf(card) + 1 && isRed(top) != isRed(card)
  }
}

// `Rules.foundation`: an Ace onto an empty pile, then up by suit.
let foundationAccepts = (s: t, card: int): bool =>
  s.found->Array.getUnsafe(suitOf(card)) == rankOf(card) - 1

// How many cards form the ordered run at the top of a column — the packed reading
// of the maximal tail `Rules.isRun` accepts, which is the most a hand may lift.
let runLength = (pile: array<int>): int => {
  let n = ref(0)
  let i = ref(Array.length(pile) - 1)
  let running = ref(Array.length(pile) > 0)
  while running.contents {
    n := n.contents + 1
    if i.contents == 0 {
      running := false
    } else {
      let above = pile->Array.getUnsafe(i.contents)
      let below = pile->Array.getUnsafe(i.contents - 1)
      if rankOf(below) == rankOf(above) + 1 && isRed(below) != isRed(above) {
        i := i.contents - 1
      } else {
        running := false
      }
    }
  }
  n.contents
}

// `Reducer.maxSupermove`, with the destination excluded from the empty tally: a
// run's own destination column can't also serve as a spare column for the relay.
let maxSupermove = (s: t, ~ignoring: int): int => {
  let empties = ref(0)
  for i in 0 to Array.length(s.casc) - 1 {
    if i != ignoring && Array.length(s.casc->Array.getUnsafe(i)) == 0 {
      empties := empties.contents + 1
    }
  }
  let doublings = Float.toInt(Math.pow(2., ~exp=Int.toFloat(empties.contents)))
  (1 + emptyCells(s)) * doublings
}

// `Reducer.isSafeToCollect`: never strand a card a cascade might still want. Aces
// and Twos are always safe — nothing is ever built down onto them — and anything
// higher only once both opposite-colour foundations are within one rank of it.
let isSafeToCollect = (s: t, card: int): bool =>
  foundationAccepts(s, card) && {
    let r = rankOf(card)
    r <= 2 || {
        let (a, b) = isRed(card) ? (0, 3) : (1, 2)
        s.found->Array.getUnsafe(a) >= r - 1 && s.found->Array.getUnsafe(b) >= r - 1
      }
  }

// Send `card` home from the cell or column it tops. Mutates `s`.
let sendHome = (s: t, ~card: int, ~cell: int, ~col: int): unit => {
  s.found->Array.setUnsafe(suitOf(card), rankOf(card))
  if cell >= 0 {
    s.cells->Array.setUnsafe(cell, -1)
  } else {
    s.casc->Array.getUnsafe(col)->Array.pop->ignore
  }
}

// `Reducer.autoCollect`: the fixpoint over the safe cards — collecting one can
// make the next safe, so it rescans until nothing is. Mutates and returns `s`.
let autoCollect = (s: t): t => {
  let progressed = ref(true)
  while progressed.contents {
    progressed := false
    let cell = ref(0)
    while !progressed.contents && cell.contents < Array.length(s.cells) {
      let card = s.cells->Array.getUnsafe(cell.contents)
      if card >= 0 && isSafeToCollect(s, card) {
        sendHome(s, ~card, ~cell=cell.contents, ~col=-1)
        progressed := true
      }
      cell := cell.contents + 1
    }
    let col = ref(0)
    while !progressed.contents && col.contents < Array.length(s.casc) {
      switch s.casc->Array.getUnsafe(col.contents)->Array.last {
      | Some(card) if isSafeToCollect(s, card) =>
        sendHome(s, ~card, ~cell=-1, ~col=col.contents)
        progressed := true
      | _ => ()
      }
      col := col.contents + 1
    }
  }
  s
}

// A cheap necessary condition for finishability, to keep the real check off the
// hot path of a search that asks after every generated move.
//
// In a foundation-only drain a column empties from the top and a suit goes home in
// ascending order — so of two cards of one suit in one column, the deeper one must
// be the higher rank. A column that breaks that can never drain, whatever the free
// cells hold.
let couldFinish = (s: t): bool => {
  let seen = [0, 0, 0, 0]
  let ok = ref(true)
  let col = ref(0)
  while ok.contents && col.contents < Array.length(s.casc) {
    let pile = s.casc->Array.getUnsafe(col.contents)
    seen->Array.fill(0, ~start=0, ~end=4)
    let i = ref(Array.length(pile) - 1)
    while ok.contents && i.contents >= 0 {
      let card = pile->Array.getUnsafe(i.contents)
      let suit = suitOf(card)
      let rank = rankOf(card)
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

// `Reducer.canFinish`: does the greedy foundation-only drain win from here?
//
// Written against scratch arrays rather than a copied position, and behind the
// cheap gate above — the search asks this of every position it generates, so both
// the allocations and the drain itself show up in a profile.
let canFinish = (s: t): bool =>
  couldFinish(s) && {
    let found = s.found->Array.copy
    let cells = s.cells->Array.copy
    let depth = s.casc->Array.map(pile => Array.length(pile))
    let remaining = ref(52 - foundationTotal(s))
    let progressed = ref(true)
    while progressed.contents {
      progressed := false
      for i in 0 to Array.length(cells) - 1 {
        let card = cells->Array.getUnsafe(i)
        if card >= 0 && found->Array.getUnsafe(suitOf(card)) == rankOf(card) - 1 {
          found->Array.setUnsafe(suitOf(card), rankOf(card))
          cells->Array.setUnsafe(i, -1)
          remaining := remaining.contents - 1
          progressed := true
        }
      }
      for i in 0 to Array.length(depth) - 1 {
        let draining = ref(true)
        while draining.contents && depth->Array.getUnsafe(i) > 0 {
          let card = s.casc->Array.getUnsafe(i)->Array.getUnsafe(depth->Array.getUnsafe(i) - 1)
          if found->Array.getUnsafe(suitOf(card)) != rankOf(card) - 1 {
            draining := false
          } else {
            found->Array.setUnsafe(suitOf(card), rankOf(card))
            depth->Array.setUnsafe(i, depth->Array.getUnsafe(i) - 1)
            remaining := remaining.contents - 1
            progressed := true
          }
        }
      }
    }
    remaining.contents == 0
  }

// --- Moves -------------------------------------------------------------------

// Where a move starts: a free cell, or the top of a column.
type source =
  | FromCell(int)
  | FromColumn(int)

// …and where it lands. `ToCell` names the cell it will occupy, so a driver aiming
// a real drag knows which one the plan meant.
type destination =
  | ToFoundation
  | ToCell(int)
  | ToColumn(int)

// One move, in the terms a player makes it: `n` cards (more than one only for a
// supermove) lifted from `source` onto `destination`, `card` being the one the
// player would grab — for a run, its *bottom* card, since grabbing that is what
// lifts the whole span.
type move = {
  n: int,
  source: source,
  destination: destination,
  card: int,
}

// Every legal move from here. The two deliberate prunings are the ones that only
// ever cost the search time: a card may go to the *first* empty free cell (the
// other empty cells are the same move), and a whole column may not move into an
// empty one (that only renames the column).
let legalMoves = (s: t): array<move> => {
  let moves = []
  for cell in 0 to Array.length(s.cells) - 1 {
    let card = s.cells->Array.getUnsafe(cell)
    if card >= 0 {
      if foundationAccepts(s, card) {
        moves->Array.push({n: 1, source: FromCell(cell), destination: ToFoundation, card})
      }
      for col in 0 to Array.length(s.casc) - 1 {
        if cascadeAccepts(s, ~col, ~card) {
          moves->Array.push({n: 1, source: FromCell(cell), destination: ToColumn(col), card})
        }
      }
    }
  }
  let firstEmptyCell = s.cells->Array.indexOf(-1)
  for src in 0 to Array.length(s.casc) - 1 {
    let pile = s.casc->Array.getUnsafe(src)
    switch pile->Array.last {
    | None => ()
    | Some(top) =>
      if foundationAccepts(s, top) {
        moves->Array.push({n: 1, source: FromColumn(src), destination: ToFoundation, card: top})
      }
      if firstEmptyCell >= 0 {
        moves->Array.push({
          n: 1,
          source: FromColumn(src),
          destination: ToCell(firstEmptyCell),
          card: top,
        })
      }
      let liftable = runLength(pile)
      for n in 1 to liftable {
        let bottom = pile->Array.getUnsafe(Array.length(pile) - n)
        for dest in 0 to Array.length(s.casc) - 1 {
          let intoEmpty = Array.length(s.casc->Array.getUnsafe(dest)) == 0
          if (
            dest != src &&
            cascadeAccepts(s, ~col=dest, ~card=bottom) &&
            !(intoEmpty && n == Array.length(pile)) &&
            n <= maxSupermove(s, ~ignoring=dest)
          ) {
            moves->Array.push({
              n,
              source: FromColumn(src),
              destination: ToColumn(dest),
              card: bottom,
            })
          }
        }
      }
    }
  }
  moves
}

// The cards a move lifts, bottom-first — one card, or the whole span of a
// supermove. What a driver expects its grab to raise off the board.
let lifted = (s: t, move: move): array<int> =>
  switch move.source {
  | FromCell(_) => [move.card]
  | FromColumn(col) =>
    let pile = s.casc->Array.getUnsafe(col)
    pile->Array.slice(~start=Array.length(pile) - move.n)
  }

// Apply a move, then the app's post-move auto-collect, and return the resulting
// position — a fresh value, the input untouched.
//
// The auto-collect is `Options.default.autoCollect` mirrored: the drivers run it
// after every accepted move but stand aside once the board is finishable, from
// where the Finish button owns the sweep (see `Repl.settle` / `TableScene`). A
// plan is therefore a plan for a game played with auto-collect *on*, which is how
// the app ships.
let applyMove = (s: t, move: move): t => {
  let t = copy(s)
  let cards = lifted(s, move)
  switch move.source {
  | FromCell(cell) => t.cells->Array.setUnsafe(cell, -1)
  | FromColumn(col) =>
    let pile = t.casc->Array.getUnsafe(col)
    pile->Array.splice(~start=Array.length(pile) - move.n, ~remove=move.n, ~insert=[])
  }
  switch move.destination {
  | ToFoundation => t.found->Array.setUnsafe(suitOf(move.card), rankOf(move.card))
  | ToCell(cell) => t.cells->Array.setUnsafe(cell, move.card)
  | ToColumn(col) =>
    let pile = t.casc->Array.getUnsafe(col)
    cards->Array.forEach(c => pile->Array.push(c))
  }
  if canFinish(t) {
    t
  } else {
    autoCollect(t)
  }
}

// A canonical key for a search's visited set: two positions that differ only in
// *which* free cell or *which* column holds what are the same position, so the
// cells and the columns are both sorted before they're spelled out.
let key = (s: t): string => {
  let cells = s.cells->Array.filter(c => c >= 0)
  cells->Array.sort(Int.compare)
  let cols = s.casc->Array.map(pile => pile->Array.joinUnsafe(","))
  cols->Array.sort(String.compare)
  s.found->Array.joinUnsafe(".") ++
  "|" ++
  cells->Array.joinUnsafe(",") ++
  "|" ++
  cols->Array.join("/")
}

// A move in words, for a play-by-play.
let describeMove = (move: move): string => {
  let where = spot =>
    switch spot {
    | ToFoundation => "foundation"
    | ToCell(i) => `cell ${Int.toString(i)}`
    | ToColumn(i) => `column ${Int.toString(i)}`
    }
  let from = switch move.source {
  | FromCell(i) => `cell ${Int.toString(i)}`
  | FromColumn(i) => `column ${Int.toString(i)}`
  }
  let what = move.n > 1 ? `${code(move.card)}+${Int.toString(move.n - 1)}` : code(move.card)
  `${what} from ${from} to ${where(move.destination)}`
}

// --- Across the seam, to the real board --------------------------------------
// The two directions that make this a mirror rather than a fork: a real
// `GameState` packed down to a position, and a planned move handed back as the
// `Reducer.action` a driver dispatches.

// The position a real snapshot is in, or `None` when the board isn't a FreeCell
// one — four free cells, four foundations, eight cascades is all this model can
// say, so a card-table demo (or any other shape) gets an honest `None` rather
// than a board with pieces missing.
let ofGameState = (~game: Game.t, state: GameState.t): option<t> => {
  let cellPiles = Game.pileIndices(game, Game.FreeCell)
  let foundationPiles = Game.pileIndices(game, Game.Foundation)
  let cascadePiles = Game.pileIndices(game, Game.Cascade)
  if (
    Array.length(cellPiles) != cellCount ||
    Array.length(foundationPiles) != foundationCount ||
    Array.length(cascadePiles) != columnCount ||
    Array.length(state.loose) > 0
  ) {
    None
  } else {
    let found = [0, 0, 0, 0]
    foundationPiles->Array.forEach(i =>
      switch GameState.topOf(state, i) {
      | Some(card) => found->Array.setUnsafe(suitIndex(card.suit), Rules.rankValue(card.rank))
      | None => ()
      }
    )
    Some({
      cells: cellPiles->Array.map(i =>
        switch GameState.topOf(state, i) {
        | Some(card) => idOf(card)
        | None => -1
        }
      ),
      found,
      casc: cascadePiles->Array.map(i =>
        GameState.cardsInPile(state, i)->Array.map(card => idOf(card))
      ),
    })
  }
}

// The `Reducer.action` that plays `move` on the real board — what a driver
// dispatches to actually make the move. `None` when the move doesn't fit this
// board (a foundation that won't take the card, a column the board hasn't got),
// which for a move this module generated means the position and the state have
// come apart.
//
// The destination is resolved against the *live* state rather than baked into the
// move: which foundation pile a suit lives on is a fact about the board being
// played, not about the plan.
let toAction = (~game: Game.t, state: GameState.t, move: move): option<Reducer.action> => {
  let cards = switch move.source {
  | FromCell(_) => Some([cardOf(move.card)])
  | FromColumn(col) =>
    Game.pileIndices(game, Game.Cascade)
    ->Array.get(col)
    ->Option.map(i => {
      let pile = GameState.cardsInPile(state, i)
      pile->Array.slice(~start=Array.length(pile) - move.n)
    })
  }
  let onto = switch move.destination {
  | ToFoundation => Reducer.foundationTarget(~game, state, cardOf(move.card))
  | ToCell(cell) => Game.pileIndices(game, Game.FreeCell)->Array.get(cell)
  | ToColumn(col) => Game.pileIndices(game, Game.Cascade)->Array.get(col)
  }
  switch (cards, onto) {
  | (Some(cards), Some(i)) if Array.length(cards) == move.n =>
    Some(
      move.n == 1
        ? Reducer.Move({card: cards->Array.getUnsafe(0), to: Reducer.ToPile(i)})
        : Reducer.MoveRun({cards, to: Reducer.ToPile(i)}),
    )
  | _ => None
  }
}
