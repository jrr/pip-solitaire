// A *game* modelled as data: a board's rules, independent of any presentation. The
// seam that makes "several supported games" possible — a board described
// declaratively so the view interprets it rather than hard-coding zones and a deal.
// A new game is a new value here and nothing else: no view code, no reducer branch,
// no new rule. `mini` and `micro` below are the proof, and `simpleSimon` is the
// harder one: a different family of game, still nothing but data.
//
// The view (`TableScene`) reads all of this and lays the board out on its own terms —
// "piles hang from the top of the stage and grow downward".

open Card

// How a newcomer lands on a pile that already holds a card: `Squared` covers the last
// card so the pile keeps one card's footprint; `Fanned` steps off it so every card
// keeps a visible edge.
type stacking =
  | Squared
  | Fanned

// A pile's classification on the board, and *only* its classification — it is what
// lets a caller address a group of piles (`pileIndices`/`pilesOf` at the foot of this
// file), never what governs a drop. Rule and capacity stay independent of it.
type role =
  | Cascade
  | FreeCell
  | Foundation

// One drop zone. `rule` is the stackability law as data — may a card land here given
// the current top card? — weighed by the pure `Rules.accepts` and shared by the
// view's hover highlight and its drop decision. Because it lives on the *pile*, one
// board carries an alternating-colour cascade and a same-suit foundation side by side.
//
// `capacity` is `None` for the unbounded piles and `Some(n)` for a capped one. The cap
// depends on the pile's *current count*, which `Rules.accepts` deliberately never
// sees, so it is enforced one layer up in `Reducer.canDrop`/`reduce`.
//
// `cards` is bottom-first, so the last is the top of the pile.
type pile = {
  role: role,
  stacking: stacking,
  rule: Rules.rule,
  capacity: option<int>,
  cards: array<card>,
}

// How long a run may move as one gesture — the second question a run raises after
// "is it a run?" (`Rules.isRun`), and the one that depends on the *board* rather than
// the pile. `Supermove` is FreeCell's: as many cards as a hand could relay one at a
// time through the empty cells and columns (`Reducer.maxSupermove`). `Unlimited` is
// Spider's: a run moves whole, however long, and nothing is relayed.
type runLimit =
  | Supermove
  | Unlimited

// How cards leave the tableau for a foundation on their own. `SafeCards` is
// FreeCell's: after a move, each card a foundation accepts and no cascade can still
// want goes home, one at a time (`Reducer.isSafeToCollect`). `CompleteRuns` is
// Spider's: a cascade's top run spanning every rank of the deck is lifted whole onto
// an empty foundation. The two are different kinds of thing — the first a
// convenience the player may switch off (`Options.autoCollect`), the second a rule
// of the game, since a Spider run is never played to a foundation by hand and a
// board that didn't lift it could never be won.
type collect =
  | SafeCards
  | CompleteRuns

// `type rec` because a board carries its own `deal` (below), which hands back another
// board: the one place this type refers to itself.
type rec t = {
  id: string, // stable scene id (also the picker / localStorage key)
  name: string, // human label shown in the scene picker
  piles: array<pile>,
  // **The cards this board is played with**, board-level rather than ambient because
  // two rules downstream would otherwise assume the 52: `Rules.isCompleteRun` (how
  // long a finished foundation is, and what tops it) and `Reducer.isSafeToCollect`
  // (which suits are the opposite-colour ones a card must wait for). A short-deck
  // board decides correctly rather than silently stalling.
  deck: Cards.deck,
  // **The deal number that reproduces this board**, so the app can report it and build
  // a `?seed=` link back to this exact layout. Deliberately narrower than "the seed
  // some shuffle used": `Some(n)` *promises* that dealing `n` lays this board out
  // again, so a board posed some other way says `None` rather than pointing at a deal
  // it doesn't descend from.
  seed: option<int>,
  // **How to lay out another board of this game** — the inverse of `seed`, so "deal me
  // another" is a question a board answers about itself.
  //
  // `deal->Option.isSome` is therefore the *capability* test, "is this board
  // re-dealable?". Ask it that way rather than comparing against `freecell.id`, which
  // asks it of one game instead and would cost an edit in both `Main` and `Session`
  // the day a second seeded game lands.
  deal: option<int => t>,
  runLimit: runLimit,
  collect: collect,
}

// --- The FreeCell family ------------------------------------------------------
// One shape, three boards. Real FreeCell is sixteen piles — eight unbounded `Fanned`
// cascades built down in alternating colour, four capacity-1 free cells, four
// foundations built up by suit — and `mini`/`micro` are that same shape with a
// different **deck** and different **counts**. So the shape is written once here and
// nothing downstream branches on which board it got.
let freecellSeed = 1 // deal #1, the fixed board scenarios and screenshots derive from

// `let rec` because the board this hands back carries this very function as its
// `deal`: same id, same deck, same counts, a new seed. That is what lets a caller
// re-deal the game in hand without naming the game.
let rec freecellShaped = (
  ~id: string,
  ~name: string,
  ~deck: Cards.deck,
  ~cascades: int,
  ~cells: int,
  ~foundations: int,
  ~seed: int,
): t => {
  // The classic opening: the deck shuffled from `seed` and dealt round-robin across
  // the cascades, spread as evenly as the counts allow (7/7/7/7/6/6/6/6 for FreeCell).
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
  // From an initializer, so each pile gets its own fresh `cards` array rather than
  // every one of them sharing a single array.
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
    // Free cells and foundations first — the view groups them across the top by role —
    // and the dealt cascades below.
    piles: cellPiles->Array.concat(foundationPiles)->Array.concat(cascadePiles),
    deck,
    // Every board here is a seeded shuffle, so the `seed`/`deal` round trip holds: a
    // `?seed=` open re-deals this game with this number and gets this board back.
    seed: Some(seed),
    deal: Some(seed => freecellShaped(~id, ~name, ~deck, ~cascades, ~cells, ~foundations, ~seed)),
    runLimit: Supermove,
    collect: SafeCards,
  }
}

