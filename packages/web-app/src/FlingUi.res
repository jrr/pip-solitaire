// Shared scaffolding for the two fling debug scenes: the pointer surface they
// both collect gestures on, and the handful of view atoms they both draw with.
//
// The surface is a plain transparent element that owns the pointer loop. Both
// scenes splice it into their view with `Html.node` — the reconciler leaves an
// externally-owned node completely alone, so the listeners attached here survive
// every re-render — and then draw *over* it with an `<svg>` sibling that has
// `pointer-events: none`. That split is what lets the visuals be an ordinary
// diffed view (a model in, a picture out) while the gesture stays imperative,
// which is what a pointer stream actually is.

@val external requestAnimationFrame: (unit => unit) => int = "requestAnimationFrame"
@val external cancelAnimationFrame: int => unit = "cancelAnimationFrame"

// Where a scene's gesture stream goes. Samples are in coordinates local to the
// surface, so a scene never has to think about the page.
type sink = {
  onBegin: Fling.sample => unit,
  onMove: Fling.sample => unit,
  onEnd: Fling.sample => unit,
  onCancel: unit => unit,
  // The surface's live pixel size, reported once it's in the document and on
  // every resize — the scenes lay their contents out in raw pixels (an `<svg>`
  // with no `viewBox`, so one user unit is one CSS pixel and no aspect-ratio
  // scaling can distort the angles this whole exercise is about).
  onResize: (float, float) => unit,
}

// Build the surface and wire the pointer loop to `sink`. Returns the element to
// splice into a view, plus a `measure` thunk to call once it's actually in the
// document (a scene mounts while still detached, so the first measurement has to
// wait a frame).
let makeSurface = (sink: sink) => {
  let el = WebDom.createElement("div")
  el->WebDom.setAttribute("class", "fling-surface")

  // The pointer currently owning the gesture. A second finger landing mid-fling
  // is ignored rather than interleaved into the sample stream — two pointers
  // averaged together would read as a gesture nobody made.
  let active = ref(None)

  let sampleAt = (ev): Fling.sample => {
    let r = Pointer.boundingRect(el)
    {
      x: Pointer.clientX(ev) -. r.left,
      y: Pointer.clientY(ev) -. r.top,
      t: Pointer.timeStamp(ev),
    }
  }

  // Only the owning pointer's events feed the stream; everything else is noise.
  let ifActive = (ev, f) =>
    switch active.contents {
    | Some(id) if id == Pointer.pointerId(ev) => f(id)
    | _ => ()
    }

  el->Pointer.on("pointerdown", ev => {
    let id = Pointer.pointerId(ev)
    // Capture, so the samples keep coming after the pointer leaves the surface —
    // a fling routinely outruns its own start element.
    el->Pointer.setCapture(id)
    active := Some(id)
    sink.onBegin(sampleAt(ev))
  })
  el->Pointer.on("pointermove", ev => ifActive(ev, _ => sink.onMove(sampleAt(ev))))
  el->Pointer.on("pointerup", ev =>
    ifActive(ev, id => {
      el->Pointer.releaseCapture(id)
      active := None
      sink.onEnd(sampleAt(ev))
    })
  )
  // A cancelled pointer (the OS taking the gesture) must never resolve to a
  // move — it's an interruption, not a throw.
  el->Pointer.on("pointercancel", ev =>
    ifActive(ev, id => {
      el->Pointer.releaseCapture(id)
      active := None
      sink.onCancel()
    })
  )

  let measure = () => {
    let r = Pointer.boundingRect(el)
    sink.onResize(r.width, r.height)
  }

  (el, measure)
}

// --- Formatting --------------------------------------------------------------
// Readouts update every frame of a drag, so they're rounded hard: an unrounded
// float is an unreadable blur of digits while your thumb is moving.

let round = (~places=0, v: float) => {
  let f = Math.pow(10., ~exp=Int.toFloat(places))
  Math.round(v *. f) /. f
}

let fmt = (~places=0, v: float) => round(~places, v)->Float.toString

// Degrees, as a signed whole number — the form the cone maths is discussed in.
let degrees = (radians: float) => fmt(Fling.radToDeg(radians)) ++ "°"

// --- View atoms --------------------------------------------------------------

// A labelled number, one per row of a readout block.
let readout = (~label, ~value) =>
  <div className="fling-readout">
    <span className="fling-readout__label"> {Html.string(label)} </span>
    <span className="fling-readout__value"> {Html.string(value)} </span>
  </div>

// A tuning knob as −/+ buttons rather than a slider: the hand-rolled `Html`
// runtime only carries `onClick`, and stepping by a known amount turns out to be
// the better control anyway — you're looking for the value at which a row of
// past attempts flips, not sweeping a continuum.
let knob = (~label, ~value, ~onLess, ~onMore) =>
  <div className="fling-knob">
    <span className="fling-knob__label"> {Html.string(label)} </span>
    <span className="fling-knob__value"> {Html.string(value)} </span>
    <button className="fling-knob__step" onClick={_ => onLess()}> {Html.string("−")} </button>
    <button className="fling-knob__step" onClick={_ => onMore()}> {Html.string("+")} </button>
  </div>

// Clamp a stepped knob so a long press on one button can't walk it somewhere
// nonsensical (a negative threshold, a cone wider than the whole board).
let clamp = (v, ~min, ~max) => Math.max(min, Math.min(max, v))

// An SVG polyline through a gesture's samples — the path the thumb actually took,
// which is how "it turned back" stops being an abstraction.
let trail = (~samples: array<Fling.sample>, ~className) =>
  Array.length(samples) < 2
    ? Html.string("")
    : <polyline
        className
        attrs={[
          ("points", samples->Array.map(s => `${fmt(s.x)},${fmt(s.y)}`)->Array.join(" ")),
          ("fill", "none"),
        ]}
      />

let dot = (~x, ~y, ~r, ~className) =>
  <circle className attrs={[("cx", fmt(x)), ("cy", fmt(y)), ("r", fmt(r))]} />

let line = (~x1, ~y1, ~x2, ~y2, ~className) =>
  <line className attrs={[("x1", fmt(x1)), ("y1", fmt(y1)), ("x2", fmt(x2)), ("y2", fmt(y2))]} />
