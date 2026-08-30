// A *game* modelled as data: a board's rules, independent of any presentation.
// This is the "several supported games" seam — a board described
// declaratively so the view can interpret it dynamically instead of hard-coding
// zones and an opening deal. A new game is a new value here, not new view code:
// `mini` and `micro` are two more boards and nothing else — no view code, no
// reducer branch, no new rule — which is what the seam is for.
//
// What a game says:
//   - `piles` — the drop zones, each with a stacking behaviour (how a second
//     card lands on the first) *and* the rule it enforces (what it will accept).
//     The model says how many there are, how each stacks, and the law each
//     obeys; where they sit on screen is the view's business.
//   - each pile's `rule` — the stackability law as data: may a card land
//     on this pile given its current top card? A `Rules.rule` value weighed by
//     the pure `Rules.accepts`, shared by the view's hover highlight and its
//     drop decision. Because the rule lives on the *pile*, one board carries
//     piles of different kinds — an alternating-colour cascade and a same-suit
//     foundation — side by side.
//   - `seed` — the deal number that reproduces this board, when it has one, so a
//     dealt board can say where it came from.
//   - `deal` — how to lay out *another* board of the same game, from a deal number.
//     The inverse of `seed`, and the reason nothing outside this module has to name
//     `freecellDeal` to mean "a fresh board of whatever is being played".
//
// The view (`TableScene`) reads all of this and lays the board out on its own
// terms — "piles hang from the top of the stage and grow downward".

open Card

// How a newcomer lands on a pile that already holds a card: `Squared`
// covers the last card so the pile keeps a single card's footprint; `Fanned`
// steps off it so every card keeps a visible edge.
type stacking =
  | Squared
  | Fanned

// A pile's *role* on the board — its classification within a game. The
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

// One drop zone: its `role` (its classification on the board), its
// stacking behaviour (layout — how a second card lands visually), the `rule` it
// enforces (what it will accept), an optional `capacity` (how many cards
// it may hold), and the cards it opens holding (bottom-first, so the last
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

// `type rec` because a board carries its own `deal` (below), which hands back another
// board: the one place this type refers to itself.
type rec t = {
  id: string, // stable scene id (also the picker / localStorage key)
  name: string, // human label shown in the scene picker
  piles: array<pile>,
  // **The cards this board is played with** — a `Cards.deck`, i.e. a subset
  // of one pack. Board-level rather than ambient because two rules downstream need
  // it and used to assume the 52 instead: `Rules.isCompleteRun` (how long a finished
  // foundation is, and what tops it) and `Reducer.isSafeToCollect` (which suits are
  // the *opposite colour* ones a card must wait for). Both now read it here, so a
  // board that isn't the full pack decides correctly rather than silently stalling.
  //
  // `Cards.standard` for FreeCell, so nothing about today's game changes.
  deck: Cards.deck,
  // The **deal number that reproduces this board**, when there is one. Originally the
  // seed was an *input* to the deal and nothing more: `freecellDeal` used it and
  // dropped it, so a dealt board couldn't say which number produced it. Carrying it
  // here makes the board self-describing, which is what lets the app report a deal
  // number and build a `?seed=` link back to this exact layout.
  //
  // It's deliberately narrower than "the seed some shuffle used": `Some(n)` promises
  // that dealing `n` lays out *this* board again, so it's set only where that round
  // trip actually holds — `freecellDeal` today. A board posed some other way says
  // `None` rather than pointing at a deal it doesn't descend from. Anything offering
  // to share a deal can then just read this field rather than special-casing a game
  // by id.
  seed: option<int>,
  // **How to lay out another board of this game**, from a deal number — the
  // inverse of `seed`, and the half that was missing. `seed` says which number produced
  // *this* board; `deal` says how to produce the next one, so "deal me another" is a
  // question a board can answer about itself.
  //
  // `None` for a fixed board with no deal to vary — the same boards that answer `None`
  // to `TableScene`'s `~newDeal`. So `deal->Option.isSome` reads as the *capability*
  // ("is this board re-dealable?") that callers used to spell as an identity check
  // against `freecell.id`, which is why a second seeded game now costs no edit in
  // `Main` or `Session`.
  //
  // A function on the record, deliberately: nothing compares a `Game.t` with
  // whole-record `==`, so it costs no structural equality, and it keeps the answer with
  // the value that knows it rather than in a table of ids somewhere else.
  deal: option<int => t>,
}

