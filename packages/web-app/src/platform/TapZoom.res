// Double-tap-to-zoom, refused app-wide.
//
// `styles/base.css` already says this in the language the platform is supposed to
// read — `touch-action: manipulation`, tightened to `none` on the board — and Chrome
// and desktop Safari honour it. iOS does not: in the home-screen web app a double-tap
// scales the viewport anyway, and once zoomed a second double-tap is the only way out.
//
// So this says the same thing the older way WebKit does observe: `preventDefault()` on
// the second `touchend` of a pair. **Not a wider policy than the stylesheet's — the
// stylesheet's policy, enforced.** Pinch is untouched, which is the point;
// `user-scalable=no` in the meta viewport would settle all of this in one line and
// take pinch with it, and `index.html` keeps pinch deliberately.
//
// The board's own send-home double-tap is unaffected: it's timed off Pointer Events,
// and refusing a touch event's default suppresses the gesture and the synthesised
// `click`, not the pointer stream.

// This one gesture has to be answered in the touch layer even though the rest of the
// app speaks Pointer Events, because `preventDefault()` on a pointer event never
// reaches WebKit's zoom gesture and on a `touchend` it does.
type touch
@get external clientX: touch => float = "clientX"
@get external clientY: touch => float = "clientY"
type touchList
@get external touchCount: touchList => int = "length"
@send external item: (touchList, int) => Nullable.t<touch> = "item"
type touchEvent
@get external touches: touchEvent => touchList = "touches"
@get external changedTouches: touchEvent => touchList = "changedTouches"
@get external timeStamp: touchEvent => float = "timeStamp"
@get external target: touchEvent => Nullable.t<WebDom.element> = "target"
@send external preventDefault: touchEvent => unit = "preventDefault"
@send external closest: (WebDom.element, string) => Nullable.t<WebDom.element> = "closest"
// `passive: false` because a passive listener's `preventDefault()` is dropped on the
// floor and the refusal *is* the point; `capture: true` so it can't be starved by
// anything downstream calling `stopPropagation`.
@val @scope("document")
external onDocument: (string, touchEvent => unit, {"passive": bool, "capture": bool}) => unit =
  "addEventListener"

// **Both bounds are tight, and have to stay tight.** Refusing a `touchend`'s default
// suppresses the zoom *and* that tap's synthesised `click`; there is no way to have
// one without the other. On the board that's free — nothing in the playfield listens
// for a click — but the chrome and the menu are clicks, so every pair refused too
// eagerly is a control that didn't respond.
//
// So the window matches WebKit's own double-tap gesture (~350ms) rather than the
// game's send-home pair, since stretching past it only buys lost clicks; and the
// distance bound lets two taps on *different* controls — open the menu, then straight
// to New — both land, while two on one spot are a single gesture where the second
// click was redundant anyway.
//
// The cost that remains: deliberately tapping one control twice inside 350ms acts
// once. That gesture is exactly the one WebKit would zoom on, so the alternative isn't
// two actions, it's one action and a zoomed page.
let suppressMs = 350.
let suppressMoveTol = 30.

// The build string opts back into `user-select: text` so it can be copied, and on iOS
// double-tap-to-select-word is how that starts. Suppressing the default here would
// take the selection gesture with the zoom.
let selectableSelector = "#version-badge"

let isSelectable = ev =>
  switch ev->target->Nullable.toOption {
  | Some(el) => el->closest(selectableSelector)->Nullable.toOption->Option.isSome
  | None => false
  }

// A lone finger lifting off an otherwise empty screen. Anything else is part of a
// pinch and not our business: a pinch's first finger lifts with the second still down,
// so `touches` is non-empty, and a two-finger release changes two touches at once.
let tapPoint = ev =>
  if touchCount(touches(ev)) == 0 && touchCount(changedTouches(ev)) == 1 {
    changedTouches(ev)->item(0)->Nullable.toOption->Option.map(t => (clientX(t), clientY(t)))
  } else {
    None
  }

// Called once at startup — the listener is on `document`, so it covers scenes that
// mount later without each having to opt in.
let arm = () => {
  // Seeded well in the past, so the first tap after load can never read as the second
  // half of a pair.
  let lastAt = ref(-10000.)
  let lastX = ref(0.)
  let lastY = ref(0.)
  onDocument(
    "touchend",
    ev =>
      switch tapPoint(ev) {
      | Some((x, y)) if !isSelectable(ev) =>
        let now = timeStamp(ev)
        let near =
          Math.abs(x -. lastX.contents) <= suppressMoveTol &&
            Math.abs(y -. lastY.contents) <= suppressMoveTol
        if now -. lastAt.contents <= suppressMs && near {
          preventDefault(ev)
          // Reset, so a third tap opens a fresh pair rather than chaining off this one.
          lastAt := -10000.
        } else {
          lastAt := now
          lastX := x
          lastY := y
        }
      | _ => ()
      },
    {"passive": false, "capture": true},
  )
}
