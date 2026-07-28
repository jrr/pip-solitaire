// The disarray channel's pure core (#236): which way a shake throws cards, how much
// of a throw sticks, and what a square-up clears. The numbers themselves
// (`driveGain`, `creep`, and the landscape convention) want a phone in hand; what's
// pinned here is the *shape* — the conventions and the invariants a tuning pass must
// not break, so changing a knob can't quietly change the semantics with it.

open Vitest

// `Math.cos` of a right angle isn't exactly zero, so "the cards didn't move on this
// axis" is a tolerance rather than an equality.
let isNil = v => Math.abs(v) < 1e-9

describe("CardShake screen axes (#236)", () => {
  test("portrait: device +x throws cards right, +y throws them up the screen", () => {
    // `devicemotion`'s natural frame is x right across the screen, y up along it. The
    // screen frame the cards live in has y pointing *down*, so a shake toward the top
    // of the phone must come back as a *negative* screen-y.
    let (right, down) = CardShake.driveFor(~x=10., ~y=0., ~angle=0)
    expect(right > 0.)->toBe(true)
    expect(isNil(down))->toBe(true)

    let (right, down) = CardShake.driveFor(~x=0., ~y=10., ~angle=0)
    expect(isNil(right))->toBe(true)
    expect(down < 0.)->toBe(true)
  })

  test("upside-down portrait mirrors both axes", () => {
    let (right, down) = CardShake.driveFor(~x=10., ~y=10., ~angle=180)
    expect(right < 0.)->toBe(true)
    expect(down > 0.)->toBe(true)
  })

  // The convention #236 flags as inferred rather than tested. We take `angle == 90` to
  // mean the device has been rotated *clockwise* — its natural top edge now points to
  // the screen's right — which is what iOS's legacy `window.orientation == 90`
  // (landscape, home button on the left) describes. If a real device throws cards
  // *across* you where it should throw them *with* you, and only in landscape, negate
  // `CardShake.angleSign`: that swaps these two cases and leaves the portrait pair
  // above untouched. These assertions then read the other way round, which is the
  // one-line change the issue asks for.
  test("landscape 90: the device's natural top edge points screen-right", () => {
    let (right, down) = CardShake.driveFor(~x=0., ~y=10., ~angle=90)
    expect(right > 0.)->toBe(true)
    expect(isNil(down))->toBe(true)

    // …and the natural right edge points screen-down.
    let (right, down) = CardShake.driveFor(~x=10., ~y=0., ~angle=90)
    expect(isNil(right))->toBe(true)
    expect(down > 0.)->toBe(true)
  })

  test("landscape 270 is the other landscape, mirrored", () => {
    let (right, down) = CardShake.driveFor(~x=0., ~y=10., ~angle=270)
    expect(right < 0.)->toBe(true)
    expect(isNil(down))->toBe(true)

    let (right, down) = CardShake.driveFor(~x=10., ~y=0., ~angle=270)
    expect(isNil(right))->toBe(true)
    expect(down < 0.)->toBe(true)
  })

  test("a rotation preserves how hard the shake was, whatever the orientation", () => {
    // Orientation-independence: turning the phone changes which way the cards go, never
    // how far. (This is the same property the gesture split gets for free by projecting
    // onto measured gravity — see `Motion_test`.)
    let magnitude = ((right, down)) => Math.sqrt(right *. right +. down *. down)
    let portrait = magnitude(CardShake.driveFor(~x=6., ~y=8., ~angle=0))
    [90, 180, 270]->Array.forEach(
      angle =>
        expect(isNil(magnitude(CardShake.driveFor(~x=6., ~y=8., ~angle)) -. portrait))->toBe(true),
    )
  })
})

