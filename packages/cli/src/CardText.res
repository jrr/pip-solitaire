// A compact *text identity* for a card, so the reducer-driver CLI can name a
// specific card in one short token — `AS` for the Ace of Spades, `TH` for the
// Ten of Hearts, `KD` for the King of Diamonds. This is the terminal's answer to
// the web-app's pointer plumbing: with no cursor to pick a card, the driver
// addresses one by typing its identity.
//
// `core` keeps display concerns out of the model (see `Card.res`), so the glyphs
// and the parsing both live here in the frontend. The grammar is deliberately
// tiny and case-insensitive: a rank character (`A 2-9 T J Q K`, or the two-digit
// `10`) followed by a suit letter (`S H D C`).

open Card

// The suit letters, matching a real deck's shorthand.
let suitLetter = suit =>
  switch suit {
  | Spades => "S"
  | Hearts => "H"
  | Diamonds => "D"
  | Clubs => "C"
  }

// The rank characters: a single glyph each, with `T` standing in for the Ten so
// every card is a two-character token that round-trips through `parse`.
let rankLetter = rank =>
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
  | Ten => "T"
  | Jack => "J"
  | Queen => "Q"
  | King => "K"
  }

// A card's compact identity, e.g. `AS`, `TH`, `KD` — the inverse of `parse`.
let format = (card: card): string => rankLetter(card.rank) ++ suitLetter(card.suit)

let parseSuit = s =>
  switch s {
  | "S" => Some(Spades)
  | "H" => Some(Hearts)
  | "D" => Some(Diamonds)
  | "C" => Some(Clubs)
  | _ => None
  }

// Both `T` and the two-digit `10` name the Ten, so a user can type whichever
// feels natural.
let parseRank = s =>
  switch s {
  | "A" => Some(Ace)
  | "2" => Some(Two)
  | "3" => Some(Three)
  | "4" => Some(Four)
  | "5" => Some(Five)
  | "6" => Some(Six)
  | "7" => Some(Seven)
  | "8" => Some(Eight)
  | "9" => Some(Nine)
  | "T" | "10" => Some(Ten)
  | "J" => Some(Jack)
  | "Q" => Some(Queen)
  | "K" => Some(King)
  | _ => None
  }

// Parse a token like `AS`/`th`/`10H` into a `{suit, rank}`, or `None` if it
// isn't a valid identity. The suit is always the last character; everything
// before it is the rank, so the two-digit `10` is handled without a special
// case. Case-insensitive.
let parse = (token: string): option<card> => {
  let s = token->String.trim->String.toUpperCase
  let n = String.length(s)
  if n < 2 {
    None
  } else {
    let rankPart = s->String.slice(~start=0, ~end=n - 1)
    let suitPart = s->String.sliceToEnd(~start=n - 1)
    switch (parseRank(rankPart), parseSuit(suitPart)) {
    | (Some(rank), Some(suit)) => Some({suit, rank})
    | _ => None
    }
  }
}
