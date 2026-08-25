// The card table's arithmetic, with no DOM under it (#319).
//
// `TableScene` sizes a board by measuring rects and dividing: how big the cards get
// on this stage, which zone a dragged card's rect lands in, how narrow the stage may
// get before docking the console is refused. None of that reads a card node, a zone
// element or the session — it is functions of rects and counts — so it lived inside
// `buildBoard`'s closure only because everything else there does.
//
// #319 named this as the first of two cuts that don't need the closure (the win
// overlay was the other, taken in #319/#329). What moved is the *maths* and the
// design footprints it multiplies. What stayed behind in `TableScene` is everything
// that touches the page: reading `getBoundingClientRect`, writing `style.left/top`,
// calling `setProperty`. So `applyScale` is still there — it measures the playfield,
// asks `scaleFor` for a number and publishes `cssVars` — and `place` stayed whole,
// since it is two `setLeft`/`setTop` calls with no arithmetic in it to take.
//
// The seam already existed in one place: `ConsoleDock` decides whether a window is
// wide enough to dock into by comparing against `minStageWidth`, and `ConsoleDock_test`
// reached through `TableScene` for it — pulling a 2,600-line jsdom-dependent module
// into a test that is one subtraction. It reaches here now, and so does
// `TableLayout_test`, which covers the fits without a browser at all. The rest of the
// layout — that the numbers below actually land the cards where they should — is
// `browser-tests/geometry.spec.mjs`, where there is a real engine to measure.

// A rectangle in viewport coordinates, which is what `getBoundingClientRect` answers
// with and what the hit-test below compares. `TableScene` binds that external
// straight to this type; the conversion to playfield-local left/top happens at the
// end of the snap maths, over there.
type rect = {left: float, top: float, width: float, height: float}

// --- The design footprints, at scale 1 ---------------------------------------
// Everything the layout measures in pixels — the fan step, the card box, the empty
// zone box — is one of these multiplied by the stage's live scale, so cards, zones
// and fans all shrink together to fit however many piles a game declares onto a
// narrow screen.

// How far each Fanned card steps off the one beneath it. The zones sit at the
// top of the stage and the pile grows downward, so the fan steps *down*, the
// newest card landing lowest and fully exposed.
let fanStep = 26.

// Card footprint in playfield pixels. The width is the design size; the height
// follows from the art's own 5:7 design box (`CardArt.aspect`) rather than being a
// second literal that has to agree with it. Used by the initial deal, which places
// cards before they're laid out and so can't read their rects yet.
let cardW = 80.
let cardH = cardW *. CardArt.aspect

// The card's corner radius at the design size, from the art's own `rx` over its
// design-box width. The empty-pile slot traces the card, so this is the slot's
// radius too — and the zone frame's radius is this plus `zoneInset` (below), which
// is what makes the two corners concentric. Published to the CSS by `cssVars` so
// the stylesheet no longer restates either ratio.
let cardRadius = cardW *. CardArt.cornerRatio

// The empty drop zone's footprint (matches `.drop-zone` in the CSS): the
// card-sized slot (`cardW` × `cardH`) plus a *uniform* breathing gap on every
// side (#166 follow-up). Sizing it as `card + 2·inset` on both axes — rather
// than the old hand-picked 88×124, which left a 4px side gap but a 6px top/bottom
// one — makes the highlight frame sit an equal distance outside the resting card
// all the way round, and rounds the frame concentrically (the slot's radius + this
// inset). A pile's cards centre vertically within the base-height box, and a fanned
// zone grows *below* it so its outline and highlight wrap the whole pile rather
// than just the top card's footprint (see `TableScene`'s reflow).
let zoneInset = 4.
let zoneWidth = cardW +. 2. *. zoneInset
let zoneBaseHeight = cardH +. 2. *. zoneInset

// Concentric with the slot: the frame sits `zoneInset` outside it on every side, so
// its radius is the slot's plus that inset and the two corners share a centre.
let zoneRadius = cardRadius +. zoneInset

// Card widths are floored here, so a game with many piles on a narrow phone
// still deals cards you can read and grab rather than shrinking them away.
// Between this and `maxScale`, cards fill `fillFraction × width` of the stage
// split across the piles. The floor is set low enough that eight cascades still
// fit *with room to spare* on a phone — otherwise the columns hit the floor,
// overflow the row and butt together with no gap to distribute (the
// `space-evenly` in the stylesheet has nothing to spread).
let minScale = 0.4

