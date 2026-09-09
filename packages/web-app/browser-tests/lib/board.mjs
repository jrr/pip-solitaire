// Shared "the board has stopped moving" waits for the browser suite.
//
// Not a spec file — Playwright only collects `*.spec.mjs` from browser-tests/,
// so helpers live here beside them.

import { expect } from "@playwright/test"

/**
 * Context options for a spec that wins a game but isn't about the win.
 *
 * Every victory now plays a ~40-second cascade before the panel goes up
 * (`docs/cascade.md`), and `prefers-reduced-motion` is the one thing that skips
 * it. A spec asking about the panel, the stats, the share button or the
 * accessibility tree of a won board would otherwise be waiting six seconds for a
 * peek and then reading a table whose cards are being hidden underneath it — so
 * it says here, in one line, that this browser wants less movement.
 *
 * `test.use(quietWin)` alongside whatever else the file already uses. The
 * celebration itself is pinned by `win.spec.mjs` and `cascade.spec.mjs`, which
 * deliberately do not.
 */
export const quietWin = { reducedMotion: "reduce" }

/**
 * The way back out of `quietWin`, for the case in an otherwise-quiet file whose
 * subject *is* the movement — a flight recorded as it's asked for, a line played a
 * move at a time. Reduced motion collapses both to a single reflow, which proves
 * nothing about either.
 *
 * Emulation outlives navigation, so this can go at the head of the test body,
 * before its `goto`.
 */
export const allowMotion = (page) => page.emulateMedia({ reducedMotion: "no-preference" })

/**
 * Wait for the board to reach its resting layout: cards present, then every
 * animation on them finished.
 *
 * This is what replaced the fixed `waitForTimeout` sleeps the old verify-*
 * scripts opened with. The deal's fly-in is a Web Animations API flight (see
 * TableScene's `animateDeal`) created on the *first* animation frame, so the two
 * `requestAnimationFrame`s come first — otherwise "no animations running" is
 * trivially true a beat before the deal starts. `?animate=off` skips the flight
 * entirely, in which case this just costs two frames.
 *
 * Scoped to `.stacking-card` rather than `document.getAnimations()` on purpose:
 * some board states carry a deliberately infinite animation (the rejected-drop
 * pulse), which would never settle. The cap is a backstop for the same reason.
 */
export async function settleBoard(page) {
  await expect(page.locator(".stacking-card").first()).toBeVisible()
  await page.evaluate(async () => {
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))
    const running = [...document.querySelectorAll(".stacking-card")].flatMap((el) =>
      el.getAnimations(),
    )
    await Promise.race([
      Promise.all(running.map((a) => a.finished.catch(() => {}))),
      new Promise((r) => setTimeout(r, 3000)),
    ])
  })
}
