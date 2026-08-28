// Double-tap-to-zoom, refused app-wide.
//
// `styles/base.css` already says this, in the language the platform is supposed
// to read: `touch-action: manipulation` on `html, body` — "no double-tap zoom,
// pinch is fine" — with the board tightening it to `none` (TableScene.css).
// Chrome and desktop Safari honour it. iOS does not: in the home-screen web app
// a double-tap scales the whole viewport anyway, on a card (where it also sends
// the card home, so the move lands *and* the page zooms), on the chrome, and on
// the menu's dead space — where, once zoomed, a second double-tap is also the
// only way back out.
//
// So this module says the same thing a second way, the way that predates
// `touch-action` and that WebKit does observe: `preventDefault()` on the second
// `touchend` of a double-tap. It is not a wider policy than the stylesheet's —
// it is the stylesheet's policy, enforced. Pinch-zoom is untouched, which is the
// point: `user-scalable=no` in the meta viewport would settle all of this in one
// line and take pinch with it, and index.html keeps pinch deliberately (#113).
//
// The board's send-home double-tap is unaffected. It is timed off Pointer Events
// (TableScene's `doubleTapMs`), and preventing a touch event's default suppresses
// the browser's gesture and the synthesised `click` — not the pointer stream.

// Everything else in the app speaks Pointer Events; this one gesture has to be
// answered in the touch layer, because `preventDefault()` on a pointer event
// never reaches WebKit's zoom gesture and on a `touchend` it does.
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
// Bound with an options object for the two flags that matter. `passive: false`
// because a passive listener's `preventDefault()` is dropped on the floor, and
// the refusal *is* the point — stated rather than left to the per-event default.
// `capture: true` so the refusal can't be starved by anything downstream calling
// `stopPropagation`, and doesn't depend on where in the tree the tap landed.
@val @scope("document")
external onDocument: (string, touchEvent => unit, {"passive": bool, "capture": bool}) => unit =
  "addEventListener"

// What counts as a double-tap, and the reason both bounds are tight.
//
// Refusing a `touchend`'s default suppresses the browser's zoom *and* that tap's
// synthesised `click` — there is no way to have one without the other. On the
// board that is free, because nothing in the playfield listens for a click. App-
// wide it is not: the chrome and the menu are clicks, so every pair refused too
// eagerly is a control that didn't respond.
//
// Hence a window matched to the gesture being refused rather than to the game's
// own send-home pair (`TableScene.doubleTapMs`, 300ms): WebKit's double-tap
// window is around 350ms, and stretching past it only buys lost clicks. And hence
// a distance bound, which the board-local version didn't need — two taps this
// close together are one gesture aimed at one spot, where a second click is
// redundant anyway (an impatient double-tap on New Game deals one game, not two).
// Two taps on *different* controls — open the menu, then straight to New — are
// further apart than this and both land, which is the case the bound protects.
//
// The cost that remains, stated plainly: deliberately tapping one control twice
// inside 350ms acts once. That gesture is exactly the one WebKit would zoom on,
// so the alternative isn't two actions, it's one action and a zoomed page.
let suppressMs = 350.
let suppressMoveTol = 30.

// The one place that wants a double-tap left alone: the build string opts back
// into `user-select: text` (components/VersionBadge.css) precisely so it can be
// selected and copied, and on iOS double-tap-to-select-word is how you start.
// Suppressing the default there would take the selection gesture with the zoom.
let selectableSelector = "#version-badge"

let isSelectable = ev =>
  switch ev->target->Nullable.toOption {
  | Some(el) => el->closest(selectableSelector)->Nullable.toOption->Option.isSome
  | None => false
  }

// The tap's position, when this `touchend` is a lone finger lifting off an
// otherwise empty screen. Anything else is part of a pinch and not our business:
// the first finger of a pinch lifts with the second still down, so `touches` is
// non-empty; a two-finger release changes two touches at once.
let tapPoint = ev =>
  if touchCount(touches(ev)) == 0 && touchCount(changedTouches(ev)) == 1 {
    changedTouches(ev)->item(0)->Nullable.toOption->Option.map(t => (clientX(t), clientY(t)))
  } else {
    None
  }

// Arm the refusal. Called once at startup — the listener is on `document`, so it
// covers scenes that mount later without each having to opt in.
let arm = () => {
  // The previous tap: when, and where. Seeded well in the past so the first tap
  // after load can never read as the second half of a pair.
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
          // Reset, so a third tap opens a fresh pair rather than chaining off this
          // one — the same shape as the send-home bookkeeping in TableScene.
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
