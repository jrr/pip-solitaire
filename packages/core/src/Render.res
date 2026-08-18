// A **text** view of a board: box-drawn cards. The counterpart to the web-app's
// `Deck`/`CardArt`, and — since it draws with characters rather than pixels — the one
// view both front ends can show. `Card.res` keeps display concerns out of the *model*;
// this is a renderer over the model, which is a different thing, and it lives here
// because two callers now want it:
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
//     plain, the terminal analogue of the red/black pips on a real deck. The suit is
//     still legible without it: the pip glyphs differ.
//   - A fanned pile is drawn as an overlapping vertical column — each lower card
//     peeks a single face line above the next, and the top card (last in the
//     model's bottom-first order) is shown in full at the foot of the fan.
//
// The board is laid out in the same role-grouped rows the web table uses (#94): the free
// cells and foundations across the top, the tableau columns below. Sixteen columns in a
// single row is wider than a terminal, and the two halves aren't the same kind of thing
// anyway — a board carrying only one of the groups keeps its single row. Every column is
// headed by the name that slot answers to (`T3`, `C1`, `F2` — see `Slot`), which is also
// what a typed move can address it by, so the drawing tells you how to play it.
//
// **What crosses the boundary is a document, not a painted string.** A board renders to
// `array<line>`, where a line is a run of `span`s each tagged with the *role* its
// characters play (`ink`) — "this is a red suit's face", not "this is SGR 31" and not
// "this is #991b1b". Painting is a front end's job, and each one does it in its own
// alphabet: the terminal wraps red faces in ANSI escapes (`toAnsi`), the web console
// hands each span to a `<span>` and lets the stylesheet colour it. Neither alphabet is
// intelligible to the other, which is why the thing they share is the one that's in
// neither.
//
// `toPlain`/`toAnsi` are the two adapters shipped here, and `board`/`stateBoard` are
// kept as the string-returning entry points they always were, so a caller that only
// wants text (the CLI, every test that predates this) never learns about spans at all.
//
// The other thing structure buys is alignment. Colour used to be baked into the
// characters, so every width the layout measured had to discount escapes it couldn't
// see (`visibleWidth` was a regex strip). A span knows its own text, so a line's width
// is a sum — and a coloured board can't drift out of alignment with a plain one,
// because they're the same document painted twice.

open Card

// --- What a rendered board is made of -----------------------------------------

// The role a run of characters plays. This is as far as `core` goes towards colour:
// naming what something *is*, and leaving what it looks like to whoever is drawing.
// Deliberately small — it grows a case when a front end has something new to say, and
// an unknown case can always be painted as plain text.
type ink =
  | Plain // frames, gaps, padding: the board's furniture
  | Suit(Rules.color) // a card's face, in the model's own red/black
  | Title // the heading naming the game and its deal

// A run of characters under one ink, and a row of them. A line carries no newline of
// its own — `toPlain` and friends join them — so a line is always exactly one row.
type span = {text: string, ink: ink}
type line = array<span>

let plain = (text: string): span => {text, ink: Plain}

let sameInk = (a: ink, b: ink): bool =>
  switch (a, b) {
  | (Plain, Plain) | (Title, Title) => true
  | (Suit(x), Suit(y)) => x == y
  | (Plain | Suit(_) | Title, _) => false
  }

// Fold neighbouring spans of the same ink into one and drop the empty ones. Purely an
// economy: it changes no output, but a board line is assembled from ~16 cards' worth of
// borders and gaps, and a front end rendering one node per span would otherwise build
// several dozen where three or four will do.
let compact = (line: line): line => {
  let out: array<span> = []
  line->Array.forEach(span =>
    if span.text != "" {
      switch out->Array.at(-1) {
      | Some(last) if sameInk(last.ink, span.ink) =>
        out->Array.set(Array.length(out) - 1, {...last, text: last.text ++ span.text})
      | _ => out->Array.push(span)
      }
    }
  )
  out
}

// Lay spans end to end. Every line in this module is built through here, so nothing
// escapes `compact`.
let concat = (parts: array<line>): line => parts->Array.flat->compact

// Lay lines side by side with `separator` between them — `Array.join` for spans.
let joinLines = (parts: array<line>, separator: line): line =>
  parts->Array.mapWithIndex((part, i) => i == 0 ? part : Array.concat(separator, part))->concat

// The visible width of a line: the characters it will actually put on screen. A sum
// now that colour lives in the ink rather than in the text — there is nothing invisible
// in a line to discount.
let visibleWidth = (line: line): int =>
  line->Array.reduce(0, (n, span) => n + String.length(span.text))

