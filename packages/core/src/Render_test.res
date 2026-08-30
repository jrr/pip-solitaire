// `core`'s text renderer: one board drawing served to a terminal and to the web app's
// debug console.
//
// The property that matters most is that **colour is a front end's choice**, because ANSI
// escapes are a terminal's alphabet and a browser panel would show them as garbage. What
// `core` renders is a *document* — lines of spans, each tagged with the role its
// characters play — and each front end paints that in its own alphabet. So the tests come
// in two layers:
//
//   - the **document**: are the spans inked with what a painter needs to know, and is a
//     line still measurable and aligned with colour kept out of its characters?
//   - the **adapters**: does `toPlain` give exactly the string a caller that wants text
//     and nothing else expects, and does `toAnsi` differ from it in colour and nothing
//     else?
//
// The second layer is what keeps the two front ends drawing the *same board*: stripping
// the colour off a coloured board has to give back the plain one — same glyphs, same
// alignment — and a third painter (the console's spans, tried below) has to be able to
// join without `core` learning anything about it.

open Vitest
open Card

let has = (s: string, sub: string): bool => s->String.includes(sub)

// The escape byte the SGR codes are built from (`Render.esc`), by value, so this file
// needs no literal control character either.
let esc = String.fromCharCode(27)
let ansi = /\[[0-9;]*m/g
let stripColor = s => s->String.replaceAll(esc, "")->String.replaceRegExp(ansi, "")

describe("Render.stateBoard", () => {
  test("shows a card after the reducer has moved it onto a pile", () => {
    let game = Game.freecell
    let state = Scenario.freecellSendHome(game)
    // Send the first free cell's card home to its foundation via the reducer.
    let cell = Game.pileIndices(game, Game.FreeCell)->Array.getUnsafe(0)
    let card = GameState.topOf(state, cell)->Option.getOrThrow
    let foundation = Reducer.foundationTarget(~game, state, card)->Option.getOrThrow
    let moved = switch Reducer.reduce(~game, state, Move({card, to: ToPile(foundation)})) {
    | Ok(next) => next
    | Error(_) => state
    }
    let board = Render.stateBoard(~game, moved)
    expect(has(board, game.name))->toBe(true)
    // The cell it left is drawn as an empty slot; the card is now on a foundation.
    expect(GameState.topOf(moved, foundation))->toEqual(Some(card))
    expect(has(board, Render.toPlain([Render.cardSpans([card])])))->toBe(true)
  })

  // The title names the deal when the caller knows one — the fact you need to open the
  // same board again, in either front end.
  test("the title names the deal the caller supplies, and nothing when it doesn't", () => {
    let game = Game.freecell
    let state = GameState.initial(game)
    expect(has(Render.stateBoard(~game, ~deal=12345, state), "deal #12345"))->toBe(true)
    expect(has(Render.stateBoard(~game, state), "deal #"))->toBe(false)
  })
})

describe("Render colour", () => {
  let game = Game.freecell
  let state = GameState.initial(game)

  // Plain by default: `core` doesn't assume its output is going to a terminal. The web
  // console renders exactly this.
  test("carries no escape codes unless asked", () =>
    expect(has(Render.stateBoard(~game, state), esc))->toBe(false)
  )

  test("paints the red suits when asked", () => {
    let colored = Render.stateBoard(~game, ~color=true, state)
    expect(has(colored, esc))->toBe(true)
    // The red suits are wrapped; the black ones are left alone.
    expect(has(colored, `${esc}[31m`))->toBe(true)
  })

  // The invariant behind serving both front ends from one renderer: colour is *only*
  // colour. Strip it and you have the plain board, character for character — which is
  // also why the columns line up either way (the layout measures spans, not characters).
  test("stripping the colour gives back the plain board exactly", () => {
    expect(stripColor(Render.stateBoard(~game, ~color=true, state)))->toBe(
      Render.stateBoard(~game, state),
    )
    expect(stripColor(Render.board(~color=true, game)))->toBe(Render.board(game))
  })

  // A board with a red card in a fanned pile exercises the peeking face lines too, not
  // just the full cards a squared pile shows. FreeCell's cascades open seven deep, so
  // the opening deal is exactly that.
  test("holds for a fanned pile of many cards", () => {
    expect(stripColor(Render.board(~color=true, game)))->toBe(Render.board(game))
  })
})

// The board's *shape*: two role-grouped rows, each column headed by the name a typed
// move can address it by. Both are how the drawing tells you how to play it — a label
// that doesn't line up over its column, or one the parser wouldn't take, is worse than
// no label at all (the parser end is checked in `Command_test`).
describe("Render layout", () => {
  let game = Game.freecell
  let state = GameState.initial(game)
  let board = Render.stateBoard(~game, state)
  let sections = board->String.split("\n\n")

  // Sixteen columns in one row is wider than a terminal, and the two halves aren't the
  // same kind of thing: the free cells and foundations sit above the tableau, the way
  // the web table lays them out.
  test("a FreeCell board is drawn in two rows, cells and foundations above", () => {
    // Title, top row, bottom row.
    expect(Array.length(sections))->toBe(3)
    let top = sections->Array.getUnsafe(1)
    let bottom = sections->Array.getUnsafe(2)
    expect(has(top, "C1"))->toBe(true)
    expect(has(top, "F4"))->toBe(true)
    expect(has(top, "T1"))->toBe(false)
    expect(has(bottom, "T1"))->toBe(true)
    expect(has(bottom, "T8"))->toBe(true)
    // The dealt cards are all in the cascades, so the top row holds only empty slots.
    expect(has(bottom, `♠`) || has(bottom, `♥`))->toBe(true)
  })

  // A board carrying only one of the two groups keeps its single row: `roleRows` only
  // splits when both halves are non-empty.
  test("a board with one group of piles keeps its single row", () => {
    let cascadesOnly: Game.t = {
      ...game,
      piles: game.piles->Array.filter(p => p.role == Game.Cascade),
    }
    let rows =
      Render.stateBoard(~game=cascadesOnly, GameState.initial(cascadesOnly))->String.split("\n\n")
    // Title and the one pile row.
    expect(Array.length(rows))->toBe(2)
    expect(has(rows->Array.getUnsafe(1), "T1"))->toBe(true)
    expect(has(rows->Array.getUnsafe(1), "T8"))->toBe(true)
  })

  // Every column is headed by the name that slot answers to, and every name is there
  // exactly once — the labels and the piles are the same set.
  test("every pile is headed by its slot name", () =>
    Slot.labels(~game)->Array.forEach(
      label => {
        let heading = board->String.split("\n")->Array.filter(line => has(line, label))
        expect(Array.length(heading))->toBe(1)
      },
    )
  )

  // The headings are padded to the column width on *both* sides rather than merely
  // indented, which is what keeps the cards beneath them aligned: every line of a row —
  // the heading included — measures the same.
  test("a heading line is exactly as wide as the row it heads", () =>
    sections
    ->Array.slice(~start=1, ~end=Array.length(sections))
    ->Array.forEach(
      section => {
        let rows = section->String.split("\n")
        let width = String.length(rows->Array.getUnsafe(0))
        rows->Array.forEach(row => expect(String.length(row))->toBe(width))
      },
    )
  )

  // The label a board prints and the pile it's printed over are one fact (`Slot`), so
  // a player reading `T3` off the screen addresses the third cascade — pile 10 here.
  test("the printed labels are the ones the model answers to", () => {
    expect(Slot.labelAt(~game, 0))->toEqual(Some("C1"))
    expect(Slot.labelAt(~game, 7))->toEqual(Some("F4"))
    expect(Slot.labelAt(~game, 10))->toEqual(Some("T3"))
    expect(Slot.indexOf(~game, ~role=Game.Cascade, ~ordinal=3))->toEqual(Some(10))
  })
})

// --- The document ---------------------------------------------------------------
// What a front end that paints for itself actually receives.
describe("Render document", () => {
  let game = Game.freecellDeal(~seed=24680)
  let state = GameState.initial(game)
  let lines = Render.stateLines(~game, ~deal=24680, state)

  let spansOf = (lines: array<Render.line>): array<Render.span> => lines->Array.flat

  let inksOf = (lines, ink) =>
    spansOf(lines)->Array.filter((span: Render.span) => Render.sameInk(span.ink, ink))

  // The adapters and the string entry points are the same thing — which is what lets a
  // caller that only wants text stay on `stateBoard` and never learn about spans.
  test("toPlain is exactly what the string entry point returns", () => {
    expect(Render.toPlain(lines))->toBe(Render.stateBoard(~game, ~deal=24680, state))
    expect(Render.toAnsi(lines))->toBe(Render.stateBoard(~game, ~deal=24680, ~color=true, state))
    expect(Render.toPlain(Render.boardLines(game)))->toBe(Render.board(game))
  })

  // One row per line, and the document reassembles into the board with plain newlines:
  // a line carries no newline of its own, so a front end can put each in its own node.
  test("a line is exactly one row", () => {
    expect(lines->Array.every(line => !has(Render.toPlain([line]), "\n")))->toBe(true)
    expect(Array.length(lines))->toBe(
      Array.length(Render.stateBoard(~game, ~deal=24680, state)->String.split("\n")),
    )
  })

  // The heading is inked apart from the board's furniture, so a panel can style it
  // without parsing the text back out.
  test("the title is the first line, inked as a title", () => {
    expect(lines->Array.get(0)->Option.map(line => Render.toPlain([line])))->toEqual(
      Some("FreeCell — deal #24680"),
    )
    expect(Array.length(inksOf(lines, Render.Title)))->toBe(1)
  })

  // The claim a painter relies on: a face carries the model's own notion of the card's
  // colour, not a code and not a hex. `Rules.color` is the same function the alternating
  // -colour stacking rule is written against.
  test("every card face is inked with the model's card colour", () => {
    let red = inksOf(lines, Render.Suit(Rules.Red))
    let black = inksOf(lines, Render.Suit(Rules.Black))
    // A full FreeCell deal shows all 52 faces at once — half of each colour.
    expect(Array.length(red))->toBe(26)
    expect(Array.length(black))->toBe(26)
    // …and each one is a face, not a stray character of frame.
    expect(red->Array.every((s: Render.span) => has(s.text, `♥`) || has(s.text, `♦`)))->toBe(
      true,
    )
    expect(black->Array.every((s: Render.span) => has(s.text, `♠`) || has(s.text, `♣`)))->toBe(
      true,
    )
  })

  // Everything that isn't a face is furniture, and a painter is free to leave it alone.
  test("frames and gaps are plain", () => {
    let plain = inksOf(lines, Render.Plain)
    expect(Array.length(plain) > 0)->toBe(true)
    expect(
      plain->Array.every((s: Render.span) => !has(s.text, `♥`) && !has(s.text, `♠`)),
    )->toBe(true)
  })

  // Adjacent spans never share an ink: the assembly folds them together, so a front end
  // building one node per span builds a handful per line rather than one per card.
  test("neighbouring spans never share an ink", () => {
    let adjacentSame = lines->Array.some(
      line =>
        line->Array.someWithIndex(
          (span: Render.span, i) =>
            switch line->Array.get(i - 1) {
            | Some(prev) => Render.sameInk(prev.ink, span.ink)
            | None => false
            },
        ),
    )
    expect(adjacentSame)->toBe(false)
    // No empty spans either — they'd be nodes drawing nothing.
    expect(spansOf(lines)->Array.some((s: Render.span) => s.text == ""))->toBe(false)
  })

  // Alignment, which is the reason the layout has to measure anything at all. Colour used
  // to be baked into the characters, so a width had to discount escapes it couldn't see;
  // now a line's width is a sum and simply *is* the width of the row it prints.
  test("a line's width is the width of the row it prints", () => {
    let rows = Render.toPlain(lines)->String.split("\n")
    expect(
      lines->Array.everyWithIndex(
        (line, i) =>
          Render.visibleWidth(line) == rows->Array.get(i)->Option.getOr("")->String.length,
      ),
    )->toBe(true)
  })
})

// --- Ordinary prose as a document --------------------------------------------------
// `text` is what lets a front end keep *one* reply channel: a board is a document, and so
// is "Nothing to undo." — the second just has nothing but furniture in it.
describe("Render.text", () => {
  test("round-trips through toPlain", () => {
    expect(Render.toPlain(Render.text("Nothing to undo.")))->toBe("Nothing to undo.")
    let help = "Commands:\n  move <card> <pile>\n  print"
    expect(Render.toPlain(Render.text(help)))->toBe(help)
  })

  test("one row per line, all of it plain", () => {
    let doc = Render.text("first\nsecond")
    expect(Array.length(doc))->toBe(2)
    expect(
      doc->Array.every(
        line => line->Array.every((s: Render.span) => Render.sameInk(s.ink, Render.Plain)),
      ),
    )->toBe(true)
  })

  // A blank row carries no span at all — the same thing `compact` does with empty text
  // everywhere else, so a front end never makes a node that draws nothing.
  test("a blank row is an empty line", () => {
    let doc = Render.text("a\n\nb")
    expect(doc->Array.map(Array.length))->toEqual([1, 0, 1])
    expect(Render.toPlain(doc))->toBe("a\n\nb")
  })

  // The empty document is how a caller says nothing at all, which is distinct from a
  // document holding one empty row.
  test("an empty document renders as no rows", () => {
    let none: array<Render.line> = []
    expect(Array.length(none))->toBe(0)
    expect(Render.toPlain(none))->toBe("")
  })
})

// --- A third alphabet -------------------------------------------------------------
// The point of the document: a front end `core` has never heard of can paint it. This is
// the web console's painter in miniature — it inks by *role*, picking colours that suit
// its own medium (a dark panel) rather than the terminal's or the card table's — and it
// needs nothing from `core` but the spans.
describe("Render portability", () => {
  let game = Game.freecell
  let lines = Render.boardLines(game)

  let className = (ink: Render.ink) =>
    switch ink {
    | Render.Plain => "ink-plain"
    | Render.Suit(Rules.Red) => "ink-red"
    | Render.Suit(Rules.Black) => "ink-black"
    | Render.Title => "ink-title"
    }

  // Text and markup kept apart, the way the panel keeps them (it sets `textContent` on a
  // node it made, and never parses game data as HTML).
  let paint = (lines: array<Render.line>) =>
    lines
    ->Array.map(line =>
      line
      ->Array.map((span: Render.span) => `<span class="${className(span.ink)}">${span.text}</span>`)
      ->Array.join("")
    )
    ->Array.join("\n")

  test("a painter core has never heard of draws the same board", () => {
    let painted = paint(lines)
    // The red suits are reachable by role — which is all a stylesheet needs.
    expect(has(painted, `class="ink-red"`))->toBe(true)
    expect(has(painted, `class="ink-title"`))->toBe(true)
    // …and no terminal escape has leaked into a browser's alphabet.
    expect(has(painted, esc))->toBe(false)
    // Strip this painter's markup and the plain board comes back, exactly as stripping
    // the terminal's escapes does. Same document, two alphabets.
    let tags = /<[^>]*>/g
    expect(painted->String.replaceRegExp(tags, ""))->toBe(Render.board(game))
  })
})

// --- A move, in words ----------------------------------------------------------
// The line the debug console narrates a dispatched move with. It replaced the
// reducer's own action, stringified, so what's being pinned down is that it says the move
// the way the *board* says it: the verb you would type, the card's face, and the label
// printed over the pile rather than the index underneath it.
describe("Render.action", () => {
  let game = Game.freecell
  // Deal #1's layout: four free cells, four foundations, then the cascades — `C1` is
  // pile 0 and `T1` is pile 8.
  let say = action => Render.toPlain([Render.action(~game, action)])

  test("a move names its card and the label over its destination", () =>
    expect(say(Reducer.Move({card: {suit: Clubs, rank: Ten}, to: Reducer.ToPile(12)})))->toBe(
      "move 10♣ → T5",
    )
  )

  test("a run names every card it lifts", () =>
    expect(
      say(
        Reducer.MoveRun({
          cards: [{suit: Spades, rank: Nine}, {suit: Hearts, rank: Eight}],
          to: Reducer.ToPile(15),
        }),
      ),
    )->toBe("moverun 9♠ 8♥ → T8")
  )

  test("a column reorder names both columns", () =>
    expect(say(Reducer.MoveColumn({from: 9, to: 11})))->toBe("movecol T2 → T4")
  )

  // A pile the board prints no label over falls back to its index rather than to
  // nothing — the log still points somewhere.
  test("a pile with no label is named by its index", () =>
    expect(Render.pileName(~game, 99))->toBe("pile 99")
  )

  // The card is inked like its face on the board, which is the reason this is a document
  // and not a string: a log that paints a printed board can paint the move too.
  test("the card is inked by suit, and the rest is furniture", () => {
    let spans = Render.action(
      ~game,
      Reducer.Move({card: {suit: Hearts, rank: Two}, to: Reducer.ToPile(8)}),
    )
    expect(
      spans->Array.some((span: Render.span) => Render.sameInk(span.ink, Render.Suit(Rules.Red))),
    )->toBe(true)
    expect(
      spans
      ->Array.filter((span: Render.span) => !Render.sameInk(span.ink, Render.Plain))
      ->Array.map((span: Render.span) => span.text),
    )->toEqual(["2♥"])
  })
})
