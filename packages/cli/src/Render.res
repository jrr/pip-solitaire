// A plain-stdout view of a `Game`'s opening layout: box-drawn cards printed to
// the terminal. This is the CLI's presentation layer — the counterpart to the
// web-app's `Deck`/`CardArt`. `core` deliberately keeps display concerns out of
// the model (see `Card.res`), so each frontend brings its own glyphs; here that
// is a Unicode suit pip and a short rank label rendered inside a box-drawing
// frame, the terminal analogue of `CardArt`'s SVG face.

open Card

// The Unicode pip glyph for each suit (the same characters the web-app draws).
let suitSymbol = suit =>
  switch suit {
  | Spades => `♠`
  | Hearts => `♥`
  | Diamonds => `♦`
  | Clubs => `♣`
  }

// The short corner label: a single character, or "10" for the ten.
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

let stackingLabel = (stacking: Game.stacking) =>
  switch stacking {
  | Game.Squared => "squared"
  | Game.Fanned => "fanned"
  }

// A card cell is `cellWidth` columns wide: two for the rank ("10"), one for the
// suit pip, and a trailing space so the glyph never crowds the right border.
let cellWidth = 4

let repeat = (s, n) => Array.make(~length=n, s)->Array.join("")

// One card drawn as three lines (top border, face, bottom border).
let cardCell = (card: card) => {
  let face = `${rankLabel(card.rank)->String.padStart(2, " ")}${suitSymbol(card.suit)} `
  (`┌${repeat("─", cellWidth)}┐`, `│${face}│`, `└${repeat("─", cellWidth)}┘`)
}

// An empty slot: a card-sized frame with a blank face, so an empty pile still
// shows where its cards would land.
let emptyCell = () => (
  `┌${repeat("─", cellWidth)}┐`,
  `│${repeat(" ", cellWidth)}│`,
  `└${repeat("─", cellWidth)}┘`,
)

// A row of cards side by side, as a single three-line string. An empty list
// renders one empty slot rather than nothing.
let cardRow = cards => {
  let cells = Array.length(cards) == 0 ? [emptyCell()] : cards->Array.map(cardCell)
  let line = pick => cells->Array.map(pick)->Array.join("")
  [line(((t, _, _)) => t), line(((_, m, _)) => m), line(((_, _, b)) => b)]->Array.join("\n")
}

// The whole opening layout for a game: a title, the optional caption, each pile
// (labelled with its stacking behaviour) and any cards dealt loose on the table.
let board = (game: Game.t) => {
  let title = [`Game: ${game.name}`]
  let caption = switch game.caption {
  | Some(c) => [c]
  | None => []
  }
  let piles =
    game.piles->Array.mapWithIndex((pile: Game.pile, i) =>
      `Pile ${Int.toString(i + 1)} · ${stackingLabel(pile.stacking)}\n${cardRow(pile.cards)}`
    )
  let loose = Array.length(game.loose) == 0 ? [] : [`Loose on the table\n${cardRow(game.loose)}`]

  [title, caption, piles, loose]->Array.flat->Array.join("\n\n")
}
