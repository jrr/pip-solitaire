// A small, throwaway card vocabulary local to the web-app demo. This is *not*
// the roadmap's real card model — that one is shared, unit-tested, and lives in
// `core` as its own game-track item. This exists only to feed the rudimentary
// gallery (#36): enough of a deck to render every rank/suit combination once.
//
// Deliberately minimal: four suits, thirteen ranks, the 52-card product, and a
// handful of display helpers (color, symbol glyph, label). No game rules, no
// ordering semantics beyond the enumeration order used to lay the gallery out.

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

// Enumeration order: suits grouped, ranks ascending within each. `allCards`
// below is the Cartesian product in this order, which is also the order the
// gallery renders them in.
let suits = [Spades, Hearts, Diamonds, Clubs]
let ranks = [Ace, Two, Three, Four, Five, Six, Seven, Eight, Nine, Ten, Jack, Queen, King]

// The full 52-card deck: every rank in every suit, exactly once.
let allCards = suits->Array.flatMap(suit => ranks->Array.map(rank => {suit, rank}))

// --- Display helpers ---------------------------------------------------------

// The two card colors. Hearts and diamonds are red; spades and clubs black —
// here a near-black that stays legible on the card's light face.
let suitColor = suit =>
  switch suit {
  | Hearts | Diamonds => "#dc2626"
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
