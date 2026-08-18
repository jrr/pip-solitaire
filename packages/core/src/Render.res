// A **text** view of a board: box-drawn cards, as a string. The counterpart to the
// web-app's `Deck`/`CardArt`, and — since it draws with characters rather than pixels
// — the one view both front ends can show. `Card.res` keeps display concerns out of
// the *model*; this is a renderer over the model, which is a different thing, and it
// lives here because two callers now want it:
//
//   - the **CLI**, which prints it to a terminal after every command;
//   - the **web app's debug console** (#273), whose `print` used to answer "the board
//     is on screen" for want of any way to draw one — the panel is a monospace log,
//     which is exactly the medium this renders for.
//
// Three visual conventions carry the model's state, mirroring how the web-app's
// styling distinguishes cards:
//   - Line weight tells you what a slot *is*. A card resting free on the table
//     gets a heavy frame (┏━┓); a card placed in a pile gets a light one (┌─┐);
//     an empty pile shows a double frame (╔═╗) where its cards would land.
//   - Colour tells suit: hearts and diamonds are drawn red, spades and clubs
//     plain, the terminal analogue of the red/black pips on a real deck. This is the
//     one convention that isn't universal — it's written as ANSI escapes, which a
//     terminal paints and a browser would show as garbage — so it's **off by default**
//     and the CLI asks for it (`~color=true`). The suit is still legible without it:
//     the pip glyphs differ.
//   - A fanned pile is drawn as an overlapping vertical column — each lower card
//     peeks a single face line above the next, and the top card (last in the
//     model's bottom-first order) is shown in full at the foot of the fan.
//
// The board is laid out in the same role-grouped rows the web table uses (#94): the
// free cells and foundations across the top, the tableau columns below. Sixteen columns
// in a single row is wider than a terminal, and the two halves aren't the same kind of
// thing anyway — a board that carries only one of the groups keeps its single row.
//
// Every column is headed by the name that slot answers to (`T3`, `C1`, `F2` — see
// `Slot`), which is also what a typed move can address it by, so the drawing tells you
// how to play it.

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

// The face line: the rank and suit, left-aligned and padded to the cell width, and
// coloured red for the red suits when the caller paints in colour. `~color` is threaded
// from the entry points rather than read from anywhere ambient, so one renderer serves a
// terminal and a browser panel in the same call shape.
let faceLine = (~color: bool, f, card: card) => {
  let text = `${rankLabel(card.rank)}${suitSymbol(card.suit)}`->String.padEnd(cellWidth, " ")
  let face = color && isRed(card.suit) ? colorize(text, red) : text
  `${f.vertical}${face}${f.vertical}`
}

// A full, four-line card in the given frame style.
let fullCard = (~color: bool, f, card) => [
  topBorder(f),
  faceLine(~color, f, card),
  blankLine(f),
  bottomBorder(f),
]

// A double-framed empty slot, so an empty pile still shows where its cards land.
let emptySlot = () => [topBorder(empty), blankLine(empty), blankLine(empty), bottomBorder(empty)]

// A fanned pile as an overlapping vertical column: every card contributes its
// top border and one face line, and the top of the pile (last in bottom-first
// order) closes the fan with its full body. An empty pile shows a slot.
let fannedColumn = (~color: bool, cards: array<card>) =>
  if Array.length(cards) == 0 {
    emptySlot()
  } else {
    let lastIndex = Array.length(cards) - 1
    cards
    ->Array.mapWithIndex((card, i) =>
      i == lastIndex
        ? fullCard(~color, placed, card)
        : [topBorder(placed), faceLine(~color, placed, card)]
    )
    ->Array.flat
  }

// A squared pile keeps a single card's footprint, so only its top card shows;
// an empty pile shows a slot.
let squaredColumn = (~color: bool, cards: array<card>) =>
  switch cards[Array.length(cards) - 1] {
  | Some(card) => fullCard(~color, placed, card)
  | None => emptySlot()
  }

// A pile's column from its stacking behaviour and the cards resting in it. The
// cards come from wherever the caller has them — the board's opening deal
// (`board`) or a live snapshot (`stateBoard`) — so the two renderers share one
// notion of how a pile looks.
let columnFor = (~color: bool, stacking: Game.stacking, cards: array<card>) =>
  switch stacking {
  | Game.Fanned => fannedColumn(~color, cards)
  | Game.Squared => squaredColumn(~color, cards)
  }

let pileColumn = (~color: bool, pile: Game.pile) => columnFor(~color, pile.stacking, pile.cards)

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

// A column's heading: the name that slot answers to (`T3`, `C1`, `F4` — see `Slot`),
// centred over the column and padded out to its full width. The padding is the load-
// bearing part: every line of a column has to measure exactly `colWidth`, or the gaps
// `spaceBetween` inserts after it would drag the rest of that row leftward.
//
// It's a heading rather than a mark inside the empty slots because the name is most
// wanted where it's least visible: an empty column shows you where a card lands, but a
// seven-card fan is the one you have to count across to address.
let headingLine = (label: string): string => {
  let pad = (colWidth - String.length(label)) / 2
  (repeat(" ", pad) ++ label)->String.padEnd(colWidth, " ")
}

