// A finger dragging across the board (issue #244).
//
// Playwright's `Touchscreen` has exactly one method — `tap(x, y)`, which fires a
// `touchstart` and a `touchend` and nothing in between. There's no swipe, and
// `locator.dragTo()` is no help either: the docs say it performs mousedown →
// move → mouseup, i.e. the mouse path. A tap alone doesn't move a card, because
// the app's drag needs `pointermove`s between the down and the up.
//
// So the moves come from CDP. `Input.dispatchTouchEvent` will dispatch a
// touchStart, any number of touchMoves and a touchEnd, which Chromium turns into
// the `pointerdown`/`pointermove`/`pointerup` sequence with `pointerType:
// "touch"` that TableScene already listens for — it chose Pointer Events
// deliberately, "so one code path covers phone and desktop", and
// `setPointerCapture` holds through the drag either way. Driving it this way is
// therefore a genuine test of the phone path, not a parallel implementation of
// it.
//
// The context must have been created with touch emulation on (`hasTouch`, i.e. a
// descriptor from lib/devices.mjs or a `devices[...]` entry); without it the page
// reports `maxTouchPoints: 0` and the media queries resolve the desktop way even
// though the events arrive.

/**
 * Drag from `from` to `to` with a single finger, in `steps` intermediate moves.
 *
 * Coordinates are CSS pixels in the viewport, same as `page.mouse`. Steps exist
 * for the same reason the mouse drag has them: one jump gives the app a single
 * `pointermove`, where the hover/drop-target highlighting wants a few.
 */
export async function touchDrag(page, from, to, { steps = 8 } = {}) {
  const cdp = await page.context().newCDPSession(page)
  const finger = (x, y) => [{ x, y, radiusX: 1, radiusY: 1, force: 1 }]
  try {
    await cdp.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: finger(from.x, from.y),
    })
    for (let i = 1; i <= steps; i++) {
      await cdp.send("Input.dispatchTouchEvent", {
        type: "touchMove",
        touchPoints: finger(
          from.x + ((to.x - from.x) * i) / steps,
          from.y + ((to.y - from.y) * i) / steps,
        ),
      })
    }
    // touchEnd carries no points — the protocol requires the list to be empty
    // for the end of the gesture.
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] })
  } finally {
    await cdp.detach()
  }
}
