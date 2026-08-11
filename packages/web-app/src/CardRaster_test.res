// The half of `CardRaster` that isn't pixels: the standalone SVG document it
// serializes a card into (#225).
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

let svg = () => CardRaster.markup(~fontCss, ~pxWidth=160, ~pxHeight=224, card)

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

  test("escapes into a data URL that survives the non-ASCII pips", () => {
    let url = CardRaster.dataUrl(svg())
    expect(url->String.startsWith("data:image/svg+xml;charset=utf-8,"))->toBe(true)
    // `♠` is U+2660 — percent-encoded as UTF-8, never passed through raw.
    expect(url->has("%E2%99%A0"))->toBe(true)
    expect(url->has(`♠`))->toBe(false)
  })
})

describe("CardRaster strategy names", () => {
  test("round-trip through the `?raster=` URL knob", () => {
    [CardRaster.Svg, CardRaster.Canvas]->Array.forEach(
      strategy =>
        expect(CardRaster.strategyFromString(CardRaster.strategyId(strategy)))->toEqual(
          Some(strategy),
        ),
    )
  })

  test("an unknown name is ignored rather than guessed at", () => {
    expect(CardRaster.strategyFromString("webgl"))->toEqual(None)
  })
})
