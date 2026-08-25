// The card SVG generator: a `Deck.card` in, an inline `<svg>` vnode out. Like
// SvgScene, these are typed vnodes rendered through `Html` — never `innerHTML`
// strings — so a card is an ordinary node the diff can patch.
//
// This is the rudimentary first cut called for by #36: a rounded-rect frame,
// the rank glyph — with a small suit pip (#223) pinned to the far right so the
// suit shows in the thin strip a fanned card exposes — in two opposite corners
// (the bottom-right
// one rotated 180° so the card reads the same either way up), and one large suit
// symbol in the middle. No pip grids and no court illustrations — those are
// follow-ups.
//
// The `~detail` parameter exists from day one even though `Full` is its only
// level. It's the hook for the later information-density variant (LOD): a second
// level will drop detail on small cards, chosen by rendered size. Until then
// every card renders `Full`.

// This component's stylesheet, in the `scenes` layer (see src/styles/index.css).
%%raw(`import "./CardArt.css"`)

type detail = Full

// The card face geometry, shared by every card, and the single source of the card's
// proportions for the whole app. A 120×168 design box keeps the familiar 5:7
// playing-card ratio; CSS sizes the rendered card responsively.
//
// `aspect` and `cornerRatio` are the *derived* forms, published because several
// other card-sized boxes have to trace this one and previously each restated the
// proportion as its own literal: `TableScene`'s `cardH` (a second 5:7 pair) and the
// stylesheet's `calc(var(--card-w) * 1.4)` / `* 0.1`. Deriving them here means the
// design box is stated once and the rest follows, so a change to the card's shape
// can't leave the empty-pile slot or the zone frame tracing the old one. The
// relationships are pinned by browser-tests/geometry.spec.mjs (`mise run browsertest`).
let boxW = 120.
let boxH = 168.

// The frame's corner radius, in design-box units (see the `<rect>` below).
let cornerR = 12.

let viewBox = `0 0 ${boxW->Float.toString} ${boxH->Float.toString}`

// Height as a multiple of width — 1.4, the 5:7 ratio.
let aspect = boxH /. boxW

// Corner radius as a fraction of width. This is the radius of the frame's *path*;
// the stroke is centred on it and extends half its width further out, so the
// painted outer corner is marginally rounder. Boxes that trace the card (the
// empty-pile slot) match the path, which is what they have always done.
let cornerRatio = cornerR /. boxW

// The frame's stroke. Centred on the path, so insetting the rect by half of it puts
// the painted outer edge exactly on the design box's edge — which is why the rect
// below is `boxW - strokeW` wide at an offset of `strokeW / 2`, rather than filling
// the box. Derived so the three stay consistent if the stroke ever changes.
//
// A hairline rather than the 2 units it used to be: the edge that separates two
// overlapping cards is now carried mostly by the board's drop-shadow (the
// `.stacking-card` filter in index.html), so the frame only has to draw the card's
// outline, not stand in for the shadow. Thin *and* dark reads as a crisper edge
// than thick and pale did — see `frameStroke`.
let strokeW = 1.
let frameInset = strokeW /. 2.

// The face's fill and the frame's colour. The stroke used to be `#cbd5e1`, a pale
// slate that all but vanished where one white card overlapped another; this is
// several steps darker, so the outline reads as an edge on its own — against the
// neighbouring card's face as well as against the dark table.
let cardFill = "#f7f7f7"
let frameStroke = "#8496ad"

// Centre of the design box: the pivot the bottom-right corner rank rotates about,
// and where the middle suit glyph sits.
let centerX = boxW /. 2.
let centerY = boxH /. 2.

