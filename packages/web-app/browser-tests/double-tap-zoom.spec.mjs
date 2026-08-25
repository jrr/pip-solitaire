// The board refuses the browser's double-tap-to-zoom gesture (issue: a card
// double-tapped in the iOS home-screen web app sends the card home *and* scales
// the whole viewport).
//
// The standards answer is already in the stylesheet — `touch-action: none` on
// `.stacking-playfield`, `manipulation` on `html, body` — and Chromium honours
// it, which is exactly why that half can't be tested here: an engine that obeys
// `touch-action` never offers the zoom for `preventDefault` to refuse. What this
// pins is the *second* mechanism, the one added because iOS ignores the first:
// `TableScene`'s `suppressDoubleTapZoom` calls `preventDefault()` on the second
// `touchend` of a rapid pair over the playfield.
//
// So this is a test of the refusal, not of the zoom. `defaultPrevented` on the
// touch event is the whole observable contract in a compliant engine, and it is
// the same flag WebKit reads when it decides whether to zoom — a Chromium run
// can't prove iOS stops zooming, but it can prove we still say no, which is the
// part that silently regresses (dropping the listener, letting it register
// passive, or narrowing the window until real taps fall outside it).
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

// `zoomSuppressMs` in TableScene.res. Two taps closer together than this are a
// pair the browser could zoom on; anything slower is two separate taps.
const SUPPRESS_MS = 500

// Record `defaultPrevented` for every `touchend` that reaches the document, in
// order. Listening on `document` (bubble phase, after the playfield's own
// handler) is what makes the flag readable at all — it is set by the time the
// event has finished bubbling, and reading it any earlier would race the
// listener under test.
async function recordTouchEnds(page) {
  await page.evaluate(() => {
    window.__touchEnds = []
    document.addEventListener("touchend", (e) => window.__touchEnds.push(e.defaultPrevented))
  })
}

const touchEnds = (page) => page.evaluate(() => window.__touchEnds)

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

  // Without the reset in `suppressDoubleTapZoom` the third tap would chain off
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
  await page.goto("/?scene=freecell&state=almost-won&animate=off")
  await settleBoard(page)

  const cell = await page.locator(".drop-zone").nth(0).boundingBox()
  const king = { x: cell.x + cell.width / 2, y: cell.y + cell.height / 2 }
  await page.touchscreen.tap(king.x, king.y)
  await page.touchscreen.tap(king.x, king.y)

  await expect(page.locator(".win-overlay")).toHaveCount(1)
})

test("refuses a pair anywhere on the stage, not just on a card", async ({ page }) => {
  // Deliberately position-blind (see the note on `zoomSuppressMs`): the browser
  // will zoom on a pair that lands on the bare table just as readily as one on a
  // card, and unlike the send-home gesture there is nothing here that needs the
  // two taps to agree on a target.
  const stage = await page.locator(".stacking-playfield").boundingBox()
  const empty = { x: stage.x + stage.width / 2, y: stage.y + stage.height - 40 }

  await page.touchscreen.tap(empty.x, empty.y)
  await page.touchscreen.tap(empty.x, empty.y)

  expect(await touchEnds(page)).toEqual([false, true])
})
