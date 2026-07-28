// The device motion sensor, in one place: the `devicemotion` bindings and the
// permission dance around them. Two callers read the accelerometer now — the
// `motion` debug scene (#231), which draws the raw numbers, and the card-shake
// spike (`CardShake`), which drives the table off them — and both need exactly
// this much and no more.
//
// Why `devicemotion` rather than the Generic Sensor API (`new Accelerometer(…)`):
// the latter is nicer but Chromium-only, and Safari has never shipped it.

// The `devicemotion` event payload. Read `accelerationIncludingGravity`, not
// `acceleration`: the gravity-free field is `null` on Android devices without a
// gyro. Every field is `Nullable` — the whole reading can be absent, and any axis
// can be `null` on a partial sensor.
type acceleration = {
  x: Nullable.t<float>,
  y: Nullable.t<float>,
  z: Nullable.t<float>,
}
type event = {accelerationIncludingGravity: Nullable.t<acceleration>}

// The `DeviceMotionEvent` constructor, read off `window` so its absence is a
// plain `undefined` (a bare global reference would throw) — that's the distinct
// "no DeviceMotionEvent" state below. Its static `requestPermission` exists only
// on iOS 13+; bound `Nullable` so we can fall straight through to listening where
// it's absent (Android, desktop Chrome). The call goes through `@send` so `this`
// stays the constructor.
type ctor = {requestPermission: Nullable.t<unit => promise<string>>}
@val @scope("window") external ctor: Nullable.t<ctor> = "DeviceMotionEvent"
@send external requestPermission: ctor => promise<string> = "requestPermission"

// Whether this device has the motion API at all — a distinct state from a denied
// prompt, and worth showing as one (a device with no sensor reads differently
// from a per-origin denial the user can't be re-prompted for).
let isSupported = () => ctor->Nullable.toOption->Option.isSome

// How a request for motion access came out.
type outcome =
  | Unsupported // no `DeviceMotionEvent` on this device/browser
  | Ungated // no prompt on this platform (Android, desktop Chrome) — just listen
  | Prompted(string) // iOS 13+ answered: "granted", "denied", …
  | Failed // the request itself threw

// Ask for motion access, reporting the outcome to `onOutcome`.
//
// **Must be called under a real user gesture.** iOS 13+ only honours
// `requestPermission()` with transient activation, so this belongs in a click
// handler and nowhere else; it also remembers a denial per-origin and won't
// re-prompt, which is why `Prompted` carries the state verbatim rather than a
// bare bool — a caller that shows it can tell a dead sensor from a broken one.
let requestAccess = onOutcome =>
  switch ctor->Nullable.toOption {
  | None => onOutcome(Unsupported)
  | Some(c) =>
    switch c.requestPermission->Nullable.toOption {
    | None => onOutcome(Ungated)
    | Some(_) =>
      c
      ->requestPermission
      ->Promise.thenResolve(state => onOutcome(Prompted(state)))
      ->Promise.catch(_ => {
        onOutcome(Failed)
        Promise.resolve()
      })
      ->ignore
    }
  }

// Whether an outcome means we may actually attach a listener.
let mayListen = outcome =>
  switch outcome {
  | Ungated => true
  | Prompted(state) => state == "granted"
  | Unsupported | Failed => false
  }
