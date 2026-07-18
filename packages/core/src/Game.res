// A *game* modelled as data: a board's rules, independent of any presentation.
// This is the first step of "several supported games" (#62) — the card-stacking
// demo, described declaratively so the view can interpret it dynamically instead
// of hard-coding zones and an opening deal. A new game is a new value here, not
// new view code.
//
// What a game says:
//   - `piles` — the drop zones, each with a stacking behaviour (how a second
//     card lands on the first) *and* the rule it enforces (what it will accept).
//     The model says how many there are, how each stacks, and the law each
//     obeys; where they sit on screen is the view's business.
//   - each pile's `rule` — the stackability law as data (#76): may a card land
//     on this pile given its current top card? A `Rules.rule` value weighed by
//     the pure `Rules.accepts`, shared by the view's hover highlight and its
//     drop decision. Because the rule lives on the *pile*, one board can carry
//     piles of different kinds — a #75 alternating-colour tableau and a
//     same-suit foundation — side by side (see `foundations`).
//   - `free`  — may a card be dropped loose on the table, outside any pile?
//     When `false`, a card released off a pile snaps back to where it came from,
//     so cards only ever rest in piles (#63).
//   - `loose` — the opening deal: specific cards resting free on the table.
//     A pile can also open holding cards (`pile.cards`), so a non-free game can
//     start with everything already stacked.
//   - `caption` — optional prose the view shows beneath the board, describing
//     how this particular game plays. `None` means no caption.
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

// A pile's *role* on the board (#94) — its classification within a game, toward
// FreeCell (M2). The three FreeCell roles: a **cascade** (the columns cards are
// dealt into and built down), a **free cell** (a single-card holding slot), and
// a **foundation** (built up by suit to the King). The role is the
// *classification*, not the mechanic: rules and capacity stay independent (a
// `FreeCell` role typically pairs with `capacity: Some(1)` and `rule: Free`, but
// nothing here enforces that). Later steps *target a group by role* — the deal
// fills only the cascades, auto-to-foundation and win detection look only at the
// foundations, the layout groups free cells + foundations across the top with
// cascades below — via `pilesOf`/`pileIndices` (below).
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
// only the classification — it's what lets later steps address a group of piles
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
  free: bool,
  loose: array<card>,
  caption: option<string>, // prose shown beneath the board; `None` for none
}

// The card-stacking demo, now as data: two empty piles (one squared, one
// fanned) enforcing the alternating-colour, ascending-run rule (#75), free drops
// allowed. It opens holding a full Ace→King run dealt loose — colours already
// alternating up the ranks — so the whole run can be assembled onto a pile.
let stacking = {
  id: "stacking",
  name: "Stacking",
  piles: [
    {role: Cascade, stacking: Squared, rule: Rules.tableau, capacity: None, cards: []},
    {role: Cascade, stacking: Fanned, rule: Rules.tableau, capacity: None, cards: []},
  ],
  free: true,
  loose: [
    {suit: Spades, rank: Ace}, // black
    {suit: Hearts, rank: Two}, // red
    {suit: Clubs, rank: Three}, // black
    {suit: Diamonds, rank: Four}, // red
    {suit: Spades, rank: Five}, // black
    {suit: Hearts, rank: Six}, // red
    {suit: Clubs, rank: Seven}, // black
    {suit: Diamonds, rank: Eight}, // red
    {suit: Spades, rank: Nine}, // black
    {suit: Hearts, rank: Ten}, // red
    {suit: Clubs, rank: Jack}, // black
    {suit: Diamonds, rank: Queen}, // red
    {suit: Spades, rank: King}, // black
  ],
  caption: Some(
    "Build a pile Ace to King: each card must be the next rank up and the opposite colour.",
  ),
}

// A second game with different rules, proving the view interprets the model
// rather than baking in the demo: four fanned piles, drops confined to the piles
// (`free: false`, #63), opening with a couple of cards already dealt into each
// pile and nothing loose on the table.
let fourFans = {
  id: "four-fans",
  name: "Four Fans",
  piles: [
    {
      role: Cascade,
      stacking: Fanned,
      rule: Rules.Free,
      capacity: None,
      cards: [{suit: Clubs, rank: Two}, {suit: Diamonds, rank: Five}],
    },
    {
      role: Cascade,
      stacking: Fanned,
      rule: Rules.Free,
      capacity: None,
      cards: [{suit: Hearts, rank: Nine}, {suit: Spades, rank: Jack}],
    },
    {
      role: Cascade,
      stacking: Fanned,
      rule: Rules.Free,
      capacity: None,
      cards: [{suit: Clubs, rank: Queen}, {suit: Hearts, rank: Three}],
    },
    {
      role: Cascade,
      stacking: Fanned,
      rule: Rules.Free,
      capacity: None,
      cards: [{suit: Spades, rank: Seven}, {suit: Diamonds, rank: Ten}],
    },
  ],
  free: false,
  loose: [],
  caption: Some("Drag the cards between the slots — they can only rest in a pile."),
}

