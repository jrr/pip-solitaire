// The Wiggle Waggle switch's pure helpers (#235): the state → is-it-on mapping and
// the problem-only subtitle. These are what the Settings row renders, so they're
// worth pinning without a device — the capability/permission side (`requestAccess`,
// the subscription) needs a real sensor and secure origin and is verified on a phone.
//
// Since #236 the gesture *classifier* is pure too, so the whole shake-vs-square-up
// split — the projection onto gravity, both thresholds and both cooldowns — is driven
// here off synthetic sample streams. What still needs a phone is whether the numbers
// match what a person means by "shake" and by "tapping the deck down".

open Vitest

describe("Motion switch state (#235)", () => {
  test("only the listening state reads as on", () => {
    expect(Motion.isOn(Motion.On))->toBe(true)
    expect(Motion.isOn(Motion.Off))->toBe(false)
    // Blocked snaps the switch *back* to off while still carrying its subtitle.
    expect(Motion.isOn(Motion.Blocked))->toBe(false)
    expect(Motion.isOn(Motion.Unavailable(NoSensor)))->toBe(false)
    expect(Motion.isOn(Motion.Unavailable(Insecure)))->toBe(false)
  })

  test("a healthy switch shows no subtitle", () => {
    // The row is title-only when off or listening — a present subtitle always means
    // there's a problem to report.
    expect(Motion.subtitle(Motion.Off))->toEqual(None)
    expect(Motion.subtitle(Motion.On))->toEqual(None)
  })

  test("each problem state carries its own explanation", () => {
    expect(Motion.subtitle(Motion.Blocked))->toEqual(
      Some(
        "Motion access is off. Turn it on in Settings → Safari → Motion & Orientation Access.",
      ),
    )
    expect(Motion.subtitle(Motion.Unavailable(NoSensor)))->toEqual(
      Some("This device doesn't report motion."),
    )
    expect(Motion.subtitle(Motion.Unavailable(Insecure)))->toEqual(
      Some("Needs a secure (https) connection."),
    )
  })
})

// --- The gesture split (#236) -------------------------------------------------

// A still phone held upright: `accelerationIncludingGravity` reads +9.81 on whichever
// axis points up, so gravity's pull is device −y here and the estimate points +y.
let upright = (~ax=0., ~ay=0., ~az=0.): Motion.reading => {
  x: ax,
  y: Motion.gravity +. ay,
  z: az,
}
// The same phone flat on a table, face up: now it's z that carries gravity.
let flat = (~ax=0., ~ay=0., ~az=0.): Motion.reading => {
  x: ax,
  y: ay,
  z: Motion.gravity +. az,
}

// Feed a timed stream of readings through one detector and collect what came out.
// Labels rather than the gestures themselves, so a case reads as the sequence a person
// would describe.
let play = (samples: array<(Motion.reading, float)>) => {
  let detector = ref(Motion.newDetector)
  let gestures = []
  samples->Array.forEach(((reading, atMs)) => {
    let (advanced, gesture) = Motion.step(detector.contents, ~reading, ~atMs)
    detector := advanced
    switch gesture {
    | Some(g) => gestures->Array.push(g)
    | None => ()
    }
  })
  gestures
}
let labels = gestures =>
  gestures->Array.map(g =>
    switch g {
    | Motion.Shake(_) => "shake"
    | Motion.SquareUp => "square-up"
    }
  )

// An impulse hard enough to read as a square-up but not as a shake: the gravity
// estimate absorbs 8% of it on the way past, leaving ~16 m/s² — over
// `squareUpThreshold`, under `shakeThreshold`.
let tapImpulse = 17.5

