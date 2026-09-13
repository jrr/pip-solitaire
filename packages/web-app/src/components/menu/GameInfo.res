// What the info screen has to say about a game: the board's numbers, and where the
// rules are written down in full. A pure value, so `<MenuGameInfoScreen>` draws it and
// `Main` never assembles a screen's worth of fields by hand.
//
// **Derived from the `Game.t`, not tabulated beside it.** A board that changes its
// cascade count or its deck reports the new number here without an edit — which is the
// half of this that could silently go stale, since nothing on screen would look wrong.
// Only the reference link is a lookup: which article describes a game is not a fact its
// rules carry.
//
// The table is keyed by **game id** rather than by name, so a game renamed still finds
// its article, and a game this build has but the table doesn't still gets a link — to
// patience itself, which is wrong about the game but never a dead end.

type t = {
  name: string,
  cascades: int,
  // 0 on a game with no free cells (Simple Simon, the Spiderettes), which is why
  // `numbers` below drops the term rather than printing "0 cells".
  cells: int,
  cards: int,
  reference: string,
}

let wikipedia = (article: string): string => "https://en.wikipedia.org/wiki/" ++ article

// The short-deck FreeCells are FreeCell, and the Spiderettes are Spider's family: each
// points at the article for the game it is a variant of, rather than at nothing.
let referenceFor = (id: string): string =>
  switch id {
  | "freecell" | "mini" | "micro" => wikipedia("FreeCell")
  | "simplesimon" => wikipedia("Simple_Simon_(solitaire)")
  | "spiderette1" | "spiderette" | "spiderette4" => wikipedia("Spider_(solitaire)")
  | _ => wikipedia("Patience_(game)")
  }

// The pack's size from the deck rather than from the dealt piles: a board with a stock
// still holds every card it is played with, and counting the tableau alone would say
// 28 for a Spiderette.
let deckSize = (deck: Cards.deck): int =>
  Array.length(deck.suits) * Array.length(deck.ranks) * deck.copies

let forGame = (game: Game.t): t => {
  name: game.name,
  cascades: Game.pilesOf(game, Game.Cascade)->Array.length,
  cells: Game.pilesOf(game, Game.FreeCell)->Array.length,
  cards: deckSize(game.deck),
  reference: referenceFor(game.id),
}

let count = (n: int, ~singular: string, ~plural: string): string =>
  Int.toString(n) ++ " " ++ (n == 1 ? singular : plural)

// The numbers as one line — "8 cascades · 4 cells · 52 cards". A term whose count is
// zero is left out entirely: "0 cells" is a number a reader has to discard, where the
// absence says the same thing and is one term shorter. The separator is a middot with
// spaces around it, which is what keeps the three readable as three.
let numbers = (info: t): string =>
  [
    Some(count(info.cascades, ~singular="cascade", ~plural="cascades")),
    info.cells == 0 ? None : Some(count(info.cells, ~singular="cell", ~plural="cells")),
    Some(count(info.cards, ~singular="card", ~plural="cards")),
  ]
  ->Array.filterMap(term => term)
  ->Array.join(" · ")
