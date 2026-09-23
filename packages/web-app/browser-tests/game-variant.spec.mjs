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
import { allowMotion, settleBoard } from "./lib/board.mjs"
import { menuSeed } from "./lib/menu.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

const openMenu = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

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

  // Four rows for the ten released boards: the families are one row each, with the
  // rest of their boards on the segment rather than in a row of their own.
  await expect(gameNames(page)).toHaveText(["FreeCell", "Simple Simon", "Spiderette", "Spider"])
  await expect(packs(page)).toHaveCount(1)
  await expect(packs(page)).toHaveAttribute("aria-label", "Spiderette pack: 2 suits")
  await expect(packs(page)).toHaveText("♠♥")

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
  await expect(packs(page)).toHaveText("♠")
  boxes.push(await packs(page).boundingBox())
  await packs(page).click()
  await expect(packs(page)).toHaveText("♠♥")

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
  const name = await gameRow(page, "Spiderette").boundingBox()
  expect(boxes[0].height).toBe(name.height)
  expect(boxes[0].y).toBe(name.y)
})

test("draws the pips in the app's own suit face, not the platform's", async ({ page }) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)

  const suits = packs(page).locator(".menu-variant-mark__suits")
  await expect(suits).toHaveCSS("font-family", /^"Pip Suits"/)
  // …and the face is really there to be used: the same subset the cards are drawn with
  // (`styles/fonts.css`), which carries the four pips and nothing else.
  expect(await page.evaluate(() => document.fonts.check('16px "Pip Suits"', "♠♥♦♣"))).toBe(true)
})

test("swaps the board under the open menu as FreeCell's size cycles", async ({ page }) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)

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

// The swap's one difference from a row tap is that the menu is still up when the new
// board mounts, and a board with no game saved is a fresh deal — on a phone, one dealt
// entirely behind the pane. So the deal is built with every card parked off-stage and
// played only once the menu goes (`TableScene`'s `~onceUncovered`, held by `Main`): what
// the player sees on closing the menu is the deal, not a board that dealt itself while
// they weren't looking.
//
// Motion is allowed and `?animate=off` left off, since the flights are the subject; a
// fresh context has no Mini FreeCell saved, so the size tap is the fresh deal wanted.
test("holds a fresh deal's cards off-stage while the menu is up, and deals them once it closes", async ({
  page,
}) => {
  await allowMotion(page)
  await page.goto("/")
  await settleBoard(page)
  await openMenu(page)

  await sizes(page).click()
  await expect(onTheTable(page)).toContainText("Mini FreeCell")

  // Every card of the new board has a flight built for it, and none has started: the
  // whole pass is paused at its origin, which is a card's height below the stage.
  const parked = () =>
    page.evaluate(() => {
      const stage = document.querySelector(".stacking-playfield").getBoundingClientRect()
      const cards = [...document.querySelectorAll(".stacking-card")]
      const flights = cards.flatMap((el) => el.getAnimations())
      return {
        cards: cards.length,
        paused: flights.filter((a) => a.playState === "paused").length,
        running: flights.filter((a) => a.playState === "running").length,
        belowStage: cards.filter((el) => el.getBoundingClientRect().top >= stage.bottom).length,
      }
    })
  const held = await parked()
  expect(held.cards).toBeGreaterThan(0)
  expect(held.paused).toBe(held.cards)
  expect(held.running).toBe(0)
  expect(held.belowStage).toBe(held.cards)

  // Closing the menu is what deals: the same flights, now running — and the cards land
  // on the stage, as a deal watched from the start would have.
  await page.getByRole("button", { name: "Close menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  const dealing = await parked()
  expect(dealing.paused).toBe(0)
  expect(dealing.running).toBe(held.cards)
  await settleBoard(page)
  expect((await parked()).belowStage).toBe(0)
  await expect(page.locator(".drop-zone__slot--cell")).toHaveCount(2)
})

// A board dealt behind the menu is nobody's until the menu goes: a plain deal saves as
// it is built, but one nobody has seen would come back *at rest* on the next visit — a
// board the player never watched dealt, sitting there as if they had. So its writes wait
// on the same release as its flights (`Main`'s `reveal`), and cycling on past it leaves
// nothing behind: the next visit deals afresh, parked and paused like the first.
test("keeps only the board the menu closed on, and deals an unseen one afresh", async ({
  page,
}) => {
  await allowMotion(page)
  await page.goto("/")
  await settleBoard(page)
  await openMenu(page)

  const dealt = () =>
    page.evaluate(() => {
      const cards = [...document.querySelectorAll(".stacking-card")]
      const paused = cards.flatMap((el) => el.getAnimations()).filter((a) => a.playState === "paused")
      return { cards: cards.length, paused: paused.length }
    })

  // Round one: Mini and Micro each deal behind the menu and are cycled past unseen.
  await sizes(page).click()
  await expect(onTheTable(page)).toContainText("Mini FreeCell")
  const first = await dealt()
  expect(first.paused).toBe(first.cards)
  await sizes(page).click()
  await expect(onTheTable(page)).toContainText("Micro FreeCell")
  await sizes(page).click()
  await expect(onTheTable(page)).toHaveText(/^FreeCell/)

  // Round two: Mini was never kept, so it deals again — parked, not resumed at rest.
  await sizes(page).click()
  await expect(onTheTable(page)).toContainText("Mini FreeCell")
  const again = await dealt()
  expect(again.paused).toBe(again.cards)

  // Closing the menu on it is what keeps it: the deal plays, and the board is now the
  // one this size comes back to.
  await page.getByRole("button", { name: "Close menu" }).click()
  await settleBoard(page)
  await openMenu(page)
  const kept = await menuSeed(page).textContent()
  await sizes(page).click()
  await expect(onTheTable(page)).toContainText("Micro FreeCell")
  await sizes(page).click()
  await expect(onTheTable(page)).toHaveText(/^FreeCell/)
  await sizes(page).click()
  await expect(onTheTable(page)).toContainText("Mini FreeCell")
  await expect(menuSeed(page)).toHaveText(kept)
  expect((await dealt()).paused).toBe(0)
})

// A trip through the sizes is a trip through three mounts of the family's scenes, and
// the board a player left has to be waiting when they come back to it. The link is what
// makes this worth a test of its own: a `?seed=` board opens on a deal fixed for the
// session, so a scene that came back without its game would deal that same link again
// and look for all the world like nothing had happened.
test("keeps the board you dealt while the size segment walks away and back", async ({ page }) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)
  await expect(menuSeed(page)).toHaveText("#24680")

  // Deal for yourself, which is what makes the board yours rather than the link's.
  await page.getByRole("button", { name: "New Deal" }).click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await settleBoard(page)
  await openMenu(page)
  const dealt = await menuSeed(page).textContent()
  expect(dealt).not.toBe("#24680")

  // Out to both short decks and back, every tap under the open menu.
  await sizes(page).click()
  await expect(sizes(page)).toHaveText("Mini")
  await sizes(page).click()
  await expect(sizes(page)).toHaveText("Micro")
  await sizes(page).click()
  await expect(sizes(page)).toHaveText("Standard")

  // The board that comes back is the one dealt above, not the deal the link named.
  await expect(onTheTable(page)).toHaveText(/^FreeCell/)
  await expect(menuSeed(page)).toHaveText(dealt)
})

test("remembers each family's choice across a launch, and opens it from the row", async ({
  page,
}) => {
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)

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
