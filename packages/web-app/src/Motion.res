// The single owner of device-motion *capability and permission* (#235), split out
// of the debug `MotionScene` (#231) so the Settings "Wiggle Waggle" switch and the
// board's shake-to-jostle can share one notion of "may we listen, and are we?".
//
// iOS remembers a motion-permission *denial* per origin and won't prompt twice, so
// there's exactly one chance to ask — it has to land on a deliberate user gesture
// (the Settings switch), not at startup. This module holds the request and the
// state it resolves to; who *calls* it (Settings, or the board's first tap on
// resume) is the caller's business. The debug scene no longer owns a grant at all —
// it just reads `current` and shows it.
//
// Two APIs could deliver motion. The Generic Sensor API (`new Accelerometer(…)`) is
// nicer but Chromium-only — Safari has never shipped it — so we use the universal
// `devicemotion` window event.

// --- The switch's state machine ---------------------------------------------
// The Wiggle Waggle switch is not a bool (#235): it can be listening, off, blocked
// by an OS refusal (asked, denied — iOS won't re-prompt), or unavailable because
// the device or origin can't support motion at all.
type unavailable =
  | NoSensor // no `DeviceMotionEvent` — the device/browser has no motion API
  | Insecure // present, but an insecure (http) origin, where iOS hides the prompt

type state =
  | Off // intent off — not listening, no problem to report
  | On // listening (granted, or ungated on Android/desktop)
  | Blocked // asked and the OS refused; the switch snaps back and shows why
  | Unavailable(unavailable) // can't even ask on this device/origin

// Whether the switch should read as *on* — only the live listening state does.
// `Blocked` snaps back to the off position while still carrying its subtitle.
let isOn = state =>
  switch state {
  | On => true
  | Off | Blocked | Unavailable(_) => false
  }

// The subtitle line the Settings row carries (#235). It exists *only* to surface a
// problem: a healthy switch (off or listening) shows nothing under its title, so a
// present subtitle always means "here's what's wrong".
let subtitle = state =>
  switch state {
  | Off | On => None
  | Blocked =>
    Some("Motion access is off. Turn it on in Settings → Safari → Motion & Orientation Access.")
  | Unavailable(NoSensor) => Some("This device doesn't report motion.")
  | Unavailable(Insecure) => Some("Needs a secure (https) connection.")
  }

// The app-wide switch state, owned by Settings (#235). Settings writes it on every
// resolution/flip; the debug `MotionScene` reads it so it can show the shared state
// rather than owning its own "Request permission" button.
let current: ref<state> = ref(Off)

// --- Bindings ---------------------------------------------------------------

// The `devicemotion` event payload. Read `accelerationIncludingGravity`, not
// `acceleration`: the gravity-free field is `null` on Android devices without a
// gyro. Every field is `Nullable` — the whole reading can be absent, and any axis
// can be `null` on a partial sensor.
type acceleration = {
  x: Nullable.t<float>,
  y: Nullable.t<float>,
  z: Nullable.t<float>,
}
type motionEvent = {accelerationIncludingGravity: Nullable.t<acceleration>}

// The `DeviceMotionEvent` constructor, read off `window` so its absence is a plain
// `undefined` (a bare global reference would throw) — the distinct "no
// DeviceMotionEvent" state. Its static `requestPermission` exists only on iOS 13+;
// bound `Nullable` so we can fall straight through to attaching the listener where
// it's absent (Android, desktop Chrome). The call goes through `@send` so `this`
// stays the constructor.
type motionCtor = {requestPermission: Nullable.t<unit => promise<string>>}
@val @scope("window") external motionCtor: Nullable.t<motionCtor> = "DeviceMotionEvent"
@send external requestPermission: motionCtor => promise<string> = "requestPermission"

