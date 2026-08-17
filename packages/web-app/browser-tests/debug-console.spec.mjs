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

// ⇧` docks the console beside the board, or puts it back over it (#275). The console is
// keyboard-only, so its mode is too — same physical key as the toggle, shifted.
const pressDock = (page) => page.keyboard.press("Shift+Backquote")

// The card footprint the layout has settled on, straight off the custom property
// `applyScale` publishes. What "the board reflowed into the remaining width" means in a
// number: docking narrows the observed box, the `ResizeObserver` re-runs the layout, and
// the cards come out smaller.
const cardWidth = (page) =>
  page.evaluate(() =>
    parseFloat(
      getComputedStyle(document.querySelector(".stacking-playfield")).getPropertyValue(
        "--card-w",
      ),
    ),
  )

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

// --- Docked beside the board (#275) -----------------------------------------------
//
// The overlay is the wrong axis for FreeCell in a desktop window: `TableScene` fits the
// tallest cascade fan plus the top row into the available *height*, so a band across the
// top eats the scarce dimension and shrinks every card, while past a point the layout
// throws surplus *width* away as equal left/right margins. Docked, the console is built
// out of that discard — and the board is told about it in exactly one way: `.table-board`,
// the box its `ResizeObserver` watches (#172), gets narrower.
//
// All of which is a layout claim, so all of which is measured here rather than in jsdom:
// the board's rect, the panel's rect, and the card footprint the two produce between them.
test.describe("docked beside the board", () => {
  // Wide enough to clear the refusal test with room over: an eight-column board needs
  // ~427px to keep cards above `minScale`, and the dock takes 340.
  test.use({ viewport: { width: 1440, height: 900 } })

  test("docking narrows the board rather than covering it", async ({ page }) => {
    await page.goto(FREECELL)
    await settleBoard(page)

    const board = page.locator(".table-board")
    const undocked = await board.boundingBox()
    const undockedCard = await cardWidth(page)

    await page.keyboard.press("Backquote")
    await expect(consolePanel(page)).toBeVisible()
    // The premise: overlaid, the panel lies *over* an untouched board.
    expect((await board.boundingBox()).width).toBeCloseTo(undocked.width, 0)

    await pressDock(page)
    await expect(page.locator("html")).toHaveAttribute("data-console-dock", "on")

    // The board gives up the dock's width and reflows into what's left — cards and all.
    await expect
      .poll(async () => (await board.boundingBox()).width)
      .toBeLessThan(undocked.width)
    const docked = await board.boundingBox()
    const panel = await consolePanel(page).boundingBox()
    expect(docked.width).toBeCloseTo(undocked.width - panel.width, 0)
    // In *this* window the cards don't move at all, and that's the point of the whole
    // exercise: the board is already ceiling-bound (`maxScale`), so the width the dock
    // takes is width `applyScale` was discarding as equal left/right margins anyway. The
    // console arrives for free. (The narrower window below is where the reflow shows.)
    expect(await cardWidth(page)).toBeCloseTo(undockedCard, 1)

    // …and nothing is hidden under anything: the two rects don't intersect, so every
    // zone on the board is somewhere the console isn't.
    expect(docked.x + docked.width).toBeLessThanOrEqual(panel.x + 0.5)
    const zonesClear = await page.evaluate(() => {
      const panelLeft = document.getElementById("debug-console").getBoundingClientRect().left
      return [...document.querySelectorAll(".drop-zone")].every(
        (zone) => zone.getBoundingClientRect().right <= panelLeft + 0.5,
      )
    })
    expect(zonesClear).toBe(true)

    // Undocking hands the width straight back.
    await pressDock(page)
    await expect(page.locator("html")).not.toHaveAttribute("data-console-dock", "on")
    await expect
      .poll(async () => (await board.boundingBox()).width)
      .toBeCloseTo(undocked.width, 0)
  })

  test("a closed console stops holding the board's width", async ({ page }) => {
    await page.goto(FREECELL)
    await settleBoard(page)
    const board = page.locator(".table-board")
    const undocked = (await board.boundingBox()).width

    await pressDock(page)
    await expect(consolePanel(page)).toBeVisible()
    await expect.poll(async () => (await board.boundingBox()).width).toBeLessThan(undocked)

    // Closing puts the strip back: the mode is remembered, but a console nobody is
    // looking at must not go on taking a slice of the playfield with it.
    await page.keyboard.press("Escape")
    await expect(consolePanel(page)).toBeHidden()
    await expect(page.locator("html")).not.toHaveAttribute("data-console-dock", "on")
    await expect.poll(async () => (await board.boundingBox()).width).toBeCloseTo(undocked, 0)
  })

  test("the dock mode survives a reload", async ({ page }) => {
    await page.goto(FREECELL)
    await settleBoard(page)
    await pressDock(page)
    await expect(page.locator("html")).toHaveAttribute("data-console-dock", "on")

    await page.reload()
    await settleBoard(page)
    // Closed on load as always — the mode is remembered, the panel isn't.
    await expect(consolePanel(page)).toBeHidden()
    await expect(page.locator("html")).not.toHaveAttribute("data-console-dock", "on")

    // …and the plain toggle brings it back docked, without having to say so again.
    await page.keyboard.press("Backquote")
    await expect(consolePanel(page)).toBeVisible()
    await expect(page.locator("html")).toHaveAttribute("data-console-dock", "on")
  })

  test("the menu and a docked console are up together", async ({ page }) => {
    await page.goto(FREECELL)
    await settleBoard(page)
    await pressDock(page)
    await expect(consolePanel(page)).toBeVisible()

    // The overlay's exclusion doesn't apply here — it exists because a band across the
    // top covers the Menu button — so the log stays up beside the open menu.
    await page.getByRole("button", { name: "Open menu" }).click()
    await expect(page.locator("#menu-overlay")).toBeVisible()
    await expect(consolePanel(page)).toBeVisible()

    // Readable, not merely present: the dimming backdrop stops at the dock edge rather
    // than washing over the log.
    const rects = await page.evaluate(() => {
      const box = (el) => {
        const r = el.getBoundingClientRect()
        return { left: r.left, right: r.right, top: r.top, height: r.height, width: r.width }
      }
      return {
        backdrop: box(document.querySelector(".menu-overlay__backdrop")),
        panel: box(document.getElementById("debug-console")),
      }
    })
    expect(rects.backdrop.right).toBeLessThanOrEqual(rects.panel.left + 0.5)

    // And the console is still just a panel: a click in it doesn't dismiss the menu.
    await page.mouse.click(
      rects.panel.left + rects.panel.width / 2,
      rects.panel.top + rects.panel.height / 2,
    )
    await expect(page.locator("#menu-overlay")).toBeVisible()
  })
})

