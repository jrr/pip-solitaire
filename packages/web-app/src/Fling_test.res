// The fling rules, pinned without a DOM. Gesture code is miserable to test
// through jsdom (no layout, no pointer stream, no real clock), which is exactly
// why `Fling` is a pure function over samples: the interesting decisions — what
// separates a throw from a placement, and which destination a direction means —
// are all checkable here, leaving the scenes to be judged by thumb.

open Vitest

// A gesture as (x, y, t) triples, in the order the pointer produced them.
let track = (points: array<(float, float, float)>): array<Fling.sample> =>
  points->Array.map(((x, y, t)): Fling.sample => {x, y, t})

// A straight run between two points, sampled every `step` ms — the shape of an
// ordinary drag or flick, with the total time deciding which it reads as.
let run = (~from: (float, float), ~to: (float, float), ~ms: float, ~step: float) => {
  let (x0, y0) = from
  let (x1, y1) = to
  let count = Float.toInt(ms /. step)
  Array.fromInitializer(~length=count + 1, i => {
    let f = Int.toFloat(i) /. Int.toFloat(count)
    (x0 +. (x1 -. x0) *. f, y0 +. (y1 -. y0) *. f, Int.toFloat(i) *. step)
  })->track
}

let verdictLabel = (v: Fling.verdict) =>
  switch v {
  | Fling(_) => "fling"
  | Rejected({reason}) => Fling.rejectionLabel(reason)
  }

describe("recognising a fling", () => {
  test("a quick straight flick is a fling", () => {
    // 120px left in 96ms — about 1.25 px/ms at release.
    let g = run(~from=(200., 200.), ~to=(80., 200.), ~ms=96., ~step=16.)
    expect(Fling.classify(g)->verdictLabel)->toBe("fling")
  })

  test("the same travel done slowly is a placement, not a throw", () => {
    // Identical distance and direction, 1.2s instead of 96ms. Only the speed at
    // release differs, and that's the whole discriminator.
    let g = run(~from=(200., 200.), ~to=(80., 200.), ~ms=1200., ~step=200.)
    expect(Fling.classify(g)->verdictLabel)->toBe("too slow at release")
  })

  test("a flick that ends in a pause is a placement", () => {
    // Moved fast, then held still before lifting — the player carried the card
    // somewhere and set it down. Measuring speed over the *tail* is what catches
    // this; an average over the whole gesture would call it a fling.
    let moved = run(~from=(200., 200.), ~to=(80., 200.), ~ms=96., ~step=16.)
    let held = track([(80., 200., 200.), (80., 200., 300.)])
    expect(Fling.classify(Array.concat(moved, held))->verdictLabel)->toBe("too slow at release")
  })

  test("a twitch is too short to be a direction", () => {
    let g = run(~from=(200., 200.), ~to=(190., 200.), ~ms=32., ~step=16.)
    expect(Fling.classify(g)->verdictLabel)->toBe("too short")
  })

  test("a drag that changes its mind is refused even when it ends up fast", () => {
    // Out to the right, then back — the classic "no, not there". It clears
    // distance and speed; only the backtrack check stops it firing a move.
    let out = run(~from=(200., 200.), ~to=(300., 200.), ~ms=64., ~step=16.)
    let back =
      run(~from=(300., 200.), ~to=(240., 200.), ~ms=48., ~step=16.)->Array.map(
        (s: Fling.sample): Fling.sample => {...s, t: s.t +. 64.},
      )
    expect(Fling.classify(Array.concat(out, back))->verdictLabel)->toBe("turned back")
  })

  test("a gesture with nothing to measure between reports no movement", () => {
    expect(Fling.classify([])->verdictLabel)->toBe("no movement")
    expect(Fling.classify(track([(10., 10., 0.)]))->verdictLabel)->toBe("no movement")
  })

  test("a fling points where it was travelling when it was released", () => {
    let g = run(~from=(200., 200.), ~to=(80., 200.), ~ms=96., ~step=16.)
    switch Fling.classify(g) {
    | Fling(m) => expect(Math.round(Fling.radToDeg(m.angle)))->toBe(180.)
    | Rejected(_) => expect("rejected")->toBe("fling")
    }
  })

  test("curl shows up as path length exceeding net distance", () => {
    // A bowed path travels further than the straight line between its ends; the
    // two numbers together are how the tuning scene shows a gesture wasn't clean.
    let g = track([(0., 0., 0.), (50., 40., 16.), (100., 0., 32.)])
    switch Fling.measure(g) {
    | Some(m) =>
      expect(Math.round(m.netDistance))->toBe(100.)
      expect(m.pathLength > m.netDistance)->toBe(true)
    | None => expect("unmeasured")->toBe("measured")
    }
  })
})