// Whether we're on a secure origin. On an insecure origin iOS doesn't expose
// `requestPermission`, so without this check an insecure iOS page would read as
// ungated (indistinguishable from a healthy Android device) and quietly report a
// listening state that never fires — see the issue's `Unavailable` rationale.
@val @scope("window") external isSecureContext: bool = "isSecureContext"

// `document.hidden` and the `visibilitychange` event, used to park the subscription
// while the page is backgrounded (below). Read `hidden` live at each visibility flip.
@val @scope("document") external documentHidden: bool = "hidden"
@val @scope("document")
external addDocListener: (string, unit => unit) => unit = "addEventListener"
@val @scope("document")
external removeDocListener: (string, unit => unit) => unit = "removeEventListener"

@val @scope("performance") external now: unit => float = "now"

// --- Capability & permission -------------------------------------------------

// Why motion is unavailable on this device/origin, or `None` if it's usable (which
// may still need a permission prompt). The secure-context check comes first so an
// insecure iOS origin reports `Insecure` rather than falling through to the ungated
// Android path (see `isSecureContext`).
let unavailableReason = (): option<unavailable> =>
  if !isSecureContext {
    Some(Insecure)
  } else {
    switch motionCtor->Nullable.toOption {
    | None => Some(NoSensor)
    | Some(_) => None
    }
  }

// The switch state to *open* in, given the persisted intent (#235). Availability is
// checked first — an unsupported device/origin shows its problem regardless of what
// was saved — then the saved intent decides on vs off. This never prompts; the real
// grant is deferred to the first user gesture (Settings, or the board's first tap).
let initialState = (~wantsShake): state =>
  switch unavailableReason() {
  | Some(reason) => Unavailable(reason)
  | None => wantsShake ? On : Off
  }

// Ask the OS for motion access and resolve to the state it lands in (#235). MUST be
// called synchronously under a real user gesture — iOS requires transient activation
// for the prompt and remembers a denial per origin, so this is the one shot. On
// Android/desktop, where the API is ungated, it resolves `On` without any prompt; if
// access was already granted a prior session, iOS resolves it silently `On` too,
// which is what makes this safe to call from the resume path's first tap.
let requestAccess = (): promise<state> =>
  switch unavailableReason() {
  | Some(reason) => Promise.resolve(Unavailable(reason))
  | None =>
    switch motionCtor->Nullable.toOption {
    | None => Promise.resolve(Unavailable(NoSensor)) // unavailableReason already caught this
    | Some(ctor) =>
      switch ctor.requestPermission->Nullable.toOption {
      | None => Promise.resolve(On) // Android / desktop Chrome: ungated
      | Some(_) =>
        ctor
        ->requestPermission
        ->Promise.thenResolve(result => result == "granted" ? On : Blocked)
        ->Promise.catch(_ => Promise.resolve(Blocked))
      }
    }
  }

// --- Subscriptions -----------------------------------------------------------

// A single decoded reading, gravity included. Absent axes read 0 (a partial sensor).
type reading = {x: float, y: float, z: float}

// Subscribe to `devicemotion` readings, returning an unsubscribe thunk (#235).
//
// The subscription is *durable but battery-polite*: it's dropped whenever the page
// is hidden and re-attached when it returns (`visibilitychange`), so a phone in a
// pocket isn't fielding ~60Hz events for a board no one is looking at. The rAF loop
// that draws already parks when cards settle, but the listener would keep firing
// regardless — this is where that hygiene lands (see the issue). The returned thunk
// tears down both the motion listener and the visibility watcher.
let subscribe = (~onReading: reading => unit): (unit => unit) => {
  let handler = (event: motionEvent) =>
    switch event.accelerationIncludingGravity->Nullable.toOption {
    | None => () // no gravity-inclusive reading this tick
    | Some(acc) =>
      let axis = n => n->Nullable.toOption->Option.getOr(0.0)
      onReading({x: axis(acc.x), y: axis(acc.y), z: axis(acc.z)})
    }

  let listening = ref(false)
  let attach = () =>
    if !listening.contents {
      listening := true
      WebDom.addWindowListener("devicemotion", handler)
    }
  let detach = () =>
    if listening.contents {
      listening := false
      WebDom.removeWindowListener("devicemotion", handler)
    }

  // Park while hidden, resume when visible — the battery-hygiene the issue calls for.
  let onVisibility = () => documentHidden ? detach() : attach()

  attach()
  addDocListener("visibilitychange", onVisibility)

  () => {
    detach()
    removeDocListener("visibilitychange", onVisibility)
  }
}

