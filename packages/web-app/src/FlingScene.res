// The fling *recogniser* playground: a dot you flick, and a readout of what the
// gesture measured and whether it registered.
//
// The question this scene exists to answer is empirical and can't be answered at
// a desk: on a real phone, with a real thumb, where is the line between "I threw
// that card" and "I dragged it somewhere and let go"? `Fling.defaults` is a guess
// until someone flicks at this fifty times.
//
// So the scene keeps the raw samples of the last several attempts and re-judges
// *all* of them against the current thresholds on every change. Step a knob and
// the history re-colours underneath you: you're not sweeping a slider hunting for
// a feel, you're looking for the value at which the flicks you meant separate
// from the ones you didn't. The numbers beside each row are what you pick it
// from.
//
// Nothing here touches `core` or the board — a fling is transient view state, and
// this scene is purely about the gesture.

let historyLimit = 9

type knob =
  | MinDistance
  | MinSpeed
  | WindowMs
  | Backtrack

// One completed gesture, kept as its raw samples rather than its verdict — the
// whole point is that the verdict is re-derived whenever the tuning moves.
type attempt = {id: int, samples: array<Fling.sample>}

type model = {
  tuning: Fling.tuning,
  width: float,
  height: float,
  // The gesture on screen: in progress while `dragging`, and left in place after
  // release so its trail and numbers stay readable.
  live: array<Fling.sample>,
  dragging: bool,
  attempts: array<attempt>,
  nextId: int,
}

type msg =
  | Resized(float, float)
  | Began(Fling.sample)
  | Moved(Fling.sample)
  | Ended(Fling.sample)
  | Cancelled
  | Step(knob, float)
  | Clear

let init = {
  tuning: Fling.defaults,
  width: 0.,
  height: 0.,
  live: [],
  dragging: false,
  attempts: [],
  nextId: 1,
}

// Steps are chosen to be one *noticeable* increment each — small enough to find
// an edge, big enough that finding it doesn't take thirty taps. Rounded on the
// way in, since repeated float addition otherwise leaves 0.39999999 on screen.
let step = (t: Fling.tuning, knob, delta): Fling.tuning =>
  switch knob {
  | MinDistance => {
      ...t,
      minDistance: FlingUi.clamp(t.minDistance +. delta *. 4., ~min=4., ~max=160.),
    }
  | MinSpeed => {
      ...t,
      minSpeed: FlingUi.round(
        ~places=2,
        FlingUi.clamp(t.minSpeed +. delta *. 0.05, ~min=0.05, ~max=3.),
      ),
    }
  | WindowMs => {...t, windowMs: FlingUi.clamp(t.windowMs +. delta *. 10., ~min=20., ~max=250.)}
  | Backtrack => {
      ...t,
      backtrackTol: FlingUi.clamp(t.backtrackTol +. delta *. 2., ~min=0., ~max=80.),
    }
  }

let update = (msg, model) =>
  switch msg {
  | Resized(width, height) => ({...model, width, height}, Html.noEffect)
  | Began(s) => ({...model, live: [s], dragging: true}, Html.noEffect)
  | Moved(s) =>
    model.dragging
      ? ({...model, live: Array.concat(model.live, [s])}, Html.noEffect)
      : (model, Html.noEffect)
  | Ended(s) =>
    if model.dragging {
      let samples = Array.concat(model.live, [s])
      let attempts =
        Array.concat([{id: model.nextId, samples}], model.attempts)->Array.slice(
          ~start=0,
          ~end=historyLimit,
        )
      (
        {...model, live: samples, dragging: false, attempts, nextId: model.nextId + 1},
        Html.noEffect,
      )
    } else {
      (model, Html.noEffect)
    }
  // A cancelled pointer leaves nothing behind — it isn't an attempt, so it
  // mustn't join the history and skew what the thresholds are read off.
  | Cancelled => ({...model, live: [], dragging: false}, Html.noEffect)
  | Step(knob, delta) => ({...model, tuning: step(model.tuning, knob, delta)}, Html.noEffect)
  | Clear => ({...model, attempts: [], live: [], dragging: false}, Html.noEffect)
  }

