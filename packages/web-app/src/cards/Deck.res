// The presentation-side card vocabulary for the web-app demo: the *identity* of
// a card (suit, rank, their pairing) plus the display helpers — colour, pip
// glyph, labels — that turn it into something on screen.
//
// The identity types are not owned here: they're re-exported from `Card` in
// `core`, so the board model (`Game`) and the view agree on what a card is
// without duplicating the enums. The `= Card.x = | ...` form keeps the
// constructors (`Spades`, `Ace`, …) in scope here while making these the *same*
// types as core's — a `Card.card` is a `Deck.card`. What stays local is only
// presentation: the 52-card product below and the display helpers, none of
// which core needs.

type suit = Card.suit = Spades | Hearts | Diamonds | Clubs

type rank = Card.rank =
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

type card = Card.card = {suit: suit, rank: rank}

// The full 52-card deck is owned by `core` now (`Cards.all`), so a shuffled deal
// and the gallery draw from the *same* deck. Re-exported here so the presentation
// layer still reaches it as `Deck.allCards`, in `core`'s enumeration order (suits
// grouped, ranks ascending) — which is the order the gallery renders them in.
let allCards = Cards.all

// --- Display helpers ---------------------------------------------------------

// The two card colors. Hearts and diamonds are red; spades and clubs black —
// here a near-black that stays legible on the card's light face. The red is a
// deep, dark red (Tailwind red-800) rather than a brighter primary, so the pips
// read as a rich card red against the light face.
let suitColor = suit =>
  switch suit {
  | Hearts | Diamonds => "#991b1b"
  | Spades | Clubs => "#0f172a"
  }

// The Unicode pip glyph for each suit.
let suitSymbol = suit =>
  switch suit {
  | Spades => `♠`
  | Hearts => `♥`
  | Diamonds => `♦`
  | Clubs => `♣`
  }

// Spelled-out suit name, used for the accessible label on each card.
let suitName = suit =>
  switch suit {
  | Spades => "spades"
  | Hearts => "hearts"
  | Diamonds => "diamonds"
  | Clubs => "clubs"
  }

// The short corner label: a plain character (or "10"), no pip grid or court art
// yet — that's a follow-up.
let rankLabel = rank =>
  switch rank {
  | Ace => "A"
  | Two => "2"
  | Three => "3"
  | Four => "4"
  | Five => "5"
  | Six => "6"
  | Seven => "7"
  | Eight => "8"
  | Nine => "9"
  | Ten => "10"
  | Jack => "J"
  | Queen => "Q"
  | King => "K"
  }

// Spelled-out rank name, paired with `suitName` for accessible labels.
let rankName = rank =>
  switch rank {
  | Ace => "ace"
  | Two => "two"
  | Three => "three"
  | Four => "four"
  | Five => "five"
  | Six => "six"
  | Seven => "seven"
  | Eight => "eight"
  | Nine => "nine"
  | Ten => "ten"
  | Jack => "jack"
  | Queen => "queen"
  | King => "king"
  }

// e.g. "ace of spades" — the `aria-label` for a rendered card.
let cardName = card => `${rankName(card.rank)} of ${suitName(card.suit)}`
