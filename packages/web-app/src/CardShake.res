// The board's *disarray* channel (#236): how far a shake throws each card off the
// spot it rests on, and how much of that throw sticks.
//
// This is deliberately a channel of its own, separate from where a card rests. The
// rest position comes from `GameState` by way of `TableScene`'s reflow, and the
// hand-placed base tilt (#65) comes from `cardTilt`; the disarray here is published
// as the `--shake-x/--shake-y/--shake-rot` custom properties and the stylesheet
// *sums* it with `--card-rot`. Three things fall out of that split, all of which
// #236 asks for:
//
//   - "Square up" means back to how the cards were *dealt*, not machine-perfect.
//     Clearing this channel leaves the base tilt untouched, so a squared-up board is
//     hand-dealt-sloppy with "Sloppy placement" on and dead-square with it off —
//     which is what tapping a real deck down on the table does.
//   - Wiggle Waggle and Sloppy placement are independent, all four combinations
//     valid, with no cross-checking logic: two custom properties that default to
//     zero, summed by the CSS.
//   - A relayout (a drop, a resize, flipping the tilt switch) can't wipe the mess,
//     because the mess doesn't live in the left/top the relayout rewrites.
//
// Everything here is pure — the DOM writes and the `Math.random` per-card rolls are
// `TableScene`'s — so the tuning and the axis conventions below are unit-testable
// without a device (`CardShake_test`). What still wants a phone in hand is the
// *values*: `driveGain`, `creep` and the landscape convention in `angleSign`.

// A card's disarray: an offset from where it rests, in *design* pixels (the caller
// multiplies by the stage's live scale, exactly as it does for every other
// footprint), plus a rotation in degrees that is *added* to the base tilt.
type t = {
  dx: float,
  dy: float,
  rot: float,
}

// A card that sits exactly where it was dealt. Every card starts here, a square-up
// returns every card here, and picking a card up puts that card back here.
let zero = {dx: 0., dy: 0., rot: 0.}

// --- Tuning ------------------------------------------------------------------
// The knobs #236 wants felt on a real phone. They're collected here so that tuning
// pass is a handful of numbers in one file rather than a hunt through the scene.

// How far a shake throws a card: design px per m/s² of (high-passed) acceleration.
// At the shake threshold (`Motion.shakeThreshold`, 18 m/s²) this is ~10px, and the
// clamps below cap the total however hard the phone is shaken.
let driveGain = 0.55

// How much a shake cocks a card: degrees per m/s². Kept low relative to `driveGain`
// — #236 notes rotation read as a touch strong in the spike, the exposed bottom
// cards looking quite cocked — and judged in the Sloppy-*off* state, where a shake
// rotates a card off a dead-square start and the visual delta is largest.
let spinGain = 0.06

// How fast the mess becomes permanent: the fraction of each throw a card keeps once
// it settles. The rest is transient — the card is thrown, then eases back. Repeated
// shakes therefore pile up toward the clamps rather than in one jump.
let creep = 0.35

// The resting bounds of the mess: a card never sits more than this far off its spot,
// nor more than this far off its base tilt, however many shakes it's taken. The 8°
// cap is what #236 pins as the biggest visual delta the tuning produces (a shake
// rotating a card off a dead-square start with Sloppy placement off).
let maxDrift = 14.
let maxDriftRot = 8.

// A throw may overshoot its resting bound by this much before easing back, which is
// what gives a shake some snap instead of a smooth crawl toward the cap. 8° × 1.75
// is the 14° transient rotation #236 describes.
let transientSlack = 1.75
let maxDriftTransient = maxDrift *. transientSlack
let maxDriftRotTransient = maxDriftRot *. transientSlack

// How long a card is held at its overshoot before settling. Matched to the card
// transition in the stylesheet (0.18s) so the throw has visibly landed before the
// settle retargets it — a shorter hold and the transition would be retargeted
// mid-flight, easing to a fraction of the overshoot and reading as no overshoot.
let settleMs = 180.

// The downward nudge a square-up gives every card before they glide home: tapping a
// deck down on the table has some weight to it (#236). Design px, applied as an
// overshoot in the same "throw then settle" shape as a shake.
let tapImpulse = 7.

