// The Hint button: there while a winning line is known from the board on the table,
// and a press shows that line's next move on the board without playing it.
//
// Browser-only, because the line is known only by thinking unasked, which needs a worker
// (jsdom has none), and what a press shows is an animation jsdom can't run.

import { expect, test } from "@playwright/test"
import { quietWin, settleBoard } from "./lib/board.mjs"
import { setBetaFeatures } from "./lib/menu.mjs"

test.use({ viewport: { width: 800, height: 1000 }, ...quietWin })
test.setTimeout(60_000)

// The deal `think-ahead.spec.mjs` uses: answered in a few milliseconds.
const DEAL = "/?game=freecell&seed=24680&animate=off"

const hint = (page) => page.getByRole("button", { name: "Hint", exact: true })

test("off without Beta features: no Hint, however long the board sits", async ({ page }) => {
  await page.goto(DEAL)
  await settleBoard(page)
  await page.waitForTimeout(4000)
  await expect(hint(page)).toHaveCount(0)
})

test("appears once a line is known, and a press lights cards without moving any", async ({
  page,
}) => {
  await page.addInitScript(() => localStorage.setItem("pip.betaFeatures", "true"))
  await page.goto(DEAL)
  await settleBoard(page)
  await expect(hint(page)).toBeVisible({ timeout: 15_000 })

  await hint(page).click()
  await expect(page.locator(".hint-mask").first()).toBeAttached()
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
  // Shown, not played: nothing to undo.
  await expect(page.getByRole("button", { name: "Undo" })).toBeDisabled()
})

test("goes when Beta features does", async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem("pip.betaFeatures", "true"))
  await page.goto(DEAL)
  await settleBoard(page)
  await expect(hint(page)).toBeVisible({ timeout: 15_000 })
  await page.getByRole("button", { name: "Open menu" }).click()
  await setBetaFeatures(page, false)
  await expect(hint(page)).toHaveCount(0)
})