// Judge a gesture and unpack it into the three things every readout wants: did
// it register, what to call it, and the numbers behind that call.
let describe = (~tuning, samples) =>
  switch Fling.classify(~tuning, samples) {
  | Fling(m) => (true, "fling", Some(m))
  | Rejected({reason, metrics}) => (false, Fling.rejectionLabel(reason), metrics)
  }

let lastOf = (samples: array<Fling.sample>) => samples->Array.get(Array.length(samples) - 1)

let view = (~surface, model: model, dispatch) => {
  let (isFling, verdictText, metrics) = describe(~tuning=model.tuning, model.live)
  let started = Array.length(model.live) > 0

  // The dot rests in the middle and follows the pointer while a gesture is in
  // flight, so the thing you're flicking is the thing under your thumb.
  let centreX = model.width /. 2.
  let centreY = model.height /. 2.
  let (puckX, puckY) = switch (model.dragging, lastOf(model.live)) {
  | (true, Some(s)) => (s.x, s.y)
  | _ => (centreX, centreY)
  }

  // The direction the gesture was travelling when it was released, drawn from
  // where it ended — the vector that would pick a destination.
  let ray = switch (metrics, lastOf(model.live)) {
  | (Some(m), Some(last)) =>
    let length = 72.
    Some(
      FlingUi.line(
        ~x1=last.x,
        ~y1=last.y,
        ~x2=last.x +. Math.cos(m.angle) *. length,
        ~y2=last.y +. Math.sin(m.angle) *. length,
        ~className={isFling ? "fling-ray fling-ray--yes" : "fling-ray fling-ray--no"},
      ),
    )
  | _ => None
  }

  let trailClass = if model.dragging {
    "fling-trail fling-trail--live"
  } else if isFling {
    "fling-trail fling-trail--yes"
  } else {
    "fling-trail fling-trail--no"
  }

  let historyRow = (a: attempt) => {
    let (ok, label, m) = describe(~tuning=model.tuning, a.samples)
    let num = (get: Fling.metrics => string) => m->Option.mapOr("–", get)
    <div className={ok ? "fling-row fling-row--yes" : "fling-row fling-row--no"}>
      <span className="fling-row__id"> {Html.string("#" ++ Int.toString(a.id))} </span>
      <span className="fling-row__verdict"> {Html.string(label)} </span>
      <span className="fling-row__num">
        {Html.string(num(m => FlingUi.fmt(m.netDistance) ++ "px"))}
      </span>
      <span className="fling-row__num">
        {Html.string(num(m => FlingUi.fmt(~places=2, m.speed)))}
      </span>
      <span className="fling-row__num"> {Html.string(num(m => FlingUi.degrees(m.angle)))} </span>
      <span className="fling-row__num">
        {Html.string(num(m => FlingUi.fmt(m.worstBacktrack)))}
      </span>
    </div>
  }

  // One wrapper so the scene anchors to the *top* of the shared scene container
  // rather than being vertically centred in it: the panel below grows as attempts
  // accumulate, and a centred layout would slide the stage upward after every
  // flick — moving the board out from under the thumb that's testing it.
  <div className="fling-scene">
    <div className="fling-stage">
      {Html.node(surface)}
      <svg className="fling-overlay">
        {FlingUi.line(
          ~x1=centreX -. 9.,
          ~y1=centreY,
          ~x2=centreX +. 9.,
          ~y2=centreY,
          ~className="fling-cross",
        )}
        {FlingUi.line(
          ~x1=centreX,
          ~y1=centreY -. 9.,
          ~x2=centreX,
          ~y2=centreY +. 9.,
          ~className="fling-cross",
        )}
        {FlingUi.trail(~samples=model.live, ~className=trailClass)}
        {ray->Option.getOr(Html.string(""))}
        {switch model.live->Array.get(0) {
        | Some(s) => FlingUi.dot(~x=s.x, ~y=s.y, ~r=4., ~className="fling-start")
        | None => Html.string("")
        }}
        {FlingUi.dot(~x=puckX, ~y=puckY, ~r=15., ~className="fling-puck")}
      </svg>
    </div>
    <div className="fling-panel">
      <p
        className={started
          ? isFling ? "fling-verdict fling-verdict--yes" : "fling-verdict fling-verdict--no"
          : "fling-verdict"}
      >
        {Html.string(started ? verdictText : "flick the dot")}
      </p>
      <div className="fling-readouts">
        {FlingUi.readout(
          ~label="release speed",
          ~value=metrics->Option.mapOr("–", m => FlingUi.fmt(~places=2, m.speed) ++ " px/ms"),
        )}
        {FlingUi.readout(
          ~label="distance",
          ~value=metrics->Option.mapOr("–", m => FlingUi.fmt(m.netDistance) ++ " px"),
        )}
        {FlingUi.readout(
          ~label="path",
          ~value=metrics->Option.mapOr("–", m => FlingUi.fmt(m.pathLength) ++ " px"),
        )}
        {FlingUi.readout(
          ~label="angle",
          ~value=metrics->Option.mapOr("–", m => FlingUi.degrees(m.angle)),
        )}
        {FlingUi.readout(
          ~label="turned back",
          ~value=metrics->Option.mapOr("–", m => FlingUi.fmt(m.worstBacktrack) ++ " px"),
        )}
        {FlingUi.readout(
          ~label="duration",
          ~value=metrics->Option.mapOr("–", m => FlingUi.fmt(m.duration) ++ " ms"),
        )}
      </div>
      <div className="fling-knobs">
        {FlingUi.knob(
          ~label="min distance",
          ~value=FlingUi.fmt(model.tuning.minDistance) ++ " px",
          ~onLess=() => dispatch(Step(MinDistance, -1.)),
          ~onMore=() => dispatch(Step(MinDistance, 1.)),
        )}
        {FlingUi.knob(
          ~label="min speed",
          ~value=FlingUi.fmt(~places=2, model.tuning.minSpeed) ++ " px/ms",
          ~onLess=() => dispatch(Step(MinSpeed, -1.)),
          ~onMore=() => dispatch(Step(MinSpeed, 1.)),
        )}
        {FlingUi.knob(
          ~label="speed window",
          ~value=FlingUi.fmt(model.tuning.windowMs) ++ " ms",
          ~onLess=() => dispatch(Step(WindowMs, -1.)),
          ~onMore=() => dispatch(Step(WindowMs, 1.)),
        )}
        {FlingUi.knob(
          ~label="backtrack",
          ~value=FlingUi.fmt(model.tuning.backtrackTol) ++ " px",
          ~onLess=() => dispatch(Step(Backtrack, -1.)),
          ~onMore=() => dispatch(Step(Backtrack, 1.)),
        )}
      </div>
      <div className="fling-history">
        <div className="fling-row fling-row--head">
          <span className="fling-row__id"> {Html.string("#")} </span>
          <span className="fling-row__verdict"> {Html.string("verdict")} </span>
          <span className="fling-row__num"> {Html.string("dist")} </span>
          <span className="fling-row__num"> {Html.string("speed")} </span>
          <span className="fling-row__num"> {Html.string("angle")} </span>
          <span className="fling-row__num"> {Html.string("back")} </span>
        </div>
        {Html.array(model.attempts->Array.map(historyRow))}
      </div>
      <button className="fling-button" onClick={_ => dispatch(Clear)}>
        {Html.string("Clear attempts")}
      </button>
    </div>
  </div>
}

let make = (): Scene.t => {
  id: "fling",
  label: "Fling",
  mount: container => {
    // The pointer loop is imperative and the picture is a diffed view, so the
    // handlers reach the loop through a ref filled in the moment `mount` returns
    // — the same trick the chrome uses for its own late-bound dispatchers.
    let dispatch = ref(_ => ())
    let (surface, measure) = FlingUi.makeSurface({
      onBegin: s => dispatch.contents(Began(s)),
      onMove: s => dispatch.contents(Moved(s)),
      onEnd: s => dispatch.contents(Ended(s)),
      onCancel: () => dispatch.contents(Cancelled),
      onResize: (w, h) => dispatch.contents(Resized(w, h)),
    })

    dispatch :=
      Html.mount(~root=container, ~init, ~update, ~view=(model, d) => view(~surface, model, d))

    // A scene mounts while its container is still detached, so the surface has
    // no size yet; measure on the next frame, before the first paint.
    FlingUi.requestAnimationFrame(measure)->ignore
    let onResize = _ => measure()
    WebDom.addWindowListener("resize", onResize)
    () => WebDom.removeWindowListener("resize", onResize)
  },
}
