// The menu's "Share" button, end to end (#98).
//
// The claim the feature makes is a *round trip*: the link this button hands over,
// opened anywhere, deals the identical board. Every link in that chain has a unit
// test — the deal is deterministic (`Core_test`), the URL is shaped right
// (`ShareLink_test`), the row shows the number it shares (`Menu_test`) — but the
// chain itself only exists in a real browser, because it runs through the clipboard
// and a page load.
//
// Browser-only for a second reason: `navigator.clipboard` doesn't exist in jsdom at
// all, so "the link actually reaches the player" is unaskable there. Here it's the
// whole point, and Playwright can grant the permission a real user grants.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({
  viewport: { width: 800, height: 1000 },
  // With no OS share sheet in headless Chromium, `ShareLink.deliver` falls back to
  // the clipboard — so that's the path under test, and reading the result back needs
  // the grant.
  permissions: ["clipboard-read", "clipboard-write"],
})

// The board's card layout as plain data: every card by name, with where it came to
// rest. Two boards dealt from the same number must produce identical lists — that's
// what "the same deal" means to a player. Sorted, because DOM order follows
// z-stacking rather than layout.
async function readBoard(page) {
  return await page.evaluate(() =>
    [...document.querySelectorAll(".stacking-card")]
      .map((card) => {
        const art = card.querySelector("[aria-label]")
        const { left, top } = getComputedStyle(card)
        return `${art?.getAttribute("aria-label") ?? "?"} @ ${left},${top}`
      })
      .sort(),
  )
}

// The Share button lives on the main menu, one tap in, beside New Game and Restart.
async function openMenu(page) {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

// The line under the buttons: the deal on the table, or where a link just went.
const shareLine = (page) => page.locator(".menu-share-line")

// Press Share and hand back the link it put on the clipboard.
async function shareDeal(page) {
  await page.getByRole("button", { name: /^Share deal / }).click()
  await expect(shareLine(page)).toHaveText("Link copied to clipboard.")
  return await page.evaluate(() => navigator.clipboard.readText())
}

test("shares a link to the deal on the table, and that link reopens it", async ({ page }) => {
  // Open a known deal, so the assertion can name the number the menu must show.
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  const dealt = await readBoard(page)
  expect(dealt.length).toBe(52)

  await openMenu(page)
  await expect(shareLine(page)).toHaveText("Deal 24680")

  const url = await shareDeal(page)
  // The link says which board to deal and nothing else — legible, and short enough
  // to be read off one screen and typed into another.
  expect(new URL(url).searchParams.get("seed")).toBe("24680")
  expect(new URL(url).hash).toBe("")

  // The round trip, as the recipient makes it: open what was shared, cold.
  await page.goto(url)
  await settleBoard(page)
  expect(await readBoard(page)).toEqual(dealt)
})

test("offers the fresh deal after a New Game", async ({ page }) => {
  // The regression this guards: the row must track the board actually on the table,
  // not the deal the page opened with. A stale number here would be the worst kind of
  // bug for a share feature — it sends someone to a board you're not playing.
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)

  await openMenu(page)
  await expect(shareLine(page)).toHaveText("Deal 13579")

  // New Game deals a fresh random seed and closes the menu; reopen and look again.
  await page.getByRole("button", { name: "New Game" }).click()
  await settleBoard(page)
  const afterNewGame = await readBoard(page)

  await openMenu(page)
  await expect(shareLine(page)).not.toHaveText("Deal 13579")

  // …and whatever it now offers is a link to *this* board.
  const url = await shareDeal(page)
  await page.goto(url)
  await settleBoard(page)
  expect(await readBoard(page)).toEqual(afterNewGame)
})

test("a resumed game can still say which deal it is", async ({ page }) => {
  // The case that made the deal number worth persisting (`SavedGame.saveSeed`): a
  // resumed board restores its *positions* from storage, and the deal that produced
  // them is long gone by then. Without the number saved beside the game, the Share
  // button would be dark on the most ordinary open there is — start the app, carry on
  // with the game you had.
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)
  const dealt = await shareLine(page).textContent()
  expect(dealt).toMatch(/^Deal \d+$/)

  // Reload with a bare URL: no seed to pin the deal, so the board that comes back is
  // the saved one, resumed.
  await page.goto("/")
  await settleBoard(page)
  await openMenu(page)
  await expect(shareLine(page)).toHaveText(dealt)
})

test("says so on a board with no deal number, rather than offering one", async ({ page }) => {
  // A fixed-layout demo isn't reproducible from a number, so the button is disabled
  // and the line explains — never a link to a board the sender isn't looking at.
  await page.goto("/?scene=stacking&animate=off")
  await settleBoard(page)

  await openMenu(page)
  await expect(page.getByRole("button", { name: "Share" })).toBeDisabled()
  await expect(shareLine(page)).toHaveText("No deal number for this board.")
})
