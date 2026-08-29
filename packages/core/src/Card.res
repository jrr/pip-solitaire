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

type card = {suit: suit, rank: rank}
