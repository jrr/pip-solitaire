// The minimal card *identity* the board model needs to name specific cards:
// suit, rank, and their pairing. Just the vocabulary of what a card *is* — no
// display concerns. Colours, pip glyphs and SVG art stay in the presentation
// layer (web-app's `Deck`/`CardArt`), which re-exports these very types so both
// layers agree on the model without duplicating it.
//
// This is deliberately small: only what the board model needs to name a card.

type suit = Spades | Hearts | Diamonds | Clubs

type rank =
  | Ace
  | Two
  | Three
  | Four
  | Five
  | Six
  | Seven
  | Eight
  | Nine
  | Ten
  | Jack
  | Queen
  | King

// A card's *identity*: its suit and rank, and — on a board played with more than one
// pack — which copy it is. `copy` is absent for the first copy, which on a single pack
// is the only one, so a card built as `{suit, rank}` is the plain card it always was;
// the extra copies carry `copy: k` for k ≥ 1, and `==` keeps telling them apart. Build
// the copies with `nth`, never with `copy: 0`: two spellings of the first copy would
// be two cards that compare unequal.
type card = {suit: suit, rank: rank, copy?: int}

// Which copy a card is, the first being 0.
let copyOf = (c: card): int => c.copy->Option.getOr(0)

// The `k`-th copy of a card, spelled the one way each copy is spelled.
let nth = (c: card, k: int): card =>
  k == 0 ? {suit: c.suit, rank: c.rank} : {suit: c.suit, rank: c.rank, copy: k}
