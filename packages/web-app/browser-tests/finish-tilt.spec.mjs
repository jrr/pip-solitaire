// The finish sweep must not re-tilt cards before it moves them — see
// docs/card-tilt.md § The sweep problem for the mechanism this pins.
//
// It has to be measured in a real browser: jsdom has no layout, no CSS
// transitions and no resolved transform matrices, so this can't be a case in
// `mise run test`. The board throughout is `?state=finish`.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

// The sweep itself runs for several seconds; the default 30s leaves little room
// for a slow CI runner on top of that.
test.setTimeout(90_000)

// `earlyMs` lands inside the 0.18s tilt transition, so a sweep that re-tilts the
// board before it moves shows up here as a boardful of turned cards. The sample runs
// *in the page* — click, wait, read — because that window is tight enough that
// round-tripping each step through the driver would smear it.
const EARLY_MS = 90

// One sweep, reported as the angles before it starts, a beat into it, and once it
// has settled.
async function sweep(page) {
  return await page.evaluate(async (earlyMs) => {
    // A card's *rendered* angle, read off the resolved transform matrix rather
    // than the `--card-rot` property — mid-transition the property already holds
    // the destination value, while the matrix is what the player actually sees.
    // The node list is captured once and reused, so the three samples line up
    // card-for-card however the sweep reorders the DOM.
    const arts = [...document.querySelectorAll(".stacking-card .card-art")]
    const angle = (el) => {
      const m = new DOMMatrixReadOnly(getComputedStyle(el).transform)
      return (Math.atan2(m.b, m.a) * 180) / Math.PI
    }

    const before = arts.map(angle)
    document.querySelector(".finish-button").click()
    await new Promise((r) => setTimeout(r, earlyMs))
    const early = arts.map(angle)

    // Let the whole staggered sweep land — the win overlay is its last act, so
    // wait on that rather than on a fixed duration.
    const deadline = performance.now() + 30000
    while (!document.querySelector(".win-overlay") && performance.now() < deadline) {
      await new Promise((r) => requestAnimationFrame(r))
    }
    const after = arts.map(angle)
    return { before, early, after, won: document.querySelectorAll(".win-overlay").length }
  }, EARLY_MS)
}

const turned = (a, b) => a.filter((v, i) => Math.abs(v - b[i]) > 0.2).length
const maxAbs = (xs) => xs.reduce((m, v) => Math.max(m, Math.abs(v)), 0)

// The tilt preference is a stored flag (`pip.cardTilt`), so seed it before the app
// boots rather than driving the menu.
async function openBoard(page, { tilt }) {
  await page.addInitScript((on) => {
    window.localStorage.setItem("pip.cardTilt", on ? "true" : "false")
  }, tilt)
  await page.goto("/?game=freecell&state=finish")
  await expect(page.locator(".finish-button")).toBeVisible()
  // The board deals with a fly-in here (the sweep is the thing under test, not
  // the deal), so wait for the cards to stop moving before sampling angles.
  await settleBoard(page)
}

test("with the tilt on, the sweep's re-tilt rides each card's flight", async ({ page }) => {
  await openBoard(page, { tilt: true })
  const on = await sweep(page)

  const earlyTurned = turned(on.early, on.before)
  const sweptCards = turned(on.after, on.before)

  // The twitch turned *every* swept card at once; only the cards already in flight
  // should have moved this early. The cap is generous — it's an order-of-magnitude
  // check against the whole board swinging, not a frame-exact assertion.
  expect
    .soft(earlyTurned, `cards turned ${EARLY_MS}ms in (expect a couple, not the board)`)
    .toBeLessThanOrEqual(4)
  expect.soft(sweptCards, "the sweep did re-tilt cards on the way home").toBeGreaterThan(8)
  // …and the sweep still delivers a hand-placed angle at the destination.
  expect.soft(maxAbs(on.after), "cards rest tilted once home (max angle, °)").toBeGreaterThan(0.5)
  expect.soft(on.won, "the sweep reached the win").toBe(1)
})

test("with the tilt off, cards stay square from source to foundation", async ({ page }) => {
  await openBoard(page, { tilt: false })
  const off = await sweep(page)

  const worst = Math.max(maxAbs(off.before), maxAbs(off.early), maxAbs(off.after))
  expect.soft(worst, "max angle at any point in the sweep (°)").toBeLessThan(0.01)
  expect.soft(off.won, "the sweep reached the win").toBe(1)
})
