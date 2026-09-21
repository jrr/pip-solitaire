// The Debug screen's "Autoplay" row: the console's `autoplay`, pressed instead of
// typed. The board goes to the solver, and the menu that was covering it comes down so
// the line can be watched being played.
//
// Browser-only for the same reason the row exists at all. `MenuDebugScreen_test` pins
// what the row says and `TableScene_test` what the board answers; what neither can
// reach is the thing in between — a real search on the page's own thread, a menu that
// takes itself down when one comes back with a line, and a board that plays it through
// to a win with nobody typing anything.

import { expect, test } from "@playwright/test"
import { quietWin, settleBoard } from "./lib/board.mjs"
import { openSettings } from "./lib/menu.mjs"

test.use({ viewport: { width: 800, height: 1000 }, ...quietWin })

// A real search, then forty-odd moves: slower than a test that only reads chrome.
test.setTimeout(90_000)

// A whole deal rather than a posed position, so the solver is handed the board a player
// would be looking at. `?animate=off` because the flights are `stop-autoplay.spec.mjs`'s
// subject, not this file's — what is under test here is that the run happens at all.
const DEAL = "/?game=freecell&seed=24680&animate=off"

const autoplayRow = (page) =>
  page.locator(".menu-row--action", {
    has: page.locator('.menu-row__label:text-is("Autoplay")'),
  })

const openDebug = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await openSettings(page)
  await page.getByRole("button", { name: "Debug" }).first().click()
  await expect(autoplayRow(page)).toBeVisible()
}

test("the row hands the board to the solver, gets out of the way, and the line is played", async ({
  page,
}) => {
  await page.goto(DEAL)
  await settleBoard(page)
  await openDebug(page)
  await expect(autoplayRow(page)).toHaveText(/Solve the current game/)

  await autoplayRow(page).click()
  // The menu goes when — and only when — there is a line to watch, so this is the press's
  // answer as much as the cards are.
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await expect(page.locator(".win-overlay")).toBeVisible({ timeout: 60_000 })
})

test("a scene with no board to solve says so, and the row can't be pressed", async ({ page }) => {
  // A demo scene publishes no board, which is the same nothing the console answers with
  // "no board on this scene" — and a row that can't act is dark rather than sorry.
  await page.goto("/?scene=gallery")
  await openDebug(page)
  await expect(autoplayRow(page)).toHaveText(/No game on screen to solve\./)
  await expect(autoplayRow(page)).toBeDisabled()
})
