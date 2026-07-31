// The web win flow, end to end (issue #121): load the near-won FreeCell position
// (`?state=almost-won`), play the single winning move by dragging the pending
// King onto its foundation, and confirm the win overlay appears — then that New
// Game tears it down.
//
// Needs a real browser for the input half: the move is a pointer drag across the
// board, which jsdom can't dispatch against a layout it doesn't have.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

// A roomy portrait viewport so every zone is comfortably on screen and the drag
// is a straight line across the board.
test.use({ viewport: { width: 800, height: 1000 } })

test("the winning move raises the overlay, and New Game tears it down", async ({ page }) => {
  // `animate=off` skips the opening fly-in (see AppUrl), so the board is at its
  // resting positions as soon as the cards exist — the drag then measures the
  // final footprints rather than racing the deal.
  await page.goto("/?scene=freecell&state=almost-won&animate=off")

  // The pending King rests alone in the first free cell (drop zone 0); its
  // foundation is the last drop zone (4 cells, then 4 foundations, Clubs last —
  // zone 7). The King is centred in its cell, so grabbing from the cell's centre
  // picks it up.
  const cell = page.locator(".drop-zone").nth(0)
  const foundation = page.locator(".drop-zone").nth(7)
  await settleBoard(page)
  await expect(foundation).toBeVisible()

  const cellBox = await cell.boundingBox()
  const foundationBox = await foundation.boundingBox()
  const from = { x: cellBox.x + cellBox.width / 2, y: cellBox.y + cellBox.height / 2 }
  const to = {
    x: foundationBox.x + foundationBox.width / 2,
    y: foundationBox.y + foundationBox.height / 2,
  }

  await page.mouse.move(from.x, from.y)
  await page.mouse.down()
  // A few incremental moves so pointermove fires and the hover highlight updates.
  for (let i = 1; i <= 6; i++) {
    await page.mouse.move(from.x + ((to.x - from.x) * i) / 6, from.y + ((to.y - from.y) * i) / 6)
  }
  await page.mouse.up()

  const overlay = page.locator(".win-overlay")
  await expect(overlay).toHaveCount(1)
  await expect(page.locator(".win-panel__title")).toBeVisible()
  await expect(page.locator(".win-panel__title")).not.toHaveText("")

  await page.locator(".win-panel__button").click()
  await expect(overlay).toHaveCount(0)
  // New Game deals a fresh board rather than just clearing the overlay.
  await expect(page.locator(".stacking-card").first()).toBeVisible()
})
