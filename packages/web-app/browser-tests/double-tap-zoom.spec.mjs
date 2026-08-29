// The app refuses the browser's double-tap-to-zoom gesture (issue: in the iOS
// home-screen web app a double-tap scales the whole viewport — on a card, where
// it also sends the card home, on the chrome, and on the menu's dead space, from
// where a second double-tap is the only way back out).
//
// The standards answer is already in the stylesheet — `manipulation` on
// `html, body`, tightened to `none` on `.stacking-playfield` — and Chromium
// honours it, which is exactly why that half can't be tested here: an engine that
// obeys `touch-action` never offers the zoom for `preventDefault` to refuse. What
// this pins is the *second* mechanism, the one added because iOS ignores the
// first: `TapZoom.arm` calls `preventDefault()` on the second `touchend` of a
// rapid pair, anywhere in the document.
//
// So this is a test of the refusal, not of the zoom. `defaultPrevented` on the
// touch event is the whole observable contract in a compliant engine, and it is
// the same flag WebKit reads when it decides whether to zoom — a Chromium run
// can't prove iOS stops zooming, but it can prove we still say no, which is the
// part that silently regresses (dropping the `arm` call, letting the listener
// register passive, or narrowing the window until real taps fall outside it).
//
// Needs a real browser: jsdom has no touch input and no layout to aim it at.

import { devices, expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"
import { contextOptions } from "../scripts/lib/devices.mjs"

// A real device descriptor rather than a phone-sized desktop window, so the page
// actually gets touch events — `page.touchscreen` needs `hasTouch`, and without
// it there are no `touchend`s to refuse. `contextOptions` drops the descriptor's
// `defaultBrowserType`; the suite is Chromium whatever the device implies.
test.use(contextOptions(devices["iPhone 13 Mini"]))

// `suppressMs` / `suppressMoveTol` in TapZoom.res. Two taps closer together than
// this in time *and* space are one gesture aimed at one spot — the pair WebKit
// would zoom on. Anything slower or further apart is two separate taps.
const SUPPRESS_MS = 350
const MOVE_TOL = 30

// Record `defaultPrevented` for every `touchend` that reaches the document, in
// order. The listener under test runs in the *capture* phase, so a plain bubble
// listener here sees the flag already settled — reading it any earlier would race
// the refusal.
async function recordTouchEnds(page) {
  await page.evaluate(() => {
    window.__touchEnds = []
    document.addEventListener("touchend", (e) => window.__touchEnds.push(e.defaultPrevented))
  })
}

const touchEnds = (page) => page.evaluate(() => window.__touchEnds)

// Drop what has been recorded so far, without adding a second recorder — the
// listener reads `window.__touchEnds` fresh on every event, so re-arming would
// double every entry from then on.
const resetTouchEnds = (page) => page.evaluate(() => (window.__touchEnds = []))

// The centre of the top card of the first cascade — a card a player would
// plausibly double-tap to send home.
async function topCardCentre(page) {
  const box = await page.locator(".stacking-card").last().boundingBox()
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 }
}

test.beforeEach(async ({ page }) => {
  // `?animate=off` skips the deal flight: the cards are where they will stay by
  // the time the taps land, so the second tap can't chase a card that moved.
  await page.goto("/?animate=off")
  await settleBoard(page)
  await recordTouchEnds(page)
})

test("refuses the second tap of a double-tap on a card", async ({ page }) => {
  const card = await topCardCentre(page)
  await page.touchscreen.tap(card.x, card.y)
  await page.touchscreen.tap(card.x, card.y)

  // The first tap is an ordinary tap and must stay one — refusing it would eat
  // gestures that never become a pair. Only the second is refused.
  expect(await touchEnds(page)).toEqual([false, true])
})

test("leaves a lone tap alone", async ({ page }) => {
  const card = await topCardCentre(page)
  await page.touchscreen.tap(card.x, card.y)

  expect(await touchEnds(page)).toEqual([false])
})

test("starts a fresh pair after a refusal, so a third tap is not refused", async ({ page }) => {
  const card = await topCardCentre(page)
  await page.touchscreen.tap(card.x, card.y)
  await page.touchscreen.tap(card.x, card.y)
  await page.touchscreen.tap(card.x, card.y)

  // Without the reset in `TapZoom.arm` the third tap would chain off
  // the second and be refused too, and every tap thereafter with it.
  expect(await touchEnds(page)).toEqual([false, true, false])
})

test("leaves taps outside the window alone", async ({ page }) => {
  const card = await topCardCentre(page)
  await page.touchscreen.tap(card.x, card.y)
  await page.waitForTimeout(SUPPRESS_MS + 150)
  await page.touchscreen.tap(card.x, card.y)

  expect(await touchEnds(page)).toEqual([false, false])
})

