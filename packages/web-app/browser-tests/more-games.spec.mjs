// The games the menu lists, from the rows up top to the group under Debug they leave
// empty.
//
// A *join*, like `game-info.spec.mjs`, between parts each covered on their own: `Main`
// names every game the switcher should file as a top-level row, the switcher files the
// rest into groups (`SceneSwitcher`), and the two screens draw whichever rows they were
// handed. What no unit test can see is that the Debug screen's "games" group is not
// merely empty but absent — the two screens are rendered by different components, and a
// game listed in both would look right in either one alone.
//
// The other half is the launch path, which only a real reload exercises: a game played
// from its row has to be what a bare open resumes.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"
import { openSettings } from "./lib/menu.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

const openMenu = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

// The Games section's rows, top-level in the main menu — the name buttons, since what
// this file asks is which games are *listed*. A family's row carries a second button
// beside its name (which of the family it is showing), a control on a row rather than a
// row: `game-variant.spec.mjs` is where that one is asked about.
const gameRows = (page) =>
  page.locator("nav[aria-label='Games'] .menu-row:not(.menu-game-row__variant)")

// …and the Debug screen's "games" disclosure, which would hold any game withheld from
// that section. It isn't placed at all when it has no entries.
const gameGroup = (page) => page.locator(".scene-menu__group").filter({ hasText: "games" })

const openDebugScreen = async (page) => {
  await openSettings(page)
  await page.getByRole("button", { name: "Debug" }).click()
}

// Every game, in the scene list's order — which is the order the menu takes, one place
// deciding it. Not a row per game: a game that belongs to a family joins that family's
// *segment* (`game-variant.spec.mjs`), so seven boards arrive as three rows, two of them
// carrying a segment.
const GAMES = ["FreeCell", "Simple Simon", "Spiderette"]

test("lists every game up top, and places no games group under Debug", async ({ page }) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)

  await expect(gameRows(page)).toHaveText(GAMES)
  await expect(page.locator(".menu-game-row__variant")).toHaveCount(2)

  // Nothing is withheld, so the Debug screen drops the group rather than showing an
  // empty disclosure.
  await openDebugScreen(page)
  await expect(gameGroup(page)).toHaveCount(0)
})

test("mounts a game from its row, and resumes it after a reload", async ({ page }) => {
  // A plain open, no `?seed=`: the one kind that saves the game, which is what makes
  // the reload a resume rather than a re-deal.
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)

  // The row mounts its game — the menu closes, and the board that comes up is
  // Spiderette's: seven cascades over a stock.
  await page.getByRole("button", { name: "Spiderette", exact: true }).click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await settleBoard(page)
  await expect(page.locator(".drop-zone__slot--stock")).toHaveCount(1)

  await openMenu(page)
  await expect(
    page
      .locator("nav[aria-label='Games']")
      .getByRole("button", { name: "Spiderette", exact: true }),
  ).toHaveAttribute("aria-current", "true")

  // A bare launch resumes it.
  await page.goto("/?animate=off")
  await settleBoard(page)
  await expect(page.locator(".drop-zone__slot--stock")).toHaveCount(1)
})
