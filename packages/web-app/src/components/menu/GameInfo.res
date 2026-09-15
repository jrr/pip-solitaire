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
  // The game this is about, which is also the board's scene id and its storage key.
  // Carried so a screen showing these facts can find its way back to the `Game.t` they
  // were read off — the info screen's variant picker asks which family the game belongs
  // to — without the pane it travels through having to carry a second field beside it.
  id: string,
  // The game as a player *names* it, which is a board's own name only where the board is
  // a game (see `nameOf`).
  name: string,
  cascades: int,
  // 0 on a game with no free cells (Simple Simon, the Spiderettes), which is why
  // `numbers` below drops the term rather than printing "0 cells".
  cells: int,
  cards: int,
  reference: string,
  // The board as dealt — every pile with its cards, and how many of them lie face down
  // — for the still of it the screen shows (`BoardPreview`). Deal #1, the one the games
  // carry and the screenshots derive from, so the picture is the same board every time.
  // Plain data still: piles are cards, counts and rule variants, no closures, which is
  // what `Menu.screen` asks of everything in here.
  opening: array<Game.pile>,
  // The shape the still is drawn in, as a ratio of its width — **one box for the whole
  // family**, so that picking another size or another pack redraws the board without
  // moving the numbers, the picker and the link below it. See `previewBoxFor`.
  previewBox: float,
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

// **The family's name where there is one**, so the screen about a Spiderette is headed
// "Spiderette" rather than "Spiderette · 2 suits". Which pack, or which size, is the
// picker's to say and the title beside it would only be saying it twice — and it is
// already the name the Games list's row wears and the name the "i" on it announces, so
// the screen a player opens is headed with what they tapped.
//
// Not a lookup either: which boards are one game is `Game.families`' answer, so a fourth
// Spiderette pack is headed like the other three without an edit here.
let nameOf = (game: Game.t): string =>
  Game.familyOf(game)->Option.mapOr(game.name, family => family.name)

// The pack's size from the deck rather than from the dealt piles: a board with a stock
// still holds every card it is played with, and counting the tableau alone would say
// 28 for a Spiderette.
let deckSize = (deck: Cards.deck): int =>
  Array.length(deck.suits) * Array.length(deck.ranks) * deck.copies

// The still's box: the *flattest* board in the game's family. It is the one board that
// fills the box on both axes, and every other one fits inside it with room to spare
// across — where the tallest-shaped board would leave the rest of the family sitting in
// a band of empty mat. Picking it off `Game.families` rather than tabulating it is what
// lets a fourth Spiderette pack arrive without an edit here.
//
// A board with no family is its own box, which is a still that fits exactly: there is
// nothing to keep still for.
let aspectOf = (game: Game.t): float => {
  let (w, h) = TableLayout.boardSize(game.piles)
  h /. w
}

let previewBoxFor = (game: Game.t): float =>
  Game.familyOf(game)->Option.mapOr(aspectOf(game), family =>
    family.variants->Array.reduce(aspectOf(game), (flattest, v) =>
      Math.min(flattest, aspectOf(v.game))
    )
  )

let forGame = (game: Game.t): t => {
  id: game.id,
  name: nameOf(game),
  cascades: Game.pilesOf(game, Game.Cascade)->Array.length,
  cells: Game.pilesOf(game, Game.FreeCell)->Array.length,
  cards: deckSize(game.deck),
  reference: referenceFor(game.id),
  opening: game.piles,
  previewBox: previewBoxFor(game),
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
