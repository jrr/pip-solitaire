// Serialize a game's *progress* to a string and back (#177), so the web app can
// persist an in-progress game to `localStorage` and resume it after a reload, a
// closed tab, or a crash. The thing being saved is exactly the board's undo/redo
// history — a `History.t<GameState.t>` — so restoring lands on the same board,
// the same card positions, *and* the same Undo stack the player left.
//
// It lives in `core`, beside the state it serializes, for two reasons: the
// encoding is pure (no `localStorage`, no `Math.random`) and so is unit-testable
// here, and keeping the wire format next to `GameState`/`History` means a change
// to those types is a change to this file, not a silently-drifting copy in the
// view. The web app's `SavedGame` is the thin impure wrapper that only reads and
// writes the browser storage; the moment a byte is in hand, (de)serialization is
// this module's job.
//
// The format is deliberately small and self-describing:
//
//   {"v":1,"past":[S,…],"present":S,"future":[S,…]}
//
// where a state S is `{"piles":[[C,…],…],"loose":[C,…]}` and a card C is a
// two-character code — rank char then suit char, e.g. "TS" (Ten of Spades),
// "AH" (Ace of Hearts). The `v` is a format version: a saved game from an older,
// incompatible layout (or any corrupt/foreign string) fails to `decode` and is
// ignored rather than crashing the board — the "never a broken board" guarantee.

open Card

// The wire-format version. Bump this whenever the shape below changes
// incompatibly; `decode` rejects any other version, so an old save is dropped and
// the player gets a fresh deal instead of a misread board.
let version = 1

// --- Card codes --------------------------------------------------------------
// A card is two characters: its rank then its suit. Compact, human-legible in a
// stored blob, and trivially reversible. The rank/suit vocabularies are closed,
// so the char maps below are total in one direction and partial (returning
// `None` on any stray character) in the other.

let rankChar = (rank: rank): string =>
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

let suitChar = (suit: suit): string =>
  switch suit {
  | Spades => "S"
  | Hearts => "H"
  | Diamonds => "D"
  | Clubs => "C"
  }

let rankOfChar = (ch: string): option<rank> =>
  switch ch {
  | "A" => Some(Ace)
  | "2" => Some(Two)
  | "3" => Some(Three)
  | "4" => Some(Four)
  | "5" => Some(Five)
  | "6" => Some(Six)
  | "7" => Some(Seven)
  | "8" => Some(Eight)
  | "9" => Some(Nine)
  | "T" => Some(Ten)
  | "J" => Some(Jack)
  | "Q" => Some(Queen)
  | "K" => Some(King)
  | _ => None
  }

let suitOfChar = (ch: string): option<suit> =>
  switch ch {
  | "S" => Some(Spades)
  | "H" => Some(Hearts)
  | "D" => Some(Diamonds)
  | "C" => Some(Clubs)
  | _ => None
  }

let encodeCard = (c: card): string => rankChar(c.rank) ++ suitChar(c.suit)

// A card code is exactly two known characters; anything else (wrong length, a
// stray glyph) is `None`, so a corrupt blob can't smuggle a bogus card through.
let decodeCard = (s: string): option<card> =>
  String.length(s) == 2
    ? switch (rankOfChar(String.charAt(s, 0)), suitOfChar(String.charAt(s, 1))) {
      | (Some(rank), Some(suit)) => Some({suit, rank})
      | _ => None
      }
    : None

// --- Small decode helpers ----------------------------------------------------
// `allSome` collapses an array of optional results into an optional array: it's
// `Some` only when *every* element decoded, so one bad card, column or state
// fails the whole parse (and the save is ignored) rather than yielding a
// partial, broken board.
let allSome = (xs: array<option<'a>>): option<array<'a>> =>
  xs->Array.every(Option.isSome) ? Some(xs->Array.filterMap(x => x)) : None

// --- Encoding to JSON --------------------------------------------------------
// Built straight from the `JSON.t` constructors (no `Encode` helpers) so the
// shape is visible here and matches `decode` field-for-field.

let encodeCards = (cards: array<card>): JSON.t => JSON.Array(
  cards->Array.map(c => JSON.String(encodeCard(c))),
)

let encodeState = (s: GameState.t): JSON.t => JSON.Object(
  Dict.fromArray([
    ("piles", JSON.Array(s.piles->Array.map(encodeCards))),
    ("loose", encodeCards(s.loose)),
  ]),
)

// --- Decoding from JSON ------------------------------------------------------

let decodeCards = (json: JSON.t): option<array<card>> =>
  switch json {
  | JSON.Array(items) =>
    items
    ->Array.map(item =>
      switch item {
      | JSON.String(s) => decodeCard(s)
      | _ => None
      }
    )
    ->allSome
  | _ => None
  }

let decodePiles = (json: JSON.t): option<array<array<card>>> =>
  switch json {
  | JSON.Array(cols) => cols->Array.map(decodeCards)->allSome
  | _ => None
  }

let decodeState = (json: JSON.t): option<GameState.t> =>
  switch json {
  | JSON.Object(dict) =>
    switch (
      dict->Dict.get("piles")->Option.flatMap(decodePiles),
      dict->Dict.get("loose")->Option.flatMap(decodeCards),
    ) {
    | (Some(piles), Some(loose)) => Some({GameState.piles, loose})
    | _ => None
    }
  | _ => None
  }

let decodeStates = (json: JSON.t): option<array<GameState.t>> =>
  switch json {
  | JSON.Array(items) => items->Array.map(decodeState)->allSome
  | _ => None
  }

// --- The public seam ---------------------------------------------------------

// Serialize a board's whole undo/redo history to a storable string.
let encode = (h: History.t<GameState.t>): string =>
  JSON.stringify(
    JSON.Object(
      Dict.fromArray([
        ("v", JSON.Number(Int.toFloat(version))),
        ("past", JSON.Array(h.past->Array.map(encodeState))),
        ("present", encodeState(h.present)),
        ("future", JSON.Array(h.future->Array.map(encodeState))),
      ]),
    ),
  )

// Parse a stored string back into a history, or `None` when it can't be trusted:
// not valid JSON, the wrong (or missing) format version, or any structural
// mismatch — a card that isn't a real card, a field of the wrong JSON shape. The
// caller treats `None` as "no saved game" and deals fresh, so a corrupt or
// outdated blob degrades to a new board instead of an error (#177).
let decode = (raw: string): option<History.t<GameState.t>> => {
  let parsed = try Some(JSON.parseOrThrow(raw)) catch {
  | _ => None
  }
  switch parsed {
  | Some(JSON.Object(dict)) =>
    switch dict->Dict.get("v") {
    | Some(JSON.Number(v)) if v == Int.toFloat(version) =>
      switch (
        dict->Dict.get("past")->Option.flatMap(decodeStates),
        dict->Dict.get("present")->Option.flatMap(decodeState),
        dict->Dict.get("future")->Option.flatMap(decodeStates),
      ) {
      | (Some(past), Some(present), Some(future)) => Some({History.past, present, future})
      | _ => None
      }
    | _ => None
    }
  | _ => None
  }
}
