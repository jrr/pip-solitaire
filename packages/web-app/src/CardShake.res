// Shake the phone, and the cards on the table shift — a spike (#231 follow-up)
// exploring whether the accelerometer can drive the resting-card variance past
// what the deterministic hand-placed tilt (#65) reaches on its own.
//
// This is deliberately *not* a physics engine. Each card is one damped spring
// with a drifting rest point — six floats and a rest triple — driven by a single
// shared acceleration vector. That's enough to buy the three things that make
// motion read as believable:
//
//   - **Lag.** Cards are driven *opposite* the phone's acceleration, so a flick
//     right slides them left in the frame and they catch up after. That's plain
//     inertia, and it reads as "these have weight" rather than "the board is
//     being blown around".
//   - **Disagreement.** A uniform response reads as camera shake, not as loose
//     cards. Every card takes its own responsiveness and spin from a hash of its
//     identity, and a buried card barely moves at all — it's pinned under the
//     ones above it, which also keeps deep fans readable mid-shake.
//   - **Consequence.** The rest point creeps toward wherever the card has been
//     pushed, clamped, so a real shake leaves the tableau *permanently* messier
//     than the dealt layout and it stays that way. This is the "further skew than
//     the built-in randomness" part: `maxDrift` is several times the ±2.5° the
//     deterministic tilt allows.
//
// Everything here is purely visual. The offsets are written as custom properties
// on the card *wrapper* and consumed by the inner `.card-art` transform (the same
// route `--card-rot` already takes), so the wrapper's `left`/`top` — and therefore
// its `boundingRect`, and therefore drop targeting, the geometry invariants and
// the screenshot report — never see any of it. A shake can make the board look
// wrong; it can't make it *play* wrong.
//
// Spike scope: gated entirely behind `?shake=on` (see `AppUrl`), tuning hardcoded
// below, nothing persisted. There's no Settings toggle yet and the `devicemotion`
// bindings are duplicated from `MotionScene` rather than shared, so this stands
// alone against `main` instead of waiting on that scene's PR.

// --- Bindings ---------------------------------------------------------------

// The `devicemotion` payload and the permission dance come from `Motion`, shared
// with the `motion` debug scene; `WebDom`'s window-scoped listener pair (generic in
// the event, so it serves both the motion listener and the permission click)
// attaches them.

// `screen.orientation.angle` (0 / 90 / 180 / 270), the viewport's clockwise
// rotation — needed because `devicemotion` axes are fixed to the *device*, not to
// the screen, so a landscape board would otherwise shake sideways. Guarded
// `Nullable` exactly as `CutoutSide` does: absent on older iOS and off-browser.
type screenOrientation = {"angle": float}
@val @scope(("window", "screen"))
external screenOrientation: Nullable.t<screenOrientation> = "orientation"

@val external requestAnimationFrame: (unit => unit) => int = "requestAnimationFrame"
@val external cancelAnimationFrame: int => unit = "cancelAnimationFrame"
@val @scope("performance") external now: unit => float = "now"
@val external matchMedia: string => {"matches": bool} = "matchMedia"

type style
@get external style: Html.element => style = "style"
@send external setProperty: (style, string, string) => unit = "setProperty"
type tokenList
@get external classList: Html.element => tokenList = "classList"
@send external addClass: (tokenList, string) => unit = "add"
@send external removeClass: (tokenList, string) => unit = "remove"

// --- Tuning -----------------------------------------------------------------
//
// Hardcoded for the spike. The numbers that most want a phone in hand are
// `driveGain` (how far a given shake throws a card) and `creep` (how fast the
// mess becomes permanent).

let gravitySmoothing = 0.9 // per-sample weight of the running gravity estimate (the high-pass)
let frictionThreshold = 4.0 // m/s² of gravity-corrected motion below which nothing moves at all
let driveGain = 90.0 // px/s² of card acceleration per m/s² of phone acceleration
let stiffness = 120.0 // spring constant pulling a card back to its rest point (1/s²)
let damping = 14.0 // velocity damping; below critical (≈21.9) so cards overshoot and wobble
let rotGain = 0.2 // deg/s² of spin per px/s² of drive, before the card's own spin factor
let rotStiffness = 70.0
let rotDamping = 9.0
let creep = 3.0 // 1/s at which a card's rest point follows where it's been pushed
let maxDrift = 12.0 // px cap on that accumulated displacement
let maxDriftRot = 8.0 // degree cap on it — several times the ±2.5° of the dealt tilt
// A hard ceiling on the *live* displacement, above the drift cap so a shake still
// visibly overshoots before settling back. Without it a card's spring equilibrium
// is just drive/stiffness, which an unusually violent reading can put well off the
// pile — the effect should stay a jostle, never a card sliding across the table.
let maxOffset = 20.0
let maxOffsetRot = 14.0
// How fast an unrefreshed drive dies away (seconds to 1/e). The sensor pushes a
// reading in and the frame loop bleeds it back out, so the drive is an *impulse*
// that decays rather than a value that latches: during a real shake the readings
// arrive far faster than this and keep it topped up, but the moment the phone goes
// still — or the sensor simply stops reporting — the cards stop being pushed and
// settle. (Left latched, the last reading before the phone came to rest would go on
// shoving every card forever, and the loop would never park.)
let driveTau = 0.08
let burialGrip = 0.6 // how much each card above pins the one below (mobility falloff)
let sleepEpsilon = 0.05 // px (and deg) of residual motion under which the loop parks itself
let maxFrame = 0.05 // s: clamp the timestep so a backgrounded tab doesn't explode the spring

