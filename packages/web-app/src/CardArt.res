// The card SVG generator: a `Deck.card` in, an inline `<svg>` vnode out. Like
// SvgScene, these are typed vnodes rendered by the hand-rolled `Html` runtime —
// never `innerHTML` strings — so a card is an ordinary node the reconciler can
// diff and patch.
//
// This is the rudimentary first cut called for by #36: a rounded-rect frame,
// the rank glyph — trailed by a small suit pip (#223) so the suit shows in the
// thin strip a fanned card exposes — in two opposite corners (the bottom-right
// one rotated 180° so the card reads the same either way up), and one large suit
// symbol in the middle. No pip grids and no court illustrations — those are
// follow-ups.
//
// The `~detail` parameter exists from day one even though `Full` is its only
// level. It's the hook for the later information-density variant (LOD): a second
// level will drop detail on small cards, chosen by rendered size. Until then
// every card renders `Full`.

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
// relationships are pinned by `mise run verify-geometry`.
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
let strokeW = 2.
let frameInset = strokeW /. 2.

// Centre of the design box: the pivot the bottom-right corner rank rotates about,
// and where the middle suit glyph sits.
let centerX = boxW /. 2.
let centerY = boxH /. 2.

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

  // Corner rank glyph, trailed by a small suit pip (#223). The top-left one uses
  // these coordinates as-is; the bottom-right one reuses the exact same node but
  // rotates the whole thing 180° about the card's center, which maps top-left to
  // bottom-right and flips it upside down — so the two corners are always mirror
  // images. The suit rides in a `<tspan>` after the rank rather than a fixed x, so
  // it follows the rank's own advance width — hugging a narrow "A" and clearing a
  // wide "10" alike — and stays high enough to sit inside the strip a fanned card
  // leaves showing. `Pip Suits` matches the middle glyph's font; `dx`/`dy` set the
  // gap and lift.
  let cornerRank = (~rotated) => {
    // Only the bottom-right corner carries a transform; the top-left one omits
    // the attribute entirely (SVG 1.1's `transform` grammar has no "none").
    let base = [
      ("x", "5"),
      ("y", "38"),
      ("font-size", "40"),
      ("font-weight", "600"),
      ("font-family", "Libre Franklin, sans-serif"),
      ("fill", color),
    ]
    let attrs = rotated
      ? base->Array.concat([("transform", `rotate(180 ${n(centerX)} ${n(centerY)})`)])
      : base
    <text attrs>
      {Html.string(label)}
      <tspan attrs={[("dx", "5"), ("dy", "-4"), ("font-size", "26"), ("font-family", "Pip Suits")]}>
        {Html.string(glyph)}
      </tspan>
    </text>
  }

  <>
    <rect
      attrs={[
        ("x", n(frameInset)),
        ("y", n(frameInset)),
        ("width", n(boxW -. strokeW)),
        ("height", n(boxH -. strokeW)),
        ("rx", n(cornerR)),
        ("ry", n(cornerR)),
        ("fill", "#f7f7f7"),
        ("stroke", "#cbd5e1"),
        ("stroke-width", n(strokeW)),
      ]}
    />
    {cornerRank(~rotated=false)}
    <text
      attrs={[
        ("x", n(centerX)),
        ("y", n(centerY)),
        ("text-anchor", "middle"),
        ("dominant-baseline", "central"),
        ("font-size", "68"),
        ("font-family", "Pip Suits"),
        ("fill", color),
      ]}
    >
      {Html.string(glyph)}
    </text>
    {cornerRank(~rotated=true)}
  </>
}

let svg = (~detail=Full, card: Deck.card) =>
  <svg
    className="card-art"
    attrs={[("viewBox", viewBox), ("role", "img"), ("aria-label", Deck.cardName(card))]}
  >
    {body(~detail, card)}
  </svg>
