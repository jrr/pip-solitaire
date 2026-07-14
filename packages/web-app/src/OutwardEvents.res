// The single source of truth for events the component sends *outward* — real
// DOM CustomEvents that escape the shadow root (see Html `emit` / `on`). Each
// event names itself and defines its `detail` type exactly once, so the emitter
// (inside the element, e.g. Board.res) and the listener (outside, e.g. Main.res)
// can't drift on the name or payload. Inward messages have their own file,
// InwardEvents.res.
//
// Adding an outward event = adding a module below.

module CardPoked = {
  type detail = {angle: float}
  let name = "card-poked"
  let emit = (host, detail: detail) => host->Html.emit(~name, ~detail)
  let on = (target, handler: detail => unit) => target->Html.on(~name, handler)
}
