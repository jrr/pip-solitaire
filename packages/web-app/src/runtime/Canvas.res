// The 2D canvas vocabulary: a `<canvas>`, and the drawing context you get out of
// one.
//
// These live here rather than inside `CardRaster` because both ends of a blit have to
// name the *same* `context` type, and rasterization owns only one of them: the victory
// overlay owns a canvas of its own, sizes its own backing store, and blits
// `CardRaster`'s sprites into it. Two copies of these externals would each type-check
// perfectly and never interoperate, which is the failure mode worth designing out
// rather than discovering.
//
// So the split is: what a canvas *is* lives here, with the rest of the DOM
// bindings; what a *card* is rasterized from — the `<img>` decode, the font
// fetch, the SVG document — stays in `CardRaster`, which is still the only thing
// that needs any of it.
//
// **Everything a caller draws with goes through the guarded `context2d`.**
// `getContext` answers `null` in an engine with no 2D implementation (jsdom, in
// the unit tests), so it's bound as a `Nullable` and the `None` arm is a case
// every caller has to write. That is what keeps a canvas-drawing scene mountable
// in a test environment that cannot draw a thing — the same shape `TableScene`
// uses to survive a jsdom with no `ResizeObserver`, and the reason none of these
// externals is exposed raw.

type t
type context

@val @scope("document") external createElement: string => t = "createElement"

// A fresh, zero-sized canvas. The caller sizes it: there is no useful default —
// a sprite's size comes from the card, an overlay's from the box it covers.
let make = (): t => createElement("canvas")

// A canvas *is* an element; the identity cast lets a scene splice one into a
// vnode tree with `Html.node`, or append it with `WebDom.appendChild`.
external element: t => WebDom.element = "%identity"

// The backing store, in device pixels — not the CSS size the element lays out
// at, which is the stylesheet's business.
//
// Assigning either one **resets the canvas**: every pixel is cleared and the
// context's transform goes back to the identity. That's a mechanic rather than an
// implementation detail — it is how a drawing surface is wiped, and it is why a
// context that was scaled has to be scaled again after any resize. `TrailScene`
// leans on both halves of that deliberately.
@set external setPixelWidth: (t, int) => unit = "width"
@set external setPixelHeight: (t, int) => unit = "height"
@get external pixelWidth: t => int = "width"
@get external pixelHeight: t => int = "height"

@send external getContext: (t, string) => Nullable.t<context> = "getContext"

// The 2D context, or `None` in an engine that has no 2D implementation. See the
// header: this `option` is the whole reason the raw external stays private.
let context2d = (canvas: t): option<context> => canvas->getContext("2d")->Nullable.toOption

// Scale the context so a caller can draw in CSS pixels while the backing store is
// in device pixels — the `ctx.scale(dpr, dpr)` half of the standard hi-dpi canvas
// setup, whose other half is sizing the store to `css × dpr`.
@send external scale: (context, float, float) => unit = "scale"

// `drawImage`'s five- and nine-argument forms: the whole source into a
// destination rect, and a source *rect* into a destination rect (how a card is
// lifted out of a sprite sheet).
//
// Polymorphic in the source, because a canvas draws from more than one thing —
// a decoded `<img>` (the rasterized sheet) and another canvas (every sprite blit)
// — and the DOM's own signature is a union of exactly those. Same trick
// `WebDom.addWindowListener` plays with its event payload.
@send external draw: (context, 'source, float, float, float, float) => unit = "drawImage"
@send
external drawPart: (
  context,
  'source,
  float,
  float,
  float,
  float,
  float,
  float,
  float,
  float,
) => unit = "drawImage"

// Fading a surface rather than clearing it. `destination-out` with a flat fill takes a
// share of every pixel's **alpha** and leaves its colour alone, so a drawing thins back
// towards the transparency it started from — which is the only thing an overlay over live
// DOM can fade *to*. Painting a translucent backdrop over it instead would dim the
// document underneath along with the drawing.
//
// The mode is put back to `source-over` here rather than left for the caller: everything
// else written to this context is an ordinary blit, and a caller that had to remember
// would eventually not.
//
// **A fade has a floor.** Alpha is eight bits and this is a multiplication, so a pixel
// too faint for `alpha × share` to reach half a unit rounds back to where it was and
// stays there — whatever is drawn settles at about `0.5 / share` of 255 and no amount of
// further fading takes it off. The gentler the share the higher that floor, so fade in the
// largest steps the effect can stand rather than the smoothest.
@set external setCompositeOperation: (context, string) => unit = "globalCompositeOperation"
@set external setFillStyle: (context, string) => unit = "fillStyle"
@send external fillRect: (context, float, float, float, float) => unit = "fillRect"

let dim = (ctx, ~width, ~height, ~share) => {
  ctx->setCompositeOperation("destination-out")
  ctx->setFillStyle(`rgba(0,0,0,${Float.toString(share)})`)
  ctx->fillRect(0., 0., width, height)
  ctx->setCompositeOperation("source-over")
}

// Erase a rectangle back to transparency — which on an overlay means back to whatever is
// underneath it, not to a colour. That is the whole use here: a card still resting on the
// board is *under* the canvas, so clearing the pixels over it shows the real card, with
// the shadow and the tilt a blitted sprite would have to imitate.
@send external clearRect: (context, float, float, float, float) => unit = "clearRect"
