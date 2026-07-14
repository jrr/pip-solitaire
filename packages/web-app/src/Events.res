// The single source of truth for the custom events crossing a web component's
// boundary. Each event names itself and defines its `detail` type exactly once;
// both the emitter (inside the element, e.g. Board.res) and the listener
// (outside, e.g. Main.res) go through the helpers here, so the two ends can't
// drift on the event name or its payload shape.
//
// Adding an event = adding a module below. The generic dispatch/listen plumbing
// lives in Html (`emit` / `on`); this file only pins the name and the type.

module CardPoked = {
  type detail = {angle: float}
  let name = "card-poked"
  let emit = (host, detail: detail) => host->Html.emit(~name, ~detail)
  let on = (target, handler: detail => unit) => target->Html.on(~name, handler)
}
