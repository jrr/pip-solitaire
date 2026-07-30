// The fling *resolution* playground: a mock FreeCell board, a source dot you can
// put anywhere, and the ability to declare which piles would legally accept the
// card — so you can build the awkward positions on purpose and see which
// destination a flick actually picks.
//
// The rule under test is deliberately one rule, and spatial: candidates are the
// legal destinations inside a cone around the fling, and among those the one most
// *in line* with it wins, with distance breaking near-ties. It has to cope with
// two very different geometries, which is what this scene is for:
//
//   - Diagonal. Free cells sit top-left and foundations top-right (that's the
//     real board — see `Game.freecellDeal`), so an up-left flick and an up-right
//     flick are far apart in angle and the choice is easy.
//   - Collinear. Every cascade to your left is at nearly the same angle from a
//     card below the row, so no cone can separate them. That's why near-ties fall
//     back to distance — and why "refuse when more than one is legal" is wrong:
//     it would fail hardest with three empty columns open, exactly when the board
//     is most playable.
//
// The two interactions deliberately mirror the layering the real feature would
// use: a *slow* drag of the dot repositions it (a deliberate placement), and a
// *flick* resolves a destination. Same gesture stream, told apart by how it ends.
//
// Simplifications worth knowing while reading results off it: a target's landing
// point is its box centre, where the real board would use the pile's current top
// card; and legality is whatever you've tapped on, not `Reducer.validMoves`.

type role =
  | Cell
  | Foundation
  | Cascade

type box = {
  id: int,
  label: string, // for the ranked list
  short: string, // for the box itself, where there's room for two characters
  role: role,
  x: float,
  y: float,
  w: float,
  h: float,
}

// A completed fling, kept as its samples plus where the dot was when it left —
// so the cone and tie-band knobs re-resolve the *same* throw as they move,
// instead of needing it flicked again.
type shot = {samples: array<Fling.sample>, origin: Fling.point}

type knob =
  | Cone
  | Tie

type model = {
  tuning: Fling.tuning,
  width: float,
  height: float,
  // `None` until the dot has been moved, so it keeps re-deriving from the live
  // board size rather than stranding itself off-stage after a rotation.
  origin: option<Fling.point>,
  legal: array<int>,
  // Treat the free cells as one fungible bank (offer only the nearest) rather
  // than four separate destinations. They're interchangeable on a real board, so
  // collapsing them isn't a priority rule — but four identical candidates at four
  // slightly different angles is a real ambiguity, and this is where you find out
  // whether it matters.
  collapseCells: bool,
  live: array<Fling.sample>,
  dragging: bool,
  last: option<shot>,
}

type msg =
  | Resized(float, float)
  | Pressed(Fling.sample)
  | Moved(Fling.sample)
  | Ended(Fling.sample)
  | Cancelled
  | Step(knob, float)
  | ToggleCells
  | ResetTargets

// How close to the dot a press has to land to grab it; anything further is a tap
// on the board, which toggles a pile's legality.
let grabRadius = 46.

// An opening position with something to argue about: the whole free-cell bank,
// one foundation, two columns to the left of the dot and one to its right.
let defaultLegal = [0, 1, 2, 3, 6, 9, 10, 13]

// The dot's home: low in column 4, where a card in a deep fan would sit.
let homeColumn = 11

let init = {
  tuning: Fling.defaults,
  width: 0.,
  height: 0.,
  origin: None,
  legal: defaultLegal,
  collapseCells: false,
  live: [],
  dragging: false,
  last: None,
}

// The board: eight boxes across the top (four free cells, then four
// foundations — the real layout) and eight cascades below.
let layout = (width, height): array<box> => {
  let pad = 8.
  let gap = 5.
  let colW = Math.max(16., (width -. 2. *. pad -. 7. *. gap) /. 8.)
  let topH = Math.max(24., height *. 0.16)
  // The cascades are deliberately deep, and the board deliberately stops short of
  // the bottom of the stage: the interesting flings come from a card low in a long
  // fan, so there has to be somewhere below the columns to park the dot.
  let botH = Math.max(34., height *. 0.42)
  let topY = pad
  let botY = topY +. topH +. gap *. 3.
  let xAt = i => pad +. Int.toFloat(i) *. (colW +. gap)
  let top = Array.fromInitializer(~length=8, i => {
    id: i,
    label: i < 4 ? `free cell ${Int.toString(i + 1)}` : `foundation ${Int.toString(i - 3)}`,
    short: i < 4 ? `c${Int.toString(i + 1)}` : `F${Int.toString(i - 3)}`,
    role: i < 4 ? Cell : Foundation,
    x: xAt(i),
    y: topY,
    w: colW,
    h: topH,
  })
  let bottom = Array.fromInitializer(~length=8, i => {
    id: 8 + i,
    label: `column ${Int.toString(i + 1)}`,
    short: Int.toString(i + 1),
    role: Cascade,
    x: xAt(i),
    y: botY,
    w: colW,
    h: botH,
  })
  Array.concat(top, bottom)
}

