// The fling gesture, as pure functions: **recognition** (was that flick a fling,
// and which way did it go?) and **resolution** (given a direction and a set of
// legal destinations, which one did the player mean?).
//
// The control scheme this serves: today a move is either a complete drag from
// source to destination, or a double-tap. A drag makes you line the card up on
// its destination, which on a phone is the fiddly part. A *fling* is an
// incomplete drag — you flick the card the way you want it to go and let go
// early, and if exactly one legal destination lies that way, it goes there.
//
// The load-bearing property is that this stays **spatial**, not semantic. A
// priority list ("foundation beats cascade beats free cell") is a rule you have
// to memorise and can't see; "it goes the way I pointed" is a rule you read off
// the board. So every tie here is broken by geometry — angle, then distance —
// and never by what kind of pile a destination is.
//
// Nothing in this module touches the DOM or `core`. It takes pointer samples and
// plain points and returns verdicts, so the thresholds can be unit-tested (see
// `Fling_test`) and — the reason it exists as its own module — replayed: the
// debug scenes keep the raw samples of past gestures and re-`classify` them all
// whenever a threshold moves, which is how the numbers below get chosen.

// --- Geometry ----------------------------------------------------------------

type point = {x: float, y: float}

// One pointer sample: where the pointer was, in coordinates local to whatever
// surface the gesture is measured against, and the event's own timestamp in ms.
type sample = {x: float, y: float, t: float}

let radToDeg = r => r *. 180. /. Math.Constants.pi

let distanceBetween = (a: point, b: point) => {
  let dx = b.x -. a.x
  let dy = b.y -. a.y
  Math.sqrt(dx *. dx +. dy *. dy)
}

// The unsigned angle between two directions, folded into [0, π] — so "40° apart"
// reads the same whichever order the two are given and however many turns either
// has wound through. Done by subtraction and folding rather than a modulo so it
// stays in float arithmetic with no sign surprises around ±π.
let angleBetween = (a: float, b: float): float => {
  let full = 2. *. Math.Constants.pi
  let raw = Math.abs(a -. b)
  let wrapped = raw -. full *. Math.floor(raw /. full)
  wrapped > Math.Constants.pi ? full -. wrapped : wrapped
}

// --- Tuning ------------------------------------------------------------------

// Every threshold the gesture depends on, in one record so a scene can hold it
// in its model, step it live, and re-run the whole judgement. These want
// choosing against a real thumb on a real phone, which is what the debug scenes
// are for; the values in `defaults` are a starting point, not a conclusion.
type tuning = {
  // Net travel (px) below which a gesture is a twitch, not a throw. Also the
  // guard that keeps a tap from being read as a fling in some noise direction.
  minDistance: float,
  // Speed (px/ms) over the trailing window, at or above which the pointer counts
  // as "still moving" when it lifted. This is the real discriminator: a
  // deliberate placement decelerates onto its target and is released at rest,
  // while a fling is released mid-motion. 0.35 px/ms is 350 px/s.
  minSpeed: float,
  // How much of the tail of the gesture the release speed is measured over. Too
  // short and it's sampling noise; too long and a flick at the end of a slow
  // drag gets averaged away.
  windowMs: float,
  // How far (px) the path may retreat back along its own net direction before
  // the gesture reads as "turned back" — a drag that went out, thought better of
  // it, and came home, which must never fire a move.
  backtrackTol: float,
  // Half-angle (degrees) of the cone around the fling direction that a
  // destination has to fall inside to be a candidate at all.
  coneHalfAngle: float,
  // Angular band (degrees) within which two candidates count as equally
  // "in line" with the fling, so the nearer one wins. This is what makes a row
  // of cascade columns work: from a card below them they are nearly collinear,
  // so no angle can separate them and distance has to decide.
  angleTie: float,
}

let defaults: tuning = {
  minDistance: 24.,
  minSpeed: 0.35,
  windowMs: 70.,
  backtrackTol: 10.,
  coneHalfAngle: 40.,
  angleTie: 12.,
}

