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
// tofu where the pips should be. There's no workaround from the outside, so the
// SVG has to carry the faces itself: `markup` serializes `CardArt.body` (the very
// same vnodes the app renders, via `StaticRender`, exactly as the icon generator
// does) with the woff2 bytes inlined as base64 in a `<style>`. Self-contained, so
// the isolated document has the faces after all — and it reuses the real card
// art, so the sprite can't drift from the card the game draws.
//
// The whole deck goes into *one* document laid out as a grid. See `markup` for
// why: it is the difference between a ~60ms build and a ~400ms one, and it costs
// nothing. That sheet is then *kept* as the source texture every sprite is drawn
// from — a card is a rectangle of it, blitted with `drawImage`'s nine-argument
// form (#226). A standalone per-card canvas is cut only when a consumer needs a
// DOM node; see `sprite`.
//
// This was one of two strategies for a while (#225). The other painted the face
// with the canvas 2D API — `roundRect` and `fillText`, no font embedding needed
// because canvas sees the document's own fonts — and the `raster` scene existed
// to pick between them by looking. It lost, and was removed once it had. It was
// quicker before the sheet (~50ms against ~400ms), which was its whole case; it
// was also worse against the live card on every sample, and it had to restate
// CardArt's geometry in a second place, which cost two real bugs in the space of
// one pull request — a middle glyph 4.5 design units high on macOS from rebuilding
// `dominant-baseline="central"` out of `measureText()`, and a corner turned with
// `rotate(pi)` whose matrix isn't exactly axis-aligned. Both were invisible to a
// Linux CI. The scene still compares the sprite against the live card, which is
// the comparison that was always doing the work.
//
// Two details that bite:
//   - `CardArt.svg` emits only a `viewBox`. An SVG with no intrinsic size
//     rasterizes inconsistently through `<img>` (engines fall back to different
//     default sizes), so `markup` below always writes explicit `width`/`height`.
//   - `img.decode()` is async, so building the cache is a promise. Callers await
//     the whole 52-card set before their first frame.

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

@val @scope("document") external createCanvas: string => canvas = "createElement"
// A canvas *is* an element; the identity casts let a scene splice a sprite
// straight into a vnode tree with `Html.node`, and hand a `<canvas>` it built
// itself (through `WebDom`, like every other node it owns) back here to be drawn
// into. Both directions are the same object — only the ReScript type differs.
external canvasElement: canvas => WebDom.element = "%identity"
external elementCanvas: WebDom.element => canvas = "%identity"

@set external setPixelWidth: (canvas, int) => unit = "width"
@set external setPixelHeight: (canvas, int) => unit = "height"
@send external getContext: (canvas, string) => Nullable.t<context> = "getContext"

@send external drawImage: (context, image, float, float, float, float) => unit = "drawImage"
// `drawImage`'s nine-argument form, cropping a source rectangle — how a card is
// lifted out of the rasterized sheet (see `markup`). Source is a canvas, not an
// image: the sheet is rasterized once into one, and blitting from that is a copy
// rather than 52 fresh rasterizations of the same SVG.
@send
external drawCanvasPart: (
  context,
  canvas,
  float,
  float,
  float,
  float,
  float,
  float,
  float,
  float,
) => unit = "drawImage"

@new external makeImage: unit => image = "Image"
@set external setSrc: (image, string) => unit = "src"
@send external decode: image => promise<unit> = "decode"

@val external fetch: string => promise<response> = "fetch"
@send external arrayBuffer: response => promise<buffer> = "arrayBuffer"
@get external responseOk: response => bool = "ok"
@get external responseStatus: response => int = "status"
@new external bytesOf: buffer => bytes = "Uint8Array"
@get external byteCount: bytes => int = "length"
@get_index external byteAt: (bytes, int) => int = ""
@val external charOf: int => string = "String.fromCharCode"
@val external btoa: string => string = "btoa"
@val external encodeURIComponent: string => string = "encodeURIComponent"

