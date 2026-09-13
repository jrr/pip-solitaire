// The game info feature, from the switch that turns it on to the screen it opens.
//
// Everything here is a *join* between parts that unit tests cover one at a time: the
// hidden switch persists a flag (`MenuSettingsScreen`), the flag decides whether a
// game's row is handed an `onInfo` (`Main`), the row draws the "i" from that
// (`MenuGameRow`), and the tap swaps the pane to a fourth screen (`Menu`). No single one
// of those can see the chain, and the chain is what a player has.
//
// The row is also a set of *measured* claims, and a stylesheet is only evaluated by a
// browser. Three of them are invisible when they break, which is why they are here at
// all: the "i" is a 44px target around an 18px mark, so a change that sizes the button
// to fit the circle would look identical and halve what a thumb has to hit; the target
// abuts the name button exactly, so it steals none of "tap the game"; and it stays
// clear of the next row's, so no tap opens the wrong game's screen. The fourth is the
// circle sitting on the same edge the panel's other controls end on (MenuGameRow.css).

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
  expect(name.width).toBeGreaterThan(info.width * 2)

  // It is the *circle* that lines up with the panel's content edge, where Enter Seed
  // and the game buttons end — not the box around it, which deliberately overhangs
  // into the padding to put it there. Asserting the target's edge instead, the
  // obvious thing to reach for, would pin the bug this fixes.
  const seed = await page.getByRole("button", { name: /Enter Seed/i }).boundingBox()
  expect(Math.round(badge.x + badge.width)).toBe(Math.round(box.x + box.width))
  expect(Math.round(badge.x + badge.width)).toBe(Math.round(seed.x + seed.width))
  expect(info.x + info.width).toBeGreaterThan(box.x + box.width)

  // The target is a 44px square around an 18px circle. Asserting both is the point:
  // a change that sizes the button to fit the mark would look identical and quietly
  // halve what a thumb has to hit.
  expect(Math.round(info.width)).toBe(44)
  expect(Math.round(info.height)).toBe(44)
  expect(Math.round(badge.width)).toBe(18)
  expect(Math.round(badge.height)).toBe(18)

  // The name button meets the same floor, and the target is level with it rather
  // than standing out of the row — which is what keeps each row's "i" inside its own
  // row (see the next test).
  expect(Math.round(name.height)).toBe(44)
  expect(Math.round(box.height)).toBe(44)
})

test("keeps one row's i out of the next row's", async ({ page }) => {
  // Neither target may reach into the 6px between rows: two that overlapped would
  // look exactly like two that don't, since neither paints anything, and the only
  // symptom would be a tap near the boundary opening the wrong game's screen. The
  // row height is what holds this, so it is asserted here rather than left to be
  // noticed the once it breaks.
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
  const close = await page.locator(".menu-close").boundingBox()

  // The two flank the title, so any difference between them reads as the title
  // sitting off centre rather than as the buttons being different — which is how
  // 32×30 beside 35×26 went unnoticed. Sized, not padded: the glyphs are different
  // widths and any shared padding gives two different boxes.
  expect(Math.round(back.width)).toBe(Math.round(close.width))
  expect(Math.round(back.height)).toBe(Math.round(close.height))
  expect(Math.round(back.width)).toBe(Math.round(back.height))

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

  // Centred, with the link under it. The panel is left-aligned everywhere else, so
  // this is the sort of exception a later tidy-up "corrects" back — and a ranged-left
  // line under a centred button is what it looked like before.
  //
  // Measured over the text itself, not the element: the <p> is a full-width block, so
  // its own box is centred on the link whether the text inside it is or not.
  const offset = await page.evaluate(() => {
    const p = document.querySelector(".game-info__numbers")
    const range = document.createRange()
    range.selectNodeContents(p)
    const ink = range.getBoundingClientRect()
    const box = p.getBoundingClientRect()
    return {
      left: Math.round(ink.left - box.left),
      right: Math.round(box.right - ink.right),
    }
  })
  expect(Math.abs(offset.left - offset.right)).toBeLessThanOrEqual(1)
  expect(offset.left).toBeGreaterThan(1)
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