// The ceiling on card size, as a multiple of the design footprint — the single
// knob for "how big do cards get on a roomy screen". Every pixel the layout
// measures (`cardW`/`cardH`, `fanStep`, the zone box, the `cardRadius`/`zoneRadius`
// corners, `maxColumnGap` and the `--rows-max-w` cap derived from them) is
// multiplied by the scale, so raising this grows the whole board in proportion
// rather than just the cards; the card faces are inline SVG, so they resharpen at
// any size instead of blurring.
//
// Above 1 the design footprint stops being the maximum and becomes what it
// really is — the size the *fits* are expressed in. Both fits still bind first
// on a smaller window (a board needs `maxScale × 711px` of width and
// `maxScale × 526px + 16px` of height to reach the ceiling, for the eight-column
// deal), so this only takes effect once there's genuinely room, and a laptop
// that falls short simply settles a little below it rather than clipping.
let maxScale = 1.35

// The share of the stage width the row of cards fills; the rest is the gaps
// `space-evenly` opens around and between the columns. Kept well below 1 so the
// columns breathe — a squared pile's zone stays framed, and the leftover width
// is real space for `space-evenly` to spread as equal outer/inter-card gaps
// rather than the columns butting card-to-card.
let fillFraction = 0.9

// The widest each `space-evenly` gap between columns is allowed to open before
// the row stops spreading (#173). Past the point where the cards have hit their
// ceiling (the scale capped at `maxScale`), a wider stage keeps pouring its extra
// width into these gaps — on a wide desktop that leaves the columns marooned in a sea
// of green. So the row's width is capped at the point each gap reaches this
// (see `rowsMaxWidth`), and the leftover stage width becomes equal left/right
// margins instead. Half a card reads as a generous-but-tidy column gap; the board
// settles into a solitaire-table shape rather than sprawling.
let maxColumnGap = 0.25 *. cardW

// Headroom, in cards, the height fit leaves below the deepest pile (#—). Card size
// is bounded by height as well as width: on a short screen the tallest column — the
// deepest cascade's fan plus the top row — must fit the safe vertical height, or the
// fan runs off the bottom. Rather than size to the deal's depth exactly (which would
// overflow the moment a pile grew), fit the deepest *opening* pile plus this many
// more cards, so a pile can take on that many before it reaches the edge. Held
// stable from the opening deal so cards don't resize as piles grow and shrink
// mid-game. (A pile that grows past this still overflows; the number is a tunable
// comfort margin, not a hard guarantee.)
let fanHeadroom = 5

// --- The fits ----------------------------------------------------------------

// The narrowest stage a row of `columns` piles can be laid into with the cards still
// clearing the `minScale` floor: `scaleFor`'s width target (`fillFraction · avail /
// columns / cardW`) solved for the floor instead of for the scale.
//
// Docking the debug console (#275) takes a strip of that width away from the board, and
// is *refused* when what's left falls below this — the layout's own arithmetic rather
// than a guessed pixel breakpoint. Below the floor `scaleFor` clamps rather than
// clipping, so a docked board would still render; it would just render at cards the
// width fit no longer sized, which is precisely the outcome the refusal exists to
// prevent.
//
// Note what this is and isn't: it's the *width* term of the clamp, so it says nothing
// about the height term that binds on a short screen. A landscape phone is wide enough
// on paper to clear this — it just has nothing worth docking beside. Docking there stays
// out of scope by being keyboard-only rather than by being refused here.
let minStageWidth = (~columns: int) => minScale *. Int.toFloat(columns) *. cardW /. fillFraction

// The dock-refusal test itself (#275), in the terms the chrome asks it in: the stage,
// less the display cutaway `.drop-rows` is pinned inside (#179), less the strip the
// dock would take — is what's left still a stage this board can be dealt onto?
//
// `~columns` is the board's busiest row rather than a constant eight: a two-pile demo
// gives up width a FreeCell board can't.
let fitsDock = (~stage: float, ~cutaway: float, ~inset: float, ~columns: int) =>
  stage -. cutaway -. inset >= minStageWidth(~columns)

// How far below the top row the deepest fan reaches, at scale 1: the gaps between
// `referenceDepth` cards, which is one fewer than the cards themselves. A board with
// no Fanned pile grows no fan at all (every pile Squared), so its extent is zero and
// the height fit below is left with only the row boxes to clear.
let fanExtent = (~hasFanned: bool, ~referenceDepth: int) =>
  hasFanned ? Int.toFloat(referenceDepth - 1) *. fanStep : 0.

