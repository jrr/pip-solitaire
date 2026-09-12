// The game info feature, from the switch that turns it on to the screen it opens.
//
// Everything here is a *join* between parts that unit tests cover one at a time: the
// hidden switch persists a flag (`MenuSettingsScreen`), the flag decides whether a
// game's row is handed an `onInfo` (`Main`), the row draws the "i" from that
// (`MenuGameRow`), and the tap swaps the pane to a fourth screen (`Menu`). No single one
// of those can see the chain, and the chain is what a player has.
//
// The segmented row is also a *measured* claim — two buttons that have to read as one
// control, which is `.menu-game-row`'s flex row and the squared-off corners between the
// segments (MenuGameRow.css). A stylesheet is only evaluated by a browser.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

const openMenu = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

const openSettings = async (page) => {
  await page.getByRole("button", { name: "Settings", exact: true }).click()
  await expect(page.getByRole("switch", { name: /^Auto-collect/ })).toBeVisible()
}

// Turn the feature on the way a tester would: ten taps on the Settings title for the
// hidden rows (`HiddenOptions`), the switch, then back to the games list.
const enableGameInfo = async (page) => {
  await openSettings(page)
  for (let i = 0; i < 10; i++) {
    await page.locator(".menu-title").click()
  }
  const gameInfo = page.getByRole("switch", { name: /^Game info/ })
  await expect(gameInfo).toBeVisible()
  await gameInfo.click()
  await expect(gameInfo).toHaveAttribute("aria-checked", "true")
  await page.getByRole("button", { name: "Back to menu" }).click()
}

test("hides the info buttons until the flag is found, then puts one beside each game", async ({
  page,
}) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)

  // Off by default, and off is the plain row the menu has always had.
  await expect(page.locator(".menu-game-row__info")).toHaveCount(0)

  await enableGameInfo(page)
  await expect(page.getByRole("button", { name: "About FreeCell" })).toBeVisible()
  await expect(page.getByRole("button", { name: "About Simple Simon" })).toBeVisible()

  // …and it stays on across a launch, the flag being persisted like every other
  // preference.
  await page.reload()
  await settleBoard(page)
  await openMenu(page)
  await expect(page.getByRole("button", { name: "About FreeCell" })).toBeVisible()
})

test("draws the two segments as one control, the name taking the width", async ({ page }) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)
  await enableGameInfo(page)

  const row = page.locator(".menu-game-row").first()
  const box = await row.boundingBox()
  const name = await row.locator(".menu-row").boundingBox()
  const info = await row.locator(".menu-game-row__info").boundingBox()

  // Side by side, not stacked, and with no gap between them: the two segments meet
  // exactly, which is what makes the seam a divider rather than a crack.
  expect(Math.round(name.y)).toBe(Math.round(info.y))
  expect(Math.round(name.x + name.width)).toBe(Math.round(info.x))
  expect(Math.round(info.x + info.width)).toBe(Math.round(box.x + box.width))

  // The name takes what's left; the "i" is a fixed tab on the end and stays tappable.
  expect(name.width).toBeGreaterThan(info.width * 2)
  expect(info.width).toBeGreaterThan(40)
  expect(Math.round(info.height)).toBe(Math.round(name.height))
})

test("opens the game's info screen from the i, and comes back to the menu", async ({ page }) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)
  await enableGameInfo(page)

  await page.getByRole("button", { name: "About Simple Simon" }).click()

  // The game names the screen, and the numbers are Simple Simon's — the game the "i"
  // belonged to, which is not the game on the table behind the menu.
  await expect(page.locator(".menu-title")).toHaveText("Simple Simon")
  await expect(page.locator(".game-info__numbers")).toHaveText("10 cascades · 52 cards")
  await expect(page.locator(".game-info__link")).toHaveAttribute(
    "href",
    "https://en.wikipedia.org/wiki/Simple_Simon_(solitaire)",
  )

  // Back to the games list, with FreeCell still on the table: reading about a game is
  // not choosing it.
  await page.getByRole("button", { name: "Back to menu" }).click()
  await expect(page.getByRole("button", { name: "About Simple Simon" })).toBeVisible()
  await expect(page.locator('[aria-label="this game"] .menu-section__heading')).toHaveText(
    "FreeCell #24680",
  )
})

test("leaves the info screen behind when the menu closes", async ({ page }) => {
  // A menu reopened is a menu as it first opens — the same rule Settings and Debug
  // follow, and the one that keeps a screen from lingering into the next open.
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)
  await enableGameInfo(page)

  await page.getByRole("button", { name: "About FreeCell" }).click()
  await expect(page.locator(".game-info__numbers")).toBeVisible()

  await page.getByRole("button", { name: "Close menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await openMenu(page)
  await expect(page.locator(".game-info__numbers")).toHaveCount(0)
  await expect(page.locator(".menu-title")).toHaveText("Pip")
})
