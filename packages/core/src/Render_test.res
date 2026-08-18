// The text renderer, now that it's `core`'s: one board drawing served to a terminal and
// to the web app's debug console (#273). It moved here from `packages/cli` when the
// console's `print` stopped answering "the board is on screen" and started showing one.
//
// The property that matters most is the one the move introduced: **colour is a front
// end's choice**, because ANSI escapes are a terminal's alphabet and a browser panel
// would show them as garbage. What `core` renders is a *document* — lines of spans, each
// tagged with the role its characters play — and each front end paints that in its own
// alphabet. So the tests come in two layers:
//
//   - the **document**: are the spans inked with what a painter needs to know, and is a
//     line still measurable and aligned now that colour isn't in its characters?
//   - the **adapters**: does `toPlain` still give exactly the string every caller before
//     the document existed was getting, and does `toAnsi` differ from it in colour and
//     nothing else?
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
    let game = Game.stacking
    let state = GameState.initial(game)
    // Found pile 0 with the Ace of Spades via the reducer.
    let moved = switch Reducer.reduce(
      ~game,
      state,
      Move({card: {suit: Spades, rank: Ace}, to: ToPile(0)}),
    ) {
    | Ok(next) => next
    | Error(_) => state
    }
    let board = Render.stateBoard(~game, moved)
    expect(has(board, game.name))->toBe(true)
    expect(has(board, `A♠`))->toBe(true)
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
  // just the full cards a squared pile shows.
  test("holds for a fanned pile of many cards", () => {
    let fanned = Game.stacking
    expect(stripColor(Render.board(~color=true, fanned)))->toBe(Render.board(fanned))
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

// --- A third alphabet -------------------------------------------------------------
// The point of the document: a front end `core` has never heard of can paint it. This is
// the web console's painter in miniature — it inks by *role*, picking colours that suit
// its own medium (a dark panel) rather than the terminal's or the card table's — and it
// needs nothing from `core` but the spans.
describe("Render portability", () => {
  let game = Game.stacking
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
