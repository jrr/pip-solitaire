// The games the **Beta features** flag lists, from the switch that turns it on to the
// rows it moves.
//
// A *join*, like `game-info.spec.mjs`, between parts each covered on their own: the
// hidden switch publishes a flag (`MenuSettingsScreen`), a ref carries it out of the
// chrome (`Main`), the switcher files scenes into groups by it (`SceneSwitcher`), and
// the two screens draw whichever rows they were handed. What no unit test can see is
// that a game is in one screen or the other and never both — the two screens are
// rendered by different components, and a game listed in both would look right in
// either one alone — nor that the group is absent rather than merely empty once
// nothing is withheld.
//
// **Nothing here reloads to make a flip count**, and that is the point of the walk: the
// switch is four taps away from the games list and the row has to be there when the
// walk gets back to it. Seeding the flag into storage and relaunching would pass
// against a menu that only reads it at launch, which is the thing being ruled out.
//
// The other half *is* the launch path, which only a real reload exercises: a game
// played from its row has to be what a bare open resumes.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"
import { openSettings, setBetaFeatures } from "./lib/menu.mjs"

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

// …and the Debug screen's "games" disclosure, which holds any game withheld from that
// section — Spider, until **Beta features** is on. It isn't placed at all when it has no
// entries.
const gameGroup = (page) => page.locator(".scene-menu__group").filter({ hasText: "games" })

const openDebugScreen = async (page) => {
  await openSettings(page)
  await page.getByRole("button", { name: "Debug" }).click()
}

// Every released game, in the scene list's order — which is the order the menu takes,
// one place deciding it. Not a row per game: a game that belongs to a family joins that
// family's *segment* (`game-variant.spec.mjs`), so seven boards arrive as three rows,
// two of them carrying a segment. Spider's three are the boards withheld until the flag
// is on, and arrive as a fourth row with a segment when it is.
const GAMES = ["FreeCell", "Simple Simon", "Spiderette"]
const WITHHELD = ["Spider · 1 suit", "Spider · 2 suits", "Spider · 4 suits"]

test("moves Spider between Debug and the games list as the flag flips, with no relaunch", async ({
  page,
}) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)

  // Off by default: the released games up top…
  await expect(gameRows(page)).toHaveText(GAMES)
  await expect(page.locator(".menu-game-row__variant")).toHaveCount(2)

  // …and the withheld boards one screen down, each on a row of its own — a segment is
  // the Games list's shape, not the Debug screen's — and nowhere else. The group opens
  // collapsed, the board on the table being none of them.
  await openDebugScreen(page)
  await expect(gameGroup(page)).toHaveCount(1)
  await gameGroup(page).locator("summary").click()
  await expect(gameGroup(page).getByRole("button")).toHaveText(WITHHELD)

  // On: the family joins the list as one row with a segment, on the render the walk
  // back from Settings draws — this is the same page it flipped the switch on, never
  // reloaded.
  await reopenMenu(page)
  await setBetaFeatures(page, true)
  await expect(gameRows(page)).toHaveText([...GAMES, "Spider"])
  await expect(page.locator(".menu-game-row__variant")).toHaveCount(3)
  // …and gone from the Debug screen, which drops the group rather than showing an
  // empty disclosure: the game moved between the two lists rather than joining one.
  await openDebugScreen(page)
  await expect(gameGroup(page)).toHaveCount(0)

  // And back the other way, on the same page again: a flag that only ever promoted
  // would pass everything above.
  await reopenMenu(page)
  await setBetaFeatures(page, false)
  await expect(gameRows(page)).toHaveText(GAMES)
  await openDebugScreen(page)
  await expect(gameGroup(page)).toHaveCount(1)
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
