// Shared "the board has stopped moving" wait for the browser suite.
//
// Not a spec file — Playwright only collects `*.spec.mjs` from browser-tests/,
// so helpers live here beside them.

import { expect } from "@playwright/test"

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
