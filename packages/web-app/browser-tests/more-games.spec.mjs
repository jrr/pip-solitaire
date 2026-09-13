// The More Games flag, from the switch that turns it on to the rows it moves.
//
// A *join*, like `game-info.spec.mjs`, between parts each covered on their own: the
// hidden switch persists a flag (`MenuSettingsScreen`), a ref carries it out of the
// chrome (`Main`), the switcher files scenes into groups by it (`SceneSwitcher`), and
// the two screens draw whichever rows they were handed. What no unit test can see is
// that a game *leaves* one list as it joins the other — the two screens are rendered by
// different components, and a game listed in both would look right in either one alone.
//
// The other half is the launch path, which only a real reload exercises: the flag is
// read during module init to decide which remembered game a bare open may resume, so a
// game played under the flag has to survive a relaunch with it on, and quietly stop
// being the launch game once it is off.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

const openMenu = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

// The way back to the main screen from anywhere in the pane: the menu always opens
// there, so closing and reopening beats walking back up through the screens.
const reopenMenu = async (page) => {
  await page.getByRole("button", { name: "Close menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await openMenu(page)
}

// The Games section's rows, top-level in the main menu — the name buttons, since what
// this file asks is which games are *listed*. A family's row carries a second button
// beside its name (which of the family it is showing), a control on a row rather than a
// row: `game-variant.spec.mjs` is where that one is asked about.
const gameRows = (page) =>
  page.locator("nav[aria-label='Games'] .menu-row:not(.menu-game-row__variant)")

// …and the Debug screen's "games" disclosure, which holds the ones that haven't been
// released into that section. It isn't placed at all when it has no entries.
const gameGroup = (page) => page.locator(".scene-menu__group").filter({ hasText: "games" })

const openSettings = async (page) => {
  await page.getByRole("button", { name: "Settings", exact: true }).click()
  await expect(page.getByRole("switch", { name: /^Auto-collect/ })).toBeVisible()
}

const openDebugScreen = async (page) => {
  await openSettings(page)
  await page.getByRole("button", { name: "Debug" }).click()
}

// Flip the feature the way a tester would, from the menu's main screen: into Settings,
// ten taps on the title for the hidden rows (`HiddenOptions`) if they aren't already
// out, the switch, then back to the games list.
//
// The reveal is a *toggle* and it is persisted, so the taps are conditional: ten more
// on a screen already showing the rows would put them away again.
const setMoreGames = async (page, on) => {
  await openSettings(page)
  const moreGames = page.getByRole("switch", { name: /^More Games/ })
  if (!(await moreGames.isVisible())) {
    for (let i = 0; i < 10; i++) {
      await page.locator(".menu-title").click()
    }
    await expect(moreGames).toBeVisible()
  }
  await moreGames.click()
  await expect(moreGames).toHaveAttribute("aria-checked", String(on))
  await page.getByRole("button", { name: "Back to menu" }).click()
}

const RELEASED = ["FreeCell", "Simple Simon"]
// …and what the flag adds, in the scene list's order — which is the order the menu takes,
// one place deciding it. Not a row per game: a game that belongs to a family joins that
// family's *segment* (`game-variant.spec.mjs`), so the four short decks and packs arrive
// as one new row and one new segment on the row that was already there.
const WITH_MORE_GAMES = ["FreeCell", "Simple Simon", "Spiderette"]

test("lists every game up top once the flag is on, and empties the debug group", async ({
  page,
}) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)

  // Off by default: the two released games up top, the rest a level down under Debug.
  await expect(gameRows(page)).toHaveText(RELEASED)
  await openDebugScreen(page)
  await expect(gameGroup(page)).toBeVisible()

  await reopenMenu(page)
  await setMoreGames(page, true)

  // On: every game in the main list — the Spiderettes as a row of their own, the short
  // FreeCells on a segment beside FreeCell…
  await expect(gameRows(page)).toHaveText(WITH_MORE_GAMES)
  await expect(page.locator(".menu-game-row__variant")).toHaveCount(2)
  // …and gone from the Debug screen, which drops the group rather than showing an
  // empty disclosure.
  await openDebugScreen(page)
  await expect(gameGroup(page)).toHaveCount(0)

  // …and back off again, which is the same walk in reverse: the rows the flag lifted
  // return to the group, and the group comes back with them.
  await reopenMenu(page)
  await setMoreGames(page, false)
  await expect(gameRows(page)).toHaveText(RELEASED)
  await expect(page.locator(".menu-game-row__variant")).toHaveCount(0)
  await openDebugScreen(page)
  await expect(gameGroup(page)).toBeVisible()
})

test("mounts a promoted game from its new row, and resumes it after a reload", async ({ page }) => {
  // A plain open, no `?seed=`: the one kind that saves the game, which is what makes
  // the reload a resume rather than a re-deal.
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)
  await setMoreGames(page, true)

  // The row mounts its game exactly as a released one's does — the menu closes, and
  // the board that comes up is Spiderette's: seven cascades over a stock.
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

  // A bare launch resumes it, the flag being read before the first scene mounts…
  await page.goto("/?animate=off")
  await settleBoard(page)
  await expect(page.locator(".drop-zone__slot--stock")).toHaveCount(1)

  // …and turning the flag off puts the game back under Debug, so the next bare launch
  // opens on FreeCell rather than on a game with no row to return to.
  await openMenu(page)
  await setMoreGames(page, false)
  await page.goto("/?animate=off")
  await settleBoard(page)
  await expect(page.locator(".drop-zone__slot--stock")).toHaveCount(0)
  await expect(page.locator(".drop-zone__slot--cell")).toHaveCount(4)
})
