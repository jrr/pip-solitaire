// The menu's scene rows, in a real browser.
//
// The switcher hands the chrome data — the games as a list, the active id as a
// value — and the rows are ordinary `<MenuRow>`s the diff draws. The behaviours
// pinned here are the ones that go wrong *silently*, which is why they're worth a
// browser: `SceneSwitcher_test` pins each rule against fake scenes, but not that
// the row a player actually taps reaches it.
//
// Browser-only for the ordinary reason: every case runs through a real page load, a
// real scene mount and the menu's own navigation, none of which jsdom assembles.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"
import { menuSeed } from "./lib/menu.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

const openMenu = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

// The Games section's rows: the switcher's primary scenes, one per game — the name
// buttons, since a family's row also carries a segment, and every row an "i". A row is
// found by its exact name for the same reason: those two are buttons named after it too.
const gameRows = (page) =>
  page.locator("nav[aria-label='Games'] .menu-row:not(.menu-game-row__variant)")
const gameRow = (page, name) =>
  page.locator("nav[aria-label='Games']").getByRole("button", { name, exact: true })

// The top bar's Undo: enabled exactly when the board on the table has a move behind
// it, which is how a test tells a game in progress from a fresh deal of the same seed.
const undo = (page) => page.getByRole("button", { name: "Undo" })

// The "this game" heading, which names the game on the table in front of its deal
// number. Only this suite switches games from the menu, so the game half of that
// heading can only be read moving here — hence a locator of its own rather than one
// beside `menuSeed` in lib/menu.mjs.
const menuGameName = (page) =>
  page.locator('[aria-label="this game"] .menu-section__heading')

// The debug console, for putting a known game on the table by typing at it — the
// same lines `debug-console.spec.mjs` pins. Deal 24680 opens with the Five of Spades
// on top of its third cascade, so a cell takes it: one move, and a history to keep.
const FIRST_MOVE_24680 = "5S C1"
const consoleInput = (page) => page.locator("#debug-console-input")
const runCommand = async (page, line) => {
  await page.keyboard.type(line)
  await page.keyboard.press("Enter")
}

// Down to the Debug screen, where the debug/demo scenes live in their disclosure.
const openDebugScreen = async (page) => {
  await page.getByRole("button", { name: "Settings" }).click()
  await page.getByRole("button", { name: "Debug" }).click()
}

// The "scenes" disclosure and one of its rows.
const sceneGroup = (page) => page.locator(".scene-menu__group").filter({ hasText: "scenes" })
const sceneRow = (page, name) => sceneGroup(page).getByRole("button", { name })

// …and the disclosures this screen places, by the summary each opens under. A game
// withheld from the main menu has no group of its own to land in (`more-games.spec.mjs`
// walks both states of the flag), so what this names is the whole of what's here.
const groupSummaries = (page) => page.locator(".scene-menu__group > summary")

// Activation tears the live scene down and builds it afresh, so a re-mount throws
// away the game in progress.
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

// The placement rule: ten boards in `Game.all`, three rows. `SceneSwitcher_test` pins
// the grouping rule against fake scenes; what it can't say is where the *real* boards
// land — every released one up top, a family's on its row's segment, and the withheld
// ones on no row at all, under "scenes" least of all.
test("every released game is listed up top, and the withheld ones nowhere at all", async ({
  page,
}) => {
  await page.goto("/?game=micro&animate=off")
  await settleBoard(page)

  await openMenu(page)
  // One row per game in `Game.all`'s order — not one per board: the short decks are
  // FreeCell's segment, the packs Spiderette's.
  await expect(gameRows(page)).toHaveText(["FreeCell", "Simple Simon", "Spiderette"])
  // The board showing is Micro, so FreeCell's row is current with Micro on its segment.
  await expect(gameRow(page, "FreeCell")).toHaveAttribute("aria-current", "true")
  await expect(page.getByRole("button", { name: "FreeCell size: Micro" })).toBeVisible()
  await expect(gameRow(page, "Simple Simon")).not.toHaveAttribute("aria-current", "true")

  await openDebugScreen(page)
  // Two disclosures, neither of them a home for a game: the withheld Spiders are on no
  // row here, and the short decks aren't filed as demos either.
  await expect(groupSummaries(page)).toHaveText(["scenes", "states"])
  await sceneGroup(page).locator("summary").click()
  await expect(sceneGroup(page).getByRole("button", { name: /Spider/ })).toHaveCount(0)
  await expect(sceneGroup(page).getByRole("button", { name: "Micro FreeCell" })).toHaveCount(0)
})

// The whole highlight path end to end: an id the switcher resolved before the
// chrome's loop existed, seeded into the model, rendered through the diff on two
// different screens.
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