test.describe("docked into a window with nothing to spare", () => {
  // Wide enough to dock, but not wide enough to do it out of discarded margin: the board
  // is at its `maxScale` ceiling undocked and drops below it once the dock is taken, so
  // here the cards really do rescale — the `ResizeObserver` path (#172) doing its work.
  test.use({ viewport: { width: 1000, height: 900 } })

  test("the board reflows into the remaining width", async ({ page }) => {
    await page.goto(FREECELL)
    await settleBoard(page)
    const before = await cardWidth(page)

    await pressDock(page)
    await expect(page.locator("html")).toHaveAttribute("data-console-dock", "on")
    await expect.poll(() => cardWidth(page)).toBeLessThan(before)

    // The cards shrank, and they shrank *into* the board — the whole row still clears
    // the dock rather than sliding under it.
    const clear = await page.evaluate(() => {
      const panelLeft = document.getElementById("debug-console").getBoundingClientRect().left
      return [...document.querySelectorAll(".stacking-card, .drop-zone")].every(
        (el) => el.getBoundingClientRect().right <= panelLeft + 0.5,
      )
    })
    expect(clear).toBe(true)

    // …and back up again when the dock is given up.
    await pressDock(page)
    await expect.poll(() => cardWidth(page)).toBeCloseTo(before, 1)
  })
})

test.describe("too narrow to dock", () => {
  // Below the width at which the board would still clear `minScale` after giving up the
  // dock (`TableScene.minStageWidth` is ~284px for eight columns, and the dock takes
  // 340), so the toggle has to refuse rather than squeeze.
  test.use({ viewport: { width: 500, height: 900 } })

  test("the toggle refuses and the console stays an overlay", async ({ page }) => {
    await page.goto(FREECELL)
    await settleBoard(page)
    const board = page.locator(".table-board")
    const before = (await board.boundingBox()).width

    await pressDock(page)
    // The console comes up regardless — a refusal you can't see is indistinguishable
    // from a key that did nothing — but it comes up as an overlay, and says why.
    await expect(consolePanel(page)).toBeVisible()
    await expect(page.locator("html")).not.toHaveAttribute("data-console-dock", "on")
    expect((await board.boundingBox()).width).toBeCloseTo(before, 0)
    await expect(consoleLines(page).filter({ hasText: "too narrow to dock" })).toHaveCount(1)

    // …and it's still refused on the next press, rather than toggling into a mode it
    // just declined.
    await pressDock(page)
    await expect(page.locator("html")).not.toHaveAttribute("data-console-dock", "on")
  })
})
