// The missing middle of the reduxey loop (#82): an `action` variant and a pure
// `reduce` that transitions the immutable `GameState.t` (#77) and enforces the
// stacking rules (#76). This is the ROADMAP's load-bearing principle made real —
// "immutable state + action variant + pure reducer, illegal actions rejected."
//
// Deliberately still *no view changes*: nothing dispatches yet. This is the
// transition function plus its tests, so the later drivers (the view cutover and
// the CLI) have something to dispatch into. The view keeps its own mutable refs
// for now.
//
// The shapes:
//   - `Game.t` is the *board definition* — each pile's `rule` and the game's
//     `free` flag. Static across a game.
//   - `GameState.t` is the *dynamic* snapshot — where each card rests. It
//     deliberately carries no rules, so the reducer must be handed the `game`
//     too: it closes over both, `reduce(~game, state, action)`.
//   - `result<GameState.t, moveError>` makes rejection explicit, so a driver can
//     tell a *rejected* move (bounce back / red flash) from a legal no-op —
//     unlike a `state => state` reducer that would swallow both.

open Card

// Where a `Move` sends a card: onto a specific pile, or loose onto the table
// (only legal when the game is `free`). `ToPile`/`ToTable` leave room for `Deal`
// and `Undo` to join `action` later.
type target =
  | ToPile(int)
  | ToTable

// The moves the current games allow. A `Move` is one card; a `MoveRun` is the
// FreeCell **supermove** (#123) — an ordered run of `cards` (bottom-first, the way
// a pile holds them) lifted and dropped as one gesture, as if each had been
// shuffled through the free cells and empty columns. `Deal`/`Undo` will grow this
// variant when their steps land.
type action =
  | Move({card: card, to: target})
  | MoveRun({cards: array<card>, to: target})

// Why a move was rejected. Distinguishing these lets a driver react precisely —
// a rule refusal flashes red, a not-`free` loose drop snaps the card home — and
// keeps `Ok`/`Error` meaning "did the state change lawfully?", never "was it a
// no-op?" (an identity re-drop is a lawful `Ok`).
type moveError =
  | Rejected // the destination pile's rule refused the card
  | PileFull // the destination pile is at its capacity (#93 — e.g. a full free cell)
  | LooseNotAllowed // a loose drop when the game isn't `free`
  | NoSuchPile // the target pile index is out of range
  | CardNotFound // the card isn't anywhere in this state
  | NotARun // a `MoveRun`'s cards aren't a legal ordered run (#123)
  | RunTooLong // a `MoveRun`'s run exceeds the supermove limit (#123)

// Is pile `onto` already full — holding as many cards as its `capacity` allows
// (#93)? A pile with `capacity: None` is unbounded and never full; a `Some(cap)`
// pile is full once its current count reaches `cap`. This is the count-aware
// check `Rules.accepts` deliberately can't make — it sees only the top card, not
// how many sit below — so it lives here, alongside the state that holds the count.
let isFull = (~game: Game.t, state: GameState.t, ~onto: int): bool =>
  switch game.piles->Array.get(onto) {
  | Some({capacity: Some(cap)}) => Array.length(GameState.cardsInPile(state, onto)) >= cap
  | _ => false
  }

// The shared legality query (#82): may `card` be dropped onto pile `onto` given
// the current state? Folds the view's current ad-hoc check into one entry point,
// so the reducer and (later) the view's hover highlight both call *this* — "valid
// outline" and "accepted drop" can never disagree, the property #75 relies on,
// now centralised. A drop is legal only if the pile isn't already full (#93) and
// the pure `Rules.accepts` clears the card against the pile's `rule` and its
// current top card; an out-of-range pile accepts nothing.
let canDrop = (~game: Game.t, state: GameState.t, card: card, ~onto: int): bool =>
  switch game.piles->Array.get(onto) {
  | Some(pile) =>
    !isFull(~game, state, ~onto) && Rules.accepts(pile.rule, card, GameState.topOf(state, onto))
  | None => false
  }

// The standard FreeCell **supermove limit** (#123): the most cards you can move
// as one ordered run is `(1 + emptyFreeCells) × 2 ^ emptyCascades` — exactly the
// number you could relay one at a time through the empty free cells and empty
// columns and back. The empties are read straight from the FreeCell/Cascade role
// groups (#94), so any board that declares those roles gets the right limit.
//
// `~ignoring`, when given, drops one pile from the empty tally: a move's own
// destination doesn't lend its emptiness to the exponent — an empty *destination*
// column can't also serve as a spare column for the relay (you're filling it).
// The reducer passes the destination here so a run onto an empty cascade is capped
// by the *other* empties, not counting the column it's about to occupy.
let maxSupermove = (~game: Game.t, state: GameState.t, ~ignoring: option<int>=?): int => {
  let counted = i => Array.length(GameState.cardsInPile(state, i)) == 0 && ignoring != Some(i)
  let emptyFreeCells = Game.pileIndices(game, Game.FreeCell)->Array.filter(counted)->Array.length
  let emptyCascades = Game.pileIndices(game, Game.Cascade)->Array.filter(counted)->Array.length
  // 2 ^ emptyCascades, exact for the small counts a board ever has.
  let doublings = Float.toInt(Math.pow(2., ~exp=Int.toFloat(emptyCascades)))
  (1 + emptyFreeCells) * doublings
}

