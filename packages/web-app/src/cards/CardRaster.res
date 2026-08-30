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
// nothing.
//
// **The sheet is kept, not cut up.** A `sprite` is a *rectangle of the shared sheet*
// (`blit`), and the standalone canvas a DOM consumer needs is cut **lazily**
// (`element`), once, on demand. Blitting the sheet apart into 52 canvases the moment it
// decodes and dropping the sheet suits the `raster` scene, whose whole job is to lay 52
// sprites out as 52 DOM nodes, and quietly taxes the animation, which wants the
// opposite: one source texture, `drawImage`'s nine-argument form, and no per-card canvas
// to keep hot. One mutable field, and both scenes get the shape they want.
//
// **Painting the face with the canvas 2D API is the tempting second strategy, and it
// isn't worth it.** `roundRect` and `fillText` need no font embedding, because canvas
// sees the document's own fonts, and it beats the SVG route only before the whole deck
// is one document (~50ms against ~400ms; the sheet is ~60ms). What it costs is a second
// statement of `CardArt`'s geometry, and that is where its bugs come from — a middle
// glyph 4.5 design units high on macOS from rebuilding `dominant-baseline="central"` out
// of `measureText()`, a corner turned with `rotate(pi)` whose matrix isn't exactly
// axis-aligned. Both were invisible to a Linux CI. The `raster` scene compares the
// sprite against the live card, which is the comparison that catches this class of
// thing.
//
// Two details that bite:
//   - `CardArt.svg` emits only a `viewBox`. An SVG with no intrinsic size
//     rasterizes inconsistently through `<img>` (engines fall back to different
//     default sizes), so `markup` below always writes explicit `width`/`height`.
//   - `img.decode()` is async, so building the cache is a promise. Callers await
//     the whole 52-card set before their first frame.

// --- Bindings ----------------------------------------------------------------
// `<img>` decoding, `fetch`, and the font-loading API — the parts of
// rasterization nothing else in the app has any use for. The *canvas* half lives in
// `runtime/Canvas`, because a sprite blit has a canvas at each end and both ends have
// to speak of one `context` type.

type image
type response
type buffer
type bytes

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

// Resolve a font URL the way `styles/fonts.css`'s `@font-face` rules do — relative to
// the document — so it inherits the GitHub Pages project subpath instead of
// hardcoding a root-absolute path that only works at a domain root.
type url
@new external makeUrl: (string, string) => url = "URL"
@get external urlHref: url => string = "href"
@val @scope("document") external baseUri: string = "baseURI"

@val @scope("window") external devicePixelRatio: float = "devicePixelRatio"

// --- The pixel ratio ---------------------------------------------------------

// How much detail a sprite is built with, capped.
//
// The cap is worth having because the raw ratio is not the small number it looks
// like: browser zoom multiplies it, and a Retina Mac one zoom step in reports
// **3.75**. At that ratio the deck is a 2400×2940 sheet — a bitmap nobody can see
// the extra detail in, blitted from on every frame of the animation.
//
// It has to be **one** number, which is the reason it lives here rather than in
// the canvas that draws. The overlay sizes its backing store from a ratio, and
// the sprites it blits are built at a ratio, and the two are computed
// independently: let them disagree and every blit is a resample instead of a
// copy — soft cards, and the cost of the scaling on each one. So the cache
// publishes the cap, and the canvas asks it rather than deciding for itself.
let maxPixelRatio = 2.

// The ratio to build at *now*: the display's, capped. Read live rather than
// captured, so a rebuild after a zoom picks up the new ratio — nothing here watches for
// the change, so the rebuild has to be asked for from outside.
let displayPixelRatio = () => Math.min(devicePixelRatio, maxPixelRatio)

// --- The faces the card face uses --------------------------------------------
// Only these two: the rank (and its corner pip's sibling) is Libre Franklin 600,
// the suit glyphs are the merged "Pip Suits" subset. Both are vendored into
// public/fonts by `mise run fonts`. Weight is spelled out because the
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
      xmlns="http://www.w3.org/2000/svg"
      width={Int.toString(columns * pxWidth)}
      height={Int.toString(rows * pxHeight)}
      viewBox={`0 0 ${n(Int.toFloat(columns) *. CardArt.boxW)} ${n(
          Int.toFloat(rows) *. CardArt.boxH,
        )}`}
    >
      <style dangerouslySetInnerHTML={{"__html": fontCss}} />
      {cards
      ->Array.mapWithIndex((card, index) => {
        let x = Int.toFloat(mod(index, columns)) *. CardArt.boxW
        let y = Int.toFloat(index / columns) *. CardArt.boxH
        <g transform={`translate(${n(x)} ${n(y)})`}> {CardArt.body(card)} </g>
      })
      ->Html.array}
    </svg>,
  )
}

