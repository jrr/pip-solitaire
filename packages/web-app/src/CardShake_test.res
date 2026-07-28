// `CardShake` is mostly a integrator driven by a sensor, which jsdom has none of.
// What *is* testable is the arithmetic around it, and that's also where the bugs
// would hide: the axis mapping (a sign error here shakes the board the wrong way
// and would be maddening to spot by eye on a phone), the burial falloff, and the
// clamp that keeps accumulated disarray from throwing a card off the table.

open Vitest

// Step an entry repeatedly under a constant drive, as one sustained shake.
let drive = (entry, ~x, ~y, ~steps) => {
  for _ in 1 to steps {
    CardShake.step(entry, ~driveX=x, ~driveY=y, ~dt=1.0 /. 60.0)->ignore
  }
}

describe("CardShake axis mapping", () => {
  // The load-bearing sign: a card is not pushed along with the phone, it lags
  // behind it. Accelerate the phone toward its right edge and the cards must
  // slide *left* in the frame.
  test("portrait: phone accelerating right drives the cards left", () => {
    let (dx, _) = CardShake.driveFor(~ax=10.0, ~ay=0.0, ~angle=0.0)
    expect(dx < 0.0)->toBe(true)
  })

  // Device y points *up* the screen and CSS y points down, so a phone jerked
  // upward leaves the cards trailing downward — a positive CSS offset.
  test("portrait: phone accelerating up the screen drives the cards down", () => {
    let (_, dy) = CardShake.driveFor(~ax=0.0, ~ay=10.0, ~angle=0.0)
    expect(dy > 0.0)->toBe(true)
  })

  // `devicemotion` axes are welded to the device, so in landscape the device's y
  // axis runs across the screen. Without this rotation a landscape board would
  // shake at right angles to the actual motion.
  test("landscape: the device's y axis drives the board horizontally", () => {
    let (dxPortrait, _) = CardShake.driveFor(~ax=0.0, ~ay=10.0, ~angle=0.0)
    let (dxLandscape, _) = CardShake.driveFor(~ax=0.0, ~ay=10.0, ~angle=90.0)
    expect(Math.abs(dxPortrait) < 0.001)->toBe(true)
    expect(Math.abs(dxLandscape) > 1.0)->toBe(true)
  })

  test("a still phone drives nothing", () => {
    let (dx, dy) = CardShake.driveFor(~ax=0.0, ~ay=0.0, ~angle=0.0)
    expect(dx)->toBe(-0.0)
    expect(dy)->toBe(0.0)
  })
})

describe("CardShake burial", () => {
  test("an exposed card has full mobility", () => {
    expect(CardShake.mobilityAtDepth(0))->toBe(1.0)
  })

  test("each card stacked on top pins the one below further", () => {
    let top = CardShake.mobilityAtDepth(0)
    let under = CardShake.mobilityAtDepth(1)
    let deep = CardShake.mobilityAtDepth(5)
    expect(under < top)->toBe(true)
    expect(deep < under)->toBe(true)
    expect(deep > 0.0)->toBe(true)
  })

  test("a buried card is displaced less than an exposed one by the same shake", () => {
    let exposed = CardShake.makeEntry(~el=Obj.magic(0), ~seed=7)
    let buried = CardShake.makeEntry(~el=Obj.magic(0), ~seed=7)
    buried.mobility := CardShake.mobilityAtDepth(6)
    drive(exposed, ~x=800.0, ~y=0.0, ~steps=20)
    drive(buried, ~x=800.0, ~y=0.0, ~steps=20)
    expect(Math.abs(buried.offsetX.contents) < Math.abs(exposed.offsetX.contents))->toBe(true)
  })
})

describe("CardShake disarray", () => {
  // The point of the spike: a shake leaves the board messier than it found it,
  // rather than springing back to the dealt layout.
  test("a sustained shake leaves a card resting away from where it started", () => {
    let entry = CardShake.makeEntry(~el=Obj.magic(0), ~seed=3)
    drive(entry, ~x=600.0, ~y=0.0, ~steps=60)
    expect(Math.abs(entry.restX.contents) > 0.5)->toBe(true)
  })

  // ...but only so far. Unclamped creep would walk a card clean off its pile.
  test("accumulated drift is clamped however long the shake lasts", () => {
    let entry = CardShake.makeEntry(~el=Obj.magic(0), ~seed=3)
    drive(entry, ~x=100000.0, ~y=100000.0, ~steps=600)
    expect(Math.abs(entry.restX.contents) <= CardShake.maxDrift +. 0.001)->toBe(true)
    expect(Math.abs(entry.restY.contents) <= CardShake.maxDrift +. 0.001)->toBe(true)
    expect(Math.abs(entry.restRot.contents) <= CardShake.maxDriftRot +. 0.001)->toBe(true)
  })

  // The *live* displacement needs its own ceiling, not just the drift it leaves
  // behind: the spring's equilibrium is `drive / stiffness`, which is unbounded in
  // the drive. Caught in a browser, where a stuck drive parked cards ~31px off
  // their piles against a 12px drift cap.
  test("live displacement is clamped, not just the drift it leaves behind", () => {
    let entry = CardShake.makeEntry(~el=Obj.magic(0), ~seed=3)
    drive(entry, ~x=100000.0, ~y=100000.0, ~steps=600)
    expect(Math.abs(entry.offsetX.contents) <= CardShake.maxOffset +. 0.001)->toBe(true)
    expect(Math.abs(entry.offsetY.contents) <= CardShake.maxOffset +. 0.001)->toBe(true)
    expect(Math.abs(entry.offsetRot.contents) <= CardShake.maxOffsetRot +. 0.001)->toBe(true)
  })

  test("placing a card by hand clears its accumulated disarray", () => {
    let entry = CardShake.makeEntry(~el=Obj.magic(0), ~seed=3)
    drive(entry, ~x=600.0, ~y=600.0, ~steps=60)
    CardShake.settle(entry)
    expect(entry.restX.contents)->toBe(0.0)
    expect(entry.restY.contents)->toBe(0.0)
    expect(entry.restRot.contents)->toBe(0.0)
  })

  // Without per-card variation the whole board moves as one, which reads as the
  // camera shaking rather than as loose cards.
  test("two cards answer the same shake differently", () => {
    let a = CardShake.makeEntry(~el=Obj.magic(0), ~seed=1)
    let b = CardShake.makeEntry(~el=Obj.magic(0), ~seed=2)
    drive(a, ~x=600.0, ~y=0.0, ~steps=20)
    drive(b, ~x=600.0, ~y=0.0, ~steps=20)
    expect(a.offsetX.contents == b.offsetX.contents)->toBe(false)
    expect(a.offsetRot.contents == b.offsetRot.contents)->toBe(false)
  })

  // The loop parks itself when the board stops moving; if this ever reported
  // "awake" forever the rAF loop would spin at 60Hz for the session's life.
  test("an undriven card reports itself settled", () => {
    let entry = CardShake.makeEntry(~el=Obj.magic(0), ~seed=3)
    let moving = CardShake.step(entry, ~driveX=0.0, ~driveY=0.0, ~dt=1.0 /. 60.0)
    expect(moving)->toBe(false)
  })
})
