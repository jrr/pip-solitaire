// The Motion scene (#231): raw accelerometer readout, groundwork for reacting to
// a vigorous shake. Nothing here touches `core` — a shake is transient view state
// that would eventually just `dispatch` an ordinary action; this scene exists to
// confirm motion data actually arrives on a real phone and to learn empirically
// what "vigorous" reads as numerically.
//
// Two APIs could deliver this. The Generic Sensor API (`new Accelerometer(…)`) is
// nicer but Chromium-only — Safari has never shipped it — so we use the universal
// `devicemotion` window event instead.
//
// The point of the scene is being *readable while the phone is moving*: raw x/y/z
// at ~60Hz is an unreadable blur, so alongside the numbers there's a per-axis bar,
// a peak-magnitude hold that decays, and a shake counter that ticks when the
// gravity-corrected magnitude crosses a threshold (debounced). The counter is the
// real deliverable — it tells us whether a threshold matches what a person means
// by "shake" without having to read anything mid-shake.
//
// Secure context only, and there's no sensor on desktop (DevTools can't usefully
// fake `devicemotion`), so this is verified with a phone pointed at the deployed
// build — hence it's also skipped by the screenshot script.

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

// The `DeviceMotionEvent` constructor, read off `window` so its absence is a
// plain `undefined` (a bare global reference would throw) — that's the distinct
// "no DeviceMotionEvent" state. Its static `requestPermission` exists only on
// iOS 13+; bound `Nullable` so we can fall straight through to attaching the
// listener where it's absent (Android, desktop Chrome). The call itself goes
// through `@send` so `this` stays the constructor.
type motionCtor = {requestPermission: Nullable.t<unit => promise<string>>}
@val @scope("window") external motionCtor: Nullable.t<motionCtor> = "DeviceMotionEvent"
@send external requestPermission: motionCtor => promise<string> = "requestPermission"

@val external requestAnimationFrame: (unit => unit) => int = "requestAnimationFrame"
@val external cancelAnimationFrame: int => unit = "cancelAnimationFrame"
@val @scope("performance") external now: unit => float = "now"

// --- Tuning -----------------------------------------------------------------

let gravity = 9.81 // subtracted from the reading's magnitude so a still phone reads ~0
let shakeThreshold = 18.0 // m/s² of gravity-corrected magnitude that counts as a shake (issue: ~15–25)
let debounceMs = 500.0 // ignore further shakes within this window, so one shake is one tick
let axisScale = 30.0 // m/s² that fills half the per-axis bar (a hard shake tops out here)
let magScale = 30.0 // m/s² that fills the whole peak-magnitude bar
let peakDecay = 0.94 // per-frame multiplier so the peak hold eases back down between shakes

// Round to one decimal for a readout that isn't a flickering blur of digits.
let fmt = v => (Math.round(v *. 10.) /. 10.)->Float.toString

