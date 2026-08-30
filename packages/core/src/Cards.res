// The deck as data, owned in `core`: the full 52-card pack, a *deterministic*
// seeded shuffle, and a round-robin deal. Toward FreeCell (M2), a real deal needs
// a whole deck shuffled reproducibly — the same deal number must reproduce the
// same board exactly (ROADMAP: "seeded shuffle … enables deal numbers") — so the
// 52 and the shuffle live here in the pure core, not in the view.
//
// This is the collection layer over `Card` (the single-card *identity*): `Card`
// says what one card is, `Cards` owns the whole pack and the operations across
// it. It's named `Cards` (not `Deck`) because the web-app already owns a `Deck`
// module for card *presentation*; that `Deck` re-exports these values, mirroring
// how it already re-exports the `Card` types, so both layers share one deck
// without duplicating it.
//
// Everything here is pure and testable: the shuffle is driven by an explicit
// little PRNG rather than `Math.random` (banned on this codebase's pure paths),
// so a seed reproduces a permutation exactly.
//
// The pack is also a *parameter*: `deck` describes which suits and
// ranks a board plays with, `standard` is today's four × thirteen, and `shuffle`
// takes one. `all` stays the whole pack for the callers that genuinely want it.

open Card

// Enumeration order: suits grouped, ranks ascending within each. `all` below is
// the Cartesian product in this order — also the order the web-app's gallery
// renders an unshuffled deck in.
let suits = [Spades, Hearts, Diamonds, Clubs]
let ranks = [Ace, Two, Three, Four, Five, Six, Seven, Eight, Nine, Ten, Jack, Queen, King]

// --- The deck as a parameter ------------------------------------------
// Which cards a board is played with, described as a **subset of one pack**: the
// suits it uses and the ranks it uses, whose Cartesian product is its cards. A
// value rather than the ambient 52, because the rules downstream used to *assume*
// the pack — "complete" meant literally thirteen cards ending on a King, and "safe
// to auto-collect" named all four suits by hand — which silently mis-decides on any
// board that isn't the full pack.
//
// Deliberately **not** multi-deck: two copies of one card would break
// `GameState.sameCard`'s structural identity (a limitation that module's own
// comment already parks as later work). A subset of one pack keeps identity
// exactly as it is — every `{suit, rank}` still appears at most once.
//
// Order is meaningful: `ranks` runs low to high (it's the run a foundation climbs),
// and `suits`/`ranks` together fix the enumeration order of `cardsOf`.
type deck = {suits: array<suit>, ranks: array<rank>}

// The ordinary pack: four suits × thirteen ranks. What every board plays with
// today, and what `all` is built from.
let standard: deck = {suits, ranks}

// The cards `deck` describes: every one of its ranks in every one of its suits,
// exactly once — suits grouped, ranks ascending within each. A fresh array each
// call, so a caller may shuffle or otherwise mutate what it gets back.
let cardsOf = (deck: deck): array<card> =>
  deck.suits->Array.flatMap(suit => deck.ranks->Array.map(rank => {suit, rank}))

// The full 52-card deck: every rank in every suit, exactly once. Still the whole
// pack, named as such — the card gallery and the `Scenario` builders want *the
// pack* and should keep saying so.
let all = cardsOf(standard)

// --- Deterministic seeded shuffle --------------------------------------------
// A tiny xorshift32 PRNG plus a Fisher–Yates shuffle. All the state lives in a
// single 32-bit int stepped by bitwise ops (which compile to JS's 32-bit `<<`,
// `>>>`, `^`), so the sequence is exact and identical everywhere — the property a
// reproducible deal number rests on. Not cryptographic; just enough spread to
// shuffle 52 cards well.

// One xorshift32 step: the classic 13/17/5 triple, entirely within int32
// (`shiftRightUnsigned` is the zero-filling `>>>`, so the middle step stays
// logical even for a negative — high-bit-set — state).
let xorshift = (x: int): int => {
  let x = x->Int.bitwiseXor(x->Int.shiftLeft(13))
  let x = x->Int.bitwiseXor(x->Int.shiftRightUnsigned(17))
  let x = x->Int.bitwiseXor(x->Int.shiftLeft(5))
  x
}

// Turn a seed into the PRNG's starting state. xorshift stalls at 0 (it maps 0 to
// 0 forever), so a zero state is bumped to 1; mixing the seed with a constant
// first (an injective xor) keeps neighbouring seeds — deal numbers 1 and 2 — well
// apart, so they diverge from the very first swap.
let seedState = (seed: int): int => {
  let s = seed->Int.bitwiseXor(0x2545f491)
  s == 0 ? 1 : s
}

// `deck` dealt in a reproducible order for `seed`: same seed → same permutation,
// and a permutation always — every card of the deck exactly once, none dropped or
// duplicated (Fisher–Yates only ever swaps, over `cardsOf`'s fresh array so no
// shared value is disturbed). `seed` is the "deal number"; `deck` defaults to the
// full pack, so the 52-card call site reads exactly as it did.
let shuffle = (~deck: deck=standard, ~seed: int): array<card> => {
  let cards = cardsOf(deck)
  let state = ref(seedState(seed))
  // Fisher–Yates from the top: pick each slot's occupant from those not yet placed.
  for i in Array.length(cards) - 1 downto 1 {
    state := xorshift(state.contents)
    // Mask off the sign bit for a non-negative draw, then fold into [0, i].
    let j = mod(state.contents->Int.bitwiseAnd(0x7fffffff), i + 1)
    let atI = cards->Array.getUnsafe(i)
    let atJ = cards->Array.getUnsafe(j)
    cards->Array.setUnsafe(i, atJ)
    cards->Array.setUnsafe(j, atI)
  }
  cards
}

// --- Dealing -----------------------------------------------------------------

// Lay `cards` out into `piles` columns by dealing one at a time round-robin —
// card 0 to pile 0, card 1 to pile 1, …, wrapping back to pile 0 — the way cards
// are physically dealt across a tableau. Returns the columns bottom-first (deal
// order), ready to seed a `Game`/`GameState` opening arrangement: a demo scene
// builds its board from this today, and the FreeCell board will later. Dealing
// 52 across N piles spreads them as evenly as the count allows (the first
// `52 mod N` piles get one extra). `piles <= 0` yields no columns.
let deal = (~piles: int, cards: array<card>): array<array<card>> => {
  if piles <= 0 {
    []
  } else {
    let columns = []
    for _ in 1 to piles {
      columns->Array.push([])
    }
    cards->Array.forEachWithIndex((card, i) =>
      switch columns->Array.get(mod(i, piles)) {
      | Some(column) => column->Array.push(card)
      | None => ()
      }
    )
    columns
  }
}