// --- Per-card state ---------------------------------------------------------

// One card's spring. `offset` is what's currently published to the CSS, `rest`
// the drifting point it's pulled toward (zero until a shake displaces it), and
// `mobility` how freely it may move right now — 1.0 for a loose or top card,
// falling off with each card stacked on it, written by the layout each reflow.
type entry = {
  el: Html.element,
  // Deterministic per-card variation, folded from the card's identity by the
  // caller so it's stable across reflows — the same property the dealt tilt has.
  seed: int,
  mobility: ref<float>,
  offsetX: ref<float>,
  offsetY: ref<float>,
  offsetRot: ref<float>,
  velX: ref<float>,
  velY: ref<float>,
  velRot: ref<float>,
  restX: ref<float>,
  restY: ref<float>,
  restRot: ref<float>,
  // Last values written to the DOM, so a settled card costs no style writes.
  wroteX: ref<float>,
  wroteY: ref<float>,
  wroteRot: ref<float>,
}

let makeEntry = (~el, ~seed) => {
  el,
  seed,
  mobility: ref(1.0),
  offsetX: ref(0.0),
  offsetY: ref(0.0),
  offsetRot: ref(0.0),
  velX: ref(0.0),
  velY: ref(0.0),
  velRot: ref(0.0),
  restX: ref(0.0),
  restY: ref(0.0),
  restRot: ref(0.0),
  wroteX: ref(0.0),
  wroteY: ref(0.0),
  wroteRot: ref(0.0),
}

// How readily this card answers a shake: a spread around 1 so no two neighbours
// move in lockstep. Coprime multipliers against the modulus keep the sequence
// from banding across a pile.
let responsiveness = entry => 0.7 +. Int.toFloat(Int.mod(entry.seed * 7, 61)) /. 61.0 *. 0.6

// Which way this card twists under a shove, and how hard: a signed lever arm, so
// a pile fans open rather than every card cocking the same way.
let spin = entry => Int.toFloat(Int.mod(entry.seed * 13, 37)) /. 37.0 *. 2.0 -. 1.0

// Clear a card's accumulated disarray — it's just been placed by hand, so it sits
// where the player put it, not where the last shake left it.
let settle = entry => {
  entry.restX := 0.0
  entry.restY := 0.0
  entry.restRot := 0.0
}

// The mobility of the card `above` cards deep in its pile: the top card (and any
// loose card) moves freely, each card stacked on top pins the one below further.
let mobilityAtDepth = depthFromTop => 1.0 /. (1.0 +. burialGrip *. Int.toFloat(depthFromTop))

let clamp = (v, limit) => Math.max(-.limit, Math.min(limit, v))

// --- The driver -------------------------------------------------------------

