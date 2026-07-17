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

// ANSI colour: wrap `s` in a SGR colour code and a reset. The escape byte is
// built from its char code so the source needs no literal control character.
let esc = String.fromCharCode(27)
let colorize = (s, code) => `${esc}[${code}m${s}${esc}[0m`
let red = "31"

// The visible width of a line: its length once the zero-width ANSI colour codes
// are stripped, so coloured and plain cards measure the same and columns align.
// The escape byte is removed first (matched by value, so no literal control
// character in the source), then the `[..m` SGR remnant it introduced.
let ansi = /\[[0-9;]*m/g
let visibleWidth = s => s->String.replaceAll(esc, "")->String.replaceRegExp(ansi, "")->String.length

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

// A pile's column from its stacking behaviour and the cards resting in it. The
// cards come from wherever the caller has them — the board's opening deal
// (`board`) or a live snapshot (`stateBoard`) — so the two renderers share one
// notion of how a pile looks.
let columnFor = (stacking: Game.stacking, cards: array<card>) =>
  switch stacking {
  | Game.Fanned => fannedColumn(cards)
  | Game.Squared => squaredColumn(cards)
  }

let pileColumn = (pile: Game.pile) => columnFor(pile.stacking, pile.cards)

// A column of card lines is `colWidth` visible columns wide (a cell plus its two
// borders); the gap that separates neighbouring piles / loose cards.
let colWidth = cellWidth + 2
let gap = 3

// The tallest of a set of card blocks — piles hold different numbers of cards,
// so a row of them has to be squared off to the deepest.
let maxHeight = blocks =>
  blocks->Array.reduce(0, (m, b) => Array.length(b) > m ? Array.length(b) : m)

// Pad a column with blank rows at its foot so every pile in a row shares a
// height and the shorter ones don't drag the cards beside them upward.
let padColumn = (col, height) =>
  col->Array.concat(Array.make(~length=height - Array.length(col), repeat(" ", colWidth)))

// The natural width of a row of `n` equal columns separated by `gap`.
let rowWidth = n => n <= 0 ? 0 : n * colWidth + (n - 1) * gap

// Indent each line of a block so it sits centred within `width` (the loose
// cards, dealt centred beneath the piles as they are on the web table).
let center = (block, width) =>
  block->Array.map(line => {
    let pad = (width - visibleWidth(line)) / 2
    pad > 0 ? repeat(" ", pad) ++ line : line
  })

// Lay equal-height card blocks side by side with a fixed gap (the loose cards).
let joinBlocks = blocks =>
  switch blocks[0] {
  | None => []
  | Some(first) =>
    first->Array.mapWithIndex((_, row) =>
      blocks->Array.map(b => b->Array.getUnsafe(row))->Array.join(repeat(" ", gap))
    )
  }

// The pile row: the columns spread across `width` like the web table's flexbox
// `space-between` — the first pile hugs the left edge, the last the right, and
// the rest are evenly spaced between (any leftover column padding falls in the
// leftmost gaps). A lone pile is simply centred.
let spaceBetween = (columns, width) => {
  let n = Array.length(columns)
  let height = maxHeight(columns)
  let cols = columns->Array.map(c => padColumn(c, height))
  switch cols[0] {
  | None => []
  | Some(_) if n == 1 => center(cols->Array.getUnsafe(0), width)
  | Some(first) =>
    let slack = width - n * colWidth
    let base = slack / (n - 1)
    let extra = Int.mod(slack, n - 1)
    first->Array.mapWithIndex((_, row) =>
      cols
      ->Array.mapWithIndex((col, i) => {
        let cell = col->Array.getUnsafe(row)
        i < n - 1 ? cell ++ repeat(" ", base + (i < extra ? 1 : 0)) : cell
      })
      ->Array.join("")
    )
  }
}

// Lay a board out like the web table: a titled row of pile columns along the
// top and the loose cards (already framed) centred beneath them. The board is as
// wide as its widest row, so whichever row is narrower is centred within it.
// Both the static-`Game` and live-`GameState` renderers assemble their columns
// and loose cards then hand them here, so the layout lives in one place.
let assemble = (
  ~title: string,
  ~columns: array<array<string>>,
  ~freeCards: array<array<string>>,
) => {
  let width = Math.Int.max(rowWidth(Array.length(columns)), rowWidth(Array.length(freeCards)))

  let top = spaceBetween(columns, width)
  let bottom = Array.length(freeCards) == 0 ? [] : center(joinBlocks(freeCards), width)

  let rows = Array.length(bottom) == 0 ? [top] : [top, bottom]
  let sections = Array.concat([[title]], rows)
  sections->Array.map(lines => lines->Array.join("\n"))->Array.join("\n\n")
}

// The whole opening layout for a game, straight from its board definition.
let board = (game: Game.t) =>
  assemble(
    ~title=game.name,
    ~columns=game.piles->Array.map(pileColumn),
    ~freeCards=game.loose->Array.map(c => fullCard(free, c)),
  )

// The same layout over a *live* `GameState.t` — so the renderer shows any state
// the reducer produces, not just the opening deal. The stacking behaviour still
// comes from the board definition (`GameState` carries only where cards rest),
// while every card comes from the snapshot.
let stateBoard = (~game: Game.t, state: GameState.t) =>
  assemble(
    ~title=game.name,
    ~columns=game.piles->Array.mapWithIndex((pile, i) =>
      columnFor(pile.stacking, GameState.cardsInPile(state, i))
    ),
    ~freeCards=state.loose->Array.map(c => fullCard(free, c)),
  )