// Resolve a font URL the way index.html's own `@font-face` rules do — relative to
// the document — so it inherits the GitHub Pages project subpath instead of
// hardcoding a root-absolute path that only works at a domain root.
type url
@new external makeUrl: (string, string) => url = "URL"
@get external urlHref: url => string = "href"
@val @scope("document") external baseUri: string = "baseURI"

// Read off `globalThis` rather than as a bare `window.devicePixelRatio`, the same
// way TableScene looks up `ResizeObserver`: a missing global then reads as
// `undefined` (→ `None` → the 1× fallback) instead of throwing a `ReferenceError`
// where there's no window at all.
@val @scope("globalThis") external devicePixelRatioValue: Nullable.t<float> = "devicePixelRatio"

let deviceRatio = () => devicePixelRatioValue->Nullable.toOption->Option.getOr(1.)

// The cap on the pixel ratio anything is rasterized at (#226). The raw device
// ratio is *not* a small number in the wild — browser zoom multiplies it, and a
// Retina Mac one zoom step in reports 3.75 — so an uncapped sprite sheet grows as
// the square of a number the player controls, for a card the size of a thumbnail.
//
// The cap has to be one number for the whole pipeline, not a canvas-local choice.
// The victory overlay sizes its backing store at `cssSize × ratio` and blits
// sprites into it 1:1; if the sprites were built at the raw ratio and the overlay
// capped, every blit would be a downscale, and if it were the other way round
// every blit would be a blur. So the overlay and `build` below read the same
// `renderRatio`, and the `trail` scene's 1×/2×/3× toggle is the check that 2 is
// far enough — that a card capped at 2× is indistinguishable from one drawn at
// the screen's full ratio.
let maxPixelRatio = 2.

// The ratio to rasterize at: a device ratio held under a cap. Split from the
// reading of `devicePixelRatio` so the arithmetic — the one thing here that can
// be wrong rather than merely environmental — can be checked without a screen.
let cappedRatio = (~cap, ~device) => Math.min(device, cap)

// This screen's ratio under a cap. The cap is spelled out at every call rather
// than defaulted, because the whole point is that one number is shared: a caller
// naming `maxPixelRatio` is saying which cap it agreed to, and the `trail`
// scene's 1×/2×/3× passes its own to look at the difference.
let renderRatio = (~cap) => cappedRatio(~cap, ~device=deviceRatio())

// The 2D context of a canvas, or `None` where there isn't one to be had.
// Everything that draws goes through here rather than calling `getContext`
// directly: jsdom has no rasterizer behind `<canvas>`, so under the unit tests
// this is genuinely `None`, and a `None` arm is the difference between a scene
// that mounts empty and one that throws on the way up. The `globalThis` lookup is
// the same guard TableScene puts in front of `ResizeObserver` — an environment
// with no canvas at all is never even asked.
@val @scope("globalThis") external contextCtor: Nullable.t<unit> = "CanvasRenderingContext2D"

let context2d = canvas =>
  switch contextCtor->Nullable.toOption {
  | None => None
  | Some(_) => canvas->getContext("2d")->Nullable.toOption
  }

// --- The faces the card face uses --------------------------------------------
// Only these two: the rank (and its corner pip's sibling) is Libre Franklin 600,
// the suit glyphs are the merged "Pip Suits" subset. Both are vendored into
// public/fonts by `mise run fonts` (#114). Weight is spelled out because the
// embedded copy has to declare the same weight the card art asks for — a
// `@font-face` at the default 400 wouldn't match `font-weight: 600` text.
//
// These are the faces the *page* serves, deliberately, rather than anything cut
// down for embedding. Subsetting the rank face to just the thirteen characters a
// rank label can be is tempting — it is 15.6KB against 3.0KB — but measured, the
// subset rasterizes a little differently from the face the live card is drawn
// with (0.08-0.66 mean channel difference per rank, and every card shows a rank
// twice), which is a fidelity loss in the one strategy whose whole claim is
// fidelity. The size mattered when each card was its own document; `markup` puts
// the deck in one, so it doesn't any more.
let faces = [
  ("Libre Franklin", "600", "libre-franklin-600.woff2"),
  ("Pip Suits", "400", "pip-suits.woff2"),
]