test("still lets the send-home double-tap through", async ({ page }) => {
  // The other half of the contract, and the reason the refusal is confined to the
  // touch layer: `preventDefault()` on a `touchend` suppresses the browser's
  // gesture and the synthesised click, but not the Pointer Events the board is
  // actually played with. Break that — refuse too early, or reach for
  // `touchstart` — and the zoom stops along with the game.
  //
  // `almost-won` leaves a single King in the first free cell, one move from home
  // (see win.spec.mjs). Double-tapping it plays that move, so the win overlay
  // standing is proof the gesture survived the suppression.
  await page.goto("/?game=freecell&state=almost-won&animate=off")
  await settleBoard(page)

  const cell = await page.locator(".drop-zone").nth(0).boundingBox()
  const king = { x: cell.x + cell.width / 2, y: cell.y + cell.height / 2 }
  await page.touchscreen.tap(king.x, king.y)
  await page.touchscreen.tap(king.x, king.y)

  await expect(page.locator(".win-overlay")).toHaveCount(1)
})

test("refuses a pair anywhere on the stage, not just on a card", async ({ page }) => {
  // The browser will zoom on a pair that lands on the bare table just as readily
  // as one on a card, and unlike the send-home gesture nothing here needs the two
  // taps to agree on a *target* — only to be aimed at the same spot.
  const stage = await page.locator(".stacking-playfield").boundingBox()
  const empty = { x: stage.x + stage.width / 2, y: stage.y + stage.height - 40 }

  await page.touchscreen.tap(empty.x, empty.y)
  await page.touchscreen.tap(empty.x, empty.y)

  expect(await touchEnds(page)).toEqual([false, true])
})

// The chrome, not the board. `.stacking-playfield` carries its own stricter
// `touch-action: none`, so a board-only refusal would have looked complete while
// the menu — the one place a double-tap could also zoom back *out* — still zoomed.
test.describe("in the menu", () => {
  test.beforeEach(async ({ page }) => {
    await page.getByRole("button", { name: /Open menu/ }).click()
    await expect(page.getByRole("button", { name: "New" })).toBeVisible()
    // Cleared after the tap that opened the menu, so the recording starts clean.
    await resetTouchEnds(page)
  })

  test("refuses a pair on the menu's dead space", async ({ page }) => {
    // The reported way back *out* of a zoom, and so the one that has to close:
    // bare pane between the controls, where nothing is listening for a tap at all.
    const pane = await page.locator(".menu-panel").boundingBox()
    const dead = { x: pane.x + pane.width / 2, y: pane.y + pane.height - 8 }

    await page.touchscreen.tap(dead.x, dead.y)
    await page.touchscreen.tap(dead.x, dead.y)

    expect(await touchEnds(page)).toEqual([false, true])
  })

  test("leaves the version badge's double-tap alone", async ({ page }) => {
    // The build string opts back into `user-select: text` so it can be copied, and
    // on iOS double-tap-to-select-word is how a selection starts — refusing the
    // default there would take the selection with the zoom (`selectableSelector`).
    const badge = await page.locator("#version-badge").boundingBox()
    const centre = { x: badge.x + badge.width / 2, y: badge.y + badge.height / 2 }

    await page.touchscreen.tap(centre.x, centre.y)
    await page.touchscreen.tap(centre.x, centre.y)

    expect(await touchEnds(page)).toEqual([false, false])
  })

  test("leaves two quick taps on different controls alone", async ({ page }) => {
    // The case that set `suppressMoveTol`. Refusing a `touchend` suppresses that
    // tap's synthesised `click` along with the zoom, so a pair refused on time
    // alone would eat the second control: open the menu and go straight for New —
    // well inside 350ms — and New would never fire. Distinct controls are further
    // apart than the tolerance, so both taps stay live.
    //
    // Asserted through `defaultPrevented` rather than by watching for a click:
    // Chromium synthesises no click from injected touch events at all (a single
    // `touchscreen.tap` on New doesn't close the menu even with this module gone),
    // so the flag is the only observable here — and it is the one WebKit reads.
    const settings = await page.getByRole("button", { name: "Settings", exact: true }).boundingBox()
    const newGame = await page.getByRole("button", { name: "New" }).boundingBox()
    expect(Math.abs(newGame.y - settings.y)).toBeGreaterThan(MOVE_TOL)

    await page.touchscreen.tap(newGame.x + newGame.width / 2, newGame.y + newGame.height / 2)
    await page.touchscreen.tap(settings.x + settings.width / 2, settings.y + settings.height / 2)

    expect(await touchEnds(page)).toEqual([false, false])
  })
})