let repeat = (s, n) => Array.make(~length=n, s)->Array.join("")

// `n` columns of blank, as a line. Empty below 1 so a zero-width pad contributes no span.
let pad = (n: int): line => n > 0 ? [plain(repeat(" ", n))] : []

// Plain text as a document: one row per newline-separated line, all of it furniture.
// The trivial document — what a front end that speaks spans needs in order to carry an
// ordinary reply (a rejection, a help listing, an echoed command) down the very channel
// a board travels, instead of keeping a second one for strings. An empty row renders as
// no spans at all, matching what `compact` does with empty text everywhere else.
let text = (s: string): array<line> =>
  s->String.split("\n")->Array.map(row => row == "" ? [] : [plain(row)])

// --- Glyphs -------------------------------------------------------------------

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

// --- A move, in words ----------------------------------------------------------
// One dispatched action as a single line of the same document a board is drawn in. The
// debug console (#213) used to narrate a move as the reducer's own `action`, stringified:
// `{"TAG":"Move","card":{"suit":"Clubs","rank":"Ten"},"to":{"TAG":"ToPile","_0":12}}` —
// every fact about the move present and not one of them legible, with the destination
// named as the index a player would have to count out rather than by the label printed
// over it. This is the same move said the way the board says it: `move 10♣ → T5`.
//
// A document rather than a string, for the reason a board is one: the card is inked by
// suit, so it reads as the card it is in a log that already paints a printed board that
// way — and the front end that can't paint still gets the words (`Render.toPlain`).

// A card's face as one inked span: the glyphs `faceLine` puts inside a frame, without the
// frame.
let cardSpan = (card: card): span => {
  text: `${rankLabel(card.rank)}${suitSymbol(card.suit)}`,
  ink: Suit(Rules.color(card.suit)),
}

// A run of cards, space-separated — a supermove's cards, or the cards a sweep sent home.
let cardSpans = (cards: array<card>): line =>
  cards->Array.map(card => [cardSpan(card)])->joinLines([plain(" ")])

// What to call a pile: the label printed over it (`T5`), or its bare index on a board
// that prints none. The same answer `Slot` gives the parser, so the place a log names is
// the place a typed move can address.
let pileName = (~game: Game.t, i: int): string =>
  Slot.labelAt(~game, i)->Option.getOr(`pile ${Int.toString(i)}`)

// Where a move sends its cards, as the board names the place.
let placeName = (~game: Game.t, target: Reducer.target): string =>
  switch target {
  | Reducer.ToTable => "table"
  | Reducer.ToPile(i) => pileName(~game, i)
  }

// The verb each action answers to is the one you would type for it (`Command`'s), so a
// logged move and a typed one are recognisably the same move.
let action = (~game: Game.t, action: Reducer.action): line =>
  switch action {
  | Reducer.Move({card, to}) =>
    concat([[plain("move ")], [cardSpan(card)], [plain(` → ${placeName(~game, to)}`)]])
  | Reducer.MoveRun({cards, to}) =>
    concat([[plain("moverun ")], cardSpans(cards), [plain(` → ${placeName(~game, to)}`)]])
  | Reducer.MoveColumn({from, to}) => [
      plain(`movecol ${pileName(~game, from)} → ${pileName(~game, to)}`),
    ]
  }

// --- Cards --------------------------------------------------------------------

// The three kinds of line that make up a card, each `cellWidth` wide inside.
let topBorder = f => [plain(`${f.topLeft}${repeat(f.horizontal, cellWidth)}${f.topRight}`)]
let bottomBorder = f => [plain(`${f.bottomLeft}${repeat(f.horizontal, cellWidth)}${f.bottomRight}`)]
let blankLine = f => [plain(`${f.vertical}${repeat(" ", cellWidth)}${f.vertical}`)]

// The face line: the rank and suit, left-aligned and padded to the cell width, between
// the frame's two verticals. The face is the one span on a board that isn't `Plain`,
// and it's inked with `Rules.color` — the model's own notion of a red or black card,
// the same one the alternating-colour stacking rule is written against — rather than a
// second opinion about which suits are red.
let faceLine = (f, card: card): line => {
  let text = `${rankLabel(card.rank)}${suitSymbol(card.suit)}`->String.padEnd(cellWidth, " ")
  concat([[plain(f.vertical)], [{text, ink: Suit(Rules.color(card.suit))}], [plain(f.vertical)]])
}