// May the ordered run `cards` (bottom-first) legally supermove onto pile `onto`
// given the current state (#123)? The shared legality query the reducer's
// `MoveRun` and the view's span hover both consult — so the "valid" outline and
// the accepted drop can never disagree, the same property `canDrop` gives
// single-card moves. A run moves only when it's a genuine run under the pile's
// rule, its bottom card `accepts` onto the pile's current top, and it's within the
// supermove limit (the destination excluded from the empty tally).
let canMoveRun = (~game: Game.t, state: GameState.t, cards: array<card>, ~onto: int): bool =>
  switch game.piles->Array.get(onto) {
  | None => false
  | Some(pile) =>
    Array.length(cards) > 0 &&
    Rules.isRun(pile.rule, cards) &&
    Rules.accepts(pile.rule, cards->Array.getUnsafe(0), GameState.topOf(state, onto)) &&
    Array.length(cards) <= maxSupermove(~game, state, ~ignoring=onto)
  }

// A fresh snapshot with `card` lifted from wherever it rests — every pile and
// the loose table. `filter`/`map` allocate new arrays, so the input is never
// mutated: the result is a value of its own.
let liftCard = (state: GameState.t, card: card): GameState.t => {
  piles: state.piles->Array.map(cards => cards->Array.filter(c => !GameState.sameCard(c, card))),
  loose: state.loose->Array.filter(c => !GameState.sameCard(c, card)),
}

// `state` with `card` moved to the top of pile `i` (removed from its old home
// first, so a card never appears twice). The array surgery is all copy-on-write.
let placeOnPile = (state: GameState.t, card: card, i: int): GameState.t => {
  let lifted = liftCard(state, card)
  {
    ...lifted,
    piles: lifted.piles->Array.mapWithIndex((cards, idx) =>
      idx == i ? Array.concat(cards, [card]) : cards
    ),
  }
}

// `state` with the ordered run `cards` (bottom-first) moved onto pile `i` — each
// card lifted from wherever it rests and appended in order, so the run keeps its
// bottom-first order at the top of the pile. Built on `placeOnPile`, so the array
// surgery stays copy-on-write.
let placeRun = (state: GameState.t, cards: array<card>, i: int): GameState.t =>
  cards->Array.reduce(state, (s, card) => placeOnPile(s, card, i))

// The pure transition. Closes over the board (`~game`) for each pile's `rule`
// and the `free` flag, since `GameState.t` carries no rules. Returns a fresh
// `Ok(state)` on a lawful move — including the identity re-drop of a card onto
// where it already rests — or `Error(moveError)` on an illegal one. The input
// `state` is never mutated.
let reduce = (~game: Game.t, state: GameState.t, action: action): result<GameState.t, moveError> =>
  switch action {
  | Move({card, to: ToPile(i)}) =>
    switch GameState.locationOf(state, card) {
    | None => Error(CardNotFound)
    | Some(_) =>
      switch GameState.topOf(state, i) {
      // Re-dropping a card onto the pile it already tops is an identity `Ok`
      // (mirrors the view's current "re-drop onto its home pile" no-op). Checked
      // before the rule, since a pile never `accepts` its own top card.
      | Some(top) if GameState.sameCard(top, card) => Ok(state)
      | _ =>
        switch game.piles->Array.get(i) {
        | None => Error(NoSuchPile)
        | Some(pile) =>
          // A full pile rejects before the rule is even consulted, and reports
          // `PileFull` so a driver can tell "no room" from a rule refusal (#93).
          // The identity re-drop above already returned `Ok`, so a card already
          // topping a capacity-1 cell isn't counted as a new arrival here.
          if isFull(~game, state, ~onto=i) {
            Error(PileFull)
          } else if Rules.accepts(pile.rule, card, GameState.topOf(state, i)) {
            Ok(placeOnPile(state, card, i))
          } else {
            Error(Rejected)
          }
        }
      }
    }
  | Move({card, to: ToTable}) =>
    if !game.free {
      // A game that confines cards to piles rejects every loose drop (#63).
      Error(LooseNotAllowed)
    } else {
      switch GameState.locationOf(state, card) {
      | None => Error(CardNotFound)
      | Some(Loose) => Ok(state) // already loose: identity re-drop
      | Some(InPile(_, _)) =>
        let lifted = liftCard(state, card)
        Ok({...lifted, loose: Array.concat(lifted.loose, [card])})
      }
    }
  // The supermove (#123): an ordered run moved as one gesture. Accepted only when
  // every card is in play, the `cards` are a legal run in order, the destination
  // `accepts` the run's bottom card, and the run fits the supermove limit — each
  // failure carrying its own `moveError` so a driver can say precisely why. A run
  // only ever moves *between piles*; there's no loose supermove.
  | MoveRun({to: ToTable}) => Error(LooseNotAllowed)
  | MoveRun({cards, to: ToPile(i)}) =>
    switch game.piles->Array.get(i) {
    | None => Error(NoSuchPile)
    | Some(pile) =>
      if cards->Array.some(c => GameState.locationOf(state, c)->Option.isNone) {
        Error(CardNotFound)
      } else if Array.length(cards) == 0 || !Rules.isRun(pile.rule, cards) {
        Error(NotARun)
      } else if !Rules.accepts(pile.rule, cards->Array.getUnsafe(0), GameState.topOf(state, i)) {
        Error(Rejected)
      } else if Array.length(cards) > maxSupermove(~game, state, ~ignoring=i) {
        Error(RunTooLong)
      } else {
        Ok(placeRun(state, cards, i))
      }
    }
  }
