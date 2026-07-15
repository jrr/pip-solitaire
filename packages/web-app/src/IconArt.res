// The app icon, drawn from the real cards: a trio of cards (7·8·9) fanned out
// over the game's own dark-blue background. It nests `CardArt.body` — the exact
// card face the app renders — so evolving the card design carries straight into
// the icon on the next `mise run icons`. `StaticRender.toString` turns this
// vnode into the SVG the generator writes as `icon.svg` and rasterizes to the
// PNGs the manifest needs.

// The game background: the same top-anchored radial gradient the page uses
// (see the `body` rule in index.html — radial-gradient(... at 50% 0%, #13233b →
// #0b1220)). Reproduced as an SVG <radialGradient> in <defs> so the icon sits on
// the very backdrop the cards sit on in-game, rather than a flat brand color.
let bgInner = "#13233b"
let bgOuter = "#0b1220"

// The icon is authored in a 512×512 square; the rasterizer scales it to each
// output size. Everything below is in these units.
let size = 512.

// The fan pivots about a point low and centered, so the cards splay upward and
// outward from a shared corner like a hand held open.
let pivotX = 256.
let pivotY = 470.
let lift = 200. // how far each card's center sits above the pivot
let cardScale = 1.7 // native card is 120×168; this sizes it into the icon

// The three fanned cards and their splay angles (degrees). 7·8·9, drawn
// left→right so each overlaps the last, with the suits chosen black·red·black
// for color balance against the dark background.
let splay_angle = 18. // 24
let fan = [
  ({Deck.suit: Deck.Clubs, rank: Deck.Nine}, (-1. *. splay_angle)),
  ({Deck.suit: Deck.Hearts, rank: Deck.Eight}, 0.),
  ({Deck.suit: Deck.Spades, rank: Deck.Seven}, splay_angle),
]

// One fanned card: just the real card face, nested and placed. There's no green
// mat anymore — instead each card carries the same soft drop-shadow the app
// gives `.card-art` on screen (see index.html), so overlapping cards separate
// the way they do in-game and the icon reads as the actual playfield.
let placedCard = ((card, angle)) => {
  let w = 120. *. cardScale
  let h = 168. *. cardScale
  let f = Float.toString
  <g
    attrs={[
      (
        "transform",
        `translate(${f(pivotX)} ${f(pivotY)}) rotate(${f(angle)}) translate(0 ${f(-.lift)})`,
      ),
      ("filter", "url(#cardShadow)"),
    ]}
  >
    <svg
      attrs={[
        ("x", f(-.(w /. 2.))),
        ("y", f(-.(h /. 2.))),
        ("width", f(w)),
        ("height", f(h)),
        ("viewBox", CardArt.viewBox),
      ]}
    >
      {CardArt.body(card)}
    </svg>
  </g>
}

// Shared <defs>: the background gradient and the card drop-shadow filter. The
// gradient is anchored top-center like the page's, fading to the darker outer
// color; the shadow mirrors `.card-art`'s `drop-shadow(0 … rgba(0,0,0,…))`,
// scaled up for the icon so the fan lifts off the background.
let defs = () => {
  let f = Float.toString
  <defs>
    <radialGradient
      attrs={[
        ("id", "bg"),
        ("gradientUnits", "userSpaceOnUse"),
        ("cx", f(size /. 2.)),
        ("cy", "0"),
        ("r", f(size *. 1.2)),
      ]}
    >
      <stop attrs={[("offset", "0"), ("stop-color", bgInner)]} />
      <stop attrs={[("offset", "0.6"), ("stop-color", bgOuter)]} />
    </radialGradient>
    <filter
      attrs={[
        ("id", "cardShadow"),
        ("x", "-30%"),
        ("y", "-30%"),
        ("width", "160%"),
        ("height", "160%"),
      ]}
    >
      <feDropShadow
        attrs={[
          ("dx", "0"),
          ("dy", "8"),
          ("stdDeviation", "10"),
          ("flood-color", "#000000"),
          ("flood-opacity", "0.42"),
        ]}
      />
    </filter>
  </defs>
}

// The full icon.
//   ~cornerRadius: rounded-square background as a fraction of `size` (0 = a
//                  full-bleed square, for maskable / iOS icons that get their
//                  own mask).
//   ~inset:        scales the whole fan about the icon center; < 1 pulls the
//                  cards into the maskable "safe zone".
let svg = (~cornerRadius=0.16, ~inset=1.0) => {
  let f = Float.toString
  <svg
    attrs={[
      ("xmlns", "http://www.w3.org/2000/svg"),
      ("viewBox", `0 0 ${f(size)} ${f(size)}`),
      ("width", f(size)),
      ("height", f(size)),
    ]}
  >
    {defs()}
    <rect
      attrs={[
        ("x", "0"),
        ("y", "0"),
        ("width", f(size)),
        ("height", f(size)),
        ("rx", f(size *. cornerRadius)),
        ("fill", "url(#bg)"),
      ]}
    />
    <g attrs={[("transform", `translate(256 256) scale(${f(inset)}) translate(-256 -256)`)]}>
      {fan->Array.map(placedCard)->Html.array}
    </g>
  </svg>
}

// Plain-argument variants for the JS build script (no labeled/optional args to
// marshal across the interop boundary): each returns finished SVG markup.
//   standard  — rounded square, full-size fan (the everyday icon and icon.svg)
//   maskable  — full-bleed square, fan pulled into the safe zone
//   fullBleed — full-bleed square, full-size fan (iOS masks the corners itself)
let standardSvg = () => StaticRender.toString(svg())
let maskableSvg = () => StaticRender.toString(svg(~cornerRadius=0., ~inset=0.78))
let fullBleedSvg = () => StaticRender.toString(svg(~cornerRadius=0.))