// `encodeURIComponent` rather than base64 for the outer document: the suit glyphs
// are non-ASCII, which `btoa` can't take without a second UTF-8 dance.
let dataUrl = svg => "data:image/svg+xml;charset=utf-8," ++ encodeURIComponent(svg)

// --- The cache ---------------------------------------------------------------

// One card's bitmap — as a *rectangle of the shared sheet*, not a canvas of its
// own (see the header). `sx`/`sy`/`pxWidth`/`pxHeight` are that rectangle, in
// device pixels; `cssWidth`/`cssHeight` are the size the card is meant to be
// shown at, so a consumer can place it without re-deriving the ratio.
//
// `cut` is the DOM's way in, and the one mutable field in this module: a
// consumer that needs a *node* per card (the `raster` scene's 52 cells) gets a
// standalone canvas blitted out of the sheet on first ask and kept. Lazy, so the
// animation — which never asks — pays neither the 52 canvases nor the 52 blits.
type sprite = {
  sheet: Canvas.t,
  sx: float,
  sy: float,
  pxWidth: float,
  pxHeight: float,
  cssWidth: float,
  cssHeight: float,
  mutable cut: option<Canvas.t>,
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

// Draw a sprite into a context, at a box given in that context's own coordinates
// — the animation's single drawing operation, and the reason the sheet is kept
// whole. `drawImage`'s nine-argument form crops the card's cell straight out of
// the shared texture: one source, no per-card canvas, and nothing pushed onto the
// transform stack, so a caller mid-`scale` (which the overlay always is) stays
// where it was.
//
// `~width`/`~height` default to the card's own CSS size, which is what a 1:1 blit
// wants; the animation passes them when a card is drawn at some other size.
let blit = (ctx, sprite: sprite, ~x, ~y, ~width=sprite.cssWidth, ~height=sprite.cssHeight) =>
  ctx->Canvas.drawPart(
    sprite.sheet,
    sprite.sx,
    sprite.sy,
    sprite.pxWidth,
    sprite.pxHeight,
    x,
    y,
    width,
    height,
  )

// A blank canvas at the sprite's device-pixel size, with its CSS size pinned so
// it lays out at exactly the width the live SVG beside it gets.
let blankCanvas = (~pxWidth, ~pxHeight, ~cssWidth, ~cssHeight) => {
  let canvas = Canvas.make()
  canvas->Canvas.setPixelWidth(pxWidth->Float.toInt)
  canvas->Canvas.setPixelHeight(pxHeight->Float.toInt)
  canvas
  ->Canvas.element
  ->WebDom.setAttribute(
    "style",
    `display:block;width:${Float.toString(cssWidth)}px;height:${Float.toString(cssHeight)}px`,
  )
  canvas
}

// The card as a node of its own, for a consumer that lays sprites out as DOM
// rather than drawing them: cut out of the sheet on first ask and kept (see
// `sprite.cut`). The `raster` scene is the one caller, and it asks for all 52.
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
    // A cut that can't draw (no 2D context) still hands back a correctly-sized
    // blank rather than nothing, so a DOM consumer's layout survives an engine
    // that can't rasterize — the same bargain `Canvas.context2d` offers everywhere.
    Canvas.context2d(canvas)->Option.forEach(ctx =>
      blit(ctx, sprite, ~x=0., ~y=0., ~width=sprite.pxWidth, ~height=sprite.pxHeight)
    )
    sprite.cut = Some(canvas)
    canvas
  }
  Canvas.element(canvas)
}

// Rasterize the whole deck through one document and hand back each card's cell
// in it: decode the sheet, draw it once into a canvas its own size, and describe
// where every card landed. Nothing is cut here — see the header.
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
    let sheet = Canvas.make()
    sheet->Canvas.setPixelWidth(sheetWidth)
    sheet->Canvas.setPixelHeight(sheetHeight)
    Canvas.context2d(sheet)->Option.forEach(ctx =>
      ctx->Canvas.draw(img, 0., 0., Int.toFloat(sheetWidth), Int.toFloat(sheetHeight))
    )

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
// can be blitted 1:1 — which only holds if the surface they're blitted onto was
// sized at the same ratio, hence the capped default (see `displayPixelRatio`).
let build = async (~cssWidth, ~pixelRatio=displayPixelRatio(), cards) => {
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
