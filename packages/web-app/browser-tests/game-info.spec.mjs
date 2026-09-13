// The game info feature, from the switch that turns it on to the screen it opens.
//
// Everything here is a *join* between parts that unit tests cover one at a time: the
// hidden **Beta features** switch persists a flag (`MenuSettingsScreen`), the flag
// decides whether a game's row is handed an `onInfo` (`Main`), the row draws the "i"
// from that (`MenuGameRow`), and the tap swaps the pane to a fourth screen (`Menu`). No
// single one of those can see the chain, and the chain is what a player has.
//
// The row is also a set of *measured* claims, and a stylesheet is only evaluated by a
// browser. Three of them are invisible when they break, which is why they are here at
// all: the "i" is a 44px target around an 18px mark, so a change that sizes the button
// to fit the circle would look identical and halve what a thumb has to hit; the target
// abuts the name button exactly, so it steals none of "tap the game"; and it stays
// clear of the next row's, so no tap opens the wrong game's screen. The fourth is the
// circle sitting on the same edge the panel's other controls end on (MenuGameRow.css).
//
// The **variant picker** on the screen is a second chain of the same kind, and the one
// place two controls meet: `Main` decides which boards a family is offering and what a
// tap on one does, `MenuVariantPicker` draws them, and the choice it writes is the one
// the Games list's segment reads back (`game-variant.spec.mjs`). A walk is the only thing
// that can see that they are one choice and not two.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"
import { setBetaFeatures } from "./lib/menu.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

const openMenu = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

// One switch now turns on every unfinished feature, so the same flip that puts the "i"
// on a row also lists the unreleased games (`more-games.spec.mjs`) — which means the
// Games list every walk below sees is the longer one, and FreeCell's row carries a
// variant segment between its name and its "i". The measured claims here are about the
// *plain* row, so they are taken on Simple Simon, the game with no family to collapse.
const infoRow = (page, game) =>
  page
    .locator(".menu-game-row")
    .filter({ has: page.getByRole("button", { name: `About ${game}` }) })

test("hides the info buttons until the flag is found, then puts one beside each game", async ({
  page,
}) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)

  // Off by default, and off is the plain row the menu has always had.
  await expect(page.locator(".menu-game-row__info")).toHaveCount(0)

  await setBetaFeatures(page, true)
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
  await setBetaFeatures(page, true)

  const row = infoRow(page, "Simple Simon")
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
  await setBetaFeatures(page, true)

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
  await setBetaFeatures(page, true)
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
  await setBetaFeatures(page, true)

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
  await setBetaFeatures(page, true)

  await page.getByRole("button", { name: "About FreeCell" }).click()
  await expect(page.locator(".game-info__numbers")).toBeVisible()

  await page.getByRole("button", { name: "Close menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await openMenu(page)
  await expect(page.locator(".game-info__numbers")).toHaveCount(0)
  await expect(page.locator(".menu-title")).toHaveText("Pip")
})

// The picker's buttons, addressed by their accessible names — the same sentence the Games
// list's segment says, which is what tells the two families' apart.
const packs = (page) => page.getByRole("button", { name: /^Spiderette pack:/ })
const sizes = (page) => page.getByRole("button", { name: /^FreeCell size:/ })
const numbers = (page) => page.locator(".game-info__numbers")