// --- Device axes → screen axes ------------------------------------------------

// Portrait convention. `devicemotion` reports, in the device's *natural* frame,
// x rightward across the screen, y up along it and z out of the glass toward the
// viewer — so a still phone held upright reads y ≈ +9.81 and one flat on a table
// z ≈ +9.81 (gravity's pull is device −y and −z respectively). The screen frame the
// cards live in has y pointing *down*, hence the negation in `driveFor`.
//
// Landscape is the same rotation with the screen's orientation angle folded in, and
// this is the sign #236 flags as inferred rather than tested: whether a phone rotated
// with its natural top edge to the left reports `screen.orientation.angle == 90` or
// `270` decides which way the two landscape orientations map. If a real device throws
// cards *across* you when it should throw them *with* you (and only in landscape —
// portrait and upside-down are unaffected, `sin 0 == sin 180 == 0`), negate this one
// constant. `CardShake_test` pins the convention either way.
let angleSign = 1.

// Rotate a device-frame vector into the screen frame: `(right, down)` in the same
// units as the input, for a screen rotated `angle` degrees (0/90/180/270).
let screenAxes = (~x, ~y, ~angle) => {
  let radians = angleSign *. Int.toFloat(angle) *. Math.Constants.pi /. 180.
  let c = Math.cos(radians)
  let s = Math.sin(radians)
  let right = x *. c +. y *. s
  let up = -.x *. s +. y *. c
  (right, -.up)
}

// The screen-space drive, in design px, that a shake of `(x, y, z)` high-passed
// acceleration gives a card at full strength. `z` — a shake toward or away from the
// glass — has no direction on screen, so it feeds only the spin (see `spinFor`).
let driveFor = (~x, ~y, ~angle) => {
  let (right, down) = screenAxes(~x, ~y, ~angle)
  (right *. driveGain, down *. driveGain)
}

// The share of the drive one card takes. Cards aren't bolted to each other: without
// this the whole board slides as a rigid block, which reads as a camera shake rather
// than as cards being knocked about. `roll` is a `[0, 1)` random, one per card per
// shake, and the range never reaches zero so every card does move.
let shareFor = (~roll) => 0.45 +. roll *. 0.85

// The spin, in degrees, a shake of `magnitude` (m/s², the whole high-passed vector
// including z) gives a card. `roll` is a `[0, 1)` random that signs it, so cards cock
// both ways and repeated shakes walk the rotation about rather than driving every
// card to the same cap.
let spinFor = (~magnitude, ~roll) => (roll *. 2. -. 1.) *. magnitude *. spinGain

// --- Accumulating and clearing the mess ---------------------------------------

let clampAbs = (v, limit) => Math.max(-.limit, Math.min(limit, v))
let clamp = (t, ~drift, ~spin) => {
  dx: clampAbs(t.dx, drift),
  dy: clampAbs(t.dy, drift),
  rot: clampAbs(t.rot, spin),
}

// One shake's contribution to a card's disarray, as the pair `(transient, settled)`:
// where the card is thrown *now*, and where it comes to rest `settleMs` later. The
// throw takes the whole drive (bounded by the transient clamps); only `creep` of it
// survives into the settled state (bounded by the resting clamps). Inputs are already
// in design px / degrees — `driveFor`, `shareFor` and `spinFor` above turn a device
// reading into them.
let throw = (t, ~dx, ~dy, ~drot) => (
  clamp(
    {dx: t.dx +. dx, dy: t.dy +. dy, rot: t.rot +. drot},
    ~drift=maxDriftTransient,
    ~spin=maxDriftRotTransient,
  ),
  clamp(
    {dx: t.dx +. dx *. creep, dy: t.dy +. dy *. creep, rot: t.rot +. drot *. creep},
    ~drift=maxDrift,
    ~spin=maxDriftRot,
  ),
)

// The square-up gesture's effect on a card, in the same `(transient, settled)` shape:
// a small downward nudge, and then home. "Home" is `zero` — this channel only, so the
// card returns to how it was *dealt* (its base tilt intact), not to machine-square.
let tap = t => (
  clamp({...t, dy: t.dy +. tapImpulse}, ~drift=maxDriftTransient, ~spin=maxDriftRotTransient),
  zero,
)