// Two games with top-level rows, and the walk between them. Each row mounts its game
// and takes the highlight; the game left behind is *kept*, not discarded — a plain
// open saves its board per game, and the way back restores it — and a tap on the row
// for the game showing changes nothing at all.
test("the games rows walk between FreeCell and Simple Simon, keeping each game", async ({
  page,
}) => {
  // A plain open, with no `?seed=`: the one kind of open that saves the game, which
  // is what makes the way back a resume rather than a re-deal.
  await page.goto("/?animate=off")
  await settleBoard(page)

  // Put a *known* FreeCell game in progress on the table: a named deal, one move in.
  await page.keyboard.press("Backquote")
  await expect(consoleInput(page)).toBeFocused()
  await runCommand(page, "deal 24680")
  await settleBoard(page)
  await runCommand(page, `move ${FIRST_MOVE_24680}`)
  await settleBoard(page)
  await page.keyboard.press("Escape")
  await expect(undo(page)).toBeEnabled()

  await openMenu(page)
  await expect(gameRows(page)).toHaveText(["FreeCell", "Simple Simon", "Spiderette"])
  await expect(gameRow(page, "FreeCell")).toHaveAttribute("aria-current", "true")
  await expect(gameRow(page, "Simple Simon")).not.toHaveAttribute("aria-current", "true")
  await expect(menuSeed(page)).toHaveText("#24680")
  // The heading names the game its two buttons act on, which is a live reading now
  // that the menu can reach a second one.
  await expect(menuGameName(page)).toContainText("FreeCell")

  // Over to Simple Simon: the menu closes on the switch, and the board that comes up
  // is its — ten cascades and four foundations, no cells — freshly dealt, with no
  // history of FreeCell's behind it.
  await gameRow(page, "Simple Simon").click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await settleBoard(page)
  await expect(page.locator(".drop-zone")).toHaveCount(14)
  await expect(page.locator(".drop-zone__slot--cell")).toHaveCount(0)
  await expect(undo(page)).toBeDisabled()

  await openMenu(page)
  await expect(gameRow(page, "Simple Simon")).toHaveAttribute("aria-current", "true")
  await expect(gameRow(page, "FreeCell")).not.toHaveAttribute("aria-current", "true")
  // Its own deal, not FreeCell's carried across — and a heading that has followed it,
  // so Restart and Share visibly act on the board in front of you.
  await expect(menuSeed(page)).not.toHaveText("#24680")
  await expect(menuGameName(page)).toContainText("Simple Simon")

  // Tapping the game already showing closes the menu and leaves the board alone.
  await gameRow(page, "Simple Simon").click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await expect(page.locator(".drop-zone")).toHaveCount(14)

  // And back: FreeCell's board, with the move still made and the deal still named.
  await openMenu(page)
  await gameRow(page, "FreeCell").click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await settleBoard(page)
  await expect(page.locator(".drop-zone")).toHaveCount(16)
  await expect(undo(page)).toBeEnabled()

  await openMenu(page)
  await expect(gameRow(page, "FreeCell")).toHaveAttribute("aria-current", "true")
  await expect(gameRow(page, "Simple Simon")).not.toHaveAttribute("aria-current", "true")
  await expect(menuSeed(page)).toHaveText("#24680")
  await expect(menuGameName(page)).toContainText("FreeCell")
})

// The same walk, from a `?seed=` link. An addressed open deliberately doesn't resume
// what was saved and doesn't write over it — but the moment the player plays the board
// the link opened, it is their game, and a walk away from it has to come back to it
// rather than to the link's opening position all over again.
test("a link's board, once played, is what the way back returns to", async ({ page }) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)

  // One move: the whole difference between a board a link addressed and a game in
  // progress that happens to have started from one.
  await page.keyboard.press("Backquote")
  await expect(consoleInput(page)).toBeFocused()
  await runCommand(page, `move ${FIRST_MOVE_24680}`)
  await settleBoard(page)
  await page.keyboard.press("Escape")
  await expect(undo(page)).toBeEnabled()

  await openMenu(page)
  await gameRow(page, "Simple Simon").click()
  await settleBoard(page)
  await expect(page.locator(".drop-zone")).toHaveCount(14)

  await openMenu(page)
  await gameRow(page, "FreeCell").click()
  await settleBoard(page)
  // The deal the link named, with the move still on it — not dealt afresh, which on a
  // pinned seed is the failure that looks like success: the same cards, no history.
  await expect(page.locator(".drop-zone")).toHaveCount(16)
  await expect(undo(page)).toBeEnabled()
  await openMenu(page)
  await expect(menuSeed(page)).toHaveText("#24680")
})

// Dealing from a link's board is the other way of making it yours, and the one where
// coming back to the link's own deal would be plainly wrong: the player asked for a
// different board and was given one.
test("a New Deal on a link's board outlives the walk away from it", async ({ page }) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)

  await openMenu(page)
  await page.getByRole("button", { name: "New Deal" }).click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await settleBoard(page)

  await openMenu(page)
  const dealt = await menuSeed(page).textContent()
  expect(dealt).not.toBe("#24680")

  await gameRow(page, "Simple Simon").click()
  await settleBoard(page)
  await openMenu(page)
  await gameRow(page, "FreeCell").click()
  await settleBoard(page)

  await openMenu(page)
  await expect(menuSeed(page)).toHaveText(dealt)
})

// `?game=simplesimon` lands on a row that is already up top, so the menu opens with it
// marked and the demos disclosure left shut — there is nothing down there to unfold for
// a game.
test("a ?game= link onto Simple Simon opens with its row marked", async ({ page }) => {
  await page.goto("/?game=simplesimon&animate=off")
  await settleBoard(page)
  await expect(page.locator(".drop-zone")).toHaveCount(14)

  await openMenu(page)
  await expect(gameRow(page, "Simple Simon")).toHaveAttribute("aria-current", "true")
  await expect(gameRow(page, "FreeCell")).not.toHaveAttribute("aria-current", "true")

  await openDebugScreen(page)
  await expect(sceneGroup(page)).not.toHaveAttribute("open", "")
})
