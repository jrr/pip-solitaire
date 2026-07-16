// The minimal card *identity* the board model needs to name specific cards:
// suit, rank, and their pairing. Just the vocabulary of what a card *is* — no
// display concerns. Colours, pip glyphs and SVG art stay in the presentation
// layer (web-app's `Deck`/`CardArt`), which re-exports these very types so both
// layers agree on the model without duplicating it.
//
// This is deliberately small: only what `Game` needs today to describe an
// opening deal. The fuller, ordering-aware card model is still its own future
// game-track item; when it lands it can grow from here.

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
