// The Debug screen's "Copy seed" row, end to end (#98).
//
// The claim the feature makes is a *round trip*: the number this button copies,
// pasted into `?seed=`, deals the identical board. Every link in that chain is
// covered by unit tests — the deal is deterministic (`Core_test`), the row renders
// the seed it was handed (`Menu_test`) — but the chain itself only exists in a real
// browser, because it runs through the clipboard and a page load.
//
// Browser-only for a second reason: `navigator.clipboard` doesn't exist in jsdom at
// all, so "the number actually reaches the clipboard" is unaskable there. Here it's
// the whole point, and Playwright can grant the permission a real user grants.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({
  viewport: { width: 800, height: 1000 },
  // The clipboard write is permission-gated; grant it as a user would.
  permissions: ["clipboard-read", "clipboard-write"],
})

// The board's card layout as plain data: every pile's cards, in order, read off the
// DOM. Two boards dealt from the same seed must produce identical strings — this is
// what "the same deal" means to a player.
async function boardLayout(page) {
  return await page.evaluate(() =>
    [...document.querySelectorAll(".stacking-card")]
      .map((el) => `${el.getAttribute("aria-label") ?? el.textContent}@${el.style.transform}`)
      .join("|"),
  )
}

// Walk the menu down to the Debug screen, where the row lives: Menu → Settings → Debug.
async function openDebugScreen(page) {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
  await page.getByRole("button", { name: "Settings", exact: true }).click()
  await page.getByRole("button", { name: "Debug", exact: true }).click()
}

test("copies the deal number, and that number reopens the same board", async ({ page }) => {
  // Open a known deal, so the assertion can name the number the row must show.
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  const original = await boardLayout(page)

  await openDebugScreen(page)

  // The row names the deal on the table…
  const row = page.locator(".menu-copy")
  await expect(row).toContainText("Deal 24680")

  // …and copying it puts exactly that number on the clipboard.
  await page.getByRole("button", { name: "Copy seed 24680" }).click()
  await expect(page.locator(".menu-copy__button")).toHaveText("Copied")
  const copied = await page.evaluate(() => navigator.clipboard.readText())
  expect(copied).toBe("24680")

  // The round trip: paste what was copied into `?seed=` — as the player receiving a
  // shared deal would — and the board comes back identical, card for card.
  await page.goto(`/?seed=${copied}&animate=off`)
  await settleBoard(page)
  expect(await boardLayout(page)).toBe(original)
})

test("offers the fresh deal number after a New Game", async ({ page }) => {
  // The regression this guards: the row must track the board actually on the table,
  // not the deal the page opened with. A stale number here would be the worst kind of
  // bug for a share feature — it sends someone to a board you're not playing.
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)

  await openDebugScreen(page)
  await expect(page.locator(".menu-copy")).toContainText("Deal 13579")

  // New Game deals a fresh random seed and closes the menu; reopen and look again.
  // The back buttons read "‹ Back" but carry an `aria-label` naming where each
  // returns to, and that label is the accessible name a role query matches on.
  await page.getByRole("button", { name: "Back to settings" }).click()
  await page.getByRole("button", { name: "Back to menu" }).click()
  await page.getByRole("button", { name: "New Game" }).click()
  await settleBoard(page)

  await openDebugScreen(page)
  const row = page.locator(".menu-copy")
  await expect(row).toBeVisible()
  await expect(row).not.toContainText("Deal 13579")

  // Whatever number it now shows is the one that reopens *this* board.
  const shown = await row.locator(".menu-toggle__label").textContent()
  const seed = shown.replace("Deal ", "").trim()
  const afterNewGame = await boardLayout(page)
  await page.goto(`/?seed=${seed}&animate=off`)
  await settleBoard(page)
  expect(await boardLayout(page)).toBe(afterNewGame)
})

test("shows no deal-number row on a board that has no deal number", async ({ page }) => {
  // A fixed-layout demo isn't reproducible from a number, so the row is absent
  // rather than offering something unshareable.
  await page.goto("/?scene=stacking&animate=off")
  await settleBoard(page)

  await openDebugScreen(page)
  await expect(page.locator(".menu-copy")).toHaveCount(0)
})
