// Named *starting scenarios* — canned `GameState.t` snapshots a driver can force
// a board into, instead of always opening from the deal. The web-app selects one
// by name from a URL query parameter (see the web-app's `AppUrl`), which is how
// the screenshot report captures a *mid-game* FreeCell without having to play the
// board interactively first.
//
// A scenario is just a pure function `Game.t => GameState.t`: it lives in `core`
// alongside the state it builds, stays deterministic (seeded, no `Math.random`),
// and is exercised by the same reducer/queries as any other state. Nothing here
// is a new game — these are *positions* within the existing boards.

open Card

// A plausible **mid-game FreeCell** snapshot, derived from the seeded deal so the
// 52-card invariant (every card exactly once) holds by construction: cards are
// only ever *moved* out of the shuffled deck, never invented. It's not the result
// of playing a specific line — it doesn't need to be, the point is a representative
// *layout* — but every pile is a shape a real game reaches: foundations part-built
// up by suit, a couple of free cells occupied, the rest spread across the cascades.
//
//   - Foundations: an ascending Ace-up run per suit, at uneven heights (one suit
//     still untouched) so the top row reads as a game in progress rather than a
//     fresh or finished board.
//   - Free cells: two of the four occupied, two empty.
//   - Cascades: everything left, dealt round-robin across the board's cascades.
//
// Distributed by *role* over the board it's handed, so the snapshot lines up with
// however that board orders its piles (FreeCell puts cells and foundations before
// the cascades — see `Game.freecellDeal`).
let freecellMidgame = (game: Game.t, ~seed: int): GameState.t => {
  let deck = Cards.shuffle(~seed)

  // Each suit's foundation as an ascending run Ace..(nth rank). Heights are
  // deliberately uneven, and one suit is left empty, so the row looks mid-game.
  // Suit order follows `Cards.suits` (Spades, Hearts, Diamonds, Clubs).
  let foundationHeights = [3, 4, 0, 2]
  let foundationPiles = Cards.suits->Array.mapWithIndex((suit, i) =>
    Cards.ranks
    ->Array.slice(~start=0, ~end=foundationHeights->Array.getUnsafe(i))
    ->Array.map(rank => {suit, rank})
  )
  let onFoundation = card =>
    foundationPiles->Array.some(run => run->Array.some(f => GameState.sameCard(f, card)))

  // The rest of the deck, foundation cards removed: two go to free cells, the
  // remainder is dealt across however many cascades the board declares.
  let rest = deck->Array.filter(card => !onFoundation(card))
  let cellCards = rest->Array.slice(~start=0, ~end=2)
  let cascadeCards = rest->Array.slice(~start=2, ~end=Array.length(rest))
  let cascadeCount = Game.pileIndices(game, Game.Cascade)->Array.length
  let cascadePiles = cascadeCards->Cards.deal(~piles=cascadeCount)
  let cellPiles = cellCards->Array.map(card => [card]) // one card per occupied cell

  // Walk the board's piles in order, drawing each role's contents from its queue,
  // so the snapshot matches the board's pile order without assuming it.
  let foundationIdx = ref(0)
  let cellIdx = ref(0)
  let cascadeIdx = ref(0)
  let next = (queue, cursor) => {
    let value = queue->Array.get(cursor.contents)->Option.getOr([])
    cursor := cursor.contents + 1
    value
  }
  let piles = game.piles->Array.map((pile: Game.pile) =>
    switch pile.role {
    | Game.Foundation => next(foundationPiles, foundationIdx)
    | Game.FreeCell => next(cellPiles, cellIdx)
    | Game.Cascade => next(cascadePiles, cascadeIdx)
    }
  )
  {GameState.piles, loose: []}
}