let centre = (b: box): Fling.point => {x: b.x +. b.w /. 2., y: b.y +. b.h /. 2.}

let contains = (b: box, p: Fling.point) =>
  p.x >= b.x && p.x <= b.x +. b.w && p.y >= b.y && p.y <= b.y +. b.h

let defaultOrigin = (width, height): Fling.point =>
  switch layout(width, height)->Array.find(b => b.id == homeColumn) {
  | Some(b) => {x: b.x +. b.w /. 2., y: b.y +. b.h *. 0.78}
  | None => {x: width /. 2., y: height *. 0.72}
  }

let originOf = (model: model) =>
  model.origin->Option.getOr(defaultOrigin(model.width, model.height))

// The destinations a fling from `origin` could resolve to: the piles marked
// legal, minus the one the dot is sitting in — a card's own pile is never a
// destination, which is what `Reducer.validMoves` already does for real.
let targetsFor = (~boxes: array<box>, ~legal, ~collapseCells, ~origin): array<Fling.target> => {
  let eligible = boxes->Array.filter(b => legal->Array.includes(b.id) && !contains(b, origin))
  let cells = eligible->Array.filter(b => b.role == Cell)
  let others = eligible->Array.filter(b => b.role != Cell)
  let offered = if collapseCells {
    cells
    ->Array.reduce(None, (best: option<box>, b) =>
      switch best {
      | Some(current) =>
        Fling.distanceBetween(origin, centre(b)) < Fling.distanceBetween(origin, centre(current))
          ? Some(b)
          : best
      | None => Some(b)
      }
    )
    ->Option.mapOr([], b => [b])
  } else {
    cells
  }
  Array.concat(others, offered)->Array.map((b): Fling.target => {
    id: b.id,
    label: b.label,
    at: centre(b),
  })
}

let step = (t: Fling.tuning, knob, delta): Fling.tuning =>
  switch knob {
  | Cone => {...t, coneHalfAngle: FlingUi.clamp(t.coneHalfAngle +. delta *. 5., ~min=5., ~max=80.)}
  | Tie => {...t, angleTie: FlingUi.clamp(t.angleTie +. delta *. 2., ~min=0., ~max=45.)}
  }

let toggle = (ids, id) =>
  ids->Array.includes(id) ? ids->Array.filter(i => i != id) : Array.concat(ids, [id])

let update = (msg, model: model) =>
  switch msg {
  | Resized(width, height) => ({...model, width, height}, Html.noEffect)
  | Pressed(s) =>
    let at: Fling.point = {x: s.x, y: s.y}
    if Fling.distanceBetween(originOf(model), at) <= grabRadius {
      ({...model, live: [s], dragging: true}, Html.noEffect)
    } else {
      // Not on the dot: a tap on a pile flips whether it would accept the card.
      switch layout(model.width, model.height)->Array.find(b => contains(b, at)) {
      | Some(b) => ({...model, legal: toggle(model.legal, b.id)}, Html.noEffect)
      | None => (model, Html.noEffect)
      }
    }
  | Moved(s) =>
    model.dragging
      ? ({...model, live: Array.concat(model.live, [s])}, Html.noEffect)
      : (model, Html.noEffect)
  | Ended(s) =>
    if model.dragging {
      let samples = Array.concat(model.live, [s])
      switch Fling.classify(~tuning=model.tuning, samples) {
      // A throw: resolve it, and leave the dot where it was — the card would have
      // flown to its destination and this is the board it flew from.
      | Fling(_) => (
          {
            ...model,
            live: samples,
            dragging: false,
            last: Some({samples, origin: originOf(model)}),
          },
          Html.noEffect,
        )
      // Not a throw: the player carried the dot somewhere and set it down. This is
      // the same fall-through the real feature would use — a deliberate placement
      // is honoured as a placement, and only an incomplete one becomes a fling.
      | Rejected(_) => (
          {...model, origin: Some({x: s.x, y: s.y}), live: [], dragging: false, last: None},
          Html.noEffect,
        )
      }
    } else {
      (model, Html.noEffect)
    }
  | Cancelled => ({...model, live: [], dragging: false}, Html.noEffect)
  | Step(knob, delta) => ({...model, tuning: step(model.tuning, knob, delta)}, Html.noEffect)
  | ToggleCells => ({...model, collapseCells: !model.collapseCells}, Html.noEffect)
  | ResetTargets => (
      {...model, legal: defaultLegal, origin: None, last: None, live: []},
      Html.noEffect,
    )
  }