// The rule-as-data demo (#76): two *different* pile kinds on one board, so the
// contrast is visible. A same-suit **foundation** (`Rules.foundation`) builds up
// from the Ace — it opens accepting only an Ace and reaching the King lights a
// "done" marker — next to a #75 **tableau** (`Rules.tableau`) that climbs in
// alternating colours. The loose deal serves both: a full Hearts Ace→King run to
// carry the foundation to completion, and a short black/red run for the tableau.
// A heart dropped on the tableau, or a spade on the foundation, flashes red.
let foundations = {
  id: "foundations",
  name: "Foundations",
  piles: [
    {role: Foundation, stacking: Squared, rule: Rules.foundation, capacity: None, cards: []},
    {role: Cascade, stacking: Fanned, rule: Rules.tableau, capacity: None, cards: []},
  ],
  free: true,
  loose: [
    // The foundation's suit: Hearts Ace→King, dealt low-to-high so it stacks
    // end-to-end up to the King and completes the run.
    {suit: Hearts, rank: Ace},
    {suit: Hearts, rank: Two},
    {suit: Hearts, rank: Three},
    {suit: Hearts, rank: Four},
    {suit: Hearts, rank: Five},
    {suit: Hearts, rank: Six},
    {suit: Hearts, rank: Seven},
    {suit: Hearts, rank: Eight},
    {suit: Hearts, rank: Nine},
    {suit: Hearts, rank: Ten},
    {suit: Hearts, rank: Jack},
    {suit: Hearts, rank: Queen},
    {suit: Hearts, rank: King},
    // A short alternating-colour run for the tableau (black/red/black), none of
    // them hearts so nothing competes with the foundation.
    {suit: Spades, rank: Ace}, // black
    {suit: Diamonds, rank: Two}, // red
    {suit: Clubs, rank: Three}, // black
  ],
  caption: Some(
    "Two rules on one board: build the foundation up in a single suit from the Ace, and the tableau up in alternating colours.",
  ),
}

// The capacity demo (#93), the first FreeCell (M2) enabler: a row of four
// **free cells** — each a `Rules.Free` pile capped at `Some(1)`, so it holds
// exactly one card of any suit — with a few cards dealt loose to park in them.
// Drop a card into an empty cell and it stays; drop a second onto an occupied
// cell and it flashes red and bounces back (the `canDrop`/`PileFull` cap). The
// eventual assembled FreeCell board reuses these cells verbatim.
let freeCells = {
  id: "free-cells",
  name: "Free Cells",
  piles: [
    {role: FreeCell, stacking: Squared, rule: Rules.Free, capacity: Some(1), cards: []},
    {role: FreeCell, stacking: Squared, rule: Rules.Free, capacity: Some(1), cards: []},
    {role: FreeCell, stacking: Squared, rule: Rules.Free, capacity: Some(1), cards: []},
    {role: FreeCell, stacking: Squared, rule: Rules.Free, capacity: Some(1), cards: []},
  ],
  free: true,
  loose: [
    {suit: Spades, rank: Ace},
    {suit: Hearts, rank: King},
    {suit: Clubs, rank: Seven},
    {suit: Diamonds, rank: Ten},
  ],
  caption: Some(
    "Free cells: each holds exactly one card of any suit. Park a card in an empty cell; a second card dropped on an occupied cell flashes red and bounces back.",
  ),
}

