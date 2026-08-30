// The card table's arithmetic, with no DOM under it: functions of rects and counts,
// nothing that reads a card node, a zone element or the session.
//
// **The derivations, the footprint table and both fits worked through are in
// `docs/board-geometry.md`.** Read that before retuning a constant; the numbers
// below drive the stylesheet too.
//
// **A new derivation belongs here; a new measurement belongs in `TableScene`.**
// Anything that touches the page — `getBoundingClientRect`, `style.left/top`,
// `setProperty` — stays over there, and keeping that line is what lets this file be
// tested without a browser.

// A rectangle in viewport coordinates, which is what `getBoundingClientRect` answers
// with — `TableScene` binds that external straight to this type.
type rect = {left: float, top: float, width: float, height: float}

// --- The design footprints, at scale 1 ---------------------------------------
// Only `fanStep`, `cardW`, `zoneInset` and the three tuning knobs are literals.
// Everything else is derived, here or off `CardArt` — a second literal is a second
// thing to keep in step, and it fails quietly.

let fanStep = 26. // how far each Fanned card steps *down* off the one beneath it
let cardW = 80.
let cardH = cardW *. CardArt.aspect
let cardRadius = cardW *. CardArt.cornerRatio

// `.drop-zone`: the card-sized slot plus a uniform gap on every side. Keep it
// `card + 2·inset` on both axes and `cardRadius + inset` for the corner, or the
// highlight frame stops sitting an equal distance outside the resting card.
let zoneInset = 4.
let zoneWidth = cardW +. 2. *. zoneInset
let zoneBaseHeight = cardH +. 2. *. zoneInset
let zoneRadius = cardRadius +. zoneInset

// The three tuning knobs. `fillFraction`'s remainder is *not* slack — it is the
// `space-evenly` gaps, so pushing it toward 1 butts the columns card-to-card.
let minScale = 0.4
let maxScale = 1.35
let fillFraction = 0.9

// The widest a gap between columns may open before `rowsMaxWidth` stops the row
// spreading and turns the surplus into left/right margins. Half a card.
let maxColumnGap = 0.25 *. cardW

// Headroom, in cards, below the deepest *opening* pile. A comfort margin, not a
// guarantee: a pile that grows past it still overflows.
let fanHeadroom = 5

// --- The fits ----------------------------------------------------------------

// The width fit solved for `minScale` instead of for the scale: the narrowest stage
// `columns` piles fit into with the cards still clearing the floor. **Retuning
// `minScale` or `cardW` moves `fitsDock` with it** — same arithmetic, no pixel
// breakpoint on either side.
let minStageWidth = (~columns: int) => minScale *. Int.toFloat(columns) *. cardW /. fillFraction

// The dock refusal: the stage, less the display cutaway `.drop-rows` is pinned
// inside, less the strip the dock would take — is what's left still a stage this
// board can be dealt onto? `~columns` is the busiest row rather than a constant
// eight, so a two-pile demo gives up width a FreeCell board can't.
let fitsDock = (~stage: float, ~cutaway: float, ~inset: float, ~columns: int) =>
  stage -. cutaway -. inset >= minStageWidth(~columns)

// The *gaps* between `referenceDepth` cards, one fewer than the cards themselves.
let fanExtent = (~hasFanned: bool, ~referenceDepth: int) =>
  hasFanned ? Int.toFloat(referenceDepth - 1) *. fanStep : 0.

// Two fits, the tighter one wins, then clamped to [`minScale`, `maxScale`].
//
// **`None` where there is nothing to divide by** — a stage not laid out yet (`avail`
// 0), or a board with no piles. Don't substitute a number here; the caller keeps the
// scale it had, and the doc's § Two clamps and a `None` has the bug that prevents.
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

// The row's width cap at scale 1. **The display cutaway is deliberately not folded
// in** — it comes off `avail` in the scale, and this stays a pure spreading limit.
let rowsMaxWidth = (~widestRow: int) =>
  Int.toFloat(widestRow) *. zoneWidth +. Int.toFloat(widestRow + 1) *. maxColumnGap

// The whole of the JS→CSS interface. **Anything the CSS needs in scaled pixels goes
// here** — the stylesheet derives nothing, so a `calc()` ratio literal over there is
// a regression. Pixels, not strings: the `px` goes on at the DOM edge, in
// `TableScene`'s `applyScale`.
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

// One primitive for both the hover highlight and the snap-on-drop decision, so the
// two can't disagree. **Deliberately asymmetric** — strict horizontally, generous
// vertically; which way round, and why, is the doc's § The hit-test.
//
// Both rects are viewport-coordinate, so nothing is converted before comparing.
let hits = (~card: rect, ~zone: rect) => {
  let centreX = card.left +. card.width /. 2.
  centreX >= zone.left &&
  centreX <= zone.left +. zone.width &&
  card.top +. card.height >= zone.top &&
  card.top <= zone.top +. zone.height
}
