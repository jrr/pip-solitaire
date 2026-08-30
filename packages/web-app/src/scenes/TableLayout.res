// The card table's arithmetic, with no DOM under it.
//
// Everything here is a function of rects and counts: how big the cards get on this
// stage, how narrow it may get before docking the console is refused, which zone a
// dragged card's rect lands in. Nothing reads a card node, a zone element or the
// session — which is what lets `TableLayout_test` cover the fits with no browser at
// all, and `ConsoleDock_test` ask about `minStageWidth` without pulling a 2,600-line
// jsdom-dependent module into a test that is one subtraction.
//
// **The derivations, the footprint table and both fits worked through are in
// `docs/board-geometry.md`.** Read that before retuning a constant; the numbers
// below drive the stylesheet too.
//
// The seam: arithmetic here, measuring in `TableScene`. Anything that touches the
// page — `getBoundingClientRect`, `style.left/top`, `setProperty` — stays over
// there. A new derivation belongs here; a new measurement does not.

// A rectangle in viewport coordinates, which is what `getBoundingClientRect` answers
// with and what the hit-test below compares. `TableScene` binds that external
// straight to this type; the conversion to playfield-local left/top happens at the
// end of the snap maths, over there.
type rect = {left: float, top: float, width: float, height: float}

// --- The design footprints, at scale 1 ---------------------------------------
// Every pixel the layout measures is one of these times the stage's live scale, so
// cards, zones and fans shrink together.

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

// The card's corner radius at the design size — again read off the art (its `rx`
// over its design-box width), not restated. The empty-pile slot traces the card, so
// this is the slot's radius too.
let cardRadius = cardW *. CardArt.cornerRatio

// The empty drop zone's footprint (`.drop-zone` in the CSS): the card-sized slot
// plus a *uniform* gap on every side. Keep it `card + 2·inset` on
// both axes — a hand-picked box is how the highlight frame ends up a different
// distance from the resting card at the top than at the sides.
let zoneInset = 4.
let zoneWidth = cardW +. 2. *. zoneInset
let zoneBaseHeight = cardH +. 2. *. zoneInset

// Concentric with the slot: the frame sits `zoneInset` outside it on every side, so
// its radius is the slot's plus that inset and the two corners share a centre.
let zoneRadius = cardRadius +. zoneInset

// The floor on card size, so a game with many piles on a narrow phone still deals
// cards you can read and grab. Set low enough that eight cascades fit *with room to
// spare*; raise it and the columns hit the floor, overflow the row and butt together
// with nothing left for the stylesheet's `space-evenly` to spread.
let minScale = 0.4

// The ceiling on card size, as a multiple of the design footprint — the single knob
// for "how big do cards get on a roomy screen". Every measured pixel is multiplied
// by the scale, so this grows the whole board in proportion rather than just the
// cards. What it costs in stage width and height is in the doc.
let maxScale = 1.35

// The share of the stage width the row of cards fills. The rest is not slack: it is
// what `space-evenly` opens around and between the columns, so pushing this toward 1
// leaves the columns butting card-to-card.
let fillFraction = 0.9

// The widest a `space-evenly` gap between columns may open before the row stops
// spreading. Past it the leftover stage width becomes equal left/right
// margins instead — see `rowsMaxWidth`. Half a card reads as generous but tidy.
let maxColumnGap = 0.25 *. cardW

// Headroom, in cards, the height fit leaves below the deepest *opening* pile, so a
// cascade can take on this many before it reaches the bottom edge. Sizing to the
// deal's actual depth would overflow the moment a pile grew; deriving it live would
// resize every card on the table as piles grow and shrink, so it is captured once
// from the opening deal and held. A pile that grows past it still overflows — this
// is a comfort margin, not a guarantee.
let fanHeadroom = 5

// --- The fits ----------------------------------------------------------------

// The narrowest stage a row of `columns` piles can be laid into with the cards still
// clearing the `minScale` floor: the width fit solved for the floor instead of for
// the scale. `ConsoleDock`'s refusal leans on it, which is why neither side
// names a pixel breakpoint — retuning `minScale` or `cardW` moves the refusal too.
//
// Note what this is and isn't: it's the *width* term of the clamp, so it says nothing
// about the height term that binds on a short screen. A landscape phone is wide enough
// on paper to clear this — it just has nothing worth docking beside. Docking there stays
// out of scope by being keyboard-only rather than by being refused here.
let minStageWidth = (~columns: int) => minScale *. Int.toFloat(columns) *. cardW /. fillFraction

// The dock-refusal test itself: the stage, less the display cutaway
// `.drop-rows` is pinned inside, less the strip the dock would take — is
// what's left still a stage this board can be dealt onto?
//
// `~columns` is the board's busiest row rather than a constant eight: a two-pile demo
// gives up width a FreeCell board can't.
let fitsDock = (~stage: float, ~cutaway: float, ~inset: float, ~columns: int) =>
  stage -. cutaway -. inset >= minStageWidth(~columns)

// How far below the top row the deepest fan reaches, at scale 1: the *gaps* between
// `referenceDepth` cards, one fewer than the cards themselves. A board with every
// pile Squared grows no fan at all, so its extent is zero and the height fit is left
// with only the row boxes to clear.
let fanExtent = (~hasFanned: bool, ~referenceDepth: int) =>
  hasFanned ? Int.toFloat(referenceDepth - 1) *. fanStep : 0.

// How much the design footprints are scaled to fit the stage — two fits, the tighter
// one wins, then clamped to [`minScale`, `maxScale`]. Both are derived in
// `docs/board-geometry.md`, along with what each argument is measured off.
//
// `None` where there is nothing to divide by — a stage not laid out yet (`avail` 0),
// or a board with no piles. Don't substitute a number here: the caller keeps the
// scale it had, which is what stops a mid-resize measurement of zero from snapping
// the board to a size nothing asked for for one visible frame.
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

// The row's width cap, at scale 1: the widest row's zones plus its
// `widestRow + 1` `space-evenly` gaps grown to at most `maxColumnGap` each.
// `.drop-rows` takes this as a `max-width` and centres itself, so once the stage is
// wider than this the extra width falls into equal left/right margins rather than
// ever-wider gaps. The display cutaway is deliberately *not* folded in — it comes off
// `avail` in the scale, and this stays a pure spreading limit.
let rowsMaxWidth = (~widestRow: int) =>
  Int.toFloat(widestRow) *. zoneWidth +. Int.toFloat(widestRow + 1) *. maxColumnGap

// The whole of the JS→CSS interface: every footprint the stylesheet reads, each a
// design constant above times the live scale. Anything the CSS needs in scaled pixels
// goes here — the stylesheet derives nothing, so the proportions (`cardH / cardW`,
// the corner ratios, `zoneInset`) are stated once and a `calc()` ratio literal can't
// drift from them.
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
// live hover highlight and the snap-on-drop decision, and deliberately
// asymmetric: horizontally it's strict — the card's *centre* must fall inside the zone —
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
