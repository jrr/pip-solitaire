// The Hint button: a beta feature, there from the start, and the only thing that sets the
// solver thinking on its own board. A press asks for a line, shows its next move on the
// board without playing it, and says what it found in a toast that fades.
//
// Browser-only, because the thinking is a worker's (jsdom has none) and what a press
// shows is an animation jsdom can't run. What was sent to the solver is read off the
// page's own `Worker`, as `solve-row.spec.mjs` reads it.

import { expect, test } from "@playwright/test"
import { quietWin, settleBoard } from "./lib/board.mjs"
import { setBetaFeatures } from "./lib/menu.mjs"

test.use({ viewport: { width: 800, height: 1000 }, ...quietWin })
test.setTimeout(60_000)

// A FreeCell deal the solver answers in a few milliseconds.
const DEAL = "/?game=freecell&seed=24680&animate=off"

const hint = (page) => page.getByRole("button", { name: "Hint", exact: true })
const toast = (page) => page.locator("#hint-toast")

const betaOn = (page) =>
  page.addInitScript(() => localStorage.setItem("pip.betaFeatures", "true"))

// Every message to the solver's worker, in order.
const listen = (page) =>
  page.addInitScript(() => {
    window.__told = []
    const Base = window.Worker
    window.Worker = class extends Base {
      postMessage(message) {
        window.__told.push(message)
        super.postMessage(message)
      }
    }
  })

const thinks = (page) =>
  page.evaluate(() => window.__told.filter((message) => message.TAG === "Think"))

test("off without Beta features: no Hint", async ({ page }) => {
  await page.goto(DEAL)
  await settleBoard(page)
  await expect(hint(page)).toHaveCount(0)
})

test("there from the start, and nothing is thought about until it is pressed", async ({
  page,
}) => {
  await betaOn(page)
  await listen(page)
  await page.goto(DEAL)
  await settleBoard(page)
  await expect(hint(page)).toBeVisible()
  // Left still for well past anything that might count as a pause.
  await page.waitForTimeout(3000)
  expect(await thinks(page)).toHaveLength(0)
  await expect(toast(page)).toHaveCount(0)

  await hint(page).click()
  await expect(toast(page)).toHaveText(/^Solution found · \d+ moves to go$/, { timeout: 15_000 })
  expect(await thinks(page)).toHaveLength(1)
  // Shown, not played: nothing to undo.
  await expect(page.getByRole("button", { name: "Undo" })).toBeDisabled()

  // A toast, not a panel: it goes on its own.
  await expect(toast(page)).toHaveCount(0, { timeout: 10_000 })

  // The same board again is already known: shown at once, with nothing more asked.
  await hint(page).click()
  await expect(toast(page)).toHaveText(/^Solution found/)
  expect(await thinks(page)).toHaveLength(1)
})

test("a press lights the move's card, then where it lands, twice", async ({ page }) => {
  await betaOn(page)
  await page.goto(DEAL)
  await settleBoard(page)
  await hint(page).click()
  await expect(page.locator(".hint-mask").first()).toBeAttached({ timeout: 15_000 })
  // Source, then target, a beat, then both again — each a mask of its own, staggered. The
  // first deal's opening move is one card, so four masks: two on it, two where it lands.
  const timings = await page.evaluate(() => {
    const masks = [...document.querySelectorAll(".hint-mask")]
    const cards = [...new Set(masks.map((mask) => mask.parentElement))]
    return masks.map((mask) => ({
      card: cards.indexOf(mask.parentElement),
      delay: mask.getAnimations()[0].effect.getTiming().delay,
    }))
  })
  const delays = timings.map((t) => t.delay).sort((a, b) => a - b)
  expect(delays).toHaveLength(4)
  const [first, second, third, fourth] = delays
  expect(first).toBe(0)
  expect(fourth - third).toBe(second - first)
  expect(third - second).toBeGreaterThan(second - first)
  const at = (delay) => timings.find((t) => t.delay === delay).card
  expect(at(first)).toBe(at(third))
  expect(at(second)).toBe(at(fourth))
  expect(at(first)).not.toBe(at(second))
})

test("goes when Beta features does", async ({ page }) => {
  await betaOn(page)
  await page.goto(DEAL)
  await settleBoard(page)
  await expect(hint(page)).toBeVisible()
  await page.getByRole("button", { name: "Open menu" }).click()
  await setBetaFeatures(page, false)
  await expect(hint(page)).toHaveCount(0)
})
