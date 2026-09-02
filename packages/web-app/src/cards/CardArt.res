// The card SVG generator: a `Deck.card` in, an inline `<svg>` vnode out. Typed vnodes
// rendered through `Html`, never `innerHTML` strings, so a card is an ordinary node
// the diff can patch.
//
// The face is deliberately rudimentary — a frame, the rank in two opposite corners,
// one large suit symbol in the middle. `~detail` has only `Full` today; it's the hook
// for a later level that drops detail on small cards.

%%raw(`import "./CardArt.css"`)

type detail = Full

// A 120×168 design box, the familiar 5:7 playing-card ratio, and **the single source
// of the card's proportions for the whole app**. `aspect` and `cornerRatio` are
// published because other card-sized boxes have to trace this one — `TableLayout`'s
// `cardH` and `cardRadius` — and would otherwise restate the proportion as their own
// literals, leaving the empty-pile slot tracing a card shape that had moved on.
// `browser-tests/geometry.spec.mjs` pins the relationships.
let boxW = 120.
let boxH = 168.
let cornerR = 12.

let viewBox = `0 0 ${boxW->Float.toString} ${boxH->Float.toString}`
let aspect = boxH /. boxW

let widthMetres = 0.0635 // 2.5" to m

// The radius of the frame's *path*. The stroke is centred on it and extends half its
// width further out, so the painted outer corner is marginally rounder; boxes that
// trace the card match the path.
let cornerRatio = cornerR /. boxW

// Centred on the path, so insetting the rect by half of it puts the painted outer edge
// exactly on the design box's edge — which is why the rect below is `boxW - strokeW`
// wide at an offset of `strokeW / 2` rather than filling the box.
let strokeW = 1.
let frameInset = strokeW /. 2.

// The stroke has to read as an edge against the neighbouring card's face as well as
// against the dark table, so it stays several steps darker than the fill: a pale slate
// all but vanishes where one white card overlaps another. Thin and dark reads as a
// crisper edge than thick and pale, the board's drop-shadow carrying the rest.
let cardFill = "#f7f7f7"
let frameStroke = "#8496ad"

// The pivot the bottom-right corner rank rotates about, and where the middle glyph sits.
let centerX = boxW /. 2.
let centerY = boxH /. 2.

// **Don't reach for `dominant-baseline="central"` with `y = centerY` here**, however
// much better it reads. `central` places the *font's* ascent-to-descent band, not the
// glyph, so the pip lands wherever the renderer's chosen metrics say — and four paths
// draw this card (inline, `<img>`-serialized and canvas 2D in `CardRaster`, resvg in
// the icon generator) which don't agree. Two reasons they can't:
//
//   - Pip Suits ships two vertical-metric pairs half an em apart (0.310 em against
//     0.380 em) and OS/2 `USE_TYPO_METRICS` is clear, so nothing says which to believe.
//   - The page's `@font-face` carries a `unicode-range`, which keeps the subset from
//     shadowing Latin text but also means Pip Suits is not the element's *primary*
//     font — so `central` measures an OS-supplied fallback that differs per platform.
//
// The cost is a pip a few design units off between renderers, invisible on any one
// machine and so invisible to the browser suite; the `raster` scene is where it shows.
// Hence a baseline stated outright, which every renderer reads alike. 0.31 is Pip
// Suits' own `central`.
//
// Separately: this is not where the pip is *optically* centred — the suits' ink rides
// ~4.8 units high in the box. Fixing that is a design change, and moves every card.
let centerGlyphSize = 68.
let centerGlyphBaseline = centerY +. centerGlyphSize *. 0.31

let n = Float.toString

// The face *contents*, with no `<svg>` wrapper, so the same drawing can nest inside
// another SVG — the app icon composes a fan of these, which is what keeps it in step
// with the card design.
let body = (~detail=Full, card: Deck.card) => {
  // Naming the level keeps the switch exhaustive, so a second one is a compile error
  // until it's handled everywhere.
  let Full = detail
  let color = Deck.suitColor(card.suit)
  let label = Deck.rankLabel(card.rank)
  let glyph = Deck.suitSymbol(card.suit)

  // One node drawn twice: the bottom-right corner is this same node rotated 180° about
  // the card's centre, so the two corners can't stop being mirror images.
  //
  // The suit pip takes an **absolute** `x` near the right edge with `text-anchor="end"`
  // rather than trailing the rank, so the pips line up in a vertical column down a fan
  // whatever the rank's width — a narrow "A" and a wide "10" put theirs in the same
  // place, and high enough to stay inside the strip a fanned card leaves showing.
  let cornerRank = (~rotated) => {
    // The top-left corner omits the attribute entirely: SVG 1.1's `transform` grammar
    // has no "none".
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
