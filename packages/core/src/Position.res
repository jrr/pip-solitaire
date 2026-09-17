// A position packed small enough to **think** with — the board as `Solver` searches
// it, under one of two laws (`law` below). Why the packing exists, and the
// row-by-row list of what it mirrors, are in `docs/solver.md` § The packed position.
//
// **Nothing here is a second set of rules.** Every predicate below is the packed
// reading of one in `Rules`/`Reducer`, named at the predicate itself. A change to a
// rule over there is a change here, and `Position_test` is what catches it.

open Card

// --- A card as an int --------------------------------------------------------
// `suit * 13 + (rank - 1)`, so every card is one small int in 0…51 and a whole
// column is a compact array of them. The suit numbering is this module's own — it
// only has to be consistent with itself — and the two red suits sit in the middle
// so `isRed` stays a single range test. Reorder them and that breaks silently.
//
// **The 13 is the numbering, not the deck.** A short pack numbers its cards exactly
// the same way and simply leaves gaps — a Micro board's sixteen cards are still
// ♠A…♠8 at 0…7 and ♥A…♥8 at 13…20. A denser numbering would save a few bytes of
// scratch array and cost `isRed`, `suitOf` and `found`'s indexing all at once.

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

// The three things the rules ask of a card number, without unpacking it — and the
// colour of a bare suit number, which is the same range test one step earlier (the
// safe-collect rule asks it of a suit that has no card in hand).
let suitOf = (id: int): int => id / 13
let rankOf = (id: int): int => mod(id, 13) + 1
let isRedSuit = (suit: int): bool => suit == 1 || suit == 2
let isRed = (id: int): bool => isRedSuit(suitOf(id))

// A card number as the text identity everything else in the repo names cards by
// (`CardText`), and back — how a driver outside ReScript says which card it means.
let code = (id: int): string => CardText.format(cardOf(id))
let idOfCode = (token: string): option<int> => CardText.parse(token)->Option.map(idOf)

// --- The law -----------------------------------------------------------------
// Which game's rules a position is the packed reading of. A `Game.t` says its rules
// as data, pile by pile; the search can't afford to consult that per move, so the
// four facts that differ between the two games it plays are folded into one tag:
//
//   | law           | cascades              | runs move   | collected        | foundations |
//   |---------------|-----------------------|-------------|------------------|-------------|
//   | `FreeCell`    | `Rules.cascade`       | `Supermove` | `SafeCards`      | open        |
//   | `SimpleSimon` | `Rules.spiderCascade` | `Unlimited` | `CompleteRuns`   | `Sealed`    |
//
// `lawOf` at the foot of this file is where a board is read as one or the other, and
// declines any board that isn't exactly one of the two.
type law =
  | FreeCell
  | SimpleSimon

// --- The pack ----------------------------------------------------------------
// The deck a board is played with, in the three numbers the rules ask of it. A
// `Game.t` carries its own `Cards.deck` and `packOf` reads this off it; it travels
// *on* the position because none of it can be recovered from one mid-game — which
// suits are in play and how far the ranks run are facts about the deal, not about
// where the cards are lying now.
//
// Every number here was once written down as a 52 or a 13 somewhere: what a won
// board totals, how long Simple Simon's "unlimited" lift is, the rank a run is
// complete at, the cards the heuristic counts down from.
type pack = {
  suits: array<int>, // the suit numbers in play, in `suitOf`'s numbering
  ranks: int, // how many ranks, Ace upward — so also the rank a foundation is done at
  size: int, // how many cards are on the board altogether
}

// Naïve on purpose: what a deck *would* pack to. Whether it may — one copy of each
// card, ranks running up from the Ace — is `ofGameState`'s question, along with
// every other thing the board has to be for the model to hold it.
let packOf = (deck: Cards.deck): pack => {
  suits: deck.suits->Array.map(suitIndex),
  ranks: Array.length(deck.ranks),
  size: Array.length(deck.suits) * Array.length(deck.ranks),
}

// The full pack, for a position posed by hand rather than read off a board.
let standardPack: pack = packOf(Cards.standard)

// --- The position ------------------------------------------------------------

