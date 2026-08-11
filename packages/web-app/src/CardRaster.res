// The card sprite cache: a `Deck.card` in, a ready-to-blit bitmap out.
//
// The victory animation wants to fling hundreds of card images around at 60fps.
// A live `CardArt.svg` per card is 52 subtrees of text the compositor re-rasters
// on every transform, so the cards get rasterized *once*, up front, into
// offscreen `<canvas>` bitmaps that the animation then blits. This module is
// that cache; the `raster` scene (RasterScene) is the fidelity check on it.
//
// The whole difficulty is fonts. An SVG loaded through `<img>` renders in an
// isolated document with no access to the page's `@font-face` rules, and our
// card face is *almost entirely text* — the rank, the corner pip, the big middle
// suit glyph. Rasterized naively, every card comes out in a fallback face with
// tofu where the pips should be. There's no workaround from the outside, so
// there are exactly two ways in, and both are built here behind `strategy` so
// they can be compared side by side rather than argued about:
//
//   Svg    — serialize `CardArt.body` (the very same vnodes the app renders, via
//            `StaticRender`, exactly as the icon generator does) into a
//            standalone SVG carrying its own `@font-face` rules with the woff2
//            bytes inlined as base64. Self-contained, so the isolated document
//            has the faces after all. Card geometry keeps one source of truth.
//
//   Canvas — draw the face with the canvas 2D API: `roundRect` for the frame,
//            `fillText` for the glyphs. Canvas sees the *document's* fonts
//            natively, so there's nothing to embed — but it restates CardArt's
//            geometry in a second place, which is exactly the drift the icon
//            generator was built to avoid.
//
// **`Svg` is the one that won**, and it's the scene's default. Measured against
// the live card at card size (browser-tests/raster.spec.mjs, mean per-channel
// distance over five sample cards):
//
//   Svg     1.2-2.4 · 52 cards in ~270ms
//   Canvas  1.6-2.9 · 52 cards in ~80ms
//
// Canvas is three times quicker and still looks fine to the eye — but the build
// is a one-off before the animation starts, so 270ms buys nothing back, and it's
// worse on every card. It also had to be *taught* the card's geometry twice
// over, and that bill came due immediately: the middle glyph originally rebuilt
// the art's `dominant-baseline="central"` from `measureText()`, which agreed with
// the SVG engine on Linux and missed it by 4.5 design units on macOS — a
// visible-at-card-size difference that the browser suite, running on Linux,
// could not see. The fix was to stop deriving the number on either side;
// `CardArt.centerGlyphBaseline` now states it, and both strategies read it.
// Canvas is kept, switchable, and budgeted in the browser suite, because it's the
// fallback if the embedded-font path ever stops working somewhere — but the
// default reuses the real card art.
//
// Two details that bite:
//   - `CardArt.svg` emits only a `viewBox`. An SVG with no intrinsic size
//     rasterizes inconsistently through `<img>` (engines fall back to different
//     default sizes), so `markup` below always writes explicit `width`/`height`.
//   - `img.decode()` is async, so building the cache is a promise. Callers await
//     the whole 52-card set before their first frame.

// --- Strategy ----------------------------------------------------------------

type strategy = Svg | Canvas

let strategyId = strategy =>
  switch strategy {
  | Svg => "svg"
  | Canvas => "canvas"
  }

let strategyLabel = strategy =>
  switch strategy {
  | Svg => "SVG + embedded font"
  | Canvas => "Canvas 2D"
  }

// Parse the `?raster=` URL knob, so a link can open the scene on either strategy
// — which is how the browser suite shoots them both without clicking. Anything
// unrecognised reads as `None` and leaves the scene's own default in place.
let strategyFromString = value =>
  switch value {
  | "svg" => Some(Svg)
  | "canvas" => Some(Canvas)
  | _ => None
  }

