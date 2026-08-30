// The Motion scene: raw accelerometer readout, groundwork for reacting to a
// vigorous shake. Nothing here touches `core` — a shake is transient view state that
// would eventually just `dispatch` an ordinary action; this scene exists to confirm
// motion data actually arrives on a real phone and to learn empirically what
// "vigorous" reads as numerically.
//
// Permission is *not* owned here any more. Settings' "Wiggle Waggle" switch is
// the single owner of the motion grant — iOS remembers a denial per origin and won't
// re-prompt, so there's exactly one chance to ask and it has to land on that
// deliberate flip. This scene lost its "Request permission" button with that change:
// it now just reads the shared `Motion.current` state and shows it, subscribing to
// readings only when the shared state says we're actually listening.
//
// The point of the scene is being *readable while the phone is moving*: raw x/y/z at
// ~60Hz is an unreadable blur, so alongside the numbers there's a per-axis bar, a
// peak-magnitude hold that decays, and a shake counter that ticks when the
// gravity-corrected magnitude crosses `Motion.shakeThreshold` (debounced). The
// counter is the real deliverable — it tells us whether the threshold matches what a
// person means by "shake" without having to read anything mid-shake.
//
// Secure context only, and there's no sensor on desktop (DevTools can't usefully fake
// `devicemotion`), so this is verified with a phone pointed at the deployed build —
// hence it's also skipped by the screenshot script.

%%raw(`import "./MotionScene.css"`)

// --- Bindings ---------------------------------------------------------------
// The `devicemotion` plumbing (the event shape, the permission request, the
// secure-context check, the durable subscription) all live in `Motion` now; this
// scene only needs the frame loop.
@val external requestAnimationFrame: (unit => unit) => int = "requestAnimationFrame"
@val external cancelAnimationFrame: int => unit = "cancelAnimationFrame"

// --- Tuning -----------------------------------------------------------------
// What counts as a shake — the gravity baseline, threshold and debounce — is
// `Motion`'s to define now (it owns the board's shake subscription too), so the
// counter reads from there. The bar/peak scales below are readout-only presentation.

let axisScale = 30.0 // m/s² that fills half the per-axis bar (a hard shake tops out here)
let magScale = 30.0 // m/s² that fills the whole peak-magnitude bar
let peakDecay = 0.94 // per-frame multiplier so the peak hold eases back down between shakes

// Round to one decimal for a readout that isn't a flickering blur of digits.
let fmt = v => (Math.round(v *. 10.) /. 10.)->Float.toString

// The status line, derived from the shared Wiggle Waggle state — the scene
// reports what Settings knows rather than owning its own permission flow.
let statusText = (state: Motion.state) =>
  switch state {
  | Motion.On => "listening — move the phone"
  | Off => "Wiggle Waggle is off — turn it on in Settings to feed this readout"
  | Blocked => "motion access is blocked — Settings → Safari → Motion & Orientation Access"
  | Unavailable(NoSensor) => "this device doesn't report motion"
  | Unavailable(Insecure) => "needs a secure (https) connection"
  }

let make = (): Scene.t => {
  id: "motion",
  label: "Motion",
  kind: Demo,
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

    // One row per axis: label, live number, and a centred bar that swings left
    // (negative) or right (positive) from the middle. Returns the value/fill nodes so
    // the frame loop can update them.
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

    // The peak-magnitude hold: gravity-corrected magnitude with a bar that jumps up
    // on a shake and decays back, so a fast peak is legible after the fact.
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
    // `None` until the first `devicemotion` fires — so a device where the loop runs
    // but no reading ever arrives (desktop Chrome) stays visibly empty rather than
    // drawing the `(0,0,0)` sentinel as if it were live data.
    let latest = ref(None) // most recent x/y/z, drawn each frame
    let peak = ref(0.0) // decaying peak of the gravity-corrected magnitude
    let shakeCount = ref(0)
    let lastShake = ref(0.0) // timestamp of the last counted shake, for debounce
    let rafId = ref(None)

    // ---- The reading handler (fed by Motion's subscription) ----
    let onReading = (reading: Motion.reading) => {
      let {x, y, z}: Motion.reading = reading
      latest := Some((x, y, z))
      let excess = Math.abs(Math.sqrt(x *. x +. y *. y +. z *. z) -. Motion.gravity)
      if excess > peak.contents {
        peak := excess
      }

      // Count a shake on the threshold crossing, but only once per debounce window — a
      // single shake spikes across many 60Hz samples otherwise.
      if excess > Motion.shakeThreshold && Motion.now() -. lastShake.contents > Motion.debounceMs {
        lastShake := Motion.now()
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
      // Only draw once a reading has arrived; until then the sentinel `(0,0,0)` would
      // read as a real still-phone measurement and, worse, park the peak hold at
      // `|0 - gravity|` forever (`Math.max` re-floors it every frame).
      switch latest.contents {
      | None => ()
      | Some((x, y, z)) =>
        xValue->WebDom.setTextContent(fmt(x))
        yValue->WebDom.setTextContent(fmt(y))
        zValue->WebDom.setTextContent(fmt(z))
        drawAxis(xFill, x)
        drawAxis(yFill, y)
        drawAxis(zFill, z)

        let excess = Math.abs(Math.sqrt(x *. x +. y *. y +. z *. z) -. Motion.gravity)
        // Ease the hold toward the current reading; a fresh spike (set in onReading) is
        // never below this, so the bar rises instantly and only the fall decays.
        peak := Math.max(peak.contents *. peakDecay, excess)
        peakValue->WebDom.setTextContent(fmt(peak.contents))
        peakFill->WebDom.setAttribute(
          "style",
          `left:0;width:${fmt(Math.min(1.0, peak.contents /. magScale) *. 100.0)}%`,
        )
      }

      counter->WebDom.setTextContent(`shakes: ${Int.toString(shakeCount.contents)}`)
      rafId := Some(requestAnimationFrame(tick))
    }

    // ---- Read the shared state and, when listening, drive the readout ----
    // The permission grant is Settings' now: this scene reads `Motion.current`
    // and reflects it. Only an actively-listening state feeds the readout; every other
    // state is a static status line with no subscription (and so no battery cost).
    let state = Motion.current.contents
    setStatus(statusText(state))
    let unsub = if Motion.isOn(state) {
      let stop = Motion.subscribe(~onReading)
      rafId := Some(requestAnimationFrame(tick))
      Some(stop)
    } else {
      None
    }

    // ---- Teardown ----
    // The switcher clears the container (dropping these nodes), but the `devicemotion`
    // listener lives on `window` (via `Motion.subscribe`), so it must be detached here
    // or every re-selection of the scene stacks another one.
    () => {
      switch rafId.contents {
      | Some(id) => cancelAnimationFrame(id)
      | None => ()
      }
      switch unsub {
      | Some(stop) => stop()
      | None => ()
      }
    }
  },
}