// A full, four-line card in the given frame style.
let fullCard = (f, card): array<line> => [
  topBorder(f),
  faceLine(f, card),
  blankLine(f),
  bottomBorder(f),
]

// A double-framed empty slot, so an empty pile still shows where its cards land.
let emptySlot = (): array<line> => [
  topBorder(empty),
  blankLine(empty),
  blankLine(empty),
  bottomBorder(empty),
]

// A fanned pile as an overlapping vertical column: every card contributes its
// top border and one face line, and the top of the pile (last in bottom-first
// order) closes the fan with its full body. An empty pile shows a slot.
let fannedColumn = (cards: array<card>): array<line> =>
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
let squaredColumn = (cards: array<card>): array<line> =>
  switch cards[Array.length(cards) - 1] {
  | Some(card) => fullCard(placed, card)
  | None => emptySlot()
  }

// A pile's column from its stacking behaviour and the cards resting in it. The
// cards come from wherever the caller has them — the board's opening deal
// (`board`) or a live snapshot (`stateBoard`) — so the two renderers share one
// notion of how a pile looks.
let columnFor = (stacking: Game.stacking, cards: array<card>): array<line> =>
  switch stacking {
  | Game.Fanned => fannedColumn(cards)
  | Game.Squared => squaredColumn(cards)
  }

let pileColumn = (pile: Game.pile): array<line> => columnFor(pile.stacking, pile.cards)

// --- Layout -------------------------------------------------------------------

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
let padColumn = (col: array<line>, height): array<line> =>
  col->Array.concat(
    Array.make(~length=height - Array.length(col), ())->Array.map(() => pad(colWidth)),
  )

// The natural width of a row of `n` equal columns separated by `gap`.
let rowWidth = n => n <= 0 ? 0 : n * colWidth + (n - 1) * gap

// A column's heading: the name that slot answers to (`T3`, `C1`, `F4` — see `Slot`),
// centred over the column and padded out to its full width on both sides. The right-hand
// padding is the load-bearing part: every line of a column has to measure exactly
// `colWidth`, or the gaps `spaceBetween` lays after it would drag the rest of that row
// leftward.
//
// It's a heading rather than a mark inside the empty slots because the name is most
// wanted where it's least visible: an empty column already shows you where a card lands,
// but a seven-card fan is the one you'd have to count across to address.
//
// `Plain` ink like the frames: a slot's name is the board's furniture, not a card.
let headingLine = (label: string): line => {
  let before = (colWidth - String.length(label)) / 2
  concat([pad(before), [plain(label)], pad(colWidth - before - String.length(label))])
}

// A column with its heading above it, when the board can name the slot.
let headed = (~label: option<string>, column: array<line>): array<line> =>
  switch label {
  | Some(label) => [headingLine(label)]->Array.concat(column)
  | None => column
  }

// Indent each line of a block so it sits centred within `width` (the loose
// cards, dealt centred beneath the piles as they are on the web table).
let center = (block: array<line>, width): array<line> =>
  block->Array.map(line => concat([pad((width - visibleWidth(line)) / 2), line]))

// Lay equal-height card blocks side by side with a fixed gap (the loose cards).
let joinBlocks = (blocks: array<array<line>>): array<line> =>
  switch blocks[0] {
  | None => []
  | Some(first) =>
    first->Array.mapWithIndex((_, row) =>
      blocks->Array.map(b => b->Array.getUnsafe(row))->joinLines(pad(gap))
    )
  }

// The pile row: the columns spread across `width` like the web table's flexbox
// `space-between` — the first pile hugs the left edge, the last the right, and
// the rest are evenly spaced between (any leftover column padding falls in the
// leftmost gaps). A lone pile is simply centred.
let spaceBetween = (columns: array<array<line>>, width): array<line> => {
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
        i < n - 1 ? concat([cell, pad(base + (i < extra ? 1 : 0))]) : cell
      })
      ->concat
    )
  }
}

// A row of nothing, which is what separates the board's sections.
let blankRow: line = []