// --- Bindings ----------------------------------------------------------------
// Canvas, `<img>` decoding, `fetch`, and the font-loading API. All kept here
// rather than in WebDom: WebDom is the shared *element* vocabulary the scenes
// speak, and none of this is useful outside rasterization.

type canvas
type context
type image
type response
type buffer
type bytes
type fontFaceSet
type fontFace

@val @scope("document") external createCanvas: string => canvas = "createElement"
// A canvas *is* an element; the identity cast lets the scene splice a sprite
// straight into a vnode tree with `Html.node`.
external canvasElement: canvas => WebDom.element = "%identity"

@set external setPixelWidth: (canvas, int) => unit = "width"
@set external setPixelHeight: (canvas, int) => unit = "height"
@send external getContext: (canvas, string) => Nullable.t<context> = "getContext"

@send external save: context => unit = "save"
@send external restore: context => unit = "restore"
@send external scale: (context, float, float) => unit = "scale"
@send external translate: (context, float, float) => unit = "translate"
@send external beginPath: context => unit = "beginPath"
@send external roundRect: (context, float, float, float, float, float) => unit = "roundRect"
@send external fill: context => unit = "fill"
@send external stroke: context => unit = "stroke"
@send external fillText: (context, string, float, float) => unit = "fillText"
@send external drawImage: (context, image, float, float, float, float) => unit = "drawImage"
@set external setFillStyle: (context, string) => unit = "fillStyle"
@set external setStrokeStyle: (context, string) => unit = "strokeStyle"
@set external setLineWidth: (context, float) => unit = "lineWidth"
@set external setFont: (context, string) => unit = "font"
@set external setTextAlign: (context, string) => unit = "textAlign"
@set external setTextBaseline: (context, string) => unit = "textBaseline"

@new external makeImage: unit => image = "Image"
@set external setSrc: (image, string) => unit = "src"
@send external decode: image => promise<unit> = "decode"

@val external fetch: string => promise<response> = "fetch"
@send external arrayBuffer: response => promise<buffer> = "arrayBuffer"
@new external bytesOf: buffer => bytes = "Uint8Array"
@get external byteCount: bytes => int = "length"
@get_index external byteAt: (bytes, int) => int = ""
@val external charOf: int => string = "String.fromCharCode"
@val external btoa: string => string = "btoa"
@val external encodeURIComponent: string => string = "encodeURIComponent"

// The document's font set — the Canvas strategy's whole reason for existing, and
// the thing it has to *wait* for: `fillText` with an unloaded face silently
// paints the fallback rather than blocking.
@val @scope("document") external documentFonts: fontFaceSet = "fonts"
@send external loadFont: (fontFaceSet, string, string) => promise<array<fontFace>> = "load"
@get external fontsReady: fontFaceSet => promise<fontFaceSet> = "ready"

// Resolve a font URL the way index.html's own `@font-face` rules do — relative to
// the document — so it inherits the GitHub Pages project subpath instead of
// hardcoding a root-absolute path that only works at a domain root.
type url
@new external makeUrl: (string, string) => url = "URL"
@get external urlHref: url => string = "href"
@val @scope("document") external baseUri: string = "baseURI"

@val @scope("window") external devicePixelRatio: float = "devicePixelRatio"

// --- The faces the card face uses --------------------------------------------
// Only these two: the rank (and its corner pip's sibling) is Libre Franklin 600,
// the suit glyphs are the merged "Pip Suits" subset. Both are vendored into
// public/fonts by `mise run fonts` (#114). Weight is spelled out because the
// embedded copy has to declare the same weight the card art asks for — a
// `@font-face` at the default 400 wouldn't match `font-weight: 600` text.
let faces = [
  ("Libre Franklin", "600", "libre-franklin-600.woff2"),
  ("Pip Suits", "400", "pip-suits.woff2"),
]

// The glyphs the card face can ask for, so the Canvas strategy can pre-load
// exactly the coverage it needs rather than the whole face.
let rankGlyphs = "A234567890JQK"
let suitGlyphs = `♠♥♦♣`

