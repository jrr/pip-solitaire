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

// Subscribe to *shakes* rather than raw readings (#235): the board's jostle only
// cares that a vigorous shake happened, not the numbers. Built on `subscribe`, so it
// inherits the same visibility-parking and returns the same unsubscribe thunk.
let subscribeShake = (~onShake: unit => unit): (unit => unit) => {
  let lastShake = ref(0.0)
  subscribe(~onReading=({x, y, z}) => {
    let excess = Math.abs(Math.sqrt(x *. x +. y *. y +. z *. z) -. gravity)
    if excess > shakeThreshold && now() -. lastShake.contents > debounceMs {
      lastShake := now()
      onShake()
    }
  })
}
