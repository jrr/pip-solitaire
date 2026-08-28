// A *game* modelled as data: a board's rules, independent of any presentation.
// This is the "several supported games" seam (#62) — a board described
// declaratively so the view can interpret it dynamically instead of hard-coding
// zones and an opening deal. A new game is a new value here, not new view code.
// FreeCell is the one game today (#342 retired the demo boards that proved the
// seam on the way here), so the type is what a second game would slot into.
//
// What a game says:
//   - `piles` — the drop zones, each with a stacking behaviour (how a second
//     card lands on the first) *and* the rule it enforces (what it will accept).
//     The model says how many there are, how each stacks, and the law each
//     obeys; where they sit on screen is the view's business.
//   - each pile's `rule` — the stackability law as data (#76): may a card land
//     on this pile given its current top card? A `Rules.rule` value weighed by
//     the pure `Rules.accepts`, shared by the view's hover highlight and its
//     drop decision. Because the rule lives on the *pile*, one board carries
//     piles of different kinds — an alternating-colour cascade and a same-suit
//     foundation — side by side.
//   - `seed` — the deal number that reproduces this board, when it has one, so a
//     dealt board can say where it came from.
//
// The view (`TableScene`) reads all of this and lays the board out on its own
// terms — "piles hang from the top of the stage and grow downward".

open Card

// How a newcomer lands on a pile that already holds a card (#56): `Squared`
// covers the last card so the pile keeps a single card's footprint; `Fanned`
// steps off it so every card keeps a visible edge.
type stacking =
  | Squared
  | Fanned

// A pile's *role* on the board (#94) — its classification within a game. The
// three FreeCell roles: a **cascade** (the columns cards are dealt into and built
// down), a **free cell** (a single-card holding slot), and a **foundation** (built
// up by suit to the King). The role is the *classification*, not the mechanic:
// rules and capacity stay independent (a `FreeCell` role typically pairs with
// `capacity: Some(1)` and `rule: Free`, but nothing here enforces that). Callers
// *target a group by role* — the deal fills only the cascades, auto-to-foundation
// and win detection look only at the foundations, the layout groups free cells +
// foundations across the top with cascades below — via `pilesOf`/`pileIndices`
// (below).
type role =
  | Cascade
  | FreeCell
  | Foundation

// One drop zone: its `role` (its classification on the board — #94), its
// stacking behaviour (layout — how a second card lands visually), the `rule` it
// enforces (what it will accept — #76), an optional `capacity` (how many cards
// it may hold — #93), and the cards it opens holding (bottom-first, so the last
// is the top of the pile).
//
// `role`, `rule` and `capacity` are independent: a FreeCell **free cell** is
// `role: FreeCell` *and* `rule: Free` *and* `capacity: Some(1)`, but the role is
// only the classification — it's what lets callers address a group of piles
// (`pilesOf`/`pileIndices`), not what governs a drop.
//
// `capacity` is `None` for the unbounded piles (cascades, foundations) and
// `Some(n)` for a capped one — a FreeCell **free cell** is `Rules.Free` with
// `Some(1)`, a pile that holds exactly one card of any suit. The cap depends on
// the pile's *current count*, which `Rules.accepts` deliberately never sees, so
// it's enforced one layer up in `Reducer.canDrop`/`reduce` — `Rules.accepts`
// stays purely about ordering/colour/rank.
type pile = {
  role: role,
  stacking: stacking,
  rule: Rules.rule,
  capacity: option<int>,
  cards: array<card>,
}

type t = {
  id: string, // stable scene id (also the picker / localStorage key)
  name: string, // human label shown in the scene picker
  piles: array<pile>,
  // The **deal number that reproduces this board**, when there is one. Originally the
  // seed was an *input* to the deal and nothing more: `freecellDeal` used it and
  // dropped it, so a dealt board couldn't say which number produced it. Carrying it
  // here makes the board self-describing, which is what lets the app report a deal
  // number and build a `?seed=` link back to this exact layout (#98).
  //
  // It's deliberately narrower than "the seed some shuffle used": `Some(n)` promises
  // that dealing `n` lays out *this* board again, so it's set only where that round
  // trip actually holds — `freecellDeal` today. A board posed some other way says
  // `None` rather than pointing at a deal it doesn't descend from. Anything offering
  // to share a deal can then just read this field rather than special-casing a game
  // by id.
  seed: option<int>,
}