// The canvas-side spelling of the two faces, as CSS font shorthand.
let rankFont = size => `600 ${Float.toString(size)}px "Libre Franklin", sans-serif`
let suitFont = size => `${Float.toString(size)}px "Pip Suits"`

// --- Strategy 1: a self-contained SVG with the faces inlined -----------------

// `btoa` wants a binary string, so walk the bytes. 16KB a face, twice, once per
// page — small enough that a plain loop is the honest implementation.
let base64 = (buf: buffer) => {
  let bytes = bytesOf(buf)
  let count = byteCount(bytes)
  let binary = ref("")
  for i in 0 to count - 1 {
    binary := binary.contents ++ charOf(byteAt(bytes, i))
  }
  btoa(binary.contents)
}

let fontUrl = file => makeUrl("./fonts/" ++ file, baseUri)->urlHref

// Fetch every face and render it as `@font-face` rules with the bytes inline.
// Deliberately *without* the stylesheet's `unicode-range` on Pip Suits: that
// exists in the page to keep the subset from shadowing Latin text, and inside a
// one-card SVG there's nothing to shadow.
let buildFontCss = async () => {
  let rules = await faces
  ->Array.map(async ((family, weight, file)) => {
    let response = await fetch(fontUrl(file))
    let encoded = base64(await response->arrayBuffer)
    `@font-face{font-family:"${family}";font-style:normal;font-weight:${weight};` ++
    `src:url(data:font/woff2;base64,${encoded}) format("woff2");}`
  })
  ->Promise.all
  rules->Array.join("")
}

// The fetch+encode is per-page, not per-card, so memoize the *promise*: 52 cards
// built concurrently all await the same one fetch.
let fontCss: ref<option<promise<string>>> = ref(None)

let embeddedFontCss = () =>
  switch fontCss.contents {
  | Some(pending) => pending
  | None =>
    let pending = buildFontCss()
    fontCss := Some(pending)
    pending
  }

// One card as standalone SVG markup: the real `CardArt.body` vnodes, an explicit
// pixel size (see the header — a viewBox alone rasterizes inconsistently), and
// the embedded faces in a `<style>`.
let markup = (~fontCss, ~pxWidth, ~pxHeight, card) =>
  StaticRender.toString(
    <svg
      attrs={[
        ("xmlns", "http://www.w3.org/2000/svg"),
        ("width", Int.toString(pxWidth)),
        ("height", Int.toString(pxHeight)),
        ("viewBox", CardArt.viewBox),
      ]}
    >
      <style> {Html.string(fontCss)} </style>
      {CardArt.body(card)}
    </svg>,
  )

// `encodeURIComponent` rather than base64 for the outer document: the suit glyphs
// are non-ASCII, which `btoa` can't take without a second UTF-8 dance.
let dataUrl = svg => "data:image/svg+xml;charset=utf-8," ++ encodeURIComponent(svg)

// --- Strategy 2: the same face, drawn with canvas 2D -------------------------