// A column with its heading above it, when the board can name the slot.
let headed = (~label: option<string>, column: array<string>): array<string> =>
  switch label {
  | Some(label) => [headingLine(label)]->Array.concat(column)
  | None => column
  }

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

// Lay a board out like the web table: the titled rows of pile columns stacked one
// above the next, and the loose cards (already framed) centred beneath them. The board
// is as wide as its widest row, so a narrower row is spread within that width rather
// than setting its own. Both the static-`Game` and live-`GameState` renderers assemble
// their rows and loose cards then hand them here, so the layout lives in one place.
let assemble = (
  ~title: string,
  ~rows: array<array<array<string>>>,
  ~freeCards: array<array<string>>,
) => {
  // Every row is laid out to one width — the widest of them — so the rows line up with
  // each other rather than each floating at its own scale.
  let width =
    rows->Array.reduce(rowWidth(Array.length(freeCards)), (w, row) =>
      Math.Int.max(w, rowWidth(Array.length(row)))
    )

  let cardRows =
    rows->Array.filter(row => Array.length(row) > 0)->Array.map(row => spaceBetween(row, width))
  let loose = Array.length(freeCards) == 0 ? [] : [center(joinBlocks(freeCards), width)]

  let sections = [[title]]->Array.concat(cardRows)->Array.concat(loose)
  sections->Array.map(lines => lines->Array.join("\n"))->Array.join("\n\n")
}

// The board's title: the game's name, and — when the caller knows one — the deal number
// that laid it out. That number is the one fact you need to open this exact board again,
// and it means the same thing in both front ends now (`deal 12345`), so a board played in
// a terminal can be handed to the browser and back. Without it a dealt board is
// unreproducible the moment you close the session.
//
// The caller supplies it rather than it being read off `game.seed`, because the two can
// differ: a posed position (`Scenario`) descends from the deal it has been *proved* to,
// which is usually none at all — the same rule the web app follows before offering a
// Share (#264).
let titleFor = (~game: Game.t, ~deal: option<int>): string =>
  switch deal {
  | Some(n) => `${game.name} — deal #${Int.toString(n)}`
  | None => game.name
  }

// Split a board's columns into the rows it's drawn in, the same role grouping the web
// table lays out (#94): the free cells and foundations across the top, the tableau
// columns below. It's what makes a sixteen-pile FreeCell board readable in a terminal —
// sixteen columns in one row is wider than a window, and the two halves aren't the same
// kind of thing anyway.
//
// A board carrying only one of the two groups — every card-table demo — keeps its single
// row, laid out exactly as before.
let roleRows = (~game: Game.t, columns: array<array<string>>): array<array<array<string>>> => {
  let isCascade = i =>
    switch game.piles->Array.get(i) {
    | Some(pile) => pile.role == Game.Cascade
    | None => false
    }
  let top = columns->Array.filterWithIndex((_, i) => !isCascade(i))
  let bottom = columns->Array.filterWithIndex((_, i) => isCascade(i))
  Array.length(top) == 0 || Array.length(bottom) == 0 ? [columns] : [top, bottom]
}

// Each pile's column, headed by the name that slot answers to (`Slot`) — so the board
// says how to address every one of its piles, and `move 8H T3` can be read straight off
// the drawing.
let headedColumns = (~game: Game.t, columns: array<array<string>>): array<array<string>> =>
  columns->Array.mapWithIndex((column, i) => headed(~label=Slot.labelAt(~game, i), column))

// The whole opening layout for a game, straight from its board definition. A game with a
// seed of its own names it (FreeCell's canonical board is deal #1).
let board = (~color: bool=false, game: Game.t) =>
  assemble(
    ~title=titleFor(~game, ~deal=game.seed),
    ~rows=roleRows(
      ~game,
      headedColumns(~game, game.piles->Array.map(pile => pileColumn(~color, pile))),
    ),
    ~freeCards=game.loose->Array.map(c => fullCard(~color, free, c)),
  )

// The same layout over a *live* `GameState.t` — so the renderer shows any state
// the reducer produces, not just the opening deal. The stacking behaviour still
// comes from the board definition (`GameState` carries only where cards rest),
// while every card comes from the snapshot.
let stateBoard = (~game: Game.t, ~deal: option<int>=?, ~color: bool=false, state: GameState.t) =>
  assemble(
    ~title=titleFor(~game, ~deal),
    ~rows=roleRows(
      ~game,
      headedColumns(
        ~game,
        game.piles->Array.mapWithIndex((pile, i) =>
          columnFor(~color, pile.stacking, GameState.cardsInPile(state, i))
        ),
      ),
    ),
    ~freeCards=state.loose->Array.map(c => fullCard(~color, free, c)),
  )
