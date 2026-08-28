// The menu's scene rows, in a real browser (#337).
//
// The switcher used to own those rows as live DOM and highlight them by rewriting a
// class on each activation. Now it hands the chrome data — the games as a list, the
// active id as a value — and the rows are ordinary `<MenuRow>`s the diff draws. That
// is a *rendering* change, and the two behaviours worth guarding across it are the two
// nothing else would catch, because both are silent when they break:
//
//   1. **Tapping the game you're already in must not re-mount it.** Activation tears
//      the live scene down and builds it afresh, so a re-mount throws away the game in
//      progress. `SceneSwitcher_test` pins the rule against a fake scene that counts
//      its mounts; what it can't pin is that the row the player actually taps reaches
//      that rule — the row is the chrome's now, and the wiring between them is exactly
//      what moved. Here the board is marked before the tap and looked for afterwards:
//      a re-mount clears `#scene-container`, so the marked node simply wouldn't
//      survive, whatever the rebuilt board happened to deal.
//
//   2. **A `?scene=` deep link must open the group it lands in**, with its row
//      highlighted and the games row above it *not*. That's the whole highlight path
//      end to end: an id the switcher resolved before the chrome's loop existed,
//      seeded into the model, rendered through the diff on two different screens.
//
// Browser-only for the ordinary reason: both run through a real page load, a real
// scene mount and the menu's own navigation, none of which jsdom assembles.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

const openMenu = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

// The Games section's rows: the switcher's primary scenes, one per game.
const gameRow = (page, name) =>
  page.locator("nav[aria-label='Games']").getByRole("button", { name })

// Down to the Debug screen, where the debug/demo scenes live in their disclosure.
const openDebugScreen = async (page) => {
  await page.getByRole("button", { name: "Settings" }).click()
  await page.getByRole("button", { name: "Debug" }).click()
}

// The "scenes" disclosure and one of its rows.
const sceneGroup = (page) => page.locator(".scene-menu__group").filter({ hasText: "scenes" })
const sceneRow = (page, name) => sceneGroup(page).getByRole("button", { name })

test("tapping the game you're already playing doesn't re-deal it", async ({ page }) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)

  // Mark the board that's up. The marker rides on the node itself, so it says
  // "this very board" rather than "a board dealt the same way" — which is the
  // distinction the test is about, `?seed=` making a re-deal look identical.
  await page.evaluate(() => {
    document.querySelector("#scene-container .table-board").dataset.pinned = "yes"
  })

  await openMenu(page)
  // The row for the game showing is marked as the current one.
  await expect(gameRow(page, "FreeCell")).toHaveAttribute("aria-current", "true")

  await gameRow(page, "FreeCell").click()
  // The tap is acknowledged — the menu closes — and that is all it does.
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await expect(page.locator("#scene-container .table-board[data-pinned='yes']")).toHaveCount(1)
})

test("a ?scene= link opens the group it lands in, with that scene marked", async ({ page }) => {
  await page.goto("/?scene=gallery&animate=off")
  await expect(page.locator(".card-gallery")).toBeVisible()

  await openMenu(page)
  // The game is still listed — it's the way back to it — but nothing here is current.
  await expect(gameRow(page, "FreeCell")).toBeVisible()
  await expect(gameRow(page, "FreeCell")).not.toHaveAttribute("aria-current", "true")

  await openDebugScreen(page)
  // Open, rather than collapsed over its own highlighted row.
  await expect(sceneGroup(page)).toHaveAttribute("open", "")
  await expect(sceneRow(page, "Gallery")).toHaveAttribute("aria-current", "true")
  await expect(sceneRow(page, "Motion")).not.toHaveAttribute("aria-current", "true")

  // …and the games row is the way back: it mounts the game, and the highlight follows.
  // (Reopening the menu is how you get back to its main screen — it always opens
  // there — rather than walking back up through Settings.)
  await page.getByRole("button", { name: "Close menu" }).click()
  await openMenu(page)
  await gameRow(page, "FreeCell").click()
  await settleBoard(page)

  await openMenu(page)
  await expect(gameRow(page, "FreeCell")).toHaveAttribute("aria-current", "true")
  await openDebugScreen(page)
  await expect(sceneRow(page, "Gallery")).not.toHaveAttribute("aria-current", "true")
})
