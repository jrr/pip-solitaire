// The Debug screen's "Clear saved data" (`StoredState`), which is the only control in
// the app whose whole subject is the *next* launch: it throws away what the device
// remembers and reopens, so that a developer can see the first-run board — the deal
// that arrives with nothing to resume — without devtools or a fresh browser profile.
//
// Browser-only by construction, three times over. `StoredState_test` pins the sweep
// against an in-memory Storage, and that is the part jsdom can host; what it cannot
// reach is real `localStorage` with the app's own keys in it, a real navigation to act
// on the clear, and a second page load to prove the erasure took. Every check below is
// about what the app does *after* the reload, so there is nowhere else for them to live.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"
import { menuSeed, openSettings } from "./lib/menu.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

// Simple Simon lays out fourteen zones and FreeCell sixteen, which is how a test tells
// which board came back without reading a word of chrome.
const SIMPLE_SIMON_ZONES = 14

const openMenu = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

// The deal number the menu names, read as text so it survives a reload to be compared
// against. The menu is left open or shut by the caller's next step.
const seedText = async (page) => {
  await openMenu(page)
  const seed = await menuSeed(page).textContent()
  await page.getByRole("button", { name: "Close menu" }).click()
  return seed
}

// Every key the app has written, as the browser actually holds them — the check the
// unit test can only make against a stub.
const appKeys = (page) =>
  page.evaluate(() => Object.keys(window.localStorage).filter((k) => k.startsWith("pip.")))

// Press the row, from the Settings screen the caller has already walked to. The press
// navigates, so what's waited on afterwards is the board that comes back rather than
// anything on the menu — the menu it was pressed from no longer exists.
const clearFromSettings = async (page) => {
  await page.getByRole("button", { name: "Debug" }).first().click()
  await page.getByRole("button", { name: /^Clear saved data/ }).click()
  await settleBoard(page)
}

// The whole walk, for a test that isn't already somewhere in the menu.
const clearSavedData = async (page) => {
  await openMenu(page)
  await openSettings(page)
  await clearFromSettings(page)
}

test("the board that comes back is a new deal, not the one that was saved", async ({ page }) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  const dealt = await seedText(page)

  // The save is real first: an ordinary reload comes back to the very same board, which
  // is what makes the difference after the clear mean something.
  await page.goto("/?animate=off")
  await settleBoard(page)
  expect(await seedText(page)).toBe(dealt)

  await clearSavedData(page)
  expect(await seedText(page)).not.toBe(dealt)
})

test("it takes the settings with it, not only the saved games", async ({ page }) => {
  await page.goto("/?animate=off")
  await settleBoard(page)

  // Auto-collect ships on and writes nothing until it is flipped, so turning it off is
  // both a preference to erase and the proof that one was stored at all.
  await openMenu(page)
  await openSettings(page)
  await page.getByRole("switch", { name: /^Auto-collect/ }).click()
  expect(await page.evaluate(() => window.localStorage.getItem("pip.autoCollect"))).toBe("false")

  // Already on Settings, which is one step above the row — the walk is the one above.
  await clearFromSettings(page)
  expect(await page.evaluate(() => window.localStorage.getItem("pip.autoCollect"))).toBe(null)
  await openMenu(page)
  await openSettings(page)
  await expect(page.getByRole("switch", { name: /^Auto-collect/ })).toHaveAttribute(
    "aria-checked",
    "true",
  )
})

// Empty storage is *not* the claim, and a test that made it would be testing the wrong
// thing: the launch that follows deals a board and saves it before anyone can look, so
// the game that was reopened has keys again within the same breath. What has to be gone
// is everything the previous session left that this launch doesn't rewrite — and every
// game keeps its own board (`pip.savedGame.<id>`), so a second game's save is the key
// that shows a sweep which only reached the game in front of it.
test("the sweep reaches past the game it reopens, to every other one", async ({ page }) => {
  await page.goto("/?game=simplesimon&animate=off")
  await settleBoard(page)
  expect(await appKeys(page)).toContain("pip.savedGame.simplesimon")

  await page.goto("/?game=freecell&animate=off")
  await settleBoard(page)

  await clearSavedData(page)
  const left = await appKeys(page)
  expect(left).not.toContain("pip.savedGame.simplesimon")
  expect(left).not.toContain("pip.savedDeal.simplesimon")
  // …and the board in front of us is a launch, not a survivor: its own save is the one
  // just written by the deal on screen.
  expect(left).toContain("pip.savedGame.freecell")
})

// The address decides which board a first launch is *of*, so it has to survive — seeing
// a game deal for the first time is most of what the control is for, and it is no use if
// it can only ever show the default game.
test("it reopens the game the address names, dealt afresh", async ({ page }) => {
  await page.goto("/?game=simplesimon&animate=off")
  await settleBoard(page)
  await expect(page.locator(".drop-zone")).toHaveCount(SIMPLE_SIMON_ZONES)
  const dealt = await seedText(page)

  await clearSavedData(page)
  await expect(page.locator(".drop-zone")).toHaveCount(SIMPLE_SIMON_ZONES)
  expect(await seedText(page)).not.toBe(dealt)
})

// The one part of the address that does *not* survive. `#g=` carries a whole shared
// game, which would land on the fresh board and take storage over again — a clear that
// undid itself in the same breath, and the confusing kind, since the board it left up
// would be the one that was just erased.
test("the shared-game fragment is dropped, so the clear can't undo itself", async ({ page }) => {
  await page.goto("/?animate=off#g=notarealblob")
  await settleBoard(page)

  await clearSavedData(page)
  expect(page.url()).not.toContain("#")
})