// How much the design footprints are scaled to fit the stage — the whole of the card
// sizing, as one expression over measurements someone else took.
//
// Two fits, and the tighter one wins. **Width**: cards fill `fillFraction × avail`
// split across the busiest row, so `fillFraction · avail / widestRow / cardW`.
// **Height** (#—): the vertical budget mirrors what reflow stacks into the playfield —
// each row's base box (`rowsCount · zoneBaseHeight`) plus the deepest fan, all scaled,
// above the fixed `~vFixed` offset (the rows' `top`, plus the inter-row gap on a
// two-row board). Solving `budget ≤ availH` for the scale gives the height cap. On a
// tall screen the width target is smaller, so the height term changes nothing there.
//
// Then clamped: `maxScale` so a wide screen doesn't blow the cards up without bound,
// `minScale` so a crowded, narrow one keeps them legible.
//
// `None` where there is nothing to divide by — a stage not laid out yet (`avail` 0),
// or a board with no piles. The caller leaves the scale it had rather than
// substituting a number, which is what keeps a mid-resize measurement of zero from
// snapping the board to a size nothing asked for.
let scaleFor = (
  ~avail: float,
  ~availH: float,
  ~vFixed: float,
  ~widestRow: int,
  ~rowsCount: int,
  ~fanExtent: float,
) =>
  if avail > 0. && widestRow > 0 {
    let widthTarget = fillFraction *. avail /. Int.toFloat(widestRow) /. cardW
    let heightDenom = Int.toFloat(rowsCount) *. zoneBaseHeight +. fanExtent
    let heightTarget =
      availH > 0. && heightDenom > 0. ? (availH -. vFixed) /. heightDenom : widthTarget
    Some(Math.max(minScale, Math.min(maxScale, Math.min(widthTarget, heightTarget))))
  } else {
    None
  }

// The row's width cap (#173), at scale 1: the widest row's zones plus its
// `widestRow + 1` `space-evenly` gaps grown to at most `maxColumnGap` each.
// `.drop-rows` takes this as a `max-width` and centres itself, so once the stage is
// wider than this the extra width falls into equal left/right margins rather than
// ever-wider gaps. Below the cap the value exceeds the stage width, so the
// `max-width` is slack and the row spreads as before.
let rowsMaxWidth = (~widestRow: int) =>
  Int.toFloat(widestRow) *. zoneWidth +. Int.toFloat(widestRow + 1) *. maxColumnGap

// Every scaled footprint the stylesheet reads, so `.stacking-card`, `.drop-zone` and
// `.drop-zone__slot` resize in step with the JS geometry. Each is a design constant
// above times the live scale — the stylesheet consumes them directly and derives
// nothing, so the proportions (`cardH / cardW`, the corner ratios, `zoneInset`) are
// stated once, here, rather than restated as `calc()` ratio literals that can drift
// from them.
//
// Pixels, not strings: the `px` suffix is CSS's business and goes on at the DOM edge
// (`TableScene`'s `applyScale`), which leaves the proportions between these numbers
// checkable without parsing anything back out of a declaration.
let cssVars = (~scale: float, ~widestRow: int) => {
  let at = v => v *. scale
  [
    ("--card-w", at(cardW)),
    ("--card-h", at(cardH)),
    ("--card-radius", at(cardRadius)),
    ("--zone-w", at(zoneWidth)),
    ("--zone-h", at(zoneBaseHeight)),
    ("--zone-radius", at(zoneRadius)),
    ("--rows-max-w", at(rowsMaxWidth(~widestRow))),
  ]
}

// --- Hit-testing --------------------------------------------------------------

// Does a dragged card's rect land in this zone? The shared primitive for both the
// live hover highlight and the snap-on-drop decision, and deliberately asymmetric
// (#183): horizontally it's strict — the card's *centre* must fall inside the zone —
// so tightly packed columns stay distinguishable; vertically it's generous — any
// overlap at all counts — so a card need only graze a zone's top or bottom to land
// in it.
//
// Both rects are viewport-coordinate, which is what `getBoundingClientRect` gives and
// so needs no conversion before comparing.
let hits = (~card: rect, ~zone: rect) => {
  let centreX = card.left +. card.width /. 2.
  centreX >= zone.left &&
  centreX <= zone.left +. zone.width &&
  card.top +. card.height >= zone.top &&
  card.top <= zone.top +. zone.height
}
