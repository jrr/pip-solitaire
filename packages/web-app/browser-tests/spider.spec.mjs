// Spider, in a real browser: Spiderette's board on two packs. `Core_test` holds the
// rules — the counts, the five rows in the stock, the eight runs. What only a browser
// can say is that a hundred and four cards lay out on the stage at all, with the
// opening's backs where the snapshot says and the stock a tap deals from until it is
// out; the compressed column is judged on Spiderette (`spiderette.spec.mjs`) and Spider
// is laid out by the same fan.
//
// The deal is played from `seed=1`, so every tap lands on the same board.

import { expect, test } from "@playwright/test"
import { settle } from "../scripts/autoplay/read-board.mjs"

test.use({ viewport: { width: 1280, height: 900 } })

const cards = (page) => page.locator(".stacking-card")
const stock = (page) => page.locator(".stacking-card--stock")
const backs = (page) => page.locator(".stacking-card--down:not(.stacking-card--stock)")

// The stock's top card is the one the board announces — reflow takes a squared pile's
// covered cards out of the accessible tree — so it is the one to tap.
async function tapStock(page) {
  const top = page.locator('.stacking-card--stock:not([aria-hidden="true"])')
  await expect(top).toHaveCount(1)
  const box = await top.boundingBox()
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
  await settle(page)
}

test("deals 54 cards with only the tops up, and the stock deals its five rows by tap", async ({
  page,
}) => {
  await page.goto("/?game=spider&seed=1&animate=off")
  await settle(page)
  await expect(cards(page)).toHaveCount(104)
  await expect(page.locator(".drop-zone")).toHaveCount(19)
  await expect(stock(page)).toHaveCount(50)
  // Six and five to a column, all but the top face down: 44 backs on the tableau.
  await expect(backs(page)).toHaveCount(44)

  // Every tap drops a row of ten; the fifth empties the stock, and its slot shows.
  for (let row = 1; row <= 5; row++) {
    await tapStock(page)
    await expect(stock(page)).toHaveCount(50 - 10 * row)
  }
  await expect(page.locator(".drop-zone__slot--stock")).toBeVisible()
  // Dealt cards land face up, over the backs the opening left.
  await expect(backs(page)).toHaveCount(44)
  await expect(cards(page)).toHaveCount(104)
})
