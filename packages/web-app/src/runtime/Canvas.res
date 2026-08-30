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