// `pack` — the deck it's played with, above.
// `cells` — the free cells, `-1` for an empty one. However many the board lays out;
//   none under Simple Simon, and the array is empty rather than absent so the loops
//   over it need no case.
// `found` — how many cards of each suit are home, indexed by `suitOf` — four wide
//   whatever the pack, since a suit keeps its number when the deck is short. Under
//   FreeCell that's the rank its foundation has climbed to (an ascending same-suit
//   run, so its top rank *is* its contents); under Simple Simon it's `0` or the
//   pack's top rank, since a suit's run is collected whole or not at all.
// `casc` — the columns, each bottom-first like `GameState.cardsInPile`.
//
// A plain record of arrays, deliberately: it is also the shape a JavaScript
// driver builds by hand (`{law, pack, cells, found, casc}`) when it reads a board off
// a rendered page — see `web-app/scripts/autoplay/read-board.mjs`.
type t = {
  law: law,
  pack: pack,
  cells: array<int>,
  found: array<int>,
  casc: array<array<int>>,
}

// A position of one's own: every array copied, so a caller can mutate the result
// without reaching back into the original. The search leans on this — `applyMove`
// works in place on a copy rather than rebuilding immutably, which is most of why
// it can afford to be called a hundred thousand times.
let copy = (s: t): t => {
  law: s.law,
  pack: s.pack, // never mutated, so every copy shares the one record
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

// How many cards are home — the game's progress, and the whole pack exactly when
// it's won.
let foundationTotal = (s: t): int => {
  let n = ref(0)
  for i in 0 to Array.length(s.found) - 1 {
    n := n.contents + s.found->Array.getUnsafe(i)
  }
  n.contents
}

let hasWon = (s: t): bool => foundationTotal(s) == s.pack.size

// `Rules.isRun`, for one pair: does `above` hold together with `below` as part of a
// run a hand may lift? One rank down under both laws; opposite colour under
// FreeCell's `Rules.cascade`, the same suit under Simple Simon's
// `Rules.spiderCascade`.
let follows = (law: law, ~below: int, ~above: int): bool =>
  rankOf(below) == rankOf(above) + 1 &&
    switch law {
    | FreeCell => isRed(below) != isRed(above)
    | SimpleSimon => suitOf(below) == suitOf(above)
    }

// `Rules.accepts` on a cascade: build down, any card founding an empty column. In
// alternating colour under FreeCell, where landing and lifting are one law — and
// regardless of suit under Simple Simon, where they aren't: any Seven takes any
// Six, but only a same-suit Six leaves with it again (`follows`).
let cascadeAccepts = (s: t, ~col: int, ~card: int): bool => {
  let pile = s.casc->Array.getUnsafe(col)
  switch pile->Array.last {
  | None => true
  | Some(top) =>
    rankOf(top) == rankOf(card) + 1 &&
      switch s.law {
      | FreeCell => isRed(top) != isRed(card)
      | SimpleSimon => true
      }
  }
}

// `Rules.accepts` on a foundation: an Ace onto an empty pile, then up by suit —
// FreeCell's `Rules.foundation`. Simple Simon's foundations are `Sealed`: the hand
// plays nothing there, so nothing is ever accepted.
let foundationAccepts = (s: t, card: int): bool =>
  switch s.law {
  | FreeCell => s.found->Array.getUnsafe(suitOf(card)) == rankOf(card) - 1
  | SimpleSimon => false
  }

// How many cards form the ordered run at the top of a column — the packed reading
// of the maximal tail `Rules.isRun` accepts, which is the most a hand may lift.
let runLength = (law: law, pile: array<int>): int => {
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
      if follows(law, ~below, ~above) {
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

// `Reducer.withinRunLimit`: the most cards one move may carry to `ignoring`. The
// supermove under FreeCell; under Simple Simon a run moves whole however long, and
// the pack is the only bound.
let liftLimit = (s: t, ~ignoring: int): int =>
  switch s.law {
  | FreeCell => maxSupermove(s, ~ignoring)
  | SimpleSimon => s.pack.size
  }

// `Reducer.isSafeToCollect`: never strand a card a cascade might still want. Aces
// and Twos are always safe — nothing is ever built down onto them — and anything
// higher only once every opposite-colour foundation is within one rank of it.
//
// Which suits those are is the pack's to say, exactly as `Reducer.oppositeColorSuits`
// asks the deck: on Micro's ♠♥ pack a black card waits on one foundation, not two,
// and naming the other two by number would stall auto-collect above the Twos.
let isSafeToCollect = (s: t, card: int): bool =>
  foundationAccepts(s, card) && {
    let r = rankOf(card)
    r <= 2 || {
        let red = isRed(card)
        let safe = ref(true)
        for i in 0 to Array.length(s.pack.suits) - 1 {
          let suit = s.pack.suits->Array.getUnsafe(i)
          if isRedSuit(suit) != red && s.found->Array.getUnsafe(suit) < r - 1 {
            safe := false
          }
        }
        safe.contents
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

// `Reducer.collectSafeCards`: the fixpoint over the safe cards — collecting one can
// make the next safe, so it rescans until nothing is. Mutates `s`.
let collectSafeCards = (s: t): unit => {
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
}

// Does the top of `pile` hold a whole suit, the pack's highest rank down to the Ace
// — `Rules.isCompleteRun` read off a column's tail, and against the deck for the
// same reason it is: "thirteen cards ending on a King" is the full pack's answer to
// the question, not the question.
let topsCompleteRun = (~ranks: int, pile: array<int>): bool => {
  let depth = Array.length(pile)
  depth >= ranks &&
  rankOf(pile->Array.getUnsafe(depth - ranks)) == ranks && {
    let ok = ref(true)
    let i = ref(depth - ranks + 1)
    while ok.contents && i.contents < depth {
      ok :=
        follows(
          SimpleSimon,
          ~below=pile->Array.getUnsafe(i.contents - 1),
          ~above=pile->Array.getUnsafe(i.contents),
        )
      i := i.contents + 1
    }
    ok.contents
  }
}

// `Reducer.collectRuns`: every column topped by a complete run has it lifted off
// home. One move can complete two — the run it lands on, and one it uncovers by
// leaving — so every column is looked at. There is always a foundation free for it:
// `ofGameState` refuses a board with fewer foundations than the pack has suits.
// Mutates `s`.
let collectRuns = (s: t): unit => {
  let ranks = s.pack.ranks
  for col in 0 to Array.length(s.casc) - 1 {
    let pile = s.casc->Array.getUnsafe(col)
    if topsCompleteRun(~ranks, pile) {
      let base = pile->Array.getUnsafe(Array.length(pile) - ranks)
      s.found->Array.setUnsafe(suitOf(base), ranks)
      pile->Array.splice(~start=Array.length(pile) - ranks, ~remove=ranks, ~insert=[])
    }
  }
}

// `Reducer.autoCollect`: what leaves the tableau on its own after a move, by the
// law's `collect` policy. Mutates and returns `s`.
let autoCollect = (s: t): t => {
  switch s.law {
  | FreeCell => collectSafeCards(s)
  | SimpleSimon => collectRuns(s)
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
// Under Simple Simon the drain plays nothing — the foundations are `Sealed` — so
// the only finishable board is the won one, and the search runs to the win itself.
//
// The FreeCell drain is written against scratch arrays rather than a copied
// position, and behind the cheap gate above — the search asks this of every
// position it generates, so both the allocations and the drain itself show up in a
// profile.
let canFinish = (s: t): bool =>
  switch s.law {
  | SimpleSimon => hasWon(s)
  | FreeCell =>
    couldFinish(s) && {
      let found = s.found->Array.copy
      let cells = s.cells->Array.copy
      let depth = s.casc->Array.map(pile => Array.length(pile))
      let remaining = ref(s.pack.size - foundationTotal(s))
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
// run move) lifted from `source` onto `destination`, `card` being the one the
// player would grab — for a run, its *bottom* card, since grabbing that is what
// lifts the whole span.
type move = {
  n: int,
  source: source,
  destination: destination,
  card: int,
}

// Every legal move from here, less three deliberate prunings that only ever cost the
// search time — `docs/solver.md` § The search names them. The same loops serve both
// laws: a Simple Simon position has no cells to loop over and no foundation that
// accepts, so the moves it has no word for are never reached.
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
  let firstEmptyColumn = s.casc->Array.findIndex(pile => Array.length(pile) == 0)
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
      let liftable = runLength(s.law, pile)
      for n in 1 to liftable {
        let bottom = pile->Array.getUnsafe(Array.length(pile) - n)
        for dest in 0 to Array.length(s.casc) - 1 {
          let intoEmpty = Array.length(s.casc->Array.getUnsafe(dest)) == 0
          if (
            dest != src &&
            cascadeAccepts(s, ~col=dest, ~card=bottom) &&
            // Only the first empty column: the others are the same move. And never a
            // whole column into one: that only renames the column.
            !(intoEmpty && (dest != firstEmptyColumn || n == Array.length(pile))) &&
            n <= liftLimit(s, ~ignoring=dest)
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
// run move. What a driver expects its grab to raise off the board.
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
// The auto-collect mirrors `Options.default.autoCollect`, which the drivers run
// after every accepted move (`Repl.settle`, `TableScene`). **A plan is therefore a
// plan for a game played with auto-collect on** — what that costs a driver with the
// flag off is the last row of `docs/solver.md` § The packed position.
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
//
// **Spelling them out is the solver's single largest cost**, and so the first thing
// to change if it is ever wanted faster. `docs/solver.md` § On making this faster
// has the profile, and what a replacement measured.
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

// The law a board is played under, read off its rules — or `None` for a board
// under neither. Only the law: whether the board also has the *shape* the model
// holds (no stock, one copy of each card, every card face up) is `ofGameState`'s
// question, so Spiderette reads as Simple Simon's law here and is refused there.
// Every pile of a role is checked, not the first, so a board with one odd pile is
// refused rather than read as the law its others follow.
let lawOf = (game: Game.t): option<law> => {
  let every = (role, rule) => Game.pilesOf(game, role)->Array.every(pile => pile.rule == rule)
  switch (game.runLimit, game.collect) {
  | (Game.Supermove, Game.SafeCards)
    if every(Game.Cascade, Rules.cascade) &&
    every(Game.Foundation, Rules.foundation) &&
    every(Game.FreeCell, Rules.Free) =>
    Some(FreeCell)
  | (Game.Unlimited, Game.CompleteRuns)
    if every(Game.Cascade, Rules.spiderCascade) &&
    every(Game.Foundation, Rules.Sealed) &&
    every(Game.FreeCell, Rules.Free) =>
    Some(SimpleSimon)
  | _ => None
  }
}

// The position a real snapshot is in, or `None` when the board isn't one the model
// can say. **The counts are read off the board, not insisted on**: however many
// cells and columns the game lays out are however many the position has, and the
// deck it carries is the pack (`packOf`). That is the whole of what Mini and Micro
// needed — four columns, two cells, a pack of twenty or sixteen — and it's what a
// seven-column board would need too.
//
// What's left is what the packing genuinely can't say, and each line below is one of
// them: a stock (the model has no word for a deal), a face-down card or a card loose
// on the table (it would go missing), a second copy of a card (two copies pack to one
// int), ranks that don't run up from the Ace (a foundation's *length* is read as the
// rank it has climbed to), and fewer foundations than there are suits to send home.
// Any such board gets an honest `None` rather than a position with pieces missing.
let ofGameState = (~game: Game.t, state: GameState.t): option<t> =>
  lawOf(game)->Option.flatMap(law => {
    let cellPiles = Game.pileIndices(game, Game.FreeCell)
    let foundationPiles = Game.pileIndices(game, Game.Foundation)
    let cascadePiles = Game.pileIndices(game, Game.Cascade)
    let deck = game.deck
    if (
      Array.length(Game.pileIndices(game, Game.Stock)) > 0 ||
      state.faceDown->Array.some(n => n > 0) ||
      Array.length(state.loose) > 0 ||
      deck.copies != 1 ||
      !(deck.ranks->Array.everyWithIndex((rank, i) => Rules.rankValue(rank) == i + 1)) ||
      Array.length(foundationPiles) != Array.length(deck.suits) ||
      Array.length(cascadePiles) == 0
    ) {
      None
    } else {
      let found = [0, 0, 0, 0]
      // A foundation holds one suit's run, whichever way up, so its top names the
      // suit and its length says how much of that suit is home.
      foundationPiles->Array.forEach(i =>
        switch GameState.topOf(state, i) {
        | Some(card) =>
          found->Array.setUnsafe(
            suitIndex(card.suit),
            Array.length(GameState.cardsInPile(state, i)),
          )
        | None => ()
        }
      )
      Some({
        law,
        pack: packOf(deck),
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
  })

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