// --- Recognition -------------------------------------------------------------

// Everything measurable about a completed gesture. Reported whether or not it
// was judged a fling, because the *rejected* ones are what the tuning scene is
// really for: you want to see the numbers of the flick that didn't register.
type metrics = {
  netDistance: float, // straight line from first sample to last
  pathLength: float, // total distance actually travelled (curl shows up as the gap)
  duration: float, // ms from first sample to last
  speed: float, // px/ms over the trailing window — the release speed
  angle: float, // radians, direction of travel at release
  netAngle: float, // radians, first sample to last
  worstBacktrack: float, // furthest the path ever retreated along its net axis
}

type rejection =
  | NoMovement // fewer than two samples, or the pointer never left where it started
  | TooShort // travelled less than `minDistance`
  | Backtracked // the path reversed on itself by more than `backtrackTol`
  | TooSlow // released below `minSpeed` — a placement, not a throw

let rejectionLabel = r =>
  switch r {
  | NoMovement => "no movement"
  | TooShort => "too short"
  | Backtracked => "turned back"
  | TooSlow => "too slow at release"
  }

type verdict =
  | Fling(metrics)
  | Rejected({reason: rejection, metrics: option<metrics>})

// Measure a gesture without judging it. `None` only when there aren't two
// samples to measure between — every other degenerate case (no movement, no
// elapsed time) still yields real, if zeroed, numbers rather than a lie.
let measure = (~tuning: tuning=defaults, samples: array<sample>): option<metrics> => {
  let n = Array.length(samples)
  if n < 2 {
    None
  } else {
    let first = samples->Array.getUnsafe(0)
    let last = samples->Array.getUnsafe(n - 1)
    let at = (s: sample): point => {x: s.x, y: s.y}

    let netDistance = distanceBetween(at(first), at(last))
    let netAngle = Math.atan2(~y=last.y -. first.y, ~x=last.x -. first.x)

    let pathLength = ref(0.)
    for i in 1 to n - 1 {
      pathLength :=
        pathLength.contents +.
        distanceBetween(at(samples->Array.getUnsafe(i - 1)), at(samples->Array.getUnsafe(i)))
    }

    // The release window: walk back from the last sample to the first one at or
    // before the cutoff, so the window spans at least `windowMs` whenever the
    // gesture is long enough to have that much tail. A gesture shorter than the
    // window measures across its whole self, which is the right answer for a
    // fast little flick.
    let cutoff = last.t -. tuning.windowMs
    let idx = ref(n - 1)
    while idx.contents > 0 && (samples->Array.getUnsafe(idx.contents)).t > cutoff {
      idx := idx.contents - 1
    }
    let windowStart = samples->Array.getUnsafe(idx.contents)
    let dt = last.t -. windowStart.t
    let wdx = last.x -. windowStart.x
    let wdy = last.y -. windowStart.y
    let windowDistance = Math.sqrt(wdx *. wdx +. wdy *. wdy)
    let speed = dt > 0. ? windowDistance /. dt : 0.
    // Direction of travel *at release* — what "the way I flung it" means. A
    // window with no movement in it (the pointer sat still before lifting) has no
    // direction of its own, so fall back to the gesture's net direction; that
    // gesture is about to be rejected as too slow anyway, but the angle is still
    // worth reporting.
    let angle = windowDistance > 0. ? Math.atan2(~y=wdy, ~x=wdx) : netAngle

    // How far the path ever retreated along its own net axis. Project every
    // sample onto that axis, track the running high-water mark, and remember the
    // largest drop below it. An out-and-back drag shows up here as a big number
    // even though its net displacement is small.
    let worstBacktrack = if netDistance <= 0. {
      0.
    } else {
      let ax = (last.x -. first.x) /. netDistance
      let ay = (last.y -. first.y) /. netDistance
      let peak = ref(0.)
      let worst = ref(0.)
      samples->Array.forEach(s => {
        let projected = (s.x -. first.x) *. ax +. (s.y -. first.y) *. ay
        if projected > peak.contents {
          peak := projected
        }
        let retreat = peak.contents -. projected
        if retreat > worst.contents {
          worst := retreat
        }
      })
      worst.contents
    }

    Some({
      netDistance,
      pathLength: pathLength.contents,
      duration: last.t -. first.t,
      speed,
      angle,
      netAngle,
      worstBacktrack,
    })
  }
}

