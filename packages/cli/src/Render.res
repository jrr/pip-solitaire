// A plain-stdout view of a `Game`'s opening layout: box-drawn cards printed to
// the terminal. This is the CLI's presentation layer — the counterpart to the
// web-app's `Deck`/`CardArt`. `core` deliberately keeps display concerns out of
// the model (see `Card.res`), so each frontend brings its own glyphs; here that
// is a Unicode suit pip and a short rank label rendered inside a box-drawing
// frame, the terminal analogue of `CardArt`'s SVG face.
//
// Three visual conventions carry the model's state, mirroring how the web-app's
// styling distinguishes cards:
//   - Line weight tells you what a slot *is*. A card resting free on the table
//     gets a heavy frame (┏━┓); a card placed in a pile gets a light one (┌─┐);
//     an empty pile shows a double frame (╔═╗) where its cards would land.
//   - Colour tells suit: hearts and diamonds are drawn red, spades and clubs
//     plain, the terminal analogue of the red/black pips on a real deck.
//   - A fanned pile is drawn as an overlapping vertical column — each lower card
//     peeks a single face line above the next, and the top card (last in the
//     model's bottom-first order) is shown in full at the foot of the fan.

open Card

// The Unicode pip glyph for each suit (the same characters the web-app draws).
let suitSymbol = suit =>
  switch suit {
  | Spades => `♠`
  | Hearts => `♥`
  | Diamonds => `♦`
  | Clubs => `♣`
  }

// Hearts and diamonds are the red suits; spades and clubs are drawn plain.
let isRed = suit =>
  switch suit {
  | Hearts | Diamonds => true
  | Spades | Clubs => false
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

// ANSI colour: wrap `s` in a SGR colour code and a reset. The escape byte is
// built from its char code so the source needs no literal control character.
let esc = String.fromCharCode(27)
let colorize = (s, code) => `${esc}[${code}m${s}${esc}[0m`
let red = "31"

// A box-drawing frame: the six characters that draw a card's border. Swapping
// the style is how a card's state (free / placed / empty) changes its outline.
type frame = {
  topLeft: string,
  topRight: string,
  bottomLeft: string,
  bottomRight: string,
  horizontal: string,
  vertical: string,
}

// Light for a placed card, heavy for a free card, double for an empty pile.
let placed = {
  topLeft: `┌`,
  topRight: `┐`,
  bottomLeft: `└`,
  bottomRight: `┘`,
  horizontal: `─`,
  vertical: `│`,
}
let free = {
  topLeft: `┏`,
  topRight: `┓`,
  bottomLeft: `┗`,
  bottomRight: `┛`,
  horizontal: `━`,
  vertical: `┃`,
}
let empty = {
  topLeft: `╔`,
  topRight: `╗`,
  bottomLeft: `╚`,
  bottomRight: `╝`,
  horizontal: `═`,
  vertical: `║`,
}

// A card face is `cellWidth` columns wide: room for the rank ("10"), the suit
// pip, and a trailing space so the glyph never crowds the right border.
let cellWidth = 4

let repeat = (s, n) => Array.make(~length=n, s)->Array.join("")

// The three kinds of line that make up a card, each `cellWidth` wide inside.
let topBorder = f => `${f.topLeft}${repeat(f.horizontal, cellWidth)}${f.topRight}`
let bottomBorder = f => `${f.bottomLeft}${repeat(f.horizontal, cellWidth)}${f.bottomRight}`
let blankLine = f => `${f.vertical}${repeat(" ", cellWidth)}${f.vertical}`

// The face line: the rank and suit, left-aligned and padded to the cell width,
// coloured red for the red suits.
let faceLine = (f, card: card) => {
  let text = `${rankLabel(card.rank)}${suitSymbol(card.suit)}`->String.padEnd(cellWidth, " ")
  let face = isRed(card.suit) ? colorize(text, red) : text
  `${f.vertical}${face}${f.vertical}`
}

// A full, four-line card in the given frame style.
let fullCard = (f, card) => [topBorder(f), faceLine(f, card), blankLine(f), bottomBorder(f)]

// A double-framed empty slot, so an empty pile still shows where its cards land.
let emptySlot = () => [topBorder(empty), blankLine(empty), blankLine(empty), bottomBorder(empty)]

// A fanned pile as an overlapping vertical column: every card contributes its
// top border and one face line, and the top of the pile (last in bottom-first
// order) closes the fan with its full body. An empty pile shows a slot.
let fannedColumn = (cards: array<card>) =>
  if Array.length(cards) == 0 {
    emptySlot()
  } else {
    let lastIndex = Array.length(cards) - 1
    cards
    ->Array.mapWithIndex((card, i) =>
      i == lastIndex ? fullCard(placed, card) : [topBorder(placed), faceLine(placed, card)]
    )
    ->Array.flat
  }

// A squared pile keeps a single card's footprint, so only its top card shows;
// an empty pile shows a slot.
let squaredColumn = (cards: array<card>) =>
  switch cards[Array.length(cards) - 1] {
  | Some(card) => fullCard(placed, card)
  | None => emptySlot()
  }

let pileColumn = (pile: Game.pile) =>
  switch pile.stacking {
  | Game.Fanned => fannedColumn(pile.cards)
  | Game.Squared => squaredColumn(pile.cards)
  }

// Lay a set of equal-height card blocks side by side, gap between them, and
// return the result as one multi-line string.
let joinHorizontally = blocks =>
  switch blocks[0] {
  | None => ""
  | Some(first) =>
    first
    ->Array.mapWithIndex((_, row) =>
      blocks->Array.map(block => block->Array.getUnsafe(row))->Array.join("  ")
    )
    ->Array.join("\n")
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
      `Pile ${Int.toString(i + 1)} · ${stackingLabel(pile.stacking)}\n${pileColumn(
          pile,
        )->Array.join("\n")}`
    )
  let loose =
    Array.length(game.loose) == 0
      ? []
      : [`Loose on the table\n${joinHorizontally(game.loose->Array.map(c => fullCard(free, c)))}`]

  [title, caption, piles, loose]->Array.flat->Array.join("\n\n")
}