// --- The FreeCell family ------------------------------------------------------
// The assembled FreeCell board, where four enablers converge: pile
// capacity, roles, the cascade rule and the seeded deck
// make a real FreeCell just a `Game.t` value — no game-specific reducer code. The
// standard board is sixteen piles:
//   - **8 cascades** — `Cascade`, `Rules.cascade` (build *down* in alternating
//     colour), unbounded, `Fanned`; the columns the deck is dealt into.
//   - **4 free cells** — `FreeCell`, `Rules.Free`, `capacity: Some(1)`, `Squared`;
//     a single-card holding slot apiece.
//   - **4 foundations** — `Foundation`, `Rules.foundation` (build *up* by suit
//     from the Ace), `Squared`; where a completed suit is assembled.
// The opening deal is the classic FreeCell layout: the whole 52-card deck,
// shuffled from `seed`, dealt round-robin across the eight cascades
// (7/7/7/7/6/6/6/6) — through the shared `Cards.deal` — with the free cells and
// foundations opening empty. A card only ever rests in a pile, so a drop that
// lands nowhere bounces back. Everything else is the shared machinery —
// `Reducer.reduce` / `canDrop` handle moves with each pile enforcing its own rule
// and capacity.
//
// That description covers *three* boards, not one. `mini` and `micro`
// are FreeCell in every mechanic and differ only in the **deck** they play with and
// **how many** piles of each role they have — so the shape is written once, in
// `freecellShaped` below, and each board is that shape with its own numbers. Nothing
// downstream branches on which: `Slot`'s labels count within a role, `Reducer`'s
// supermove limit reads the role groups, and `Rules.isCompleteRun` /
// `Reducer.isSafeToCollect` read `deck`, so a short deck decides correctly
// rather than stalling.
let freecellSeed = 1 // deal #1, the fixed board scenarios and screenshots derive from

// Build one board of the family: `cascades` columns holding `deck` dealt from `seed`,
// plus `cells` empty free cells and `foundations` empty foundations.
//
// `let rec` because the board it hands back carries this very function as its
// `deal`: a board knows how to lay out another board *of its own game* — same id, same
// deck, same counts, a new seed — which is what lets a caller re-deal the game in hand
// without naming the game.
let rec freecellShaped = (
  ~id: string,
  ~name: string,
  ~deck: Cards.deck,
  ~cascades: int,
  ~cells: int,
  ~foundations: int,
  ~seed: int,
): t => {
  // The deck shuffled and dealt round-robin across the cascades — the standard
  // opening, spread as evenly as the counts allow. Each column becomes an unbounded,
  // alternating-colour *descending* cascade (`Rules.cascade`).
  let cascadePiles =
    Cards.shuffle(~deck, ~seed)
    ->Cards.deal(~piles=cascades, _)
    ->Array.map(column => {
      role: Cascade,
      stacking: Fanned,
      rule: Rules.cascade,
      capacity: None,
      cards: column,
    })
  // The capacity-1 `Free` cells and the same-suit foundations, all opening empty.
  // Built from an initializer so each pile gets its own fresh `cards` array rather
  // than sharing one.
  let cellPiles = Array.fromInitializer(~length=cells, _ => {
    role: FreeCell,
    stacking: Squared,
    rule: Rules.Free,
    capacity: Some(1),
    cards: [],
  })
  let foundationPiles = Array.fromInitializer(~length=foundations, _ => {
    role: Foundation,
    stacking: Squared,
    rule: Rules.foundation,
    capacity: None,
    cards: [],
  })
  {
    id,
    name,
    // Free cells and foundations first (the view groups them across the top by
    // role), the dealt cascades below.
    piles: cellPiles->Array.concat(foundationPiles)->Array.concat(cascadePiles),
    // The pack the cascades were dealt from, kept so `isCompleteRun` and
    // `isSafeToCollect` read the deck instead of assuming it.
    deck,
    // The deal number that laid this board out, kept so the app can report it and
    // link back to it. Re-dealing this game with this number is exactly what a
    // `?seed=` open calls, so the round trip holds.
    seed: Some(seed),
    // …and the way back out: another deal of this same game. Every board here is
    // a seeded shuffle, so every number lays out a real board — the board is
    // re-dealable, and says so here rather than being recognised by id somewhere else.
    deal: Some(seed => freecellShaped(~id, ~name, ~deck, ~cascades, ~cells, ~foundations, ~seed)),
  }
}