test("offers a family's packs on its info screen, and moves the screen to the one picked", async ({
  page,
}) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)
  await setBetaFeatures(page, true)
  await page.getByRole("button", { name: "About Spiderette" }).click()

  // All three at once, in the family's own order, with the pack the screen is about lit.
  // The section is headed with the word for what they vary in — "PACK" on screen, the
  // uppercasing being the heading's own, which is why the text asserted here is not.
  const heading = page.locator("[aria-label='pack'] .menu-section__heading")
  await expect(heading).toHaveText("pack")
  await expect(heading).toHaveCSS("text-transform", "uppercase")
  await expect(packs(page)).toHaveText(["♠×4", "♠♥×2", "♠♥♦♣"])
  await expect(packs(page).nth(1)).toHaveAttribute("aria-current", "true")
  await expect(page.locator(".menu-title")).toHaveText("Spiderette · 2 suits")

  // A pack picked is the screen's new subject: the title is that board's, and the
  // highlight has moved with it. FreeCell is still the game on the table — reading about
  // a game is still not choosing to play it.
  await packs(page).nth(2).click()
  await expect(page.locator(".menu-title")).toHaveText("Spiderette · 4 suits")
  await expect(packs(page).nth(2)).toHaveAttribute("aria-current", "true")
  await expect(packs(page).nth(1)).not.toHaveAttribute("aria-current", "true")
  await expect(page.locator("#menu-overlay")).toBeVisible()

  // …and it is the *same* choice the Games list's segment offers, not a second one: back
  // on the main menu the segment is showing the pack picked here, and it survives a
  // launch like every other preference.
  await page.getByRole("button", { name: "Back to menu" }).click()
  await expect(packs(page)).toHaveText("♠♥♦♣")
  await page.reload()
  await settleBoard(page)
  await openMenu(page)
  await expect(packs(page)).toHaveText("♠♥♦♣")
})

test("swaps the board under the menu when the picker names the game being played", async ({
  page,
}) => {
  // The same rule the Games list's segment follows: a choice about the board on the
  // table is a board change, and the menu stays put so the control is still there.
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)
  await setBetaFeatures(page, true)
  await page.getByRole("button", { name: "About FreeCell" }).click()

  await expect(sizes(page)).toHaveText(["Standard", "Mini", "Micro"])
  await expect(numbers(page)).toHaveText("8 cascades · 4 cells · 52 cards")

  await sizes(page).nth(1).click()
  await expect(page.locator(".menu-title")).toHaveText("Mini FreeCell")
  // The numbers are the reason the picker sits under them: four cascades and two cells,
  // on the line immediately above the control that changed them.
  await expect(numbers(page)).toHaveText("4 cascades · 2 cells · 20 cards")
  await expect(page.locator("#menu-overlay")).toBeVisible()

  // …and the board really did change under the open menu.
  await page.getByRole("button", { name: "Close menu" }).click()
  await settleBoard(page)
  await expect(page.locator(".drop-zone__slot--cell")).toHaveCount(2)
})

test("gives a game with no family no such section at all", async ({ page }) => {
  // Not an empty band with a heading over it: Simple Simon is a game on its own, so
  // there is nothing to choose between and nothing to head.
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)
  await setBetaFeatures(page, true)
  await page.getByRole("button", { name: "About Simple Simon" }).click()

  await expect(page.locator(".menu-variant-picker")).toHaveCount(0)
  await expect(page.locator(".menu-screen .menu-section__heading")).toHaveCount(0)
})

test("draws the picker as one control the width of the panel, not three side by side", async ({
  page,
}) => {
  // Three equal shares, each seam a single 1px rule where two borders land on each
  // other, and the whole thing ending where the panel's other controls end. None of it
  // is visible when it breaks: a picker whose buttons fit their own words would put the
  // seams somewhere different on every family, and doubled borders read as a slightly
  // heavier line rather than as a bug.
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openMenu(page)
  await setBetaFeatures(page, true)
  await page.getByRole("button", { name: "About FreeCell" }).click()

  const boxes = await sizes(page).evaluateAll((els) => els.map((el) => el.getBoundingClientRect()))
  const link = await page.locator(".game-info__link").boundingBox()

  // "Standard" is twice the width of "Mini", and all three are the same box anyway.
  for (const box of boxes) {
    expect(Math.round(box.width)).toBe(Math.round(boxes[0].width))
    expect(Math.round(box.height)).toBe(Math.round(boxes[0].height))
  }
  // One border's overlap at each seam, rather than a gap or a 2px rule.
  expect(Math.round(boxes[1].left - boxes[0].right)).toBe(-1)
  expect(Math.round(boxes[2].left - boxes[1].right)).toBe(-1)
  // …and the control spans the panel's content width, ending on the edge the link under
  // it ends on.
  expect(Math.round(boxes[0].left)).toBe(Math.round(link.x))
  expect(Math.round(boxes[2].right)).toBe(Math.round(link.x + link.width))
})
