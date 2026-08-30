// The half of `CardRaster` that isn't pixels: the standalone SVG document it
// serializes a card into.
//
// The rasterization itself needs a real engine — an `<img>` decode, a canvas,
// and the actual font files — so its fidelity is measured in the browser suite
// (browser-tests/raster.spec.mjs). What can be pinned here, cheaply and without
// one, is the *shape of the document* that gets handed to the engine, and it's
// worth pinning because every one of these is a silent failure rather than a
// crash: an SVG with no intrinsic size rasterizes at whatever the engine feels
// like, an SVG with no `xmlns` isn't an SVG at all through `<img>`, and an SVG
// whose `@font-face` block went missing renders in a fallback face with tofu
// where the pips should be. All three produce a picture; none produces an error.
open Vitest

let card: Deck.card = {suit: Deck.Spades, rank: Deck.Ace}

// Stand-in for the real (very long, base64) rules — this module's job is to
// place the CSS, not to produce it.
let fontCss = "@font-face{font-family:\"Pip Suits\";src:url(data:font/woff2;base64,AAA)}"

// A one-card sheet: same document the deck-sized one is, with a 1x1 grid, so the
// structural checks below read without grid arithmetic in them.
let svg = () => CardRaster.markup(~fontCss, ~pxWidth=160, ~pxHeight=224, ~columns=1, [card])

let has = (haystack, needle) => haystack->String.includes(needle)

describe("CardRaster's standalone SVG", () => {
  test("carries an intrinsic pixel size as well as the viewBox", () => {
    let markup = svg()
    // `CardArt.svg` emits only a viewBox, which is fine inline and not fine
    // through `<img>`; these two are the difference.
    expect(markup->has(`width="160"`))->toBe(true)
    expect(markup->has(`height="224"`))->toBe(true)
    expect(markup->has(`viewBox="${CardArt.viewBox}"`))->toBe(true)
  })

  test("declares the SVG namespace, so <img> parses it as SVG", () => {
    expect(svg()->has(`xmlns="http://www.w3.org/2000/svg"`))->toBe(true)
  })

  test("embeds the font rules inside the document", () => {
    expect(svg()->has(`<style>${fontCss}</style>`))->toBe(true)
  })

  test("draws the real card face, not a restatement of it", () => {
    // The whole point of this strategy is that the geometry has one source: the
    // markup has to *contain* `CardArt.body`'s output verbatim. Compare against
    // the body itself rather than against copied-out literals, so this keeps
    // holding as the card design changes.
    expect(svg()->has(StaticRender.toString(CardArt.body(card))))->toBe(true)
  })

  test("places the middle glyph without asking the renderer to read font metrics", () => {
    // `dominant-baseline="central"` resolves against the font's vertical metrics,
    // and Pip Suits ships two pairs of those half an em apart (see
    // `CardArt.centerGlyphBaseline`). Which pair a renderer believes is its own
    // business, so the card art states the baseline instead — and this is the
    // check that it keeps doing so, because every renderer that disagrees fails
    // silently, by drawing the pip somewhere else.
    let markup = svg()
    expect(markup->has("dominant-baseline"))->toBe(false)
    expect(markup->has(`y="${CardArt.centerGlyphBaseline->Float.toString}"`))->toBe(true)
  })

  test("lays the deck out on one grid, at one card's size per cell", () => {
    // The sheet is why this strategy is fast: one document, one font parse, one
    // decode, then blitted apart. The pixel size has to be the grid's, the
    // viewBox has to be the grid's in design units, and each card has to be
    // translated to its own cell — get any of those wrong and cards land on top
    // of each other, or the sprites are cut from the wrong place.
    let cards = [
      {Deck.suit: Deck.Spades, rank: Deck.Ace},
      {Deck.suit: Deck.Hearts, rank: Deck.Two},
      {Deck.suit: Deck.Clubs, rank: Deck.King},
    ]
    let sheet = CardRaster.markup(~fontCss, ~pxWidth=160, ~pxHeight=224, ~columns=2, cards)
    // 3 cards over 2 columns is a 2x2 grid.
    expect(sheet->has(`width="320"`))->toBe(true)
    expect(sheet->has(`height="448"`))->toBe(true)
    expect(sheet->has(`viewBox="0 0 240 336"`))->toBe(true)
    // Cells in design-box units, row-major: (0,0) (120,0) (0,168).
    expect(sheet->has(`transform="translate(0 0)"`))->toBe(true)
    expect(sheet->has(`transform="translate(120 0)"`))->toBe(true)
    expect(sheet->has(`transform="translate(0 168)"`))->toBe(true)
  })

  test("carries the embedded faces once, not once per card", () => {
    // The point of the sheet. 52 copies of the base64 woff2 was the old cost.
    let cards = Deck.allCards
    let sheet = CardRaster.markup(~fontCss, ~pxWidth=160, ~pxHeight=224, ~columns=8, cards)
    let occurrences = sheet->String.split(fontCss)->Array.length - 1
    expect(occurrences)->toBe(1)
    // …and it really is the whole deck in there.
    expect(sheet->String.split("<g ")->Array.length - 1)->toBe(Array.length(cards))
  })

  test("escapes into a data URL that survives the non-ASCII pips", () => {
    let url = CardRaster.dataUrl(svg())
    expect(url->String.startsWith("data:image/svg+xml;charset=utf-8,"))->toBe(true)
    // `♠` is U+2660 — percent-encoded as UTF-8, never passed through raw.
    expect(url->has("%E2%99%A0"))->toBe(true)
    expect(url->has(`♠`))->toBe(false)
  })
})