let make = (): Scene.t => {
  id: "motion",
  label: "Motion",
  mount: container => {
    // ---- DOM ----
    let el = (tag, className) => {
      let e = WebDom.createElement(tag)
      e->WebDom.setAttribute("class", className)
      e
    }

    let panel = el("div", "motion-panel")
    container->WebDom.appendChild(panel)->ignore

    let status = el("p", "motion-status")
    panel->WebDom.appendChild(status)->ignore
    let setStatus = text => status->WebDom.setTextContent(text)

    let button = el("button", "motion-button")
    button->WebDom.setAttribute("type", "button")
    button->WebDom.setTextContent("Request permission")
    panel->WebDom.appendChild(button)->ignore

    // One row per axis: label, live number, and a centred bar that swings left
    // (negative) or right (positive) from the middle. Returns the value/fill
    // nodes so the frame loop can update them.
    let axisRow = name => {
      let row = el("div", "motion-axis")
      let label = el("span", "motion-axis__label")
      label->WebDom.setTextContent(name)
      let value = el("span", "motion-axis__value")
      value->WebDom.setTextContent("0")
      let track = el("div", "motion-bar")
      let fill = el("div", "motion-bar__fill")
      track->WebDom.appendChild(fill)->ignore
      row->WebDom.appendChild(label)->ignore
      row->WebDom.appendChild(value)->ignore
      row->WebDom.appendChild(track)->ignore
      panel->WebDom.appendChild(row)->ignore
      (value, fill)
    }
    let (xValue, xFill) = axisRow("x")
    let (yValue, yFill) = axisRow("y")
    let (zValue, zFill) = axisRow("z")

    // The peak-magnitude hold: gravity-corrected magnitude with a bar that jumps
    // up on a shake and decays back, so a fast peak is legible after the fact.
    let peakRow = el("div", "motion-axis")
    let peakLabel = el("span", "motion-axis__label")
    peakLabel->WebDom.setTextContent("peak")
    let peakValue = el("span", "motion-axis__value")
    peakValue->WebDom.setTextContent("0")
    let peakTrack = el("div", "motion-bar")
    let peakFill = el("div", "motion-bar__fill motion-bar__fill--peak")
    peakTrack->WebDom.appendChild(peakFill)->ignore
    peakRow->WebDom.appendChild(peakLabel)->ignore
    peakRow->WebDom.appendChild(peakValue)->ignore
    peakRow->WebDom.appendChild(peakTrack)->ignore
    panel->WebDom.appendChild(peakRow)->ignore

    // The real deliverable: how many shakes we've counted. Big and centred so it's
    // readable across the room while shaking the phone.
    let counter = el("p", "motion-counter")
    counter->WebDom.setTextContent("shakes: 0")
    panel->WebDom.appendChild(counter)->ignore

    // ---- State ----
    let latest = ref((0.0, 0.0, 0.0)) // most recent x/y/z, drawn each frame
    let peak = ref(0.0) // decaying peak of the gravity-corrected magnitude
    let shakeCount = ref(0)
    let lastShake = ref(0.0) // timestamp of the last counted shake, for debounce
    let rafId = ref(None)
    let attached = ref(false)

    // ---- The listener (attached to `window`, so teardown must detach it) ----
    let onMotion = (event: motionEvent) =>
      switch event.accelerationIncludingGravity->Nullable.toOption {
      | None => () // no gravity-inclusive reading this tick — nothing to show
      | Some(acc) =>
        let axis = n => n->Nullable.toOption->Option.getOr(0.0)
        let x = axis(acc.x)
        let y = axis(acc.y)
        let z = axis(acc.z)
        latest := (x, y, z)
        let excess = Math.abs(Math.sqrt(x *. x +. y *. y +. z *. z) -. gravity)
        if excess > peak.contents {
          peak := excess
        }

        // Count a shake on the threshold crossing, but only once per debounce
        // window — a single shake spikes across many 60Hz samples otherwise.
        if excess > shakeThreshold && now() -. lastShake.contents > debounceMs {
          lastShake := now()
          shakeCount := shakeCount.contents + 1
        }
      }

    // Position a centred axis bar: the fill grows right of centre for a positive
    // value, left of centre for a negative one, clamped to the track.
    let drawAxis = (fill, v) => {
      let half = Math.max(-1.0, Math.min(1.0, v /. axisScale)) *. 50.0
      let style =
        half >= 0.0
          ? `left:50%;width:${fmt(half)}%`
          : `left:${fmt(50.0 +. half)}%;width:${fmt(-.half)}%`
      fill->WebDom.setAttribute("style", style)
    }

    // ---- The frame loop: redraw the numbers/bars and ease the peak down ----
    let rec tick = () => {
      let (x, y, z) = latest.contents
      xValue->WebDom.setTextContent(fmt(x))
      yValue->WebDom.setTextContent(fmt(y))
      zValue->WebDom.setTextContent(fmt(z))
      drawAxis(xFill, x)
      drawAxis(yFill, y)
      drawAxis(zFill, z)

      let excess = Math.abs(Math.sqrt(x *. x +. y *. y +. z *. z) -. gravity)
      // Ease the hold toward the current reading; a fresh spike (set in onMotion)
      // is never below this, so the bar rises instantly and only the fall decays.
      peak := Math.max(peak.contents *. peakDecay, excess)
      peakValue->WebDom.setTextContent(fmt(peak.contents))
      peakFill->WebDom.setAttribute(
        "style",
        `left:0;width:${fmt(Math.min(1.0, peak.contents /. magScale) *. 100.0)}%`,
      )

      counter->WebDom.setTextContent(`shakes: ${Int.toString(shakeCount.contents)}`)
      rafId := Some(requestAnimationFrame(tick))
    }

    let attach = () =>
      if !attached.contents {
        attached := true
        WebDom.addWindowListener("devicemotion", onMotion)
        rafId := Some(requestAnimationFrame(tick))
      }

    // ---- The button: request permission (iOS), else attach directly ----
    let onRequest = () =>
      switch motionCtor->Nullable.toOption {
      | None => setStatus("no DeviceMotionEvent") // shouldn't reach here (button disabled), but explicit
      | Some(ctor) =>
        switch ctor.requestPermission->Nullable.toOption {
        | None =>
          // Android / desktop Chrome: no gate — attach straight away.
          setStatus("listening (no prompt needed)")
          attach()
        | Some(_) =>
          // iOS 13+: prompt under this real click's transient activation, then
          // show the resolved state verbatim. iOS remembers a denial per-origin
          // and won't re-prompt, so surfacing "denied" tells a dead scene from a
          // broken one.
          ctor
          ->requestPermission
          ->Promise.thenResolve(state => {
            setStatus(`permission: ${state}`)
            if state == "granted" {
              attach()
            }
          })
          ->Promise.catch(_ => {
            setStatus("permission request failed")
            Promise.resolve()
          })
          ->ignore
        }
      }
    button->WebDom.addEventListener("click", onRequest)

    // Initial status: distinguish a missing API from an un-prompted one.
    switch motionCtor->Nullable.toOption {
    | None =>
      setStatus("no DeviceMotionEvent — this device/browser has no motion sensor API")
      button->WebDom.setAttribute("disabled", "")
    | Some(_) => setStatus("tap “Request permission”, then move the phone")
    }

    // ---- Teardown ----
    // The switcher clears the container (dropping these nodes), but the
    // `devicemotion` listener is on `window`, so it must be detached here or every
    // re-selection of the scene stacks another one.
    () => {
      switch rafId.contents {
      | Some(id) => cancelAnimationFrame(id)
      | None => ()
      }
      WebDom.removeWindowListener("devicemotion", onMotion)
    }
  },
}