describe("resolving a fling to a destination", () => {
  let at = (id, label, x, y): Fling.target => {id, label, at: {x, y}}
  // Screen coordinates: y grows downward, so straight up is a negative angle.
  let left = Math.Constants.pi
  let up = -.Math.Constants.pi /. 2.

  test("along a row of columns, no angle can separate them — the nearest wins", () => {
    // The case that rules out strict "refuse if more than one": from a card below
    // a row of cascades, every column to the left is at the same angle. Three
    // legal columns must still resolve, or the gesture stops working exactly when
    // the board opens up.
    let targets = [
      at(1, "col 3", 300., 500.),
      at(2, "col 2", 200., 500.),
      at(3, "col 1", 100., 500.),
    ]
    let r = Fling.resolve(~origin={x: 400., y: 500.}, ~angle=left, targets)
    expect(r.best->Option.map(t => t.label))->toEqual(Some("col 3"))
  })

  test("a target more in line wins over a nearer one off to the side", () => {
    // Angle is the primary key: the foundation straight up beats the column just
    // to the left, even though the column is three times closer.
    let targets = [at(1, "col left", 300., 500.), at(2, "foundation", 390., 200.)]
    let r = Fling.resolve(~origin={x: 400., y: 500.}, ~angle=up, targets)
    expect(r.best->Option.map(t => t.label))->toEqual(Some("foundation"))
  })

  test("nothing in that direction resolves to nothing", () => {
    // The bounce-and-flash case: legal moves exist, but not the way you flung.
    let targets = [at(1, "col left", 300., 500.), at(2, "col far left", 100., 500.)]
    let r = Fling.resolve(~origin={x: 400., y: 500.}, ~angle=0., targets)
    expect(r.best)->toEqual(None)
    // They're still scored and ranked, just all outside the cone — that's what
    // the debug scene draws.
    expect(Array.length(r.ranked))->toBe(2)
    expect(r.ranked->Array.every(s => !s.inCone))->toBe(true)
  })

  test("no targets at all resolves to nothing", () => {
    let r = Fling.resolve(~origin={x: 400., y: 500.}, ~angle=left, [])
    expect(r.best)->toEqual(None)
    expect(Array.length(r.ranked))->toBe(0)
  })

  test("widening the cone brings a sideways target into play", () => {
    // The cone is the knob that decides how sloppy a fling may be. A target 45°
    // off is out at the default 40° half-angle and in at 60°.
    let targets = [at(1, "diagonal", 500., 400.)]
    let origin: Fling.point = {x: 400., y: 500.}
    let tight = Fling.resolve(~origin, ~angle=0., targets)
    let wide = Fling.resolve(
      ~tuning={...Fling.defaults, coneHalfAngle: 60.},
      ~origin,
      ~angle=0.,
      targets,
    )
    expect(tight.best)->toEqual(None)
    expect(wide.best->Option.map(t => t.label))->toEqual(Some("diagonal"))
  })

  test("a narrow tie band lets angle out-rank distance among near-collinear targets", () => {
    // Same row, but the far column is a touch better aligned. With a wide band
    // they tie and the near one wins; with a narrow band the alignment shows
    // through. This is the knob that decides how much "nearest" really governs.
    let targets = [at(1, "near", 300., 480.), at(2, "far", 100., 500.)]
    let origin: Fling.point = {x: 400., y: 500.}
    let wideBand = Fling.resolve(~origin, ~angle=left, targets)
    let narrowBand = Fling.resolve(
      ~tuning={...Fling.defaults, angleTie: 1.},
      ~origin,
      ~angle=left,
      targets,
    )
    expect(wideBand.best->Option.map(t => t.label))->toEqual(Some("near"))
    expect(narrowBand.best->Option.map(t => t.label))->toEqual(Some("far"))
  })
})