// Lay a board out like the web table: the titled rows of pile columns stacked one above
// the next, and the loose cards (already framed) centred beneath them. The board is as
// wide as its widest row, so a narrower row is spread within that width rather than
// setting its own. Both the static-`Game` and live-`GameState` renderers assemble their
// rows and loose cards then hand them here, so the layout lives in one place.
let assemble = (
  ~title: string,
  ~rows: array<array<array<line>>>,
  ~freeCards: array<array<line>>,
): array<line> => {
  // Every row is laid out to one width — the widest of them — so the rows line up with
  // each other rather than each floating at its own scale.
  let width =
    rows->Array.reduce(rowWidth(Array.length(freeCards)), (w, row) =>
      Math.Int.max(w, rowWidth(Array.length(row)))
    )

  let cardRows =
    rows->Array.filter(row => Array.length(row) > 0)->Array.map(row => spaceBetween(row, width))
  let loose = Array.length(freeCards) == 0 ? [] : [center(joinBlocks(freeCards), width)]

  let sections = [[[{text: title, ink: Title}]]]->Array.concat(cardRows)->Array.concat(loose)
  // One blank row between sections; none before the first.
  sections
  ->Array.mapWithIndex((section, i) => i == 0 ? section : Array.concat([blankRow], section))
  ->Array.flat
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

// --- The boards ---------------------------------------------------------------

// Split a board's columns into the rows it's drawn in, the same role grouping the web
// table lays out (#94): the free cells and foundations across the top, the tableau
// columns below. It's what makes a sixteen-pile FreeCell board readable in a terminal —
// sixteen columns in one row is wider than a window, and the two halves aren't the same
// kind of thing anyway.
//
// A board carrying only one of the two groups — every card-table demo — keeps its single
// row, laid out exactly as before.
let roleRows = (~game: Game.t, columns: array<array<line>>): array<array<array<line>>> => {
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
let headedColumns = (~game: Game.t, columns: array<array<line>>): array<array<line>> =>
  columns->Array.mapWithIndex((column, i) => headed(~label=Slot.labelAt(~game, i), column))

// The whole opening layout for a game, straight from its board definition. A game with a
// seed of its own names it (FreeCell's canonical board is deal #1).
let boardLines = (game: Game.t): array<line> =>
  assemble(
    ~title=titleFor(~game, ~deal=game.seed),
    ~rows=roleRows(~game, headedColumns(~game, game.piles->Array.map(pileColumn))),
    ~freeCards=game.loose->Array.map(c => fullCard(free, c)),
  )

// The same layout over a *live* `GameState.t` — so the renderer shows any state
// the reducer produces, not just the opening deal. The stacking behaviour still
// comes from the board definition (`GameState` carries only where cards rest),
// while every card comes from the snapshot.
let stateLines = (~game: Game.t, ~deal: option<int>=?, state: GameState.t): array<line> =>
  assemble(
    ~title=titleFor(~game, ~deal),
    ~rows=roleRows(
      ~game,
      headedColumns(
        ~game,
        game.piles->Array.mapWithIndex((pile, i) =>
          columnFor(pile.stacking, GameState.cardsInPile(state, i))
        ),
      ),
    ),
    ~freeCards=state.loose->Array.map(c => fullCard(free, c)),
  )

// --- Painting -----------------------------------------------------------------
// Two adapters over the document above, one per alphabet. A third — the web console's
// spans — isn't here, because it doesn't produce a string: it walks `line` itself and
// hands each span to the DOM.

// Ink dropped: the characters alone. What a browser panel, a test, or a pipe wants.
let toPlain = (lines: array<line>): string =>
  lines
  ->Array.map(line => line->Array.map(span => span.text)->Array.join(""))
  ->Array.join("\n")

// ANSI colour, for a terminal: wrap the red faces in an SGR colour code and a reset.
// The escape byte is built from its char code so the source needs no literal control
// character. Black faces, frames and the title are left alone — this renderer has only
// ever painted the one thing.
let esc = String.fromCharCode(27)
let colorize = (s, code) => `${esc}[${code}m${s}${esc}[0m`
let red = "31"

let paintAnsi = (span: span): string =>
  switch span.ink {
  | Suit(Rules.Red) => colorize(span.text, red)
  | Suit(Rules.Black) | Plain | Title => span.text
  }

let toAnsi = (lines: array<line>): string =>
  lines
  ->Array.map(line => line->Array.map(paintAnsi)->Array.join(""))
  ->Array.join("\n")

// --- The string entry points --------------------------------------------------
// What every caller before the document existed asked for, unchanged: a board as text,
// plain by default and coloured when the caller knows it's talking to a terminal.
// `core` doesn't assume it is.

let board = (~color: bool=false, game: Game.t): string => {
  let lines = boardLines(game)
  color ? toAnsi(lines) : toPlain(lines)
}

let stateBoard = (
  ~game: Game.t,
  ~deal: option<int>=?,
  ~color: bool=false,
  state: GameState.t,
): string => {
  let lines = stateLines(~game, ~deal?, state)
  color ? toAnsi(lines) : toPlain(lines)
}
