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

test("gives the i a target bigger than the mark, without disturbing the row", async ({ page }) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)
  await enableGameInfo(page)

  const row = page.locator(".menu-game-row").first()
  const box = await row.boundingBox()
  const name = await row.locator(".menu-row").boundingBox()
  const info = await row.locator(".menu-game-row__info").boundingBox()
  const badge = await row.locator(".menu-game-row__badge").boundingBox()

  // The pair sits side by side, and the two targets meet exactly rather than
  // overlapping: the "i" must not reach back over the name button's right edge, or
  // the last few pixels of "tap the game" would silently open its info screen
  // instead. This is what `gap: 0` buys, and it only holds while the button carries
  // its own transparent margin.
  expect(Math.round(name.x + name.width)).toBe(Math.round(info.x))
  expect(Math.round(info.x + info.width)).toBe(Math.round(box.x + box.width))
  expect(name.width).toBeGreaterThan(info.width * 2)

  // The target is a 44px square around an 18px circle. Asserting both is the point:
  // a change that sizes the button to fit the mark would look identical and quietly
  // halve what a thumb has to hit.
  expect(Math.round(info.width)).toBe(44)
  expect(Math.round(info.height)).toBe(44)
  expect(Math.round(badge.width)).toBe(18)
  expect(Math.round(badge.height)).toBe(18)

  // …and the row is still the height it would be without an "i" in it. The target is
  // taller than the row it sits in and overhangs into the gaps either side, which is
  // only invisible for as long as it contributes nothing to layout.
  expect(info.height).toBeGreaterThan(name.height)
  expect(Math.round(box.height)).toBe(Math.round(name.height))
})

test("keeps one row's i out of the next row's", async ({ page }) => {
  // The overhang has about a pixel of room in it: the gap between rows is 6px and
  // each target hangs 2.5px into it. Nothing about that is visible — two targets that
  // overlapped would look exactly like two that don't, and the only symptom would be
  // a tap near the boundary opening the wrong game's screen. So it is asserted rather
  // than left to be noticed.
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)
  await enableGameInfo(page)

  const targets = page.locator(".menu-game-row__info")
  const first = await targets.nth(0).boundingBox()
  const second = await targets.nth(1).boundingBox()
  expect(second.y).toBeGreaterThanOrEqual(first.y + first.height)
})

test("holds a game's name on one header row at a narrow width", async ({ page }) => {
  // The header is sized for "Pip", "Settings" and "Debug" — one word apiece, chosen
  // by the app. A game's name is neither, and "Simple Simon" is already wider than
  // the room a 20rem panel leaves between the back button and the ✕. What buys it
  // that room is the back button being a bare chevron, so this is really a test that
  // nobody has put the word back.
  await page.setViewportSize({ width: 360, height: 800 })
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)
  await enableGameInfo(page)
  await page.getByRole("button", { name: "About Simple Simon" }).click()

  const header = await page.locator(".menu-panel__header").boundingBox()
  const title = await page.locator(".menu-title").boundingBox()
  const back = await page.locator(".menu-back").boundingBox()

  // One line of title, and a back button that is still one line of its own: as
  // ordinary flex items the two controls shrink before the title does, so a squeeze
  // shows up on them first.
  await expect(page.locator(".menu-title")).toHaveText("Simple Simon")
  expect(title.height).toBeLessThan(40)
  expect(back.height).toBeLessThan(40)
  expect(Math.round(header.height)).toBe(Math.round(Math.max(title.height, back.height)))
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
