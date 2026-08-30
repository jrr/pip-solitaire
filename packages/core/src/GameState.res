// An immutable snapshot of *where every card currently rests*, kept separate from the
// board *definition*: `Game.t` is the empty board and its rules, static across a
// game, and this is the dynamic value moved over it. A board's opening deal
// (`pile.cards`) is only the initial value of one of these.
//
// A pure position and nothing else, which is what makes it comparable, replayable and
// cheap to record. The counters beside it are `Stats` and `Timing`; the line of play
// over it is `History`; the transitions are `Reducer`.

open Card

// `InPile(pileIndex, slot)` counts `slot` from 0 = the bottom of the pile upward.
// `Loose` records only *that* a card lies free on the table, not where — a loose
// card's pixel coordinates stay transient view state.
type location =
  | InPile(int, int)
  | Loose

// Identity is structural `{suit, rank}`, which is unique within a single deck, and it
// is compared field-by-field rather than by whole-record `==` so the decision stays
// explicit and deck-scoped — a fuller multi-deck identity would grow from here.
let sameCard = (a: card, b: card): bool => a.suit == b.suit && a.rank == b.rank

// Piles run bottom-first, so a card's slot is its index and the last element is the
// pile's top card.
type t = {
  piles: array<array<card>>,
  loose: array<card>,
}

// Inner arrays are copied so the snapshot never shares mutable storage with the
// board value: it is a value of its own from the moment it's built.
let initial = (game: Game.t): t => {
  piles: game.piles->Array.map(p => p.cards->Array.copy),
  loose: [],
}

// A copy, so a caller can't reach back through it and mutate the snapshot.
let cardsInPile = (state: t, i: int): array<card> =>
  switch state.piles->Array.get(i) {
  | Some(cards) => cards->Array.copy
  | None => []
  }

// The card a newcomer would land on.
let topOf = (state: t, i: int): option<card> =>
  switch state.piles->Array.get(i) {
  | Some(cards) => cards->Array.get(Array.length(cards) - 1)
  | None => None
  }

// Piles are searched first, then the loose table.
let locationOf = (state: t, card: card): option<location> => {
  let found = ref(None)
  state.piles->Array.forEachWithIndex((cards, i) =>
    switch found.contents {
    | Some(_) => () // already located it in an earlier pile
    | None =>
      switch cards->Array.findIndex(c => sameCard(c, card)) {
      | -1 => ()
      | slot => found := Some(InPile(i, slot))
      }
    }
  )
  switch found.contents {
  | Some(_) as inPile => inPile
  | None => state.loose->Array.some(c => sameCard(c, card)) ? Some(Loose) : None
  }
}

// Lets a driver ask "did this move actually change the board?", so a lawful no-op —
// an identity re-drop, a `MoveColumn` with `from == to` — is un-undoable rather than
// a fresh step.
let equal = (a: t, b: t): bool => {
  let sameCards = (xs: array<card>, ys: array<card>) =>
    Array.length(xs) == Array.length(ys) &&
      xs->Array.mapWithIndex((c, i) => sameCard(c, ys->Array.getUnsafe(i)))->Array.every(x => x)
  Array.length(a.piles) == Array.length(b.piles) &&
  a.piles
  ->Array.mapWithIndex((cards, i) => sameCards(cards, b.piles->Array.getUnsafe(i)))
  ->Array.every(x => x) &&
  sameCards(a.loose, b.loose)
}

// Every foundation holding a complete run of the board's own deck. Purely an
// observation of the foundations, so how the cards got there — a drag, an
// auto-collect, the solver — is beside the point.
//
// The non-empty guard is load-bearing: `Array.every` over an empty group is vacuously
// true, so without it a foundation-less board reads as an instant win.
let hasWon = (game: Game.t, state: t): bool => {
  let foundations = Game.pileIndices(game, Game.Foundation)
  Array.length(foundations) > 0 &&
    foundations->Array.every(i => Rules.isCompleteRun(~deck=game.deck, cardsInPile(state, i)))
}
