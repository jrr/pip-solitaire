// The win overlay's Share button, end to end (#264).
//
// What the feature promises is a *boast that's also an invitation*: when you win,
// the button hands over a message naming the deal you beat and a link that deals
// that same board to whoever reads it. The unit tests pin each half — the message's
// wording (`ShareLink_test`), and the board offering the button only when there's a
// deal to name (`TableScene_test`) — but the two only meet in a real browser, which
// is also the only place with a clipboard for the link to land on.
//
// Getting to a *won* board with a deal number behind it is the awkward part, and
// worth spelling out, because it's the one path that exists:
//
//   - `?state=almost-won` (what `win.spec.mjs` uses) is a posed position, so the app
//     deliberately reports no deal for it and the button is correctly absent.
//   - `?seed=N` names a deal, but nothing saves on a URL-addressed open, so dropping
//     a debug state onto that board loses the number.
//   - A *plain* open deals a real board and saves its number beside the game. From
//     there a debug state can pose the position without the number going anywhere —
//     `SavedGame.loadSeed` still answers for the deal that was dealt here.
//
// So this opens plainly, notes the deal it got, jumps the board to one move from
// victory, and plays that move. Everything after the jump is the ordinary win.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({
  viewport: { width: 800, height: 1000 },
  // Headless Chromium has no OS share sheet, so `ShareLink.deliver` falls through to
  // the clipboard — the path under test, and reading it back needs the grant.
  permissions: ["clipboard-read", "clipboard-write"],
})

// Walk the menu down to the Debug screen and drop the board into a named position,
// the in-app twin of `?state=` (see `DebugStates`). The "states" group opens
// collapsed, so it has to be disclosed before its rows can be clicked.
async function loadDebugState(page, label) {
  await page.getByRole("button", { name: "Open menu" }).click()
  await page.getByRole("button", { name: "Settings" }).click()
  await page.getByRole("button", { name: "Debug" }).first().click()
  await page.locator("summary", { hasText: "states" }).click()
  await page.getByRole("button", { name: label }).click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
}

// Play the single winning move: the pending King rests alone in the first free cell
// (drop zone 0) and its foundation is the last zone (4 cells, then 4 foundations,
// Clubs last). The same drag `win.spec.mjs` makes, by mouse.
async function playTheWinningMove(page) {
  const cell = page.locator(".drop-zone").nth(0)
  const foundation = page.locator(".drop-zone").nth(7)
  await settleBoard(page)
  await expect(foundation).toBeVisible()

  const cellBox = await cell.boundingBox()
  const foundationBox = await foundation.boundingBox()
  const from = { x: cellBox.x + cellBox.width / 2, y: cellBox.y + cellBox.height / 2 }
  const to = {
    x: foundationBox.x + foundationBox.width / 2,
    y: foundationBox.y + foundationBox.height / 2,
  }

  await page.mouse.move(from.x, from.y)
  await page.mouse.down()
  for (let i = 1; i <= 6; i++) {
    await page.mouse.move(from.x + ((to.x - from.x) * i) / 6, from.y + ((to.y - from.y) * i) / 6)
  }
  await page.mouse.up()
}

const shareButton = (page) => page.locator(".win-panel__button--share")
const shareStatus = (page) => page.locator(".win-panel__status")

test("a won game shares the deal it was played from", async ({ page }) => {
  // A plain open: a random deal, whose number the app stores beside the saved game.
  await page.goto("/?animate=off")
  await settleBoard(page)
  const seed = await page.evaluate(() => localStorage.getItem("pip.savedDeal.freecell"))
  expect(seed).toMatch(/^\d+$/)

  await loadDebugState(page, "Almost won")
  await playTheWinningMove(page)
  await expect(page.locator(".win-overlay")).toHaveCount(1)

  // The status line is present but empty before the press, holding its height so the
  // confirmation lands without pushing the buttons around — the same reserved slot
  // the menu's share line uses.
  await expect(shareStatus(page)).toHaveText("")
  const before = await shareStatus(page).boundingBox()

  await shareButton(page).click()
  await expect(shareStatus(page)).toHaveText("Link copied to clipboard.")
  expect((await shareStatus(page).boundingBox()).height).toBe(before.height)

  const shared = await page.evaluate(() => navigator.clipboard.readText())

  // The message: the suits that make it recognisable in a chat, the deal that was
  // beaten, and the length of the winning line — one move, since the jump to the
  // posed position starts a fresh history.
  expect(shared).toContain("♠️♥️♦️♣️ Pip FreeCell #" + seed)
  expect(shared).toContain("Solved in 1 move")

  // …and the link. It has to be the *deal*, not the position: a link to the board as
  // it stands would hand the recipient a solved game, which is the one thing this
  // share must never do.
  const url = new URL(shared.slice(shared.indexOf("http")))
  expect(url.searchParams.get("seed")).toBe(seed)
  expect(url.hash).toBe("")

  // The round trip, as the recipient makes it: the link opens that deal, unplayed.
  await page.goto(url.toString())
  await settleBoard(page)
  await expect(page.locator(".win-overlay")).toHaveCount(0)
  await expect(page.locator(".stacking-card")).toHaveCount(52)
})

test("a posed board offers no share, having no deal to name", async ({ page }) => {
  // `?state=almost-won` is a position, not a deal — the app has no number for it, so
  // the win overlay is New Game alone rather than a button that would send someone to
  // a board nobody is looking at. (This is the case worth revisiting: the position is
  // real, it just doesn't carry where it came from.)
  await page.goto("/?scene=freecell&state=almost-won&animate=off")
  await playTheWinningMove(page)

  await expect(page.locator(".win-overlay")).toHaveCount(1)
  await expect(shareButton(page)).toHaveCount(0)
  // The New Game button is still there, and still the way out.
  await page.locator(".win-panel__button").click()
  await expect(page.locator(".win-overlay")).toHaveCount(0)
})
