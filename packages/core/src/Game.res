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
  // Spider's stock: the undealt remainder of the pack, face down, that a `Reducer.Deal`
  // drops a row from onto the cascades. The hand never touches it — its rule is
  // `Sealed` — so it is addressed only by the deal, and by the view's tap on it.
  | Stock

// One drop zone. `rule` is the stackability law as data — may a card land here given
// the current top card? — weighed by the pure `Rules.accepts` and shared by the
// view's hover highlight and its drop decision. Because it lives on the *pile*, one
// board carries an alternating-colour cascade and a same-suit foundation side by side.
//
// `capacity` is `None` for the unbounded piles and `Some(n)` for a capped one. The cap
// depends on the pile's *current count*, which `Rules.accepts` deliberately never
// sees, so it is enforced one layer up in `Reducer.canDrop`/`reduce`.
//
// `cards` is bottom-first, so the last is the top of the pile. `faceDown` is how many
// of them, counted from the bottom, the opening deal turns face down — the initial
// value of `GameState.faceDown` for this pile, and 0 on every board that deals
// everything face up.
type pile = {
  role: role,
  stacking: stacking,
  rule: Rules.rule,
  capacity: option<int>,
  cards: array<card>,
  faceDown: int,
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
      faceDown: 0,
    })
  // From an initializer, so each pile gets its own fresh `cards` array rather than
  // every one of them sharing a single array.
  let cellPiles = Array.fromInitializer(~length=cells, _ => {
    role: FreeCell,
    stacking: Squared,
    rule: Rules.Free,
    capacity: Some(1),
    cards: [],
    faceDown: 0,
  })
  let foundationPiles = Array.fromInitializer(~length=foundations, _ => {
    role: Foundation,
    stacking: Squared,
    rule: Rules.foundation,
    capacity: None,
    cards: [],
    faceDown: 0,
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
let miniDeck: Cards.deck = {suits: Cards.suits, ranks: [Ace, Two, Three, Four, Five], copies: 1}

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
  copies: 1,
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
      faceDown: 0,
    })
  let foundationPiles = Array.fromInitializer(~length=4, _ => {
    role: Foundation,
    stacking: Squared,
    rule: Rules.Sealed,
    capacity: None,
    cards: [],
    faceDown: 0,
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

// --- Spiderette ------------------------------------------------------------------
// Spider on fifty-two cards: Simple Simon's laws (`Rules.spiderCascade`, `Unlimited`,
// `CompleteRuns`) over a Klondike layout. Seven cascades dealt 1/2/3/4/5/6/7 with only
// the top card of each face up, and the other 24 cards a face-down **stock** that a
// `Reducer.Deal` drops one card from onto every cascade — three deals of seven, then
// the last three cards onto the first three columns.
//
// **The pack is the variant.** Three boards share this shape and differ in nothing
// but the deck: one suit taken four times, two taken twice, or the standard pack once.
// Each is 52 cards and four runs to collect, one foundation each — the number of
// foundations is the number of runs, `suits × copies`, which every variant keeps at
// four. Nothing else here depends on which pack it got: a run is complete by the
// deck's own ranks (`Rules.isCompleteRun`), and the near-won scenario poses its runs
// from `deck.suits` and `deck.copies` rather than assuming two of each.
//
// Repeated cards are what `Card.copy` is for — the two Sevens of Spades are two cards
// to the reducer and one face to a typed name.
//
// The stock is dealt from its top, and its top is the card the shuffle would have
// dealt next: the remainder is stacked in reverse so that dealing carries on through
// the pack in shuffle order. That order, the counts, and the pack's own order
// (`Cards.cardsOf`) are each variant's deal-number promise — a promise per variant,
// since the same number shuffles a different pack on each.
let spideretteCounts = [1, 2, 3, 4, 5, 6, 7]

// The seams that differ per variant, so the shape below can be written once — and per
// game, since Spider (below) is this same shape at ten columns and two packs: the
// counts are what tell the two apart, and everything after them is read off the deck
// and the counts. `id` stays the storage key and `?game=` value, so the two-suit board
// keeps the bare `spiderette` it has always had: a save or link written for it still
// opens it.
let rec spiderShaped = (
  ~id: string,
  ~name: string,
  ~deck: Cards.deck,
  ~counts: array<int>,
  ~seed: int,
): t => {
  let shuffled = Cards.shuffle(~deck, ~seed)
  let dealt = counts->Array.reduce(0, (a, b) => a + b)
  let cascadePiles = Cards.dealByCounts(~counts, shuffled)->Array.map(column => {
    role: Cascade,
    stacking: Fanned,
    rule: Rules.spiderCascade,
    capacity: None,
    cards: column,
    faceDown: Array.length(column) - 1,
  })
  let stockCards =
    shuffled->Array.slice(~start=dealt, ~end=Array.length(shuffled))->Array.toReversed
  let stockPile = {
    role: Stock,
    stacking: Squared,
    rule: Rules.Sealed,
    capacity: None,
    cards: stockCards,
    faceDown: Array.length(stockCards),
  }
  let foundationPiles = Array.fromInitializer(~length=Array.length(deck.suits) * deck.copies, _ => {
    role: Foundation,
    stacking: Squared,
    rule: Rules.Sealed,
    capacity: None,
    cards: [],
    faceDown: 0,
  })
  {
    id,
    name,
    // The stock leads the top row, the foundations beside it, the cascades below.
    piles: [stockPile]->Array.concat(foundationPiles)->Array.concat(cascadePiles),
    deck,
    seed: Some(seed),
    deal: Some(seed => spiderShaped(~id, ~name, ~deck, ~counts, ~seed)),
    runLimit: Unlimited,
    collect: CompleteRuns,
  }
}

// One suit, four times over: every card builds on every card, so a run only ever
// needs assembling, never untangling.
let spiderette1Deck: Cards.deck = {suits: [Spades], ranks: Cards.ranks, copies: 4}

let spiderette1Deal = (~seed: int): t =>
  spiderShaped(
    ~id="spiderette1",
    ~name="Spiderette · 1 suit",
    ~deck=spiderette1Deck,
    ~counts=spideretteCounts,
    ~seed,
  )

// Spades and hearts, twice over — the variant the game is usually meant by.
let spideretteDeck: Cards.deck = {suits: [Spades, Hearts], ranks: Cards.ranks, copies: 2}

let spideretteDeal = (~seed: int): t =>
  spiderShaped(
    ~id="spiderette",
    ~name="Spiderette · 2 suits",
    ~deck=spideretteDeck,
    ~counts=spideretteCounts,
    ~seed,
  )

// The standard pack: the hard one, where a lawful drop across suits is most often a
// card in the way.
let spiderette4Deal = (~seed: int): t =>
  spiderShaped(
    ~id="spiderette4",
    ~name="Spiderette · 4 suits",
    ~deck=Cards.standard,
    ~counts=spideretteCounts,
    ~seed,
  )

let spiderette1 = spiderette1Deal(~seed=freecellSeed)
let spiderette = spideretteDeal(~seed=freecellSeed)
let spiderette4 = spiderette4Deal(~seed=freecellSeed)

// --- Spider ----------------------------------------------------------------------
// The full game: Spiderette's shape on two packs. Ten cascades dealt 6/6/6/6/5/5/5/5/5/5
// with only the top card of each face up, and the other fifty a stock — five deals of
// ten, one card to every column, and the stock runs out on exactly the fifth.
//
// **The pack is the variant here too**, and is the game's difficulty setting: the same
// 104 cards as one suit taken eight times, two taken four times, or the standard pack
// twice over. Eight runs to collect whichever pack it is, so eight foundations
// (`suits × copies`) — which, with the stock's fifty, is what tells Spider's top row from
// Spiderette's. One suit makes the same-suit run rule vacuous and four suits is the real
// game; two is where most players start. The two-suit board keeps the bare `spider` id
// as the two-suit Spiderette keeps `spiderette`, so the two families' ids read alike.
let spiderCounts = [6, 6, 6, 6, 5, 5, 5, 5, 5, 5]

let spider1Deck: Cards.deck = {suits: [Spades], ranks: Cards.ranks, copies: 8}

let spider1Deal = (~seed: int): t =>
  spiderShaped(
    ~id="spider1",
    ~name="Spider · 1 suit",
    ~deck=spider1Deck,
    ~counts=spiderCounts,
    ~seed,
  )

let spiderDeck: Cards.deck = {suits: [Spades, Hearts], ranks: Cards.ranks, copies: 4}

let spiderDeal = (~seed: int): t =>
  spiderShaped(
    ~id="spider",
    ~name="Spider · 2 suits",
    ~deck=spiderDeck,
    ~counts=spiderCounts,
    ~seed,
  )

// The standard pack twice: every suit, and two of every card.
let spider4Deck: Cards.deck = {...Cards.standard, copies: 2}

let spider4Deal = (~seed: int): t =>
  spiderShaped(
    ~id="spider4",
    ~name="Spider · 4 suits",
    ~deck=spider4Deck,
    ~counts=spiderCounts,
    ~seed,
  )

let spider1 = spider1Deal(~seed=freecellSeed)
let spider = spiderDeal(~seed=freecellSeed)
let spider4 = spider4Deal(~seed=freecellSeed)

// In picker order; a further game joins it here. The scene picker and the CLI's
// `games`/`deal <id>` both enumerate it.
let all = [
  freecell,
  mini,
  micro,
  simpleSimon,
  spiderette1,
  spiderette,
  spiderette4,
  spider1,
  spider,
  spider4,
]

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

// --- Games offered as one --------------------------------------------------------
// **A family is one game to a player and several boards to the app.** The three
// Spiderettes differ in the pack alone (see above) and the three FreeCells in how much
// of a game they are — so a menu listing each board separately asks a player to choose
// the same game three times over. They belong on one row, with the choice a control on
// it.
//
// Which boards are the same game is a fact about the boards, so it is settled here
// rather than in the front end that draws that row — a list of ids hard-coded in a menu
// is a second place to edit the day a fourth variant lands, and a silent one, since a
// list that misses one still renders.
//
// Each variant keeps its own id throughout: `?game=` still reaches every one of them, a
// save is kept per board, and the deal numbers stay a promise per variant (the same
// number shuffles a different deck on each).

// How a control offering a family tells its variants apart.
//
// `Pack` is **read the board's own deck**: the Spiderettes differ in nothing else, so
// the mark is the suits in play and how many times each card is in the deck, and no
// variant is written down twice — a board that changed its pack would say so with no
// edit here.
//
// `Size` is **a word**, because the FreeCells differ in deck, cascades and cells at
// once — 52 cards over eight columns, 20 over four, 16 over four — and no reading of one
// board says which of the three it is. What tells those apart is what a player calls
// them, so that is what is written down.
type mark =
  | Pack
  | Size(string)

// One board of a family, with what tells it apart from its siblings.
type variant = {game: t, mark: mark}

type family = {
  // The family's own id, not a game's: what a front end files a remembered choice under.
  id: string,
  name: string,
  // In offering order — easiest or smallest first — which is the order a control cycling
  // through them takes.
  variants: array<variant>,
  // What a player who has expressed no preference gets.
  default: variant,
}

// The full game, and the two short-deck boards under the same name. "Standard" is the
// word for it *beside the other two*; on its own it is FreeCell, which is why this is
// the family's business and not the board's `name`.
let freecellStandard: variant = {game: freecell, mark: Size("Standard")}

let freecellFamily: family = {
  id: "freecell",
  name: "FreeCell",
  variants: [
    freecellStandard,
    {game: mini, mark: Size("Mini")},
    {game: micro, mark: Size("Micro")},
  ],
  default: freecellStandard,
}

// The pack the game is usually meant by, and so what a player who hasn't chosen gets.
let spideretteTwoSuit: variant = {game: spiderette, mark: Pack}

let spideretteFamily: family = {
  id: "spiderette",
  name: "Spiderette",
  variants: [{game: spiderette1, mark: Pack}, spideretteTwoSuit, {game: spiderette4, mark: Pack}],
  default: spideretteTwoSuit,
}

// Spider's packs, ordered easiest-first like Spiderette's and defaulting to the same
// middle pack: two suits is where most players start, and four is a choice to make.
let spiderTwoSuit: variant = {game: spider, mark: Pack}

let spiderFamily: family = {
  id: "spider",
  name: "Spider",
  variants: [{game: spider1, mark: Pack}, spiderTwoSuit, {game: spider4, mark: Pack}],
  default: spiderTwoSuit,
}

// Every family. A fourth joins here.
let families: array<family> = [freecellFamily, spideretteFamily, spiderFamily]

// The family a board belongs to, or `None` for a board that is a game on its own —
// which is also the question a caller asks before offering the choice at all.
let familyOf = (game: t): option<family> =>
  families->Array.find(family => family.variants->Array.some(v => v.game.id == game.id))

// …and the board as its family holds it, mark and all. Which variants a menu actually
// offers is the menu's own business — a build or a feature flag can be showing some of
// them and not others — so *cycling* through them belongs to whoever draws the control,
// and what lives here is only which boards are siblings and how each is told apart.
let variantOf = (game: t): option<variant> =>
  familyOf(game)->Option.flatMap(family => family.variants->Array.find(v => v.game.id == game.id))

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