describe("Motion gesture split (#236)", () => {
  test("a still phone reports nothing at all", () => {
    let samples =
      Array.make(~length=60, ())->Array.mapWithIndex((_, i) => (upright(), Int.toFloat(i) *. 16.))
    expect(labels(play(samples)))->toEqual([])
  })

  test("energy across gravity is a shake, and says which way it went", () => {
    // A hard sideways swing: perpendicular to gravity, well over the shake threshold.
    let gestures = play([(upright(), 0.), (upright(~ax=26.), 16.)])
    expect(labels(gestures))->toEqual(["shake"])
    switch gestures->Array.get(0) {
    // The board throws the cards along this vector, so its direction is the point:
    // the swing was along +x, and gravity's own 9.81 must not be in it.
    | Some(Motion.Shake(h)) =>
      expect(h.x > 20.)->toBe(true)
      expect(Math.abs(h.y) < 1.)->toBe(true)
    | _ => expect(false)->toBe(true)
    }
  })

  test("a single sharp impulse along gravity is a square-up", () => {
    // Tapping the deck down on the table: the sharp part is the *stop*, which reads as
    // acceleration along the gravity estimate.
    expect(labels(play([(upright(), 0.), (upright(~ay=tapImpulse), 16.)])))->toEqual(["square-up"])
  })

  test("the same tap reads the same whatever way the phone is held", () => {
    // Projecting onto *measured* gravity is what buys orientation-independence: "down"
    // is device −y held upright and −z flat on a table, and neither the classification
    // nor the numbers behind it care which.
    let heldUpright = play([(upright(), 0.), (upright(~ay=tapImpulse), 16.)])
    let onTable = play([(flat(), 0.), (flat(~az=tapImpulse), 16.)])
    expect(labels(heldUpright))->toEqual(["square-up"])
    expect(labels(onTable))->toEqual(labels(heldUpright))

    // And a sideways swing is a shake in both, from the perpendicular energy alone.
    expect(labels(play([(upright(), 0.), (upright(~ax=26.), 16.)])))->toEqual(["shake"])
    expect(labels(play([(flat(), 0.), (flat(~ax=26.), 16.)])))->toEqual(["shake"])
  })

  test("a vigorous shake's tail doesn't tidy the board you just messed up", () => {
    // The cooldown that matters: a shake decays *through* the square-up band, so
    // without a quiet period after the last loud sample the gesture would square up the
    // mess it had just made.
    // A still sample to seed gravity, the shake itself, then its tail — an impulse that
    // would read as a square-up on its own, arriving inside the suppression window.
    let shakeThenTail = [(upright(), 0.), (upright(~ax=26.), 16.), (upright(~ay=tapImpulse), 300.)]
    expect(labels(play(shakeThenTail)))->toEqual(["shake"])

    // Once the phone has been quiet for `shakeSuppressMs`, the very same impulse is
    // taken at face value again.
    let andThenLater = Array.concat(
      shakeThenTail,
      [(upright(~ay=tapImpulse), 16. +. Motion.shakeSuppressMs +. 50.)],
    )
    expect(labels(play(andThenLater)))->toEqual(["shake", "square-up"])
  })

  test("one tap on the table tidies the board once", () => {
    // A tap spikes across several 60Hz samples; the board must not glide home twice.
    let gestures = play([
      (upright(), 0.),
      (upright(~ay=tapImpulse), 100.),
      (upright(~ay=tapImpulse), 300.), // same tap, still inside the cooldown
      (upright(~ay=tapImpulse), 100. +. Motion.squareUpCooldownMs +. 50.), // a second tap
    ])
    expect(labels(gestures))->toEqual(["square-up", "square-up"])
  })

  test("shaking the phone up and down is still a shake, not a square-up", () => {
    // The awkward case for a gravity-axis test: oscillating energy that happens to be
    // *along* gravity. Loud samples are shakes whatever direction they point, which is
    // the safe way round — a shake misread as a square-up would undo the mess mid-shake.
    let gestures = play([
      (upright(), 0.),
      (upright(~ay=30.), 100.),
      (upright(~ay=-30.), 200.),
      (upright(~ay=30.), 300.),
      (upright(~ay=-30.), 400.),
      (upright(~ay=30.), 700.),
    ])
    expect(gestures->Array.some(g => g == Motion.SquareUp))->toBe(false)
    expect(gestures->Array.length > 0)->toBe(true)
  })

  test("the square-up band sits below the shake threshold, so no gesture-free gap", () => {
    // #236: the spike's friction floor and the debug scene's shake threshold were picked
    // independently, leaving a wide band where cards drifted but nothing was counted.
    // One measure now, and the two thresholds are ordered — every gravity-axis impulse
    // above `squareUpThreshold` is *some* gesture.
    expect(Motion.squareUpThreshold < Motion.shakeThreshold)->toBe(true)
  })
})
