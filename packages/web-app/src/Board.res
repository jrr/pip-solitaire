// The *inside* of <game-board>, rendered as ReScript JSX on the Html runtime
// and mounted into the element's shadow root — no innerHTML, no querySelector,
// no hand-wired listeners. The custom-element contract is unchanged:
//   inward  — `spin` stays a pure-CSS concern; the host attribute drives
//             `animation-direction` (see `:host([spin="ccw"])` below).
//   outward — clicking the card samples its current rotation and emits it via
//             Events.CardPoked off the host element.

@val external getComputedStyle: Html.element => {"transform": string} = "getComputedStyle"
@get external currentTarget: Html.domEvent => Html.element = "currentTarget"

// Same scoped stylesheet as the old innerHTML string; it lives in the shadow
// root as a <style> node the view renders.
let css = `
  :host { display: inline-block; cursor: pointer; }
  .card { font-size: 4rem; animation: spin 2s linear infinite; }
  :host([spin="ccw"]) .card { animation-direction: reverse; }
  @keyframes spin { to { transform: rotate(360deg); } }
`

// The animation lives entirely in CSS, so we read the card's *computed*
// transform at click time and decode its 2-D matrix — `matrix(a, b, …)`, where
// the rotation is atan2(b, a). "none" (no transform yet) reads as 0°.
let angleOf = el => {
  let transform = getComputedStyle(el)["transform"]
  if transform->String.startsWith("matrix(") {
    let parts = transform->String.slice(~start=7, ~end=String.length(transform))->String.split(", ")
    switch (
      parts[0]->Option.flatMap(Float.fromString),
      parts[1]->Option.flatMap(Float.fromString),
    ) {
    | (Some(a), Some(b)) => Math.atan2(~y=b, ~x=a) *. 180. /. Math.Constants.pi
    | _ => 0.
    }
  } else {
    0.
  }
}

// No internal state yet — spin is attribute/CSS-driven — but the Elm shape is
// here so real board state (cards, selection) drops straight in later.
type model = unit
type msg = Poked(float)

// Called from game-board.js with the shadow root to paint into and the host
// element to fire events from. Outward events go through Events (one source of
// truth for name + detail), so this never spells "card-poked" itself.
let mount = (root, host) => {
  let update = (msg, _model) =>
    switch msg {
    | Poked(angle) => ((), () => Events.CardPoked.emit(host, {angle: angle})) // outward, as an Elm effect
    }
  let view = (_model, dispatch) => <>
    <style> {Html.string(css)} </style>
    <div className="card" onClick={ev => dispatch(Poked(angleOf(currentTarget(ev))))}>
      {Html.string("🃏")}
    </div>
  </>
  Html.mount(~root, ~init=(), ~update, ~view)->ignore
}