// Judge a gesture against the thresholds. The checks are ordered most-basic
// first, so the reason reported is the most informative one: a flick that barely
// moved is "too short" rather than "too slow", even though it fails both.
let classify = (~tuning: tuning=defaults, samples: array<sample>): verdict =>
  switch measure(~tuning, samples) {
  | None => Rejected({reason: NoMovement, metrics: None})
  | Some(m) =>
    if m.netDistance <= 0. {
      Rejected({reason: NoMovement, metrics: Some(m)})
    } else if m.netDistance < tuning.minDistance {
      Rejected({reason: TooShort, metrics: Some(m)})
    } else if m.worstBacktrack > tuning.backtrackTol {
      Rejected({reason: Backtracked, metrics: Some(m)})
    } else if m.speed < tuning.minSpeed {
      Rejected({reason: TooSlow, metrics: Some(m)})
    } else {
      Fling(m)
    }
  }

// --- Resolution --------------------------------------------------------------

// A place a flung card could land. `at` is the point the card would land *on* —
// for a cascade that's its current top card, not the middle of its column — so
// the angles measured here are the angles the player actually sees.
type target = {id: int, label: string, at: point}

type scored = {
  target: target,
  deviation: float, // degrees between the fling direction and this target
  distance: float, // px from the fling's origin
  inCone: bool, // within `coneHalfAngle`, i.e. a candidate at all
}

type resolution = {
  // The destination the fling resolves to, or `None` when nothing legal lies
  // that way — the caller's cue to bounce the card back and flash the moves that
  // do exist, turning a failed fling into a hint.
  best: option<target>,
  // Every target scored and ranked, winner first. The feature only needs `best`;
  // this is what lets the debug scene show *why* it won.
  ranked: array<scored>,
}

// Which target did the player mean? Candidates are the legal destinations inside
// the cone; among those, the one most *in line* with the fling wins, with
// distance breaking near-ties.
//
// One rule, two geometries. Flinging up-left from a cascade, a free cell and a
// column to the left differ sharply in angle, so angle decides and you get the
// one you pointed at. Flinging left along a row of columns, the candidates are
// nearly collinear and their angles are within noise of each other, so they land
// in one `angleTie` band and the nearest wins. Bucketing the deviation before
// sorting (rather than comparing angles with a tolerance) keeps the ordering a
// genuine total order, so the sort is well-defined.
let resolve = (
  ~tuning: tuning=defaults,
  ~origin: point,
  ~angle: float,
  targets: array<target>,
): resolution => {
  let scored = targets->Array.map(t => {
    let dx = t.at.x -. origin.x
    let dy = t.at.y -. origin.y
    let distance = Math.sqrt(dx *. dx +. dy *. dy)
    // A target sitting exactly on the origin has no direction from it; call it
    // maximally off-axis rather than letting `atan2(0, 0)` decide.
    let deviation = distance > 0. ? radToDeg(angleBetween(Math.atan2(~y=dy, ~x=dx), angle)) : 180.
    {target: t, deviation, distance, inCone: deviation <= tuning.coneHalfAngle}
  })

  let band = (s: scored) => tuning.angleTie > 0. ? Math.floor(s.deviation /. tuning.angleTie) : 0.

  let ranked = scored->Array.toSorted((a, b) =>
    if a.inCone != b.inCone {
      a.inCone ? -1. : 1.
    } else if band(a) != band(b) {
      band(a) < band(b) ? -1. : 1.
    } else if a.distance != b.distance {
      a.distance < b.distance ? -1. : 1.
    } else {
      0.
    }
  )

  {
    best: ranked->Array.get(0)->Option.flatMap(s => s.inCone ? Some(s.target) : None),
    ranked,
  }
}
