// `CutoutSide` decides the cutout side from the orientation angle (iOS reports
// symmetric safe-area insets in landscape, so the insets can't tell the sides
// apart — see the module header). These cover the angle→side mapping and the
// screen-over-window fallback; the DOM listeners around them are the
// untestable-in-jsdom glue.

open Vitest

describe("CutoutSide angle mapping (#179 follow-up)", () => {
  test("screen angle 90 ⇒ notch on the left", () => {
    expect(CutoutSide.sideOfScreenAngle(90.))->toBe("left")
  })

  test("screen angle 270 ⇒ notch on the right", () => {
    expect(CutoutSide.sideOfScreenAngle(270.))->toBe("right")
  })

  test("portrait (0 / 180) exposes no side", () => {
    expect(CutoutSide.sideOfScreenAngle(0.))->toBe("none")
    expect(CutoutSide.sideOfScreenAngle(180.))->toBe("none")
  })

  test("legacy window.orientation flips sign for the right landscape", () => {
    expect(CutoutSide.sideOfWindowAngle(90.))->toBe("left")
    expect(CutoutSide.sideOfWindowAngle(-90.))->toBe("right")
    expect(CutoutSide.sideOfWindowAngle(0.))->toBe("none")
  })

  test("side() prefers the modern screen angle when present", () => {
    expect(CutoutSide.side(~screenAngle=Some(270.), ~windowAngle=Some(90.)))->toBe("right")
  })

  test("side() falls back to window.orientation without screen.orientation", () => {
    expect(CutoutSide.side(~screenAngle=None, ~windowAngle=Some(-90.)))->toBe("right")
  })

  test("side() is none when neither angle is available (desktop / jsdom)", () => {
    expect(CutoutSide.side(~screenAngle=None, ~windowAngle=None))->toBe("none")
  })
})