let px = v => FlingUi.fmt(~places=1, v)

// The cone the fling has to hit, as a filled wedge from the dot out past the edge
// of the board — the clearest possible answer to "was that target in range?".
let coneWedge = (~origin: Fling.point, ~angle, ~halfAngle, ~radius) => {
  let half = halfAngle *. Math.Constants.pi /. 180.
  let edge = a => (origin.x +. Math.cos(a) *. radius, origin.y +. Math.sin(a) *. radius)
  let (x1, y1) = edge(angle -. half)
  let (x2, y2) = edge(angle +. half)
  // The half-angle is capped below 90°, so the wedge is always the minor arc.
  <path
    className="fling-cone"
    attrs={[
      (
        "d",
        `M ${px(origin.x)} ${px(origin.y)} L ${px(x1)} ${px(y1)} A ${px(radius)} ${px(
            radius,
          )} 0 0 1 ${px(x2)} ${px(y2)} Z`,
      ),
    ]}
  />
}

let view = (~surface, model: model, dispatch) => {
  let boxes = layout(model.width, model.height)
  let origin = originOf(model)

  // Everything below is re-derived from the stored samples, so moving the cone or
  // the tie band re-answers the last throw rather than needing a new one.
  let angle = model.last->Option.flatMap(shot =>
    switch Fling.classify(~tuning=model.tuning, shot.samples) {
    | Fling(m) => Some(m.angle)
    | Rejected({metrics}) => metrics->Option.map(m => m.angle)
    }
  )
  let shotOrigin = model.last->Option.mapOr(origin, shot => shot.origin)
  let targets = targetsFor(
    ~boxes,
    ~legal=model.legal,
    ~collapseCells=model.collapseCells,
    ~origin=shotOrigin,
  )
  let resolution =
    angle->Option.map(a =>
      Fling.resolve(~tuning=model.tuning, ~origin=shotOrigin, ~angle=a, targets)
    )
  let winner = resolution->Option.flatMap(r => r.best)->Option.map(t => t.id)

  let (puckX, puckY) = switch (
    model.dragging,
    model.live->Array.get(Array.length(model.live) - 1),
  ) {
  | (true, Some(s)) => (s.x, s.y)
  | _ => (origin.x, origin.y)
  }

  let boxNode = (b: box) => {
    let isLegal = model.legal->Array.includes(b.id)
    let isWinner = winner == Some(b.id)
    let cls =
      "fling-box" ++ (isLegal ? " fling-box--legal" : "") ++ (isWinner ? " fling-box--winner" : "")
    <>
      <rect
        className={cls}
        attrs={[
          ("x", px(b.x)),
          ("y", px(b.y)),
          ("width", px(b.w)),
          ("height", px(b.h)),
          ("rx", "4"),
        ]}
      />
      <text
        className="fling-box__label"
        attrs={[
          ("x", px(b.x +. b.w /. 2.)),
          ("y", px(b.y +. b.h /. 2. +. 3.)),
          ("text-anchor", "middle"),
        ]}
      >
        {Html.string(b.short)}
      </text>
    </>
  }

  // A spoke to every candidate inside the cone, so the winner's claim is visible
  // rather than asserted.
  let spokes = switch resolution {
  | Some(r) =>
    r.ranked
    ->Array.filter(s => s.inCone)
    ->Array.map(s =>
      FlingUi.line(
        ~x1=shotOrigin.x,
        ~y1=shotOrigin.y,
        ~x2=s.target.at.x,
        ~y2=s.target.at.y,
        ~className={
          winner == Some(s.target.id) ? "fling-spoke fling-spoke--winner" : "fling-spoke"
        },
      )
    )
  | None => []
  }

  let rankRow = (s: Fling.scored) => {
    let isWinner = winner == Some(s.target.id)
    <div
      className={"fling-row" ++ (isWinner ? " fling-row--yes" : s.inCone ? "" : " fling-row--no")}
    >
      <span className="fling-row__verdict"> {Html.string(s.target.label)} </span>
      <span className="fling-row__num"> {Html.string(FlingUi.fmt(s.deviation) ++ "°")} </span>
      <span className="fling-row__num"> {Html.string(FlingUi.fmt(s.distance) ++ "px")} </span>
      <span className="fling-row__num">
        {Html.string(isWinner ? "win" : s.inCone ? "in" : "out")}
      </span>
    </div>
  }

  let outcome = switch (model.last, resolution) {
  | (None, _) => "flick the dot toward a pile"
  | (Some(_), Some(r)) =>
    switch r.best {
    | Some(t) => `→ ${t.label}`
    | None => "nothing legal that way — bounce back and flash the moves that exist"
    }
  | (Some(_), None) => "no direction"
  }

  // Anchored to the top of the scene container (see `FlingScene`): the ranked list
  // below changes length as the legal set changes, and a centred layout would
  // shift the board every time it did.
  <div className="fling-scene">
    <div className="fling-stage fling-stage--board">
      {Html.node(surface)}
      <svg className="fling-overlay">
        {switch (angle, model.last) {
        | (Some(a), Some(_)) =>
          coneWedge(
            ~origin=shotOrigin,
            ~angle=a,
            ~halfAngle=model.tuning.coneHalfAngle,
            ~radius=Math.sqrt(model.width *. model.width +. model.height *. model.height),
          )
        | _ => Html.string("")
        }}
        {Html.array(boxes->Array.map(boxNode))}
        {Html.array(spokes)}
        {switch angle {
        | Some(a) =>
          FlingUi.line(
            ~x1=shotOrigin.x,
            ~y1=shotOrigin.y,
            ~x2=shotOrigin.x +. Math.cos(a) *. 90.,
            ~y2=shotOrigin.y +. Math.sin(a) *. 90.,
            ~className="fling-ray fling-ray--yes",
          )
        | None => Html.string("")
        }}
        {FlingUi.trail(
          ~samples=model.live,
          // Blue while the throw is in the air, settled green once it has been
          // resolved — otherwise a finished gesture keeps reading as in-progress.
          ~className={
            model.dragging ? "fling-trail fling-trail--live" : "fling-trail fling-trail--yes"
          },
        )}
        {FlingUi.dot(~x=puckX, ~y=puckY, ~r=15., ~className="fling-puck")}
      </svg>
    </div>
    <div className="fling-panel">
      <p
        className={switch (model.last, winner) {
        // Idle is neutral — nothing has been thrown yet, so there's no verdict to
        // colour. Only a real throw earns green or amber.
        | (None, _) => "fling-verdict"
        | (Some(_), None) => "fling-verdict fling-verdict--no"
        | (Some(_), Some(_)) => "fling-verdict fling-verdict--yes"
        }}
      >
        {Html.string(outcome)}
      </p>
      <p className="fling-hint">
        {Html.string(
          "tap a pile to toggle legal · drag the dot slowly to move it · flick to resolve",
        )}
      </p>
      <div className="fling-knobs">
        {FlingUi.knob(
          ~label="cone",
          ~value=FlingUi.fmt(model.tuning.coneHalfAngle) ++ "°",
          ~onLess=() => dispatch(Step(Cone, -1.)),
          ~onMore=() => dispatch(Step(Cone, 1.)),
        )}
        {FlingUi.knob(
          ~label="tie",
          ~value=FlingUi.fmt(model.tuning.angleTie) ++ "°",
          ~onLess=() => dispatch(Step(Tie, -1.)),
          ~onMore=() => dispatch(Step(Tie, 1.)),
        )}
      </div>
      <div className="fling-history">
        {Html.array(resolution->Option.mapOr([], r => r.ranked->Array.map(rankRow)))}
      </div>
      <div className="fling-buttons">
        <button className="fling-button" onClick={_ => dispatch(ToggleCells)}>
          {Html.string(model.collapseCells ? "free cells: one bank" : "free cells: four targets")}
        </button>
        <button className="fling-button" onClick={_ => dispatch(ResetTargets)}>
          {Html.string("Reset board")}
        </button>
      </div>
    </div>
  </div>
}

let make = (): Scene.t => {
  id: "fling-targets",
  label: "Fling targets",
  mount: container => {
    let dispatch = ref(_ => ())
    let (surface, measure) = FlingUi.makeSurface({
      onBegin: s => dispatch.contents(Pressed(s)),
      onMove: s => dispatch.contents(Moved(s)),
      onEnd: s => dispatch.contents(Ended(s)),
      onCancel: () => dispatch.contents(Cancelled),
      onResize: (w, h) => dispatch.contents(Resized(w, h)),
    })

    dispatch :=
      Html.mount(~root=container, ~init, ~update, ~view=(model, d) => view(~surface, model, d))

    FlingUi.requestAnimationFrame(measure)->ignore
    let onResize = _ => measure()
    WebDom.addWindowListener("resize", onResize)
    () => WebDom.removeWindowListener("resize", onResize)
  },
}