// A **near-won FreeCell**: three suits fully assembled on their foundations and
// the fourth built to the Queen, with that suit's King parked alone in a free
// cell — a single legal move (the King onto its foundation) short of a win (#121).
// Like `freecellMidgame`, it's built straight from the deck so the 52-card
// invariant holds by construction; the one pending King makes the *winning* move —
// and the win state it flips on (the overlay, the CLI line) — easy to exercise,
// including in the browser via `?state=almost-won`.
//
// Distributed by *role* over whatever board it's handed, so it lines up with
// however that board orders its piles (FreeCell puts cells and foundations before
// the cascades — see `Game.freecellDeal`).
let freecellAlmostWon = (game: Game.t): GameState.t => {
  // Each suit's foundation as an ascending Ace→King run — except the last suit,
  // held one short at the Queen so its King is the winning move still to play.
  // Suit order follows `Cards.suits`.
  let lastSuit = Array.length(Cards.suits) - 1
  let foundationPiles = Cards.suits->Array.mapWithIndex((suit, i) => {
    let height = i == lastSuit ? Array.length(Cards.ranks) - 1 : Array.length(Cards.ranks)
    Cards.ranks->Array.slice(~start=0, ~end=height)->Array.map(rank => {suit, rank})
  })
  // The one card still to play: the last suit's King, parked alone in a free cell,
  // ready to drop onto its Queen-topped foundation.
  let pendingKing = {
    suit: Cards.suits->Array.getUnsafe(lastSuit),
    rank: Cards.ranks->Array.getUnsafe(Array.length(Cards.ranks) - 1),
  }

  // Walk the board's piles in order, filling each foundation from its run and
  // dropping the pending King into the first free cell; everything else is empty.
  let foundationIdx = ref(0)
  let kingPlaced = ref(false)
  let piles = game.piles->Array.map((pile: Game.pile) =>
    switch pile.role {
    | Game.Foundation =>
      let run = foundationPiles->Array.get(foundationIdx.contents)->Option.getOr([])
      foundationIdx := foundationIdx.contents + 1
      run
    | Game.FreeCell if !kingPlaced.contents =>
      kingPlaced := true
      [pendingKing]
    | _ => []
    }
  )
  {GameState.piles, loose: []}
}

// A **supermove FreeCell** (#123): a ready-to-lift ordered run sitting atop the
// first cascade, with all four free cells empty and one empty column, so the
// free-cell/empty-column limit is plainly visible. In full it reads
// `(1 + 4) × 2 ^ 1 = 10`; but moving the run *onto* the empty column can't count
// that column as a spare, so there the cap is `(1 + 4) × 2 ^ 0 = 5` — exactly the
// run's length. The whole five-card run lands on the empty column as one gesture,
// and a sixth card would be one over — making both the formula and the
// "destination column doesn't count toward its own exponent" subtlety concrete in
// the CLI (`deal freecell supermove`) and in a `?state=supermove` screenshot.
//
// Built straight from the deck, like the other scenarios, so the 52-card invariant
// holds by construction: the run is carved out and the rest dealt across the
// middle cascades, leaving the first cascade to the run and the last one empty.
let freecellSupermove = (game: Game.t): GameState.t => {
  // A descending-alternating run — black/red/black/red/black — the maximal tail a
  // cascade can offer to a supermove.
  let run = [
    {suit: Spades, rank: Nine}, // black
    {suit: Hearts, rank: Eight}, // red
    {suit: Spades, rank: Seven}, // black
    {suit: Hearts, rank: Six}, // red
    {suit: Spades, rank: Five}, // black
  ]
  let inRun = card => run->Array.some(c => GameState.sameCard(c, card))
  // Everything else, dealt across the *middle* cascades so the free cells and
  // foundations stay empty (keeping the limit's free-cell term at its maximum) and
  // the last cascade stays the empty column the run can move onto.
  let rest = Cards.all->Array.filter(card => !inRun(card))
  let cascadeCount = Game.pileIndices(game, Game.Cascade)->Array.length
  // First cascade: the run. Middle cascades: the rest of the deck. Last: empty.
  let cascadePiles =
    [run]->Array.concat(rest->Cards.deal(~piles=cascadeCount - 2))->Array.concat([[]])

  let cascadeIdx = ref(0)
  let piles = game.piles->Array.map((pile: Game.pile) =>
    switch pile.role {
    | Game.Cascade =>
      let value = cascadePiles->Array.get(cascadeIdx.contents)->Option.getOr([])
      cascadeIdx := cascadeIdx.contents + 1
      value
    | Game.FreeCell | Game.Foundation => []
    }
  )
  {GameState.piles, loose: []}
}

// Resolve a scenario *name* to an initial state for `game`, or `None` when the
// name doesn't apply to this board. This is the whole vocabulary the URL exposes:
// FreeCell's "midgame" and its near-won "almost-won"; new scenarios slot in as
// new arms.
let forName = (game: Game.t, name: string): option<GameState.t> =>
  switch (game.id, name) {
  | ("freecell", "midgame") => Some(freecellMidgame(game, ~seed=Game.freecellSeed))
  | ("freecell", "almost-won") => Some(freecellAlmostWon(game))
  | ("freecell", "supermove") => Some(freecellSupermove(game))
  | _ => None
  }