// Advance one card by `dt` under the shared drive vector, and return whether it's
// still moving (so the loop knows when the whole board has settled).
let step = (entry, ~driveX, ~driveY, ~dt) => {
  let m = entry.mobility.contents *. responsiveness(entry)
  let ax = driveX *. m
  let ay = driveY *. m

  // Linear: a damped spring about the (drifting) rest point, pushed by the drive.
  let accelX =
    ax -.
    stiffness *. (entry.offsetX.contents -. entry.restX.contents) -.
    damping *. entry.velX.contents
  let accelY =
    ay -.
    stiffness *. (entry.offsetY.contents -. entry.restY.contents) -.
    damping *. entry.velY.contents
  entry.velX := entry.velX.contents +. accelX *. dt
  entry.velY := entry.velY.contents +. accelY *. dt
  // Clamped as it's written, so no reading — however violent, however long it's
  // sustained — can walk a card off its pile. The spring's own equilibrium is
  // `drive / stiffness`, which is unbounded in the drive; this is the backstop.
  entry.offsetX := clamp(entry.offsetX.contents +. entry.velX.contents *. dt, maxOffset)
  entry.offsetY := clamp(entry.offsetY.contents +. entry.velY.contents *. dt, maxOffset)

  // Angular: the same spring driven by the drive's magnitude through this card's
  // signed lever, so a shove in any direction twists it its own way.
  let torque = spin(entry) *. Math.sqrt(ax *. ax +. ay *. ay) *. rotGain
  let accelRot =
    torque -.
    rotStiffness *. (entry.offsetRot.contents -. entry.restRot.contents) -.
    rotDamping *. entry.velRot.contents
  entry.velRot := entry.velRot.contents +. accelRot *. dt
  entry.offsetRot := clamp(entry.offsetRot.contents +. entry.velRot.contents *. dt, maxOffsetRot)

  // The disarray: the rest point creeps toward wherever the card has been pushed
  // — friction re-grabbing it at its new spot — clamped so a long shake messes the
  // table up without ever throwing a card clear of its pile.
  entry.restX :=
    clamp(
      entry.restX.contents +. (entry.offsetX.contents -. entry.restX.contents) *. creep *. dt,
      maxDrift,
    )
  entry.restY :=
    clamp(
      entry.restY.contents +. (entry.offsetY.contents -. entry.restY.contents) *. creep *. dt,
      maxDrift,
    )
  entry.restRot :=
    clamp(
      entry.restRot.contents +. (entry.offsetRot.contents -. entry.restRot.contents) *. creep *. dt,
      maxDriftRot,
    )

  // Still awake while it's either moving or still travelling toward its rest point.
  Math.abs(entry.velX.contents) +.
  Math.abs(entry.velY.contents) +.
  Math.abs(entry.offsetX.contents -. entry.restX.contents) +.
  Math.abs(entry.offsetY.contents -. entry.restY.contents) +.
  Math.abs(entry.velRot.contents) +.
  Math.abs(entry.offsetRot.contents -. entry.restRot.contents) > sleepEpsilon
}

// Publish a card's offsets, skipping the write when nothing moved enough to see —
// 52 cards × 3 properties every frame is worth not paying for a settled board.
let publish = entry => {
  let dx = entry.offsetX.contents
  let dy = entry.offsetY.contents
  let rot = entry.offsetRot.contents
  if (
    Math.abs(dx -. entry.wroteX.contents) > 0.05 ||
    Math.abs(dy -. entry.wroteY.contents) > 0.05 ||
    Math.abs(rot -. entry.wroteRot.contents) > 0.05
  ) {
    entry.wroteX := dx
    entry.wroteY := dy
    entry.wroteRot := rot
    let s = style(entry.el)
    s->setProperty("--shake-x", Float.toString(dx) ++ "px")
    s->setProperty("--shake-y", Float.toString(dy) ++ "px")
    s->setProperty("--shake-rot", Float.toString(rot) ++ "deg")
  }
}

// Map a device-frame acceleration onto the screen. `devicemotion` axes are fixed
// to the *device*, so a landscape board needs the reading rotated by the
// viewport's own angle; device y also points *up* the screen where CSS y points
// down. Returns the vector to drive the cards with — negated, because a card lags
// behind the phone rather than being pushed along with it.
//
// The two landscape signs here are the one thing in this spike that really wants
// checking with a phone in hand; portrait (angle 0, the common case) is the
// identity and is straightforward.
let driveFor = (~ax, ~ay, ~angle) => {
  let radians = angle *. Math.Constants.pi /. 180.0
  let c = Math.cos(radians)
  let s = Math.sin(radians)
  let screenX = ax *. c +. ay *. s
  let screenUp = -.ax *. s +. ay *. c
  // Negate for inertia (cards lag), then flip the vertical to CSS's downward y —
  // which for the y component cancels back out.
  (-.screenX *. driveGain, screenUp *. driveGain)
}

// The class hung on the board host for as long as cards are actually moving, so
// the CSS can drop the resting-card transform transition that would otherwise
// smear the per-frame writes.
let activeClass = "card-shake-active"