// A restatement of `CardArt.body` in canvas calls, in the same design-box units
// (the caller has already scaled the context), which is this strategy's whole
// cost: these numbers have to be kept in step with the vnodes by hand. The ones
// CardArt publishes as bindings are reused; the ones it writes as attribute
// literals (the corner's 5/38/40, the pip's 106/34/26) are restated, and that is
// the drift the `raster` scene exists to show.
let paintFace = (ctx, card: Deck.card) => {
  let color = Deck.suitColor(card.suit)
  let label = Deck.rankLabel(card.rank)
  let glyph = Deck.suitSymbol(card.suit)

  // The frame: the same inset-by-half-a-stroke rect the card art draws, so the
  // painted outer edge lands on the design box's edge.
  ctx->beginPath
  ctx->roundRect(
    CardArt.frameInset,
    CardArt.frameInset,
    CardArt.boxW -. CardArt.strokeW,
    CardArt.boxH -. CardArt.strokeW,
    CardArt.cornerR,
  )
  ctx->setFillStyle("#f7f7f7")
  ctx->fill
  ctx->setStrokeStyle("#cbd5e1")
  ctx->setLineWidth(CardArt.strokeW)
  ctx->stroke

  ctx->setFillStyle(color)

  // The corner rank plus its right-pinned suit pip. SVG `<text>` places its
  // baseline at `y` and canvas's default `textBaseline` is "alphabetic", so the
  // coordinates carry over unchanged; the pip's `text-anchor="end"` becomes
  // `textAlign = "right"`.
  let cornerRank = () => {
    ctx->setFont(rankFont(40.))
    ctx->setTextAlign("start")
    ctx->setTextBaseline("alphabetic")
    ctx->fillText(label, 5., 38.)
    ctx->setFont(suitFont(26.))
    ctx->setTextAlign("right")
    ctx->fillText(glyph, 106., 34.)
  }

  cornerRank()

  // The middle glyph, on the baseline `CardArt` publishes. This used to rebuild
  // the art's `dominant-baseline="central"` here from `measureText()`, which is
  // the drift this strategy was expected to produce arriving for real: the sprite
  // sat 4.5 design units above the live card on macOS while matching it on Linux.
  // `CardArt.centerGlyphBaseline` (see its comment — the cause turned out to be
  // worth writing down) settles the number in one place, so there is nothing left
  // here for a renderer to resolve differently.
  ctx->setFont(suitFont(CardArt.centerGlyphSize))
  ctx->setTextAlign("center")
  ctx->setTextBaseline("alphabetic")
  ctx->fillText(glyph, CardArt.centerX, CardArt.centerGlyphBaseline)

  // The bottom-right corner is the top-left one turned 180° about the card's
  // centre — the same trick the vnodes use, so the two corners can't drift apart.
  //
  // `scale(-1, -1)` rather than the `rotate(pi)` that reads more naturally,
  // because `rotate` goes through `sin`/`cos` and `Math.sin(pi)` is not 0 — it's
  // 1.2246e-16. The resulting matrix carries that as an off-diagonal term, so
  // the CTM is *very nearly* axis-aligned rather than exactly so, and a text
  // rasterizer that grid-fits axis-aligned glyph runs (Skia's `rectStaysRect`
  // fast path) can take one route for the upright corner drawn under the
  // identity and another for this one. That is a sub-pixel vertical split
  // between the two corners of a single card, visible only on the rotated half
  // — which is what the raster scene was reported showing on macOS, where the
  // two SVG renderings agreed with each other and only Canvas 2D's bottom
  // corner sat differently.
  //
  // `scale(-1, -1)` is the same geometry with an exactly axis-aligned matrix
  // (the off-diagonal terms are 0, not 1e-16), so both corners are the same kind
  // of transform. Chromium on Linux renders the two spellings byte-for-byte
  // identically, so this is not *confirmed* to be the macOS cause — but the
  // inexactness is real, it costs nothing to remove, and an exact matrix is
  // what this code meant to ask for either way.
  ctx->save
  ctx->translate(CardArt.centerX, CardArt.centerY)
  ctx->scale(-1., -1.)
  ctx->translate(-.CardArt.centerX, -.CardArt.centerY)
  cornerRank()
  ctx->restore
}

// Make sure the document actually has the faces before `fillText` runs — an
// unloaded face paints the fallback silently rather than waiting.
let ensureDocumentFonts = async () => {
  let _ = await Promise.all([
    documentFonts->loadFont(rankFont(40.), rankGlyphs),
    documentFonts->loadFont(suitFont(CardArt.centerGlyphSize), suitGlyphs),
  ])
  let _ = await documentFonts->fontsReady
}

// --- The cache ---------------------------------------------------------------

// One card's bitmap. `canvas` is sized in *device* pixels; `cssWidth`/`cssHeight`
// are the size it's meant to be shown at, so a consumer can place it without
// re-deriving the ratio.
type sprite = {
  canvas: canvas,
  cssWidth: float,
  cssHeight: float,
}

