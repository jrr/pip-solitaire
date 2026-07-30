// Shared Pointer Events bindings for the gesture code.
//
// `WebDom.addEventListener` is event-less, and a gesture needs the PointerEvent
// itself — where the pointer is, when, and which pointer it is. `TableScene` has
// carried its own copy of these since the drag-and-drop spike (#21); the fling
// scenes need the same handful, so they live here rather than being re-bound per
// scene. (TableScene's copies are deliberately left alone for now — folding them
// into this module is a separate, mechanical change.)
//
// Why Pointer Events rather than touch/mouse: one event stream covers finger,
// stylus and mouse, and `setCapture` keeps the samples coming even when the
// pointer outruns the element it started on — which is exactly what a fling does.

type event

@get external clientX: event => float = "clientX"
@get external clientY: event => float = "clientY"
@get external pointerId: event => int = "pointerId"
// Milliseconds since page load. Sampling the *event's* clock rather than a
// wall clock keeps the timing honest: the timestamps are the browser's own, so a
// velocity computed from them isn't skewed by when our handler happened to run.
@get external timeStamp: event => float = "timeStamp"
// "touch" | "mouse" | "pen" — a fling threshold tuned for a thumb isn't
// necessarily the one a mouse wants, so the input kind is worth reading.
@get external pointerType: event => string = "pointerType"

@send external setCapture: (WebDom.element, int) => unit = "setPointerCapture"
@send external releaseCapture: (WebDom.element, int) => unit = "releasePointerCapture"
@send external on: (WebDom.element, string, event => unit) => unit = "addEventListener"

// Viewport-space geometry, for turning a pointer's client coordinates into
// coordinates local to whatever element the gesture is being measured against.
type rect = {left: float, top: float, width: float, height: float}
@send external boundingRect: WebDom.element => rect = "getBoundingClientRect"