// The gravity-corrected magnitude above which a reading counts as a "shake", and the
// debounce that keeps one physical shake — which spikes across many 60Hz samples —
// from counting as many. Lifted from the debug scene's empirically-tuned values (#231).
let gravity = 9.81
let shakeThreshold = 18.0
let debounceMs = 500.0

// --- Gestures ----------------------------------------------------------------
// Two gestures come off the same stream (#236), told apart by *where* the energy is
// relative to gravity rather than by how much of it there is:
//
//   - A shake is oscillating energy, mostly *perpendicular* to gravity.
//   - A square-up — tapping a deck down on the table, which is what people actually
//     do with cards — is a single sharp impulse *along* it.
//
// Projecting onto the gravity estimate we already low-pass out of the stream makes
// the split orientation-independent for free: "down" is device −y held upright and
// −z flat on a table, and the estimate points the opposite way (a still phone reads
// +9.81 along whichever axis is up), so a tap-down's abrupt *stop* is a strongly
// positive projection onto it. The happy accident #236 notes is worth keeping: simply
// setting the phone down is also a gravity-axis spike, so the likeliest false
// positive maps to the *benign* gesture — it tidies the board rather than messing it
// up further.

type gesture =
  | Shake(reading) // the high-passed acceleration, which the board throws cards along
  | SquareUp

// One reading, decomposed against the running gravity estimate: how much
// acceleration is left once gravity is removed (`excess`), how much of that lies
// along the gravity axis (`along`, positive = the phone being stopped on its way
// down) and how much across it (`perp`). This is the *one* gravity-corrected measure
// now — the board and the debug scene's readout both read it, so the two can't drift
// apart the way the spike's friction floor and the debug threshold did (#236).
type split = {excess: float, along: float, perp: float}

// How hard a gravity-axis impulse must be to read as a square-up. Deliberately
// *below* `shakeThreshold`: anything more vigorous than that is a shake whatever
// direction it points, so the ambiguous middle band belongs to the gentler gesture
// and there's no band where cards drift but no gesture fires.
let squareUpThreshold = 12.0

// How much the impulse must be dominated by its gravity-axis component to count. A
// square-up is a single axial tap; a shake that happens to be swung vertically is
// not, and the loud-sample suppression below is the other half of that defence.
let squareUpDominance = 2.0

// Two cooldowns (#236). The first is the important one: a vigorous shake's tail
// decays *through* the square-up band, so without a quiet period after the last loud
// sample the shake tidies the very board it just messed up. The second just keeps one
// tap from firing twice.
let shakeSuppressMs = 700.0
let squareUpCooldownMs = 900.0

// The gravity estimate's low-pass coefficient, per reading at ~60Hz: slow enough that
// a shake's oscillation stays in the high-passed remainder rather than being tracked
// out of it, fast enough to follow a real orientation change within a second or so.
let gravityAlpha = 0.08

// The gesture detector's state: the gravity estimate, the last decomposition (which
// the debug readout draws), and the three timestamps the cooldowns are measured from.
// `None` gravity means "not seeded yet" — the first reading seeds it, since a phone
// that has just started reporting is overwhelmingly likely to be near rest, and
// seeding beats easing up from zero (which would read as one huge fake impulse).
type detector = {
  gravity: option<reading>,
  last: split,
  lastLoudMs: float, // last reading above `shakeThreshold`, however it was classified
  lastShakeMs: float, // last *emitted* shake, for the debounce
  lastSquareUpMs: float,
}