// The tail of the deal-number contract: `~cascades=8` here, and the pile order
// `freecellShaped` fixes above, decide where a shuffled card lands on screen. The
// frozen banner in `Cards.res` says what changing either costs.
let freecellDeal = (~seed: int): t =>
  freecellShaped(
    ~id="freecell",
    ~name="FreeCell",
    ~deck=Cards.standard,
    ~cascades=8,
    ~cells=4,
    ~foundations=4,
    ~seed,
  )

// The default board: deal #1.
let freecell = freecellDeal(~seed=freecellSeed)

// --- The short-deck siblings ------------------------------------------
// **Two free cells** on both, measured rather than picked. Over deals 1–200, by
// exhaustive single-card search: one cell solves 141/200 `mini` and 102/200 `micro`;
// two solves 198 and 196; three all 200. One cell is punishing and three is never a
// puzzle. For `mini` it's a real trade — a single cell would narrow its widest row to
// 5 and grow its cards 20%, at 70% solvable — while `micro` pays nothing, since 2
// cells + 2 foundations is still 4 across.

// Ace through Five in all four suits: 20 cards, and a foundation complete at the
// Five, which `Rules.isCompleteRun` reads off the deck rather than assuming a King.
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

// Ace through Eight in ♠♥ only: 16 cards, and the case a hard-coded four-suit rule
// would stall auto-collect on above a Two. `Reducer.isSafeToCollect` asks the deck
// which suits are the opposite-colour ones to wait for; here that is one, not two.
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

let mini = miniDeal(~seed=freecellSeed)
let micro = microDeal(~seed=freecellSeed)

// --- Simple Simon ----------------------------------------------------------------
// The Spider family's one-pack, everything-face-up member, and the first board here
// whose piles don't all answer FreeCell's questions: ten cascades under Spider's law
// (`Rules.spiderCascade`), no cells, and four foundations the hand never touches. A
// run moves whole (`Unlimited`), and a cascade that builds a same-suit King-to-Ace
// run has it lifted off onto a foundation (`CompleteRuns`); four of those win.
//
// The pack is dealt by counts, 8/8/8/7/6/5/4/3/2/1 left to right — the shape the
// game is defined by, and (with `Cards.shuffle`) the whole of its deal-number promise.
let simpleSimonCounts = [8, 8, 8, 7, 6, 5, 4, 3, 2, 1]

let rec simpleSimonDeal = (~seed: int): t => {
  let cascadePiles =
    Cards.shuffle(~deck=Cards.standard, ~seed)
    ->Cards.dealByCounts(~counts=simpleSimonCounts, _)
    ->Array.map(column => {
      role: Cascade,
      stacking: Fanned,
      rule: Rules.spiderCascade,
      capacity: None,
      cards: column,
    })
  let foundationPiles = Array.fromInitializer(~length=4, _ => {
    role: Foundation,
    stacking: Squared,
    rule: Rules.Sealed,
    capacity: None,
    cards: [],
  })
  {
    id: "simplesimon",
    name: "Simple Simon",
    piles: foundationPiles->Array.concat(cascadePiles),
    deck: Cards.standard,
    seed: Some(seed),
    deal: Some(seed => simpleSimonDeal(~seed)),
    runLimit: Unlimited,
    collect: CompleteRuns,
  }
}

let simpleSimon = simpleSimonDeal(~seed=freecellSeed)

// In picker order; a further game joins it here. The scene picker and the CLI's
// `games`/`deal <id>` both enumerate it.
let all = [freecell, mini, micro, simpleSimon]

// The game a bare `deal`/`new`, or a bare deal *number*, lays out. Named here so each
// front end asks for "the default game" rather than deciding for itself that a number
// means FreeCell — this is the one line to change the day that stops being true.
let default = freecell

// The lookup lives beside the list it looks in, so a caller holds a `Game.t` rather
// than a string it hopes is one.
let byId = (id: string): option<t> => all->Array.find(game => game.id == id)

// A game with no deal to vary has only the one board, so it answers with itself: a
// caller asking for "the next board of this game" always gets a board.
let dealt = (game: t, ~seed: int): t =>
  switch game.deal {
  | Some(deal) => deal(seed)
  | None => game
  }

// --- Addressing piles by role ------------------------------------------
// How a caller targets a *group*: the deal fills only the cascades, auto-collect and
// win detection look only at the foundations, the layout groups free cells +
// foundations across the top. Take `pileIndices` to transition state — an index is a
// pile's identity in `GameState` — and `pilesOf` only to read.

let pileIndices = (game: t, role: role): array<int> => {
  let indices = []
  for i in 0 to Array.length(game.piles) - 1 {
    if (game.piles->Array.getUnsafe(i)).role == role {
      indices->Array.push(i)
    }
  }
  indices
}

let pilesOf = (game: t, role: role): array<pile> => game.piles->Array.filter(p => p.role == role)