describe("CardShake per-card rolls (#236)", () => {
  test("every card takes some of the drive, none takes it all twice over", () => {
    // The board must not slide as a rigid block (that reads as a camera shake), but no
    // card may sit the shake out either.
    expect(CardShake.shareFor(~roll=0.) > 0.)->toBe(true)
    expect(CardShake.shareFor(~roll=0.999) < 2.)->toBe(true)
    expect(CardShake.shareFor(~roll=0.9) > CardShake.shareFor(~roll=0.1))->toBe(true)
  })

  test("spin is signed by the roll, so cards cock both ways", () => {
    expect(CardShake.spinFor(~magnitude=20., ~roll=0.) < 0.)->toBe(true)
    expect(CardShake.spinFor(~magnitude=20., ~roll=1.) > 0.)->toBe(true)
    expect(isNil(CardShake.spinFor(~magnitude=20., ~roll=0.5)))->toBe(true)
  })
})

describe("CardShake creep and clamps (#236)", () => {
  test("a throw overshoots where it settles, and only `creep` of it sticks", () => {
    let (transient, settled) = CardShake.zero->CardShake.throw(~dx=10., ~dy=0., ~drot=2.)
    expect(transient.dx)->toBe(10.)
    expect(settled.dx)->toBe(10. *. CardShake.creep)
    expect(settled.rot)->toBe(2. *. CardShake.creep)
    // The overshoot is the point: a shake has to land visibly further out than the mess
    // it leaves behind, or it reads as a slow crawl toward the cap.
    expect(transient.dx > settled.dx)->toBe(true)
  })

  test("the mess accumulates but is bounded, however many shakes it takes", () => {
    // Twenty hard shakes all the same way: the settled disarray creeps outward and then
    // stops at the resting clamp; the transient never exceeds the overshoot clamp.
    let disarray = ref(CardShake.zero)
    let firstStep = ref(0.)
    for i in 0 to 19 {
      let (transient, settled) = disarray.contents->CardShake.throw(~dx=12., ~dy=-12., ~drot=12.)
      if i == 0 {
        firstStep := settled.dx
      }
      expect(Math.abs(transient.dx) <= CardShake.maxDriftTransient)->toBe(true)
      expect(Math.abs(transient.rot) <= CardShake.maxDriftRotTransient)->toBe(true)
      expect(Math.abs(settled.dx) <= CardShake.maxDrift)->toBe(true)
      expect(Math.abs(settled.dy) <= CardShake.maxDrift)->toBe(true)
      expect(Math.abs(settled.rot) <= CardShake.maxDriftRot)->toBe(true)
      disarray := settled
    }
    // It really did creep rather than jump: one shake left well under the cap, and
    // repeated shakes got there.
    expect(firstStep.contents < CardShake.maxDrift)->toBe(true)
    expect(disarray.contents.dx)->toBe(CardShake.maxDrift)
    expect(disarray.contents.rot)->toBe(CardShake.maxDriftRot)
  })

  test("the resting rotation cap is the visual delta the tuning has to answer for", () => {
    // #236 judges the rotation tuning in the Sloppy-*off* state, where a shake cocks a
    // card off a dead-square start: 8° at rest, 14° in the throw.
    expect(CardShake.maxDriftRot)->toBe(8.)
    expect(CardShake.maxDriftRotTransient)->toBe(14.)
  })
})

describe("CardShake square-up (#236)", () => {
  test("a square-up clears the disarray and nothing else", () => {
    let messy = {CardShake.dx: 9., dy: -4., rot: 6.}
    let (transient, settled) = CardShake.tap(messy)
    // Home is this channel's zero — the *dealt* position, not machine-square: the base
    // tilt lives in `--card-rot`, which a square-up never touches (see `TableScene`).
    expect(settled)->toEqual(CardShake.zero)
    // The gesture has some weight to it: a small downward nudge before the cards glide.
    expect(transient.dy > messy.dy)->toBe(true)
    expect(transient.dx)->toBe(messy.dx)
    expect(transient.rot)->toBe(messy.rot)
  })

  test("squaring up an already-tidy board is a no-op it can't tell from tidy", () => {
    let (_, settled) = CardShake.tap(CardShake.zero)
    expect(settled)->toEqual(CardShake.zero)
  })
})