// Far enough in the past that the first gesture of a session is never held back by a
// cooldown (the same sentinel idiom as the board's double-tap clock).
let longAgo = -1000000.

let newDetector = {
  gravity: None,
  last: {excess: 0., along: 0., perp: 0.},
  lastLoudMs: longAgo,
  lastShakeMs: longAgo,
  lastSquareUpMs: longAgo,
}

// Feed one reading in at time `atMs` and get back the advanced detector and whichever
// gesture — if any — that reading completed. Pure, so the whole classification
// (thresholds, projection, both cooldowns) is testable off synthetic sample streams
// without a device; `subscribeGestures` below is the thin live wrapper.
let step = (d: detector, ~reading: reading, ~atMs: float): (detector, option<gesture>) => {
  // Track gravity, then subtract it: what's left is the acceleration the *hand* is
  // applying. Note this reads gravity out of the very sample being classified, which
  // costs a hair of sensitivity (α of the impulse leaks into the estimate) and keeps
  // the estimate honest when the phone is simply re-oriented.
  let g = switch d.gravity {
  | None => reading
  | Some(g) => {
      x: g.x +. (reading.x -. g.x) *. gravityAlpha,
      y: g.y +. (reading.y -. g.y) *. gravityAlpha,
      z: g.z +. (reading.z -. g.z) *. gravityAlpha,
    }
  }
  let h = {x: reading.x -. g.x, y: reading.y -. g.y, z: reading.z -. g.z}
  let excess = Math.sqrt(h.x *. h.x +. h.y *. h.y +. h.z *. h.z)
  let gMag = Math.sqrt(g.x *. g.x +. g.y *. g.y +. g.z *. g.z)
  // Signed projection onto the gravity estimate's unit vector. A sensor reporting all
  // zeroes (`gMag == 0`) has no axis to project onto, so nothing is along anything.
  let along = gMag > 0.001 ? (h.x *. g.x +. h.y *. g.y +. h.z *. g.z) /. gMag : 0.
  let perpSquared = excess *. excess -. along *. along
  let perp = perpSquared > 0. ? Math.sqrt(perpSquared) : 0.
  let split = {excess, along, perp}

  let loud = excess > shakeThreshold
  let advanced = {
    ...d,
    gravity: Some(g),
    last: split,
    lastLoudMs: loud ? atMs : d.lastLoudMs,
  }

  if loud {
    // Anything this vigorous is a shake, whichever way it points — a shake read as a
    // square-up would tidy the board mid-mess, which is the one failure that matters.
    // Debounced samples still refresh `lastLoudMs` above, so the suppression window
    // below spans the *whole* shake rather than just its first spike.
    atMs -. d.lastShakeMs > debounceMs
      ? ({...advanced, lastShakeMs: atMs}, Some(Shake(h)))
      : (advanced, None)
  } else if (
    along > squareUpThreshold &&
    along > perp *. squareUpDominance &&
    atMs -. advanced.lastLoudMs > shakeSuppressMs &&
    atMs -. d.lastSquareUpMs > squareUpCooldownMs
  ) {
    ({...advanced, lastSquareUpMs: atMs}, Some(SquareUp))
  } else {
    (advanced, None)
  }
}

// Subscribe to *gestures* rather than raw readings (#235, #236): the board only cares
// that a shake happened (and which way) or that the deck was tapped down, not the
// numbers. Built on `subscribe`, so it inherits the same visibility-parking and
// returns the same unsubscribe thunk.
let subscribeGestures = (~onGesture: gesture => unit): (unit => unit) => {
  let detector = ref(newDetector)
  subscribe(~onReading=reading => {
    let (advanced, gesture) = step(detector.contents, ~reading, ~atMs=now())
    detector := advanced
    switch gesture {
    | Some(g) => onGesture(g)
    | None => ()
    }
  })
}
