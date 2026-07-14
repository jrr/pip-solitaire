// The *inside* of <game-board>, rendered as ReScript JSX on the Html runtime
// and mounted into the element's shadow root. Both boundary directions are real
// Elm messages:
//   inward  — the outside sends InwardEvents commands through the element's
//             `send` conduit; here they're messages fed to `dispatch`. `Flip`
//             toggles the spin direction (held in the model).
//   outward — clicking the card samples its current rotation and emits it via
//             OutwardEvents.CardPoked off the host element.
//
// The rotation is driven by the Web Animations API rather than a CSS animation,
// so a reversal is *seamless*: instead of toggling `animation-direction` (which
// snaps the card to its mirror angle — `360 − A` — because CSS only re-maps
// keyframe progress), we re-seat the animation to begin at the card's current
// angle and turn the other way. See `respin`.

@val external getComputedStyle: Html.element => {"transform": string} = "getComputedStyle"
@get external currentTarget: Html.domEvent => Html.element = "currentTarget"

// Web Animations API bindings. `element.animate(keyframes, options)` starts an
// animation we own (and can cancel); `getAnimations` lets us clear the old one.
type animation
@send
external animate: (
  Html.element,
  array<{"transform": string}>,
  {"duration": int, "iterations": float, "easing": string},
) => animation = "animate"
@send external getAnimations: Html.element => array<animation> = "getAnimations"
@send external cancel: animation => unit = "cancel"
@send external querySelector: (Html.element, string) => Nullable.t<Html.element> = "querySelector"
@val external infinity: float = "Infinity"

// Scoped stylesheet in the shadow root. No animation here anymore — just looks;
// the spin is all WAAPI now.
let css = `
  :host { display: inline-block; cursor: pointer; }
  .card { font-size: 4rem; }
`

// Read the card's current rotation from its *computed* transform and decode the
// 2-D matrix — `matrix(a, b, …)`, rotation = atan2(b, a). "none" reads as 0°.
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

type msg =
  | Poked(float)
  | Command(InwardEvents.command)

let dirOf = spin =>
  switch spin {
  | Cw => 1.
  | Ccw => -1.
  }

// (Re)start the spin: begin an infinite, linear rotation from the card's CURRENT
// angle, turning in `spin`'s direction. Reading the angle *before* cancelling
// the running animation is what makes a reversal seamless — the new animation
// picks up exactly where the old one was, with no jump. (playbackRate = -1
// can't do this: run backwards, an infinite animation hits currentTime 0 and
// stops.)
let respin = (root, spin) =>
  switch root->querySelector(".card")->Nullable.toOption {
  | Some(card) =>
    let from = angleOf(card)
    card->getAnimations->Array.forEach(cancel)
    let to_ = from +. dirOf(spin) *. 360.
    card
    ->animate(
      [
        {"transform": `rotate(${Float.toString(from)}deg)`},
        {"transform": `rotate(${Float.toString(to_)}deg)`},
      ],
      {"duration": 2000, "iterations": infinity, "easing": "linear"},
    )
    ->ignore
  | None => ()
  }

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
      ({spin: spin}, () => respin(root, spin)) // seamless direction change, as an effect
    }
  let view = (_model, dispatch) => <>
    <style> {Html.string(css)} </style>
    <div className="card" onClick={ev => dispatch(Poked(angleOf(currentTarget(ev))))}>
      {Html.string("🃏")}
    </div>
  </>
  let dispatch = Html.mount(~root, ~init={spin: Cw}, ~update, ~view)
  respin(root, Cw) // kick off the initial spin once the card is in the DOM
  // Expose only the inbound-command surface to the outside; internal messages
  // (Poked) stay private.
  (command: InwardEvents.command) => dispatch(Command(command))
}
