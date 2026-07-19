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

// A **send-home FreeCell** (#122): each suit's foundation part-built to the Two,
// with that suit's *next* card — the Three — parked alone in a free cell, one per
// suit across the four cells. Every one of those four Threes is immediately
// home-able, so a run of send-home gestures (a double-click on the web, or the
// CLI's `home` verb) collects them to their foundations one after another — the
// explicit player-initiated shortcut this issue adds, made concrete in a
// `?state=sendhome` screenshot and the CLI (`deal freecell sendhome`).
//
// Built straight from the deck, like the other scenarios, so the 52-card
// invariant holds by construction: the eight foundation cards and the four
// pending Threes are carved out and the remaining forty dealt across the cascades.
let freecellSendHome = (game: Game.t): GameState.t => {
  // Each suit's foundation as an Ace→Two run, so the Three is the card still to
  // send home. Suit order follows `Cards.suits`.
  let foundationPiles = Cards.suits->Array.map(suit => [Ace, Two]->Array.map(rank => {suit, rank}))
  // The four pending cards — one suit's Three apiece — each parked in a free cell.
  let pending = Cards.suits->Array.map(suit => {suit, rank: Three})
  let cellPiles = pending->Array.map(card => [card])

  let inFoundations = card =>
    foundationPiles->Array.some(run => run->Array.some(f => GameState.sameCard(f, card)))
  let isPending = card => pending->Array.some(c => GameState.sameCard(c, card))
  // Everything else — the foundation and pending cards removed — dealt across the
  // cascades, so no card is invented or lost.
  let rest = Cards.all->Array.filter(card => !inFoundations(card) && !isPending(card))
  let cascadeCount = Game.pileIndices(game, Game.Cascade)->Array.length
  let cascadePiles = rest->Cards.deal(~piles=cascadeCount)

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

// A **finishable FreeCell** (#132): the trapped-tail endgame safe auto-collect
// (#125) stalls on, but the "Finish" sweep completes in one gesture. Foundations
// stand at ♠5 / ♣5 / ♥2 / ♦2, and the first cascade holds ♠6 sitting on ♥3 — the
// crux: ♠6 is *accepted* by its foundation but not *safe* (the reds are only at
// the Two), so #125 refuses it, and the wanted ♥3 is trapped beneath. The board is
// nonetheless drainable by foundation moves alone — playing any accepted card
// (♠6 home, then ♥3, …) finishes it — so `canFinish` holds and the button appears.
// Every other suit's remaining cards sit as a descending run in its own cascade,
// each already in foundation-drain order, so the whole board sweeps home.
//
// Built straight from the deck, like the other scenarios, so the 52-card invariant
// holds by construction. Reached in the browser via `?state=finish` and from the
// CLI (`deal freecell finish`).
let freecellFinish = (game: Game.t): GameState.t => {
  // Each suit's foundation as an Ace→(named rank) run. Suit order follows
  // `Cards.suits` (Spades, Hearts, Diamonds, Clubs), matching how the board orders
  // its foundation piles.
  let runTo = (suit, rank) =>
    Cards.ranks
    ->Array.filter(r => Rules.rankValue(r) <= Rules.rankValue(rank))
    ->Array.map(r => {suit, rank: r})
  let foundationRuns = [
    runTo(Spades, Five),
    runTo(Hearts, Two),
    runTo(Diamonds, Two),
    runTo(Clubs, Five),
  ]

  // The trapped tail: ♥3 on the bottom with ♠6 on top, so ♠6 must move before the
  // wanted ♥3 can — exactly what stalls #125's safe rule.
  let trapped = [{suit: Hearts, rank: Three}, {suit: Spades, rank: Six}]

  // A suit's remaining cards as a descending cascade (King at the bottom, the
  // lowest remaining rank on top), so its top is always the next card the drain
  // wants. `lowRank` is the lowest rank not already on the foundation or in the
  // trapped tail.
  let descFrom = (suit, lowRank) =>
    Cards.ranks
    ->Array.filter(r => Rules.rankValue(r) >= Rules.rankValue(lowRank))
    ->Array.toReversed
    ->Array.map(r => {suit, rank: r})
  let cascadePiles = [
    trapped,
    descFrom(Spades, Seven), // ♠6 is in the trapped tail, so this starts at the Seven
    descFrom(Clubs, Six),
    descFrom(Hearts, Four), // ♥3 is in the trapped tail
    descFrom(Diamonds, Three),
  ]

  // Walk the board's piles in order, filling foundations and cascades from their
  // queues and leaving the free cells empty.
  let foundationIdx = ref(0)
  let cascadeIdx = ref(0)
  let next = (queue, cursor) => {
    let value = queue->Array.get(cursor.contents)->Option.getOr([])
    cursor := cursor.contents + 1
    value
  }
  let piles = game.piles->Array.map((pile: Game.pile) =>
    switch pile.role {
    | Game.Foundation => next(foundationRuns, foundationIdx)
    | Game.Cascade => next(cascadePiles, cascadeIdx)
    | Game.FreeCell => []
    }
  )
  {GameState.piles, loose: []}
}

// A named scenario as *data*: the `name` the URL/CLI address it by, a human
// `label` for a picker (the web-app's debug "states" menu), and the pure `build`
// that produces its `GameState` for a board. Collecting the set here — rather
// than burying it in `forName`'s switch — gives a single source of truth a UI can
// enumerate (`scenariosFor`) and a resolver can look up (`forName`) alike.
type named = {
  name: string,
  label: string,
  build: Game.t => GameState.t,
}

// FreeCell's scenarios, in menu order — the whole vocabulary `?state=` and the
// CLI's `deal freecell <scenario>` expose. A new scenario slots in as a new
// entry and is instantly reachable from both the URL and the debug menu.
let freecellScenarios: array<named> = [
  {
    name: "midgame",
    label: "Mid-game",
    build: game => freecellMidgame(game, ~seed=Game.freecellSeed),
  },
  {name: "almost-won", label: "Almost won", build: freecellAlmostWon},
  {name: "supermove", label: "Supermove", build: freecellSupermove},
  {name: "sendhome", label: "Send home", build: freecellSendHome},
  {name: "finish", label: "Finishable", build: freecellFinish},
]

// The named scenarios that apply to `game`, in menu order — empty for a board
// with none (every demo but FreeCell today). This is what a picker enumerates.
let scenariosFor = (game: Game.t): array<named> =>
  switch game.id {
  | "freecell" => freecellScenarios
  | _ => []
  }

// Resolve a scenario *name* to an initial state for `game`, or `None` when the
// name doesn't apply to this board. Derived from `scenariosFor`, so the URL/CLI
// vocabulary and the debug menu's list can never drift apart.
let forName = (game: Game.t, name: string): option<GameState.t> =>
  scenariosFor(game)->Array.find(s => s.name == name)->Option.map(s => s.build(game))
