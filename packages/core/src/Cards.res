// The deck as data: the pack, a deterministic seeded shuffle, and a round-robin deal.
// The collection layer over `Card`, which owns a single card's identity.
//
// Named `Cards` rather than `Deck` because the web-app already owns a `Deck` module
// for card *presentation*; that one re-exports these values, so both layers share one
// deck. The shuffle is driven by an explicit PRNG rather than `Math.random` (banned on
// pure paths here), because a deal number must reproduce a board exactly.
//
// ⚠️ **Changing anything between the `frozen` markers changes every deal number.**
//
// A seed shared out of this app is a promise that `?seed=N` lays out this exact board,
// in this build and in every build after it. The suit and rank order, the pack's
// construction order, the PRNG constants, the direction Fisher–Yates walks and the
// draw it takes, and the round-robin deal are all inputs to that promise — so are the
// cascade count and the pile order `Game.freecellDeal` adds on top. Change one and
// every link anyone has ever shared points somewhere else, silently, because the link
// still opens a perfectly playable board. `Core_test`'s golden deal is the tripwire:
// when it goes red, that is what happened, and the fix is not to update the expected
// board.
//
// The way out, when the shuffle genuinely has to change, is to **version the seed**
// rather than mutate it in place: a new parameter (`?seed2=`) or a prefix on the
// value, with the old form still routed to this algorithm. Old links keep opening the
// board they were shared for; new links get the better shuffle.
//
// Not in the contract: the constructor order in `Card.res`. `suits` and `ranks` are
// explicit arrays, so the type may grow or reorder freely — it is the arrays below
// that are frozen.

open Card

// --- frozen: the deal-number contract ------------------------------------------

// Enumeration order: suits grouped, ranks ascending within each — also the order the
// web-app's gallery renders an unshuffled deck in.
let suits = [Spades, Hearts, Diamonds, Clubs]
let ranks = [Ace, Two, Three, Four, Five, Six, Seven, Eight, Nine, Ten, Jack, Queen, King]

// Which cards a board is played with, as a **subset of one pack**. A value rather
// than the ambient 52, because a downstream rule that assumes the pack silently
// mis-decides on any board that isn't the full one — "complete" as thirteen cards
// ending on a King, or "safe to auto-collect" naming four suits by hand.
//
// Deliberately **not** multi-deck: two copies of one card would break
// `GameState.sameCard`'s structural identity. A subset keeps every `{suit, rank}`
// appearing at most once.
//
// Order is meaningful: `ranks` runs low to high, the run a foundation climbs.
type deck = {suits: array<suit>, ranks: array<rank>}

let standard: deck = {suits, ranks}

// A fresh array each call, so a caller may shuffle or otherwise mutate what it gets.
let cardsOf = (deck: deck): array<card> =>
  deck.suits->Array.flatMap(suit => deck.ranks->Array.map(rank => {suit, rank}))

// The whole pack, named as such — the card gallery and the `Scenario` builders want
// *the pack* and should keep saying so.
let all = cardsOf(standard)

// --- Deterministic seeded shuffle --------------------------------------------
// xorshift32 plus Fisher–Yates. All state is one 32-bit int stepped by bitwise ops,
// which compile to JS's 32-bit `<<`/`>>>`/`^`, so the sequence is identical
// everywhere — the property a reproducible deal number rests on. Not cryptographic.

// The classic 13/17/5 triple, within int32: `shiftRightUnsigned` is the zero-filling
// `>>>`, so the middle step stays logical even for a high-bit-set state.
let xorshift = (x: int): int => {
  let x = x->Int.bitwiseXor(x->Int.shiftLeft(13))
  let x = x->Int.bitwiseXor(x->Int.shiftRightUnsigned(17))
  let x = x->Int.bitwiseXor(x->Int.shiftLeft(5))
  x
}

// xorshift maps 0 to 0 forever, so a zero state is bumped to 1. Mixing the seed with
// a constant first (an injective xor) keeps neighbouring deal numbers well apart, so
// they diverge from the very first swap.
let seedState = (seed: int): int => {
  let s = seed->Int.bitwiseXor(0x2545f491)
  s == 0 ? 1 : s
}

// Same seed → same permutation, and a permutation always: Fisher–Yates only swaps,
// over `cardsOf`'s fresh array. `seed` is the deal number.
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

// Round-robin across `piles` columns — card 0 to pile 0, card 1 to pile 1, wrapping —
// the way cards are physically dealt across a tableau. Columns come back bottom-first
// (deal order), ready to seed an opening arrangement. `piles <= 0` yields no columns.
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

// --- end frozen ------------------------------------------------------------------