// The middle suit glyph's size, and the baseline it sits on.
//
// This used to be `dominant-baseline="central"` with `y = centerY`, which reads
// far better and is why it was written that way — but `central` doesn't place the
// glyph, it places the *font's* ascent-to-descent band, and then everything
// depends on which font's metrics the renderer decided to use. Four paths draw
// this card (inline in the page, serialized through `<img>` by CardRaster, canvas
// 2D by CardRaster, resvg by the icon generator) and they did not agree:
//
//   - Pip Suits ships two vertical-metric pairs half an em apart — hhea/OS2-typo
//     1060/-440 (0.310 em) against OS2-usWin/head-bbox 815/-55 (0.380 em).
//     `scripts/generate/fonts.mjs` builds the face with opentype.js, which takes
//     the first from IBM Plex Sans JP and computes the second from the bounding
//     box of the four pip glyphs it kept. Nothing says which to believe: OS/2
//     fsSelection bit 7 (USE_TYPO_METRICS) is clear.
//   - Worse, the page's `@font-face` for Pip Suits carries a `unicode-range`
//     (styles/fonts.css), which keeps the subset from shadowing Latin text but also
//     means Pip Suits is *not* the element's primary font. The pips still come
//     from it, but `central` was measuring the fallback — a different, OS-supplied
//     face on every platform. The band it centres is 75.25 units in the page and
//     102 (Pip Suits' own 1500/1000 em) inside the embedded-font SVG, from the
//     very same markup.
//
// The visible result was the `raster` scene's whole point: the canvas sprite's
// pip sat 4.5 design units above the live card's on macOS, and the live card and
// the SVG sprite were 1.5 apart on Linux. None of it is catchable on one machine,
// which is why the browser suite was green throughout.
//
// So the baseline is stated outright rather than derived at paint time, and every
// renderer now reads the same number. 0.310 em is Pip Suits' own `central` — the
// value the embedded-font SVG and resvg were already using (the icon PNGs come
// out byte-identical across this change); it's the live page card that moves,
// about 1.5 units, off the fallback face it should never have been measuring.
//
// Worth knowing separately: this is not where the pip is optically centred. The
// suits' ink sits 0.355-0.380 em above their baseline, so the glyph rides ~4.8
// units high in the design box. That's how the card has always looked; centring
// it properly is a design change, not this one.
let centerGlyphSize = 68.
let centerGlyphBaseline = centerY +. centerGlyphSize *. 0.31

let n = Float.toString

// The card face *contents* — everything inside the `viewBox`, with no `<svg>`
// wrapper. Kept separate from `svg` so the same drawing can be nested inside
// another SVG (e.g. the app icon composes a fan of these), which is what keeps
// the icon in step with the card design: it reuses this exact body.
let body = (~detail=Full, card: Deck.card) => {
  // Only one detail level today; naming it keeps the switch exhaustive so adding
  // a second level later is a compile error until it's handled everywhere.
  let Full = detail
  let color = Deck.suitColor(card.suit)
  let label = Deck.rankLabel(card.rank)
  let glyph = Deck.suitSymbol(card.suit)

  // Corner rank glyph, with a small suit pip (#223) pinned to the far right. The
  // top-left one uses these coordinates as-is; the bottom-right one reuses the
  // exact same node but rotates the whole thing 180° about the card's center,
  // which maps top-left to bottom-right and flips it upside down — so the two
  // corners are always mirror images. The suit rides in a `<tspan>` given an
  // absolute `x` near the card's right edge (with `text-anchor="end"`) rather than
  // trailing the rank, so the pips line up in a vertical column across a fan
  // regardless of rank width — a narrow "A" and a wide "10" put their pip in the
  // same place. It sits high enough to stay inside the strip a fanned card leaves
  // showing. `Pip Suits` matches the middle glyph's font.
  let cornerRank = (~rotated) => {
    // Only the bottom-right corner carries a transform; the top-left one omits
    // the attribute entirely (SVG 1.1's `transform` grammar has no "none").
    <text
      x="5"
      y="38"
      fontSize="40"
      fontWeight="600"
      fontFamily="Libre Franklin, sans-serif"
      fill={color}
      transform=?{rotated ? Some(`rotate(180 ${n(centerX)} ${n(centerY)})`) : None}
    >
      {Html.string(label)}
      <tspan x="106" y="34" textAnchor="end" fontSize="26" fontFamily="Pip Suits">
        {Html.string(glyph)}
      </tspan>
    </text>
  }

  <>
    <rect
      x={n(frameInset)}
      y={n(frameInset)}
      width={n(boxW -. strokeW)}
      height={n(boxH -. strokeW)}
      rx={n(cornerR)}
      ry={n(cornerR)}
      fill={cardFill}
      stroke={frameStroke}
      strokeWidth={n(strokeW)}
    />
    {cornerRank(~rotated=false)}
    <text
      x={n(centerX)}
      y={n(centerGlyphBaseline)}
      textAnchor="middle"
      fontSize={n(centerGlyphSize)}
      fontFamily="Pip Suits"
      fill={color}
    >
      {Html.string(glyph)}
    </text>
    {cornerRank(~rotated=true)}
  </>
}

let svg = (~detail=Full, card: Deck.card) =>
  <svg className="card-art" viewBox={viewBox} role="img" ariaLabel={Deck.cardName(card)}>
    {body(~detail, card)}
  </svg>
