// An immutable snapshot of *where every card currently rests* — the in-progress
// gameplay state — kept deliberately separate from the board *definition*
// (`Game.t`, the empty board plus its rules). This is the first migration step
// toward M1 (#77): the load-bearing roadmap principle is that all game state
// lives in `core` as immutable data plus pure transition functions, with the UI
// holding only transient view state. Today the live "where is each card" lives
// as mutable refs in the view (`TableScene`); this type is where it will move.
//
// Deliberately *no behaviour* yet: this is the type, the initial-state builder,
// and the read-only queries the view will eventually need — no `action`, no
// reducer, no view rewiring. Later steps (a pure `canDrop` query, an
// `action` + `reducer`, then the view cutover) build on this.
//
// The split:
//   - `Game.t` is the *board definition* — the piles and the rules they enforce,
//     static across a game. The "empty board".
//   - `GameState.t` is the *dynamic* snapshot — where each card rests right now.
//     The opening deal, which used to be baked into `Game.t` (`loose` +
//     `pile.cards`), becomes just the *initial* `GameState` derived from a board.
//
// Card identity for lookups is structural `{suit, rank}` — unique within a
// single deck — so the queries below key off a `card` value directly via `==`.
// (A full multi-deck model, where identity would need more, is later.)

open Card

// Where a single card rests right now. `InPile(pileIndex, slot)` locates it in
// pile `pileIndex` at `slot`, counting from 0 = the bottom of the pile up toward
// the top. `Loose` records only *that* a card lies free on the table, not where —
// a loose card's pixel coordinates stay transient view state, not model state.
type location =
  | InPile(int, int)
  | Loose

// Card identity for lookups: two cards are the same when suit and rank match.
// `{suit, rank}` is unique within a single deck, so this is enough to key the
// queries below. Compared field-by-field (both are payload-free variants) rather
// than by whole-record `==`, so identity stays an explicit, deck-scoped decision
// the queries share — and a fuller multi-deck identity can grow from here.
let sameCard = (a: card, b: card): bool => a.suit == b.suit && a.rank == b.rank

// The snapshot: each pile's cards bottom-first (so a card's slot is its index in
// `piles[pileIndex]`, and the last element is the pile's top card), plus the
// cards lying loose on the table.
type t = {
  piles: array<array<card>>,
  loose: array<card>,
}

// The opening layout derived from a board definition: each pile starts holding
// the cards the board deals it, and `loose` holds the board's opening loose deal.
// Inner arrays are copied so the snapshot never shares mutable storage with the
// board value — the state is a value of its own from the moment it's built.
let initial = (game: Game.t): t => {
  piles: game.piles->Array.map(p => p.cards->Array.copy),
  loose: game.loose->Array.copy,
}

// The cards resting in pile `i`, bottom-first — a copy, so a caller can't reach
// back through it and mutate the snapshot. An out-of-range index yields `[]`.
let cardsInPile = (state: t, i: int): array<card> =>
  switch state.piles->Array.get(i) {
  | Some(cards) => cards->Array.copy
  | None => []
  }

// The top card of pile `i` — the card a newcomer would land on — or `None` when
// the pile is empty or the index is out of range.
let topOf = (state: t, i: int): option<card> =>
  switch state.piles->Array.get(i) {
  | Some(cards) => cards->Array.get(Array.length(cards) - 1)
  | None => None
  }

// Where `card` currently rests, or `None` if it isn't in this state at all.
// Piles are searched first (returning the pile index and the card's slot), then
// the loose table. Identity is the structural `{suit, rank}` equality above.
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
