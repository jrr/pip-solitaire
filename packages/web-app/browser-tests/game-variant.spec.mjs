// The variant segment on the Games list — the FreeCell sizes and the Spiderette packs —
// from the tap to the board.
//
// A *join*, like `more-games.spec.mjs`: `Game` gathers the boards into families, `Main`
// draws one row for each and decides what a tap on the segment does, `MenuGameRow` puts
// the segment beside the name, and `Preferences` remembers the choice. Each half is
// unit-tested; what none of them can see is the chain — that the row a player taps mounts
// the board the segment was showing, that the menu is still there to tap again, and that
// the choice survives a launch.
//
// It also carries the *measured* claims about the segment, each invisible when it breaks
// and none of them answerable in jsdom: it is one size for every mark on every row, so
// nothing moves under the thumb between taps and the list doesn't read as ragged; it
// stands exactly as tall as the name beside it, the pips being a size up from the row's
// type; and the pips are drawn in the app's own suit face rather than in whatever the
// platform keeps at U+2660 — which on a phone is the emoji face, and would be red hearts
// in a monochrome menu. That last is the mark's own (`MenuVariantMark`), and so is taken
// here for the picker on the info screen too, which wears the same one.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"
import { setBetaFeatures } from "./lib/menu.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

const openMenu = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

// Both families have boards that aren't released yet, and a family is collapsed only over
// the boards the list is offering — so every walk here starts by turning **Beta features**
// on (`lib/menu.mjs`).
const showTheGames = (page) => setBetaFeatures(page, true)

// The rows' names, and each family's segment. The segments are addressed by their
// accessible names — what a player's screen reader has, and what changes as the mark does
// — which is also what keeps the two families' apart.
const gameNames = (page) =>
  page.locator("nav[aria-label='Games'] .menu-row:not(.menu-game-row__variant)")
const gameRow = (page, name) =>
  page.locator("nav[aria-label='Games']").getByRole("button", { name, exact: true })
const packs = (page) => page.getByRole("button", { name: /^Spiderette pack:/ })
const sizes = (page) => page.getByRole("button", { name: /^FreeCell size:/ })

// What the "this game" heading says, which is the only place a variant's own name appears:
// "Spiderette · 4 suits", "Mini FreeCell". It is how a test tells which board is on the
// table without reading the cards.
const onTheTable = (page) => page.locator('[aria-label="this game"] .menu-section__heading')

test("offers a family as one row, and cycles it in place", async ({ page }) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)
  await showTheGames(page)

  // Three rows for seven boards: the families are one row each, with the rest of their
  // boards on the segment rather than in a row of their own.
  await expect(gameNames(page)).toHaveText(["FreeCell", "Simple Simon", "Spiderette"])
  await expect(packs(page)).toHaveCount(1)
  await expect(packs(page)).toHaveAttribute("aria-label", "Spiderette pack: 2 suits")
  // Pips and multiplier are separate spans held apart by the mark's own margin, so the
  // text runs together and the *space* a player sees is the layout's.
  await expect(packs(page)).toHaveText("♠♥×2")

  // A tap changes the pack and nothing else: the menu is still open, the row is still
  // where it was, and FreeCell is still the game on the table.
  const boxes = [await packs(page).boundingBox()]
  await packs(page).click()
  await expect(packs(page)).toHaveAttribute("aria-label", "Spiderette pack: 4 suits")
  await expect(packs(page)).toHaveText("♠♥♦♣")
  await expect(page.locator("#menu-overlay")).toBeVisible()
  await expect(onTheTable(page)).toContainText("FreeCell")

  // …and it wraps, so every pack is reachable from every other.
  boxes.push(await packs(page).boundingBox())
  await packs(page).click()
  await expect(packs(page)).toHaveText("♠×4")
  boxes.push(await packs(page).boundingBox())
  await packs(page).click()
  await expect(packs(page)).toHaveText("♠♥×2")

  // One box for all three packs — the widest mark neither widened the control nor moved
  // it, so the name button beside it is the same length throughout…
  for (const box of boxes) {
    expect(box).toEqual(boxes[0])
  }
  // …and the other family's segment is that same box one row up, so the names all end on
  // one edge rather than wherever their own mark happens to leave them.
  const size = await sizes(page).boundingBox()
  expect(size.width).toBe(boxes[0].width)
  expect(size.x).toBe(boxes[0].x)
  // …and each is level with the name beside it, which is the segment taking the row's
  // height rather than the pips' (`MenuGameRow.css`).
  const name = await gameNames(page).last().boundingBox()
  expect(boxes[0].height).toBe(name.height)
  expect(boxes[0].y).toBe(name.y)
})

