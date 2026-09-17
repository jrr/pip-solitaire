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
  // How many of those cards the deal holds back in a stock, and 0 on a board with no
  // stock at all — which is why `numbers` drops the term rather than printing it, as it
  // does for cells. The *opening* count, not a running one: this screen describes a game
  // rather than reporting on the one in hand, and the board it shows above is deal #1's.
  stock: int,
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
  // The game in a paragraph, or `None` for a game this build has and the copy doesn't
  // — which the screen shows as no paragraph rather than as a sentence about patience
  // in general. See `descriptionFor`.
  description: option<string>,
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

// The game in two or three sentences, written for a reader who has played a solitaire
// game or two: what is hidden, how a run moves, and the one rule that catches a player
// coming from another game. Not the rules in full — the link out is for that.
//
// **Keyed by family where there is one**, which is what makes the paragraph steady under
// the picker: the three FreeCell sizes are one game to describe and the three Spiderette
// packs are another, and a reader who saw the words change would go back looking for a
// difference that isn't there. The same rule forbids naming anything the picker moves:
// "the free cells", never "four free cells".
let descriptionFor = (id: string): option<string> =>
  switch id {
  | "freecell" =>
    Some(
      "Every card is face up from the deal: nothing is hidden, and almost any board can be solved by thinking it through. Columns build down in alternating colours, and the free cells park one card each — how many stand empty is how long a run you can move at once.",
    )
  | "simplesimon" =>
    Some(
      "Spider's game with nothing hidden: every card is face up from the start, and there is nowhere to park one you can't place yet. Build down in rank whatever the suit, but only a same-suit run lifts as a block, and a suit gathered King down to Ace leaves the board for good.",
    )
  | "spiderette" =>
    Some(
      "Spider's rules over a Klondike deal: seven columns, only the top card of each face up. Build down in rank whatever the suit, but only a same-suit run lifts as a block, and a suit gathered King down to Ace leaves the board. The stock deals onto every column at once, and refuses while a column stands empty.",
    )
  | _ => None
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

// The undealt remainder, counted off the piles rather than as `deckSize` minus the
// tableau: a board could hold a card back somewhere that isn't a stock, and the
// subtraction would report it as stock anyway.
let stockSize = (game: Game.t): int =>
  Game.pilesOf(game, Game.Stock)->Array.reduce(0, (n, pile) => n + Array.length(pile.cards))

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
  stock: stockSize(game),
  reference: referenceFor(game.id),
  opening: game.piles,
  previewBox: previewBoxFor(game),
  description: Game.familyOf(game)
  ->Option.mapOr(game.id, family => family.id)
  ->descriptionFor,
}

// `\u{a0}` rather than a space, here and in the stock term below: the panel is narrow
// enough that the line wraps on a phone, and a term is the unit it should wrap at.
// Broken at an ordinary space it reads "24 in" over "stock", a number severed from what
// it counts; unbreakable, the only place left to wrap is a middot, which is the one
// place the line already says it may be read in parts.
let count = (n: int, ~singular: string, ~plural: string): string =>
  Int.toString(n) ++ "\u{a0}" ++ (n == 1 ? singular : plural)

// The numbers as one line — "8 cascades · 4 cells · 52 cards". A term whose count is
// zero is left out entirely: "0 cells" is a number a reader has to discard, where the
// absence says the same thing and is one term shorter. The separator is a middot with
// spaces around it, which is what keeps the terms readable as separate terms.
//
// **The stock comes after the pack, and names no noun of its own.** Every other term
// counts a thing the board has some number of; "24 in stock" counts part of the 52 just
// named, so it reads as a share of the term before it rather than as a fourth thing to
// add up — which "24 stock cards" beside "52 cards" would not.
let numbers = (info: t): string =>
  [
    Some(count(info.cascades, ~singular="cascade", ~plural="cascades")),
    info.cells == 0 ? None : Some(count(info.cells, ~singular="cell", ~plural="cells")),
    Some(count(info.cards, ~singular="card", ~plural="cards")),
    info.stock == 0 ? None : Some(Int.toString(info.stock) ++ "\u{a0}in\u{a0}stock"),
  ]
  ->Array.filterMap(term => term)
  ->Array.join(" · ")