// --- The self-contained SVG -------------------------------------------------

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
// exists in the page to keep the subset from shadowing Latin text, and inside
// the sprite sheet there's nothing to shadow.
//
// A face that doesn't fetch is checked for rather than trusted, because the
// failure is otherwise invisible: an empty `src:url(data:font/woff2;base64,)`
// is a *valid* `@font-face` that simply never loads, so the SVG falls through to
// the `sans-serif` in the card art's font stack and every rank quietly renders
// in the wrong typeface. The cards still look like cards. Raising here instead
// puts it on the scene's error line, which is what that line is for.
let buildFontCss = async () => {
  let rules = await faces
  ->Array.map(async ((family, weight, file)) => {
    let url = fontUrl(file)
    let response = await fetch(url)
    if !(response->responseOk) {
      panic(`couldn't fetch ${file} (HTTP ${response->responseStatus->Int.toString})`)
    }
    let bytes = await response->arrayBuffer
    if byteCount(bytesOf(bytes)) == 0 {
      panic(`${file} fetched empty`)
    }
    let encoded = base64(bytes)
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

// How many cards a sheet lays out per row. Any value renders the same picture —
// see `markup` for why there is a sheet at all — so this is only a shape choice:
// 8 puts the 52-card deck in a 1280x1568 bitmap at card size on a 2x screen,
// comfortably inside every engine's maximum, and keeps it roughly square so no
// single dimension grows fast if the card size or the pixel ratio goes up.
let sheetColumns = 8

let sheetRows = (~columns, count) => (count + columns - 1) / columns

// The cards as *one* SVG document: a grid of `CardArt.body` vnodes, an explicit
// pixel size (see the header — a viewBox alone rasterizes inconsistently), and
// the embedded faces in a single `<style>`.
//
// One document rather than one per card is the whole performance story of this
// strategy. Each `<img>`-rasterized SVG is an isolated document: it parses its
// own copy of the embedded woff2 faces, and shares nothing with its siblings —
// so a card per document meant decoding the same ~22KB of font bytes 52 times
// and standing up 52 documents to draw one card each. Measured, that is ~230ms
// against ~28ms for the sheet, and the sheet's output is the same picture: every
// cell sits at an integer device-pixel offset and is drawn at the same scale, so
// each card rasterizes exactly as it did standalone (worst per-card mean channel
// difference between the two, over the deck: 0.0018/255).
//
// `~pxWidth`/`~pxHeight` are one *card's* size; the sheet is that times the grid.
let markup = (~fontCss, ~pxWidth, ~pxHeight, ~columns, cards) => {
  let rows = sheetRows(~columns, Array.length(cards))
  let n = Float.toString
  StaticRender.toString(
    <svg
      attrs={[
        ("xmlns", "http://www.w3.org/2000/svg"),
        ("width", Int.toString(columns * pxWidth)),
        ("height", Int.toString(rows * pxHeight)),
        (
          "viewBox",
          `0 0 ${n(Int.toFloat(columns) *. CardArt.boxW)} ${n(Int.toFloat(rows) *. CardArt.boxH)}`,
        ),
      ]}
    >
      <style> {Html.string(fontCss)} </style>
      {cards
      ->Array.mapWithIndex((card, index) => {
        let x = Int.toFloat(mod(index, columns)) *. CardArt.boxW
        let y = Int.toFloat(index / columns) *. CardArt.boxH
        <g attrs={[("transform", `translate(${n(x)} ${n(y)})`)]}> {CardArt.body(card)} </g>
      })
      ->Html.array}
    </svg>,
  )
}

// `encodeURIComponent` rather than base64 for the outer document: the suit glyphs
// are non-ASCII, which `btoa` can't take without a second UTF-8 dance.
let dataUrl = svg => "data:image/svg+xml;charset=utf-8," ++ encodeURIComponent(svg)

// --- The cache ---------------------------------------------------------------

// One card's bitmap: where it sits in the rasterized sheet. `sheet` is the whole
// deck as *one* texture, `sx`/`sy`/`pxWidth`/`pxHeight` are the rectangle of it
// this card occupies (device pixels), and `cssWidth`/`cssHeight` are the size it's
// meant to be shown at, so a consumer can place it without re-deriving the ratio.
//
// The sheet is kept rather than dropped once cut (#226). Both consumers are
// served from it, and they want opposite things:
//
//   - the `raster` scene lays 52 cards out as 52 independent DOM nodes, so it
//     needs a standalone canvas per card. `element` cuts one on demand and
//     remembers it in `cut`.
//   - the victory animation blits a card somewhere new every frame, so what it
//     wants is `drawImage`'s nine-argument form against a single source texture —
//     no per-card canvas to keep hot, nothing on the transform stack. That's
//     `blit`, and it never cuts anything.
//
// Cutting eagerly (what #225 shipped) served the first and quietly taxed the
// second: it made 52 canvases up front, of which the animation would use none.
// Lazily is the shape that suits both, and it costs one mutable field.
type sprite = {
  sheet: canvas,
  sx: float,
  sy: float,
  pxWidth: float,
  pxHeight: float,
  cssWidth: float,
  cssHeight: float,
  // The standalone canvas `element` hands to DOM consumers, cut from the sheet
  // the first time one asks and reused after. `None` until then — the animation
  // never asks.
  mutable cut: option<canvas>,
}

type t = {
  cssWidth: float,
  pixelRatio: float,
  // How long building all of them took, in ms. Kept because it's the number that
  // settled which strategy shipped, and the one to watch if the deck, the card
  // art or the sheet layout ever grows.
  elapsedMs: float,
  sprites: Dict.t<sprite>,
}

// Cards are values, not references, so key on the name they already publish.
let key = (card: Deck.card) => Deck.cardName(card)

let get = (cache, card) => cache.sprites->Dict.get(key(card))

// Draw a card onto a context at a CSS-pixel position — the animation's whole
// interface to the cache. One `drawImage` against the shared sheet, cropping this
// card's cell: the destination is in CSS pixels because an overlay's context is
// pre-scaled by the pixel ratio (`ctx.scale(ratio, ratio)`), and the source
// rectangle is device pixels because that's what the sheet is measured in. The
// two agree — 1:1, no resampling — precisely because the sheet was built at the
// same `renderRatio` the overlay scaled by.
let blit = (ctx, sprite, ~x, ~y) =>
  ctx->drawCanvasPart(
    sprite.sheet,
    sprite.sx,
    sprite.sy,
    sprite.pxWidth,
    sprite.pxHeight,
    x,
    y,
    sprite.cssWidth,
    sprite.cssHeight,
  )

// A blank canvas at the sprite's device-pixel size, with its CSS size pinned so
// it lays out at exactly the width the live SVG beside it gets.
let blankCanvas = (~pxWidth, ~pxHeight, ~cssWidth, ~cssHeight) => {
  let canvas = createCanvas("canvas")
  canvas->setPixelWidth(Float.toInt(pxWidth))
  canvas->setPixelHeight(Float.toInt(pxHeight))
  canvas
  ->canvasElement
  ->WebDom.setAttribute(
    "style",
    `display:block;width:${Float.toString(cssWidth)}px;height:${Float.toString(cssHeight)}px`,
  )
  canvas
}

// A standalone canvas holding just this card, for a consumer that needs a DOM
// node rather than a draw call (the `raster` scene's 52 grid cells). Cut from the
// sheet the first time it's asked for and remembered, so a re-render doesn't
// rasterize the deck all over again — and so the animation, which only ever
// `blit`s, pays for none of them.
let element = sprite => {
  let canvas = switch sprite.cut {
  | Some(canvas) => canvas
  | None =>
    let canvas = blankCanvas(
      ~pxWidth=sprite.pxWidth,
      ~pxHeight=sprite.pxHeight,
      ~cssWidth=sprite.cssWidth,
      ~cssHeight=sprite.cssHeight,
    )
    switch context2d(canvas) {
    | Some(ctx) =>
      ctx->drawCanvasPart(
        sprite.sheet,
        sprite.sx,
        sprite.sy,
        sprite.pxWidth,
        sprite.pxHeight,
        0.,
        0.,
        sprite.pxWidth,
        sprite.pxHeight,
      )
    | None => ()
    }
    sprite.cut = Some(canvas)
    canvas
  }
  canvasElement(canvas)
}

// Rasterize the whole deck through one document: decode the sheet, draw it once
// into a canvas its own size, and hand back each card's rectangle within it. The
// cutting-up is `element`'s now, on demand — see `sprite` for why.
let rasterizeSheet = async (~fontCss, ~pxWidth, ~pxHeight, ~cssWidth, ~cssHeight, cards) => {
  let columns = sheetColumns
  let rows = sheetRows(~columns, Array.length(cards))

  // An empty deck would ask for a zero-height SVG, which doesn't decode.
  if rows == 0 {
    []
  } else {
    let img = makeImage()
    img->setSrc(dataUrl(markup(~fontCss, ~pxWidth, ~pxHeight, ~columns, cards)))
    await img->decode

    let sheetWidth = columns * pxWidth
    let sheetHeight = rows * pxHeight
    let sheet = createCanvas("canvas")
    sheet->setPixelWidth(sheetWidth)
    sheet->setPixelHeight(sheetHeight)
    switch context2d(sheet) {
    | Some(ctx) => ctx->drawImage(img, 0., 0., Int.toFloat(sheetWidth), Int.toFloat(sheetHeight))
    | None => ()
    }

    cards->Array.mapWithIndex((card, index) => (
      key(card),
      {
        sheet,
        sx: Int.toFloat(mod(index, columns) * pxWidth),
        sy: Int.toFloat(index / columns * pxHeight),
        pxWidth: Int.toFloat(pxWidth),
        pxHeight: Int.toFloat(pxHeight),
        cssWidth,
        cssHeight,
        cut: None,
      },
    ))
  }
}

// Build the whole cache. `~cssWidth` is the width a card is shown at; the bitmaps
// come out at `~pixelRatio` times that, so they're crisp on a retina screen and
// can be blitted 1:1. The default is the capped `renderRatio` — the same number an
// overlay scales its backing store by, which is what makes "blitted 1:1" true
// (see `maxPixelRatio`). A caller only passes `~pixelRatio` to say something
// different on purpose.
let build = async (~cssWidth, ~pixelRatio=renderRatio(~cap=maxPixelRatio), cards) => {
  let started = Date.now()
  let cssHeight = cssWidth *. CardArt.aspect
  let pxWidth = Math.round(cssWidth *. pixelRatio)->Float.toInt
  let pxHeight = Math.round(cssHeight *. pixelRatio)->Float.toInt

  let fontCss = await embeddedFontCss()
  let built = await rasterizeSheet(~fontCss, ~pxWidth, ~pxHeight, ~cssWidth, ~cssHeight, cards)

  let sprites = Dict.make()
  built->Array.forEach(((name, sprite)) => sprites->Dict.set(name, sprite))

  {cssWidth, pixelRatio, elapsedMs: Date.now() -. started, sprites}
}
