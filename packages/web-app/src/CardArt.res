// The card SVG generator: a `Deck.card` in, an inline `<svg>` vnode out. Like
// SvgScene, these are typed vnodes rendered by the hand-rolled `Html` runtime —
// never `innerHTML` strings — so a card is an ordinary node the reconciler can
// diff and patch.
//
// This is the rudimentary first cut called for by #36: a rounded-rect frame,
// the rank character in two opposite corners (the bottom-right one rotated 180°
// so the card reads the same either way up), and one suit symbol in the middle.
// No pip grids and no court illustrations — those are follow-ups.
//
// The `~detail` parameter exists from day one even though `Full` is its only
// level. It's the hook for the later information-density variant (LOD): a second
// level will drop detail on small cards, chosen by rendered size. Until then
// every card renders `Full`.

type detail = Full

// The card face geometry, shared by every card. A 120×168 viewBox keeps the
// familiar 5:7 playing-card ratio; CSS sizes the rendered card responsively.
let viewBox = "0 0 120 168"

let svg = (~detail=Full, card: Deck.card) => {
  // Only one detail level today; naming it keeps the switch exhaustive so adding
  // a second level later is a compile error until it's handled everywhere.
  let Full = detail
  let color = Deck.suitColor(card.suit)
  let label = Deck.rankLabel(card.rank)
  let glyph = Deck.suitSymbol(card.suit)

  // Corner rank glyph. The top-left one uses these coordinates as-is; the
  // bottom-right one reuses the exact same node but rotates the whole thing 180°
  // about the card's center (60, 84), which maps top-left to bottom-right and
  // flips it upside down — so the two corners are always mirror images.
  let cornerRank = (~rotated) => {
    // Only the bottom-right corner carries a transform; the top-left one omits
    // the attribute entirely (SVG 1.1's `transform` grammar has no "none").
    let base = [
      ("x", "16"),
      ("y", "34"),
      ("font-size", "26"),
      ("font-weight", "700"),
      ("font-family", "system-ui, sans-serif"),
      ("fill", color),
    ]
    let attrs = rotated ? base->Array.concat([("transform", "rotate(180 60 84)")]) : base
    <text attrs> {Html.string(label)} </text>
  }

  <svg
    className="card-art"
    attrs={[("viewBox", viewBox), ("role", "img"), ("aria-label", Deck.cardName(card))]}
  >
    <rect
      attrs={[
        ("x", "1"),
        ("y", "1"),
        ("width", "118"),
        ("height", "166"),
        ("rx", "12"),
        ("ry", "12"),
        ("fill", "#f8fafc"),
        ("stroke", "#cbd5e1"),
        ("stroke-width", "2"),
      ]}
    />
    {cornerRank(~rotated=false)}
    <text
      attrs={[
        ("x", "60"),
        ("y", "84"),
        ("text-anchor", "middle"),
        ("dominant-baseline", "central"),
        ("font-size", "60"),
        ("fill", color),
      ]}
    >
      {Html.string(glyph)}
    </text>
    {cornerRank(~rotated=true)}
  </svg>
}
