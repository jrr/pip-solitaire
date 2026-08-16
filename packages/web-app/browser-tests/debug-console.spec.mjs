// The drop-down debug console (#271): press `` ` `` and the log the app already
// publishes (#213) drops over the board, live, with no devtools in sight.
//
// Browser-only by nature, on all three counts. The way in is a *physical key*
// (`event.code === "Backquote"`, so the panel opens on layouts where backtick is a
// dead key), the lines it shows come from a real pointer drag through `core`'s
// reducer, and the layering against the open menu is a paint-order question —
// `elementFromPoint` over a stacking context, which jsdom has neither of.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

const FREECELL = "/?scene=freecell&animate=off"
// The one-move-from-won position (`Scenario.freecellAlmostWon`), the cheapest real
// move there is: the pending King in the first free cell goes home to the last
// foundation. The same drag `win.spec.mjs` and `share-win.spec.mjs` make.
const ALMOST_WON = "/?scene=freecell&state=almost-won&animate=off"

const consolePanel = (page) => page.locator("#debug-console")
const consoleLines = (page) => page.locator("#debug-console-lines li")

// Every label showing in the scrollback, in order — what the panel is actually
// narrating.
const labels = (page) =>
  page.locator("#debug-console-lines .debug-console__label").allTextContents()

// Play the single winning move by mouse, in incremental steps so `pointermove` fires
// as it crosses the board.
async function playTheWinningMove(page) {
  const cell = page.locator(".drop-zone").nth(0)
  const foundation = page.locator(".drop-zone").nth(7)
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

test("the ` key drops the console over the board, and puts it away", async ({ page }) => {
  await page.goto(FREECELL)
  await settleBoard(page)

  // Closed on load, always — a rendered screenshot or link-preview image must never
  // catch one open.
  await expect(consolePanel(page)).toBeHidden()

  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeVisible()

  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeHidden()

  // Escape is the other way out (and is inert when nothing is showing).
  await page.keyboard.press("Escape")
  await expect(consolePanel(page)).toBeHidden()
  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeVisible()
  await page.keyboard.press("Escape")
  await expect(consolePanel(page)).toBeHidden()
})

test("a real move shows up in the console as it is played", async ({ page }) => {
  await page.goto(ALMOST_WON)
  await settleBoard(page)

  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeVisible()
  // Nothing has happened yet: the panel only listens while it's open.
  await expect(consoleLines(page)).toHaveCount(0)

  await playTheWinningMove(page)
  await expect(page.locator(".win-overlay")).toHaveCount(1)

  // The move the UI asked core to make, what core said back, and the win it reached —
  // the interactions `DebugLog` narrates, now readable without devtools.
  await expect(consoleLines(page).first()).toBeVisible()
  const shown = await labels(page)
  expect(shown).toContain("dispatch")
  expect(shown.some((label) => label.startsWith("result:"))).toBe(true)
  expect(shown).toContain("win")

  // The action's payload rides beside its label as JSON, which is what makes the line
  // worth reading at all.
  const dispatched = await page
    .locator("#debug-console-lines li", { hasText: "dispatch" })
    .first()
    .locator(".debug-console__value")
    .textContent()
  expect(dispatched).toContain("Move")

  // The scrollback survives a close: reopening resumes the log rather than wiping it.
  const count = await consoleLines(page).count()
  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeHidden()
  await page.keyboard.press("Backquote")
  await expect(consoleLines(page)).toHaveCount(count)
})

test("the menu wins over the console, on screen and in the model", async ({ page }) => {
  await page.goto(FREECELL)
  await settleBoard(page)

  // Only ever one of the two: the menu is the modal chrome, so opening it puts the
  // console away…
  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeVisible()
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
  await expect(consolePanel(page)).toBeHidden()

  // …and opening the console closes the menu.
  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeVisible()
  await expect(page.locator("#menu-overlay")).toBeHidden()

  // The layering underneath that rule, checked directly. Both are forced up at once
  // by poking the DOM — the model would never do it — and the console is given
  // pointer events for the length of the probe, since `elementFromPoint` skips a
  // pointer-transparent element and would answer "menu" without proving anything
  // about paint order. What's being asked is purely the z-index question: with the
  // two overlapping, which one is on top?
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
  const hitOverConsole = await page.evaluate(() => {
    const panel = document.getElementById("debug-console")
    panel.removeAttribute("hidden")
    panel.style.pointerEvents = "auto"
    const box = panel.getBoundingClientRect()
    const hit = document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2)
    const owner = hit?.closest("#menu-overlay")
      ? "menu"
      : hit?.closest("#debug-console")
        ? "console"
        : "board"
    panel.style.pointerEvents = ""
    panel.setAttribute("hidden", "")
    return owner
  })
  expect(hitOverConsole).toBe("menu")
})

test("an open console takes no input away from the board", async ({ page }) => {
  await page.goto(ALMOST_WON)
  await settleBoard(page)
  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeVisible()

  // The panel drops over the top of the board — the free cells, the foundations, and
  // the top bar with it — so if it took pointer events, the game underneath would be
  // half unplayable while you watched it being narrated. It doesn't: what's under the
  // console at that point is what a click reaches.
  const overCells = await page.evaluate(() => {
    const zone = document.querySelector(".drop-zone")
    const box = zone.getBoundingClientRect()
    const console_ = document.getElementById("debug-console").getBoundingClientRect()
    const point = { x: box.x + box.width / 2, y: box.y + box.height / 2 }
    return {
      covered: point.y < console_.bottom,
      hitsConsole: !!document.elementFromPoint(point.x, point.y)?.closest("#debug-console"),
    }
  })
  // The premise — the console really is over the cells — then the property.
  expect(overCells.covered).toBe(true)
  expect(overCells.hitsConsole).toBe(false)

  // And the whole move goes through, drag and all, with the panel up.
  await playTheWinningMove(page)
  await expect(page.locator(".win-overlay")).toHaveCount(1)
})