// Build a FreeCell board for deal `seed`: the whole pack across eight cascades, four
// cells, four foundations.
let freecellDeal = (~seed: int): t =>
  freecellShaped(
    ~id="freecell",
    ~name="FreeCell",
    // FreeCell plays with the whole pack; the board carries it so the rules can read
    // it back rather than assume it.
    ~deck=Cards.standard,
    ~cascades=8,
    ~cells=4,
    ~foundations=4,
    ~seed,
  )

// The default board: deal #1.
let freecell = freecellDeal(~seed=freecellSeed)

// --- The short-deck siblings ------------------------------------------
// Two small boards that make a second and third `Game.t` real without inventing a
// stock, a tap action or a new rule: every rule is already expressible in
// `Rules.rule` and every pile is one of the three existing roles. What they change is
// the deck — which is precisely why the deck is a parameter — and the counts.
//
// **Two free cells** on both, measured rather than picked.
// Over deals 1–200, by exhaustive single-card search (exact for reachability): one
// cell solves 141/200 `mini` and 102/200 `micro`; two solves 198 and 196; three all 200.
// One cell is punishing and three is never a puzzle. For `mini` the count is a real
// trade — a single cell would narrow its widest row to 5 and grow its cards 20%, at
// 70% solvable, which isn't worth it — while `micro` pays nothing, since 2 cells + 2
// foundations is still 4 across.

// **Mini FreeCell** — Ace through Five in all four suits (20 cards) across four
// five-card cascades, with two cells and four foundations. A foundation is complete
// at the Five, which `Rules.isCompleteRun` reads off the deck rather than assuming a
// King. Widest row: six (2 cells + 4 foundations).
let miniDeck: Cards.deck = {suits: Cards.suits, ranks: [Ace, Two, Three, Four, Five]}

let miniDeal = (~seed: int): t =>
  freecellShaped(
    ~id="mini",
    ~name="Mini FreeCell",
    ~deck=miniDeck,
    ~cascades=4,
    ~cells=2,
    ~foundations=4,
    ~seed,
  )

// **Micro FreeCell** — Ace through Eight in the two suits ♠♥ (16 cards) across four
// four-card cascades, with two cells and two foundations, one per suit. The
// two-suit deck is the case a hard-coded four-suit rule would stall auto-collect on
// above a Two: `Reducer.isSafeToCollect` asks the deck which suits are the
// opposite-colour ones to wait for, and here that's a single suit rather than the two a full pack
// has. Widest row: four (2 cells + 2 foundations), the same as its cascades.
let microDeck: Cards.deck = {
  suits: [Spades, Hearts],
  ranks: [Ace, Two, Three, Four, Five, Six, Seven, Eight],
}

let microDeal = (~seed: int): t =>
  freecellShaped(
    ~id="micro",
    ~name="Micro FreeCell",
    ~deck=microDeck,
    ~cascades=4,
    ~cells=2,
    ~foundations=2,
    ~seed,
  )

// Deal #1 of each, the canonical opening the way `freecell` takes `freecellSeed`.
let mini = miniDeal(~seed=freecellSeed)
let micro = microDeal(~seed=freecellSeed)

// Every supported game, in picker order — FreeCell first (it's `default`, and the one
// the menu surfaces at top level), then the two short-deck siblings. Kept as an
// array because it's what the scene picker and the CLI's `games`/`deal <id>` enumerate;
// a further game joins it here.
let all = [freecell, mini, micro]

// The game a `deal` that names none lays out — a bare `deal`/`new`, and a bare deal
// *number* (`deal 12345`), both of which say which board without saying which game.
// Named here so the front ends can ask for "the default game" rather than each deciding
// for itself that a number means FreeCell; the day a second seeded game arrives,
// this is the line that says which one a plain number belongs to.
let default = freecell

// The game with a given id, or `None` for a name that isn't one of `all`'s. Every front
// end asks this same question of the same list — the CLI resolving `deal mini`, the web
// app resolving `?game=mini` — and each used to spell the `Array.find` for itself.
// Answered here so the lookup lives beside the list it looks in, and so a caller holds
// a `Game.t` rather than a string it hopes is one.
let byId = (id: string): option<t> => all->Array.find(game => game.id == id)

// Another board of `game`, laid out from deal number `seed` — its `deal` capability
// applied. A game with no deal to vary has only the one board, so it answers with
// itself: a caller asking for "the next board of this game" always gets a board.
let dealt = (game: t, ~seed: int): t =>
  switch game.deal {
  | Some(deal) => deal(seed)
  | None => game
  }

// --- Addressing piles by role ------------------------------------------
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
