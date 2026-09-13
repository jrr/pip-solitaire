// The pack segment on the Games list's Spiderette row, from the tap to the board.
//
// A *join*, like `more-games.spec.mjs`: `Game` gathers the three packs into a family,
// `Main` draws one row for them and decides what a tap on the segment does, `MenuGameRow`
// puts the segment beside the name, and `Preferences` remembers the choice. Each half is
// unit-tested; what none of them can see is the chain — that the row a player taps mounts
// the pack the segment was showing, that the menu is still there to tap again, and that
// the choice survives a launch.
//
// It also carries one *measured* claim, invisible when it breaks: the segment keeps its
// width as the pack cycles. A segment sized to its contents would shove the name button
// sideways between one tap and the next, and every screenshot of it would look right.

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

// The Spiderettes are still behind More Games, so every walk here starts by turning it
// on the way a tester would: into Settings, ten taps on the title for the hidden rows
// (`HiddenOptions`), the switch, then back to the games list.
const showTheGames = async (page) => {
  await openSettings(page)
  for (let i = 0; i < 10; i++) {
    await page.locator(".menu-title").click()
  }
  const moreGames = page.getByRole("switch", { name: /^More Games/ })
  await expect(moreGames).toBeVisible()
  await moreGames.click()
  await expect(moreGames).toHaveAttribute("aria-checked", "true")
  await page.getByRole("button", { name: "Back to menu" }).click()
}

// The row and its two halves. The pack is addressed by its accessible name, which is
// what a player's screen reader has and what changes as the pack does.
const gameNames = (page) =>
  page.locator("nav[aria-label='Games'] .menu-row:not(.menu-game-row__pack)")
const spiderette = (page) =>
  page.locator("nav[aria-label='Games']").getByRole("button", { name: "Spiderette", exact: true })
const pack = (page) => page.locator(".menu-game-row__pack")

// What the "this game" heading says, which is the only place the *variant's* own name
// appears: "Spiderette · 4 suits". It is how a test tells which of the three packs is on
// the table without reading the cards.
const onTheTable = (page) => page.locator('[aria-label="this game"] .menu-section__heading')

test("offers the three packs as one row, and cycles it in place", async ({ page }) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)
  await showTheGames(page)

  // One Spiderette among the games, not three, and it opens wearing the pack the game
  // is usually meant by.
  await expect(gameNames(page)).toHaveText([
    "FreeCell",
    "Mini FreeCell",
    "Micro FreeCell",
    "Simple Simon",
    "Spiderette",
  ])
  await expect(pack(page)).toHaveCount(1)
  await expect(pack(page)).toHaveAttribute("aria-label", "Spiderette pack: 2 suits")
  // Pips and multiplier are separate spans held apart by the segment's own flex gap, so
  // the text runs together and the *space* a player sees is the layout's.
  await expect(pack(page)).toHaveText("♠♥×2")

  // A tap changes the pack and nothing else: the menu is still open, the row is still
  // where it was, and FreeCell is still the game on the table.
  const before = await pack(page).boundingBox()
  await pack(page).click()
  await expect(pack(page)).toHaveAttribute("aria-label", "Spiderette pack: 4 suits")
  await expect(pack(page)).toHaveText("♠♥♦♣")
  await expect(page.locator("#menu-overlay")).toBeVisible()
  await expect(onTheTable(page)).toContainText("FreeCell")

  // …and it wraps, so every pack is reachable from every other.
  await pack(page).click()
  await expect(pack(page)).toHaveText("♠×4")
  await pack(page).click()
  await expect(pack(page)).toHaveText("♠♥×2")

  // The measured claim: the widest pack didn't resize the control the thumb is on.
  const after = await pack(page).boundingBox()
  expect(after.width).toBe(before.width)
  expect(after.x).toBe(before.x)
})

test("swaps the board under the menu when the game it names is the one being played", async ({
  page,
}) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)
  await showTheGames(page)

  // Open Spiderette from its row: the pack the segment was showing is the board that
  // comes up — seven cascades over a stock — and the menu gets out of the way.
  await spiderette(page).click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await settleBoard(page)
  await expect(page.locator(".drop-zone__slot--stock")).toHaveCount(1)

  await openMenu(page)
  await expect(onTheTable(page)).toContainText("Spiderette · 2 suits")
  await expect(spiderette(page)).toHaveAttribute("aria-current", "true")

  // Now the pack is a board change: the four-suit board replaces the two-suit one, and
  // the menu stays up so the segment can be tapped again.
  await pack(page).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
  await expect(onTheTable(page)).toContainText("Spiderette · 4 suits")
  await expect(spiderette(page)).toHaveAttribute("aria-current", "true")
  await expect(pack(page)).toHaveText("♠♥♦♣")

  // The board behind it really did change: still a Spiderette, and a different deal of
  // a different pack (each variant keeps its own saved game).
  await page.getByRole("button", { name: "Close menu" }).click()
  await settleBoard(page)
  await expect(page.locator(".drop-zone__slot--stock")).toHaveCount(1)
})

test("remembers the pack across a launch, and opens that one from the row", async ({ page }) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)
  await showTheGames(page)

  // A pack chosen on a game that isn't on the table is remembered, not played: FreeCell
  // is still up, and nothing has mounted.
  await pack(page).click()
  await expect(pack(page)).toHaveText("♠♥♦♣")
  await expect(onTheTable(page)).toContainText("FreeCell")

  // The choice is persisted like every other preference, so a relaunch finds the row
  // wearing it — the flag being persisted too, the row is still there to look at.
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)
  await expect(pack(page)).toHaveText("♠♥♦♣")

  // …and the name beside it opens *that* pack, which is the whole promise of showing it.
  await spiderette(page).click()
  await settleBoard(page)
  await openMenu(page)
  await expect(onTheTable(page)).toContainText("Spiderette · 4 suits")
})