type t = {
  strategy: strategy,
  cssWidth: float,
  pixelRatio: float,
  // How long building all of them took, in ms — the other half of "pick by
  // looking": one strategy can win on fidelity and lose badly on cost.
  elapsedMs: float,
  sprites: Dict.t<sprite>,
}

// Cards are values, not references, so key on the name they already publish.
let key = (card: Deck.card) => Deck.cardName(card)

let get = (cache, card) => cache.sprites->Dict.get(key(card))

let element = sprite => canvasElement(sprite.canvas)

// A blank canvas at the sprite's device-pixel size, with its CSS size pinned so
// it lays out at exactly the width the live SVG beside it gets.
let blankCanvas = (~pxWidth, ~pxHeight, ~cssWidth, ~cssHeight) => {
  let canvas = createCanvas("canvas")
  canvas->setPixelWidth(pxWidth)
  canvas->setPixelHeight(pxHeight)
  canvas
  ->canvasElement
  ->WebDom.setAttribute(
    "style",
    `display:block;width:${Float.toString(cssWidth)}px;height:${Float.toString(cssHeight)}px`,
  )
  canvas
}

let rasterizeSvg = async (~fontCss, ~pxWidth, ~pxHeight, ~cssWidth, ~cssHeight, card) => {
  let img = makeImage()
  img->setSrc(dataUrl(markup(~fontCss, ~pxWidth, ~pxHeight, card)))
  await img->decode
  let canvas = blankCanvas(~pxWidth, ~pxHeight, ~cssWidth, ~cssHeight)
  switch canvas->getContext("2d")->Nullable.toOption {
  | Some(ctx) => ctx->drawImage(img, 0., 0., Int.toFloat(pxWidth), Int.toFloat(pxHeight))
  | None => ()
  }
  canvas
}

let paintCanvas = (~pxWidth, ~pxHeight, ~cssWidth, ~cssHeight, card) => {
  let canvas = blankCanvas(~pxWidth, ~pxHeight, ~cssWidth, ~cssHeight)
  switch canvas->getContext("2d")->Nullable.toOption {
  | Some(ctx) =>
    // Scale once, then draw in the card's own design-box units — the same units
    // the vnodes are written in, so the two are comparable line for line.
    ctx->scale(Int.toFloat(pxWidth) /. CardArt.boxW, Int.toFloat(pxHeight) /. CardArt.boxH)
    paintFace(ctx, card)
  | None => ()
  }
  canvas
}

// Build the whole cache. `~cssWidth` is the width a card is shown at; the bitmaps
// come out at `~pixelRatio` times that, so they're crisp on a retina screen and
// can be blitted 1:1.
let build = async (~strategy, ~cssWidth, ~pixelRatio=devicePixelRatio, cards) => {
  let started = Date.now()
  let cssHeight = cssWidth *. CardArt.aspect
  let pxWidth = Math.round(cssWidth *. pixelRatio)->Float.toInt
  let pxHeight = Math.round(cssHeight *. pixelRatio)->Float.toInt

  let built = switch strategy {
  | Svg =>
    let fontCss = await embeddedFontCss()
    await cards
    ->Array.map(async card => (
      key(card),
      await rasterizeSvg(~fontCss, ~pxWidth, ~pxHeight, ~cssWidth, ~cssHeight, card),
    ))
    ->Promise.all
  | Canvas =>
    await ensureDocumentFonts()
    cards->Array.map(card => (
      key(card),
      paintCanvas(~pxWidth, ~pxHeight, ~cssWidth, ~cssHeight, card),
    ))
  }

  let sprites = Dict.make()
  built->Array.forEach(((name, canvas)) => sprites->Dict.set(name, {canvas, cssWidth, cssHeight}))

  {strategy, cssWidth, pixelRatio, elapsedMs: Date.now() -. started, sprites}
}
