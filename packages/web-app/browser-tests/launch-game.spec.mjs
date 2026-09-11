// Which game a launch opens on, across a reload.
//
// Choosing a game from the menu is a choice that survives closing the tab: the id is
// stored (`SavedGame.saveLastGame`) as each game mounts, and a bare launch resolves it
// back (`Main`'s `launchGame`). The per-game saves do the rest, so coming back to a
// remembered game comes back to the board that was on it.
//
// Two rules keep that from answering things it shouldn't, and both are pinned here
// because both fail *silently* — the app still opens a playable board, just not the one
// asked for. **A URL that names a board wins**, which matters most for the bare
// `?seed=` a FreeCell share link is: `ShareLink.urlForDeal` omits `?game=` for the
// default game, so a remembered game answering that link would open a different board
// under it. And **only a game the menu offers is ever remembered**, so neither a demo
// scene nor a debug-menu board becomes what the app opens on.
//
// Browser-only, and reload-only: nothing below can be assembled in jsdom, because the
// whole subject is what a second page load does with what the first one stored.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"
import { menuSeed } from "./lib/menu.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

// The two boards, told apart by their shape: FreeCell lays out sixteen zones with free
// cells among them, Simple Simon fourteen and none.
const FREECELL_ZONES = 16
const SIMPLE_SIMON_ZONES = 14

const zones = (page) => page.locator(".drop-zone")

const openMenu = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

const gameRow = (page, name) =>
  page.locator("nav[aria-label='Games']").getByRole("button", { name })

// The "this game" heading, which names the game the board belongs to.
const menuGameName = (page) => page.locator('[aria-label="this game"] .menu-section__heading')

// Choose a game the way a player does, and wait for its board.
const chooseGame = async (page, name) => {
  await openMenu(page)
  await gameRow(page, name).click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await settleBoard(page)
}

// The deal number the menu names, read as text so it can be compared across a reload.
const seedText = async (page) => {
  await openMenu(page)
  const seed = await menuSeed(page).textContent()
  await page.getByRole("button", { name: "Close menu" }).click()
  return seed
}

test("a bare launch opens the game last chosen, on the board it was on", async ({ page }) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await expect(zones(page)).toHaveCount(FREECELL_ZONES)

  await chooseGame(page, "Simple Simon")
  await expect(zones(page)).toHaveCount(SIMPLE_SIMON_ZONES)
  // Its deal, noted before the reload. A Simple Simon opened fresh takes a *random*
  // six-digit seed, so the same number coming back is the saved board coming back
  // rather than a new one that merely happens to be the same game.
  const dealt = await seedText(page)

  await page.goto("/?animate=off")
  await settleBoard(page)
  await expect(zones(page)).toHaveCount(SIMPLE_SIMON_ZONES)
  expect(await seedText(page)).toBe(dealt)

  await openMenu(page)
  await expect(menuGameName(page)).toContainText("Simple Simon")
  await expect(gameRow(page, "Simple Simon")).toHaveAttribute("aria-current", "true")
})

// The rule the whole feature is fenced by. A FreeCell deal link carries no `?game=` at
// all, so if a remembered game could answer a bare `?seed=` the link would quietly open
// someone else's board.
test("a shared deal link opens its own board, whatever game is remembered", async ({ page }) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await chooseGame(page, "Simple Simon")
  await expect(zones(page)).toHaveCount(SIMPLE_SIMON_ZONES)

  // The link a FreeCell share hands out: a deal number, and nothing naming the game.
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await expect(zones(page)).toHaveCount(FREECELL_ZONES)
  await openMenu(page)
  await expect(menuGameName(page)).toContainText("FreeCell")
  await expect(menuSeed(page)).toHaveText("#24680")
})

// What is remembered is the game that was *played*, however it got on the table — a
// link included. So a FreeCell deal opened from someone else's link is where the next
// bare launch opens, the same as if its row had been tapped.
//
// The deliberate half of that is the asymmetry with the test above: the link is still
// answered exactly as addressed, because reading is what the plain-open rule gates.
// Only the launch *after* it moves, and it moves to a game the player really did just
// play. Remembering the menu tap alone would be the other choice, and would need the
// switcher to report why a scene mounted rather than merely that it did.
test("a game reached by a link is remembered like one chosen from the menu", async ({ page }) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await chooseGame(page, "Simple Simon")

  await page.goto("/?game=freecell&seed=24680&animate=off")
  await settleBoard(page)
  await expect(zones(page)).toHaveCount(FREECELL_ZONES)

  await page.goto("/?animate=off")
  await settleBoard(page)
  await expect(zones(page)).toHaveCount(FREECELL_ZONES)
})

// Only a game the menu offers is remembered. A demo owns no board at all, so opening on
// one would be opening on no game — the failure this rules out is a launch into the
// card gallery.
test("a demo scene never becomes the game a launch opens on", async ({ page }) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await chooseGame(page, "Simple Simon")

  await page.goto("/?scene=gallery&animate=off")
  await expect(page.locator(".card-gallery")).toBeVisible()

  await page.goto("/?animate=off")
  await settleBoard(page)
  await expect(page.locator(".card-gallery")).toHaveCount(0)
  await expect(zones(page)).toHaveCount(SIMPLE_SIMON_ZONES)
})

// Nor does a board that only the Debug screen offers: a developer who opens one by URL
// gets it, and gets their own game back the next time they launch without one.
test("a debug-menu game never becomes the game a launch opens on", async ({ page }) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await chooseGame(page, "Simple Simon")

  await page.goto("/?game=micro&animate=off")
  await settleBoard(page)

  await page.goto("/?animate=off")
  await settleBoard(page)
  await expect(zones(page)).toHaveCount(SIMPLE_SIMON_ZONES)
})

// A fresh device has nothing stored, so the default game is what it opens on — the
// behaviour every launch had before anything was remembered.
test("a first launch with nothing stored opens the default game", async ({ page }) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await expect(zones(page)).toHaveCount(FREECELL_ZONES)
  await openMenu(page)
  await expect(menuGameName(page)).toContainText("FreeCell")
})