// The pile-roles demo (#94), a proto-FreeCell board: the three FreeCell roles
// coexisting on one board so the classification is visible before anything
// consumes it. One `Foundation` (built up by suit from the Ace) and two
// single-card `FreeCell` cells share the top; one `Cascade` sits below. Rules
// and capacity follow each role's usual pairing — the foundation is a same-suit
// ascending pile, the cells are capacity-1 `Free` slots, the cascade an
// alternating tableau — but it's the `role` field that groups them
// (`pilesOf`/`pileIndices`), and the visible group-targeted payoff arrives with
// FreeCell later. A Hearts Ace→King run is dealt loose to carry the foundation,
// plus a couple of stray cards to park in the cells.
let mixedRoles = {
  id: "mixed-roles",
  name: "Mixed Roles",
  piles: [
    {role: Foundation, stacking: Squared, rule: Rules.foundation, capacity: None, cards: []},
    {role: FreeCell, stacking: Squared, rule: Rules.Free, capacity: Some(1), cards: []},
    {role: FreeCell, stacking: Squared, rule: Rules.Free, capacity: Some(1), cards: []},
    {role: Cascade, stacking: Fanned, rule: Rules.tableau, capacity: None, cards: []},
  ],
  free: true,
  loose: [
    // The foundation's suit: Hearts Ace→King, to carry it to completion.
    {suit: Hearts, rank: Ace},
    {suit: Hearts, rank: Two},
    {suit: Hearts, rank: Three},
    {suit: Hearts, rank: Four},
    {suit: Hearts, rank: Five},
    {suit: Hearts, rank: Six},
    {suit: Hearts, rank: Seven},
    {suit: Hearts, rank: Eight},
    {suit: Hearts, rank: Nine},
    {suit: Hearts, rank: Ten},
    {suit: Hearts, rank: Jack},
    {suit: Hearts, rank: Queen},
    {suit: Hearts, rank: King},
    // A couple of stray cards to park in the free cells.
    {suit: Spades, rank: King},
    {suit: Clubs, rank: Seven},
  ],
  caption: Some(
    "Three roles on one board: a foundation and two free cells across the top, a cascade below — a proto-FreeCell layout.",
  ),
}

// The cascade demo (#95), proving `Rules.Down`: two piles enforcing
// `Rules.cascade` — build *down* in alternating colour, the mirror of the
// `stacking` scene (which builds *up*). It opens holding a loose
// descending-alternating run (K♠, Q♥, J♠, …, Ace) — colours already alternating
// *down* the ranks — so the whole run can be assembled onto a cascade one card
// at a time. A same-colour or wrong-rank drop flashes red.
let cascade = {
  id: "cascade",
  name: "Cascade",
  piles: [
    {role: Cascade, stacking: Squared, rule: Rules.cascade, capacity: None, cards: []},
    {role: Cascade, stacking: Fanned, rule: Rules.cascade, capacity: None, cards: []},
  ],
  free: true,
  loose: [
    {suit: Spades, rank: King}, // black
    {suit: Hearts, rank: Queen}, // red
    {suit: Spades, rank: Jack}, // black
    {suit: Hearts, rank: Ten}, // red
    {suit: Spades, rank: Nine}, // black
    {suit: Hearts, rank: Eight}, // red
    {suit: Spades, rank: Seven}, // black
    {suit: Hearts, rank: Six}, // red
    {suit: Spades, rank: Five}, // black
    {suit: Hearts, rank: Four}, // red
    {suit: Spades, rank: Three}, // black
    {suit: Hearts, rank: Two}, // red
    {suit: Spades, rank: Ace}, // black
  ],
  caption: Some(
    "Build a cascade King down to Ace: each card must be the next rank down and the opposite colour — the reverse of Stacking.",
  ),
}

// The seeded-shuffle demo (#96): a full 52-card deck shuffled from a *fixed
// seed* and dealt round-robin across eight piles. It shows the reproducible deal
// the FreeCell board (M2) will be built from — `core` now owns the deck and a
// deterministic `Cards.shuffle`, so the same seed reproduces this exact board
// every load (the basis for shareable "deal numbers"). No stacking rules are
// needed to demonstrate the *deal*, so the piles are permissive `Rules.Free`
// cascades; the FreeCell-specific board and its rules are the later assembly step.
let shuffledDealSeed = 1

let shuffledDeal = {
  id: "shuffled-deal",
  name: "Shuffled Deal",
  // Build the piles straight from the deal: shuffle the deck for the seed, deal
  // it across eight columns, and wrap each column as a `Free` cascade opening
  // holding those cards.
  piles: Cards.shuffle(~seed=shuffledDealSeed)
  ->Cards.deal(~piles=8, _)
  ->Array.map(column => {
    role: Cascade,
    stacking: Fanned,
    rule: Rules.Free,
    capacity: None,
    cards: column,
  }),
  free: true,
  loose: [],
  caption: Some(
    `A full 52-card deck, shuffled from a fixed seed (${Int.toString(
        shuffledDealSeed,
      )}) and dealt across eight piles. The shuffle is deterministic, so the same seed always lays out this exact board — the seed is the future "deal number".`,
  ),
}

// Every supported game, in picker order.
let all = [stacking, foundations, fourFans, freeCells, mixedRoles, cascade, shuffledDeal]

// --- Addressing piles by role (#94) ------------------------------------------
// Later steps target a *group* of piles by role — the deal fills only the
// cascades, auto-to-foundation and win detection look only at the foundations,
// the layout groups free cells + foundations. These two helpers are how they
// address a group: `pileIndices` yields the positions (the index is a pile's
// identity in `GameState`, so callers that transition state want these), and
// `pilesOf` yields the pile records themselves (for callers that only read).

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