// Start driving `cards()` from the accelerometer, marking `host` while a shake is
// live. Returns a teardown thunk: the `devicemotion` listener is on `window`, so
// it outlives the scene's nodes and must be detached by hand.
//
// iOS 13+ won't hand over motion data without `requestPermission()` under a real
// user gesture, so — this being a spike with no UI of its own — the first click
// anywhere does the asking. iOS's own prompt is the only affordance; Android and
// desktop Chrome attach on that same first click without one.
let attach = (~host: Html.element, ~cards: unit => array<entry>) => {
  // The OS "reduce motion" preference outranks the URL knob: someone who's asked
  // for less movement shouldn't get a table that wobbles when they walk.
  if matchMedia("(prefers-reduced-motion: reduce)")["matches"] {
    () => ()
  } else {
    // The running estimate of gravity, per axis. Subtracting it high-passes the
    // signal: slow tilting converges into the estimate and moves nothing, while a
    // jerk outruns it and drives the cards.
    //
    // Seeded from the *first* reading rather than from an assumed pose. Guessing —
    // "9.81 on y, a phone held upright" — is wrong for a phone lying flat on a
    // table, where gravity is on z, and the whole 9.81 then lands in the high-passed
    // signal as a phantom shake that scatters the board the instant the listener
    // attaches. Adopting the first sample wholesale makes the initial error exactly
    // zero for any pose.
    let seeded = ref(false)
    let gx = ref(0.0)
    let gy = ref(0.0)
    let gz = ref(0.0)
    let driveX = ref(0.0)
    let driveY = ref(0.0)
    let rafId = ref(None)
    let lastFrame = ref(0.0)

    let angle = () =>
      switch screenOrientation->Nullable.toOption {
      | Some(o) => o["angle"]
      | None => 0.0
      }

    let rec tick = () => {
      let t = now()
      let dt = Math.min(maxFrame, (t -. lastFrame.contents) /. 1000.0)
      lastFrame := t
      let entries = cards()
      let awake = entries->Array.reduce(false, (awake, entry) => {
        let moving = step(entry, ~driveX=driveX.contents, ~driveY=driveY.contents, ~dt)
        publish(entry)
        awake || moving
      })

      // Bleed the drive back toward zero (see `driveTau`). Incoming readings top it
      // up far faster than this during an actual shake, so what this really governs
      // is how quickly the board gives up once the readings stop.
      let decay = Math.exp(-.dt /. driveTau)
      driveX := driveX.contents *. decay
      driveY := driveY.contents *. decay

      // Park the loop once every card has reached its rest point and the phone is
      // quiet; the next reading above the friction threshold restarts it. Restoring
      // the transition on the way out means the *settled* board still eases when the
      // layout re-tilts a card.
      if awake || Math.abs(driveX.contents) +. Math.abs(driveY.contents) > 1.0 {
        rafId := Some(requestAnimationFrame(tick))
      } else {
        rafId := None
        classList(host)->removeClass(activeClass)
      }
    }

    let wake = () =>
      switch rafId.contents {
      | Some(_) => ()
      | None =>
        lastFrame := now()
        classList(host)->addClass(activeClass)
        rafId := Some(requestAnimationFrame(tick))
      }

    let onMotion = (event: Motion.event) =>
      switch event.accelerationIncludingGravity->Nullable.toOption {
      | None => () // no gravity-inclusive reading this tick
      | Some(acc) =>
        let axis = n => n->Nullable.toOption->Option.getOr(0.0)
        let x = axis(acc.x)
        let y = axis(acc.y)
        let z = axis(acc.z)

        // Adopt the very first reading as the gravity estimate outright (see above)
        // and drive nothing off it, so attaching the listener never itself looks like
        // a shake. Every later sample only nudges the estimate.
        if !seeded.contents {
          seeded := true
          gx := x
          gy := y
          gz := z
        }
        // Fold this sample into the gravity estimate, then drive on what's left.
        gx := gx.contents *. gravitySmoothing +. x *. (1.0 -. gravitySmoothing)
        gy := gy.contents *. gravitySmoothing +. y *. (1.0 -. gravitySmoothing)
        gz := gz.contents *. gravitySmoothing +. z *. (1.0 -. gravitySmoothing)
        let ax = x -. gx.contents
        let ay = y -. gy.contents
        let az = z -. gz.contents

        // Static friction: a pocket jostle or a walking gait shouldn't slowly
        // destroy the board, so anything under the threshold drives nothing at all.
        // The z axis counts toward "is this a shake?" even though it can't push a
        // card across a 2-D table.
        if Math.sqrt(ax *. ax +. ay *. ay +. az *. az) > frictionThreshold {
          let (dx, dy) = driveFor(~ax, ~ay, ~angle=angle())
          driveX := dx
          driveY := dy
          wake()
        } else {
          driveX := 0.0
          driveY := 0.0
        }
      }

    // The first click is the permission gesture. Where no prompt is needed the
    // listener attaches on that same click, which keeps one code path for both.
    let listening = ref(false)
    let startListening = () =>
      if !listening.contents {
        listening := true
        WebDom.addWindowListener("devicemotion", onMotion)
      }

    // Unlike the debug scene, which narrates every outcome to a status line, the
    // spike has no UI of its own: an unsupported sensor or a refused prompt just
    // leaves the knob inert, and the board plays exactly as it would without it.
    let rec onFirstClick = () => {
      WebDom.removeWindowListener("click", onFirstClick)
      Motion.requestAccess(outcome =>
        if Motion.mayListen(outcome) {
          startListening()
        }
      )
    }
    WebDom.addWindowListener("click", onFirstClick)

    () => {
      WebDom.removeWindowListener("click", onFirstClick)
      if listening.contents {
        WebDom.removeWindowListener("devicemotion", onMotion)
      }
      switch rafId.contents {
      | Some(id) => cancelAnimationFrame(id)
      | None => ()
      }
    }
  }
}