test("draws the pips in the app's own suit face, not the platform's", async ({ page }) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)
  await showTheGames(page)

  const suits = page.locator(".menu-variant-mark__suits")
  await expect(suits).toHaveCSS("font-family", /^"Pip Suits"/)
  // …and the face is really there to be used: the same subset the cards are drawn with
  // (`styles/fonts.css`), which carries the four pips and nothing else.
  expect(await page.evaluate(() => document.fonts.check('16px "Pip Suits"', "♠♥♦♣"))).toBe(true)
})

test("gives FreeCell a size only once the short decks are listed", async ({ page }) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)

  // Off: the released list, and no segment anywhere. A family is collapsed over the
  // boards the menu is *offering*, so FreeCell is one board here and the row is the plain
  // one it has always been — Mini and Micro no more reachable than before.
  await expect(gameNames(page)).toHaveText(["FreeCell", "Simple Simon"])
  await expect(page.locator(".menu-game-row__variant")).toHaveCount(0)

  await showTheGames(page)
  await expect(sizes(page)).toHaveText("Standard")

  // Standard is the game on the table, so the size is a board change: four cells become
  // two, under an open menu. The heading is matched from its start, "FreeCell" being a
  // substring of "Mini FreeCell" and so no evidence of anything.
  await expect(onTheTable(page)).toHaveText(/^FreeCell/)
  await sizes(page).click()
  await expect(sizes(page)).toHaveText("Mini")
  await expect(onTheTable(page)).toContainText("Mini FreeCell")
  await expect(gameRow(page, "FreeCell")).toHaveAttribute("aria-current", "true")
  await page.getByRole("button", { name: "Close menu" }).click()
  await settleBoard(page)
  await expect(page.locator(".drop-zone__slot--cell")).toHaveCount(2)

  // …and the third size is a size, not a pack: Micro is ♠♥ Ace-to-Eight, and a mark read
  // off the deck would have called it what it called Mini.
  await openMenu(page)
  await sizes(page).click()
  await expect(sizes(page)).toHaveText("Micro")
  await expect(onTheTable(page)).toContainText("Micro FreeCell")
  await sizes(page).click()
  await expect(sizes(page)).toHaveText("Standard")
  await expect(onTheTable(page)).toHaveText(/^FreeCell/)
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
  await gameRow(page, "Spiderette").click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await settleBoard(page)
  await expect(page.locator(".drop-zone__slot--stock")).toHaveCount(1)

  await openMenu(page)
  await expect(onTheTable(page)).toContainText("Spiderette · 2 suits")
  await expect(gameRow(page, "Spiderette")).toHaveAttribute("aria-current", "true")

  // Now the pack is a board change: the four-suit board replaces the two-suit one, and
  // the menu stays up so the segment can be tapped again.
  await packs(page).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
  await expect(onTheTable(page)).toContainText("Spiderette · 4 suits")
  await expect(gameRow(page, "Spiderette")).toHaveAttribute("aria-current", "true")
  await expect(packs(page)).toHaveText("♠♥♦♣")

  // The board behind it really did change: still a Spiderette, and a different deal of
  // a different pack (each variant keeps its own saved game).
  await page.getByRole("button", { name: "Close menu" }).click()
  await settleBoard(page)
  await expect(page.locator(".drop-zone__slot--stock")).toHaveCount(1)
})

test("remembers each family's choice across a launch, and opens it from the row", async ({
  page,
}) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)
  await showTheGames(page)

  // A variant chosen on a family whose board isn't on the table is remembered, not
  // played: FreeCell is still up, and nothing has mounted.
  await packs(page).click()
  await expect(packs(page)).toHaveText("♠♥♦♣")
  await expect(onTheTable(page)).toContainText("FreeCell")

  // The choices are persisted like every other preference — a key per family, so the two
  // don't overwrite each other — and a relaunch finds both rows showing them.
  await sizes(page).click()
  await expect(sizes(page)).toHaveText("Mini")
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)
  await expect(packs(page)).toHaveText("♠♥♦♣")
  await expect(sizes(page)).toHaveText("Mini")

  // …and the name beside a segment opens *that* board, which is the whole promise of
  // showing it.
  await gameRow(page, "Spiderette").click()
  await settleBoard(page)
  await openMenu(page)
  await expect(onTheTable(page)).toContainText("Spiderette · 4 suits")
  await expect(sizes(page)).toHaveText("Mini")
})
