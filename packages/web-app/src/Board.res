// The *inside* of <game-board>, rendered as ReScript JSX on the Html runtime
// and mounted into the element's shadow root — no innerHTML, no querySelector,
// no hand-wired listeners. Both boundary directions are real Elm messages now:
//   inward  — the outside sends InwardEvents commands through the element's
//             `send` conduit; here they're just messages fed to `dispatch`.
//             `Flip` toggles the spin direction, held in the model.
//   outward — clicking the card samples its current rotation and emits it via
//             OutwardEvents.CardPoked off the host element.

@val external getComputedStyle: Html.element => {"transform": string} = "getComputedStyle"
@get external currentTarget: Html.domEvent => Html.element = "currentTarget"

// Scoped stylesheet, rendered as a <style> node in the shadow root. Direction is
// driven by a class on the card (from the model) rather than a host attribute.
let css = `
  :host { display: inline-block; cursor: pointer; }
  .card { font-size: 4rem; animation: spin 2s linear infinite; }
  .card.reverse { animation-direction: reverse; }
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

type spin = Cw | Ccw
type model = {spin: spin}

// The board's own messages: internal ones (a click) plus the inward commands
// the outside sends, wrapped so both flow through one Elm loop.
type msg =
  | Poked(float)
  | Command(InwardEvents.command)

// Called from game-board.js with the shadow root to paint into and the host
// element to fire events from. Returns the inward conduit — a function the
// element hands to the outside for sending InwardEvents commands in.
let mount = (root, host) => {
  let update = (msg, model) =>
    switch msg {
    | Poked(angle) => (model, () => OutwardEvents.CardPoked.emit(host, {angle: angle})) // outward effect
    | Command(Flip) =>
      let spin = switch model.spin {
      | Cw => Ccw
      | Ccw => Cw
      }
      ({spin: spin}, Html.noEffect)
    }
  let view = (model, dispatch) => <>
    <style> {Html.string(css)} </style>
    <div
      className={switch model.spin {
      | Cw => "card"
      | Ccw => "card reverse"
      }}
      onClick={ev => dispatch(Poked(angleOf(currentTarget(ev))))}
    >
      {Html.string("🃏")}
    </div>
  </>
  let dispatch = Html.mount(~root, ~init={spin: Cw}, ~update, ~view)
  // Expose only the inbound-command surface to the outside; internal messages
  // (Poked) stay private.
  (command: InwardEvents.command) => dispatch(Command(command))
}