// The assembled FreeCell board (#97), where four enablers converge: pile
// capacity (#93), roles (#94), the cascade rule (#95) and the seeded deck (#96)
// make a real FreeCell just a `Game.t` value — no game-specific reducer code. The
// standard board is sixteen piles:
//   - **8 cascades** — `Cascade`, `Rules.cascade` (build *down* in alternating
//     colour), unbounded, `Fanned`; the columns the deck is dealt into.
//   - **4 free cells** — `FreeCell`, `Rules.Free`, `capacity: Some(1)`, `Squared`;
//     a single-card holding slot apiece (the #93 cells, verbatim).
//   - **4 foundations** — `Foundation`, `Rules.foundation` (build *up* by suit
//     from the Ace), `Squared`; where a completed suit is assembled.
// The opening deal is the classic FreeCell layout: the whole 52-card deck,
// shuffled from `seed`, dealt round-robin across the eight cascades
// (7/7/7/7/6/6/6/6) — reusing #96's `Cards.deal` — with the free cells and
// foundations opening empty. A card only ever rests in a pile, so a drop that
// lands nowhere bounces back. Everything else is the shared machinery —
// `Reducer.reduce` / `canDrop` handle moves with each pile enforcing its own rule
// and capacity.
let freecellSeed = 1 // deal #1, the fixed board scenarios and screenshots derive from

// Build a FreeCell board for deal `seed`. The cascades hold the dealt deck; the
// free cells and foundations open empty.
let freecellDeal = (~seed: int): t => {
  // The 52 shuffled and dealt round-robin across the eight cascades — the
  // standard opening. Each column becomes an unbounded, alternating-colour
  // *descending* cascade (`Rules.cascade`).
  let cascades =
    Cards.shuffle(~seed)
    ->Cards.deal(~piles=8, _)
    ->Array.map(column => {
      role: Cascade,
      stacking: Fanned,
      rule: Rules.cascade,
      capacity: None,
      cards: column,
    })
  // Four capacity-1 `Free` cells and four same-suit foundations, all opening
  // empty. Built by mapping over an index array so each pile gets its own fresh
  // `cards` array rather than sharing one.
  let cells = [0, 1, 2, 3]->Array.map(_ => {
    role: FreeCell,
    stacking: Squared,
    rule: Rules.Free,
    capacity: Some(1),
    cards: [],
  })
  let foundations = [0, 1, 2, 3]->Array.map(_ => {
    role: Foundation,
    stacking: Squared,
    rule: Rules.foundation,
    capacity: None,
    cards: [],
  })
  {
    id: "freecell",
    name: "FreeCell",
    // Free cells and foundations first (the view groups them across the top by
    // role, #94), the eight dealt cascades below.
    piles: cells->Array.concat(foundations)->Array.concat(cascades),
    // The deal number that laid this board out, kept so the app can report it and
    // link back to it (#98). `freecellDeal(~seed)` is exactly what a `?seed=` open
    // calls, so the round trip holds.
    seed: Some(seed),
  }
}

// The default board: deal #1.
let freecell = freecellDeal(~seed=freecellSeed)

// Every supported game, in picker order — FreeCell alone (#342). Kept as an array
// because it's what the scene picker and the CLI's `games`/`deal <id>` enumerate;
// a second game joins it here.
let all = [freecell]

// --- Addressing piles by role (#94) ------------------------------------------
// Callers target a *group* of piles by role — the deal fills only the cascades,
// auto-to-foundation and win detection look only at the foundations, the layout
// groups free cells + foundations. These two helpers are how they address a
// group: `pileIndices` yields the positions (the index is a pile's identity in
// `GameState`, so callers that transition state want these), and `pilesOf` yields
// the pile records themselves (for callers that only read).

// The indices of every pile with the given role, in board order.
let pileIndices = (game: t, role: role): array<int> => {
  let indices = []
  for i in 0 to Array.length(game.piles) - 1 {
    if (game.piles->Array.getUnsafe(i)).role == role {
      indices->Array.push(i)
    }
  }
  indices
}

// Every pile with the given role, in board order.
let pilesOf = (game: t, role: role): array<pile> => game.piles->Array.filter(p => p.role == role)
