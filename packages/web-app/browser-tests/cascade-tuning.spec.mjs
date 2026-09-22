// The Debug screen's cascade knobs, checked where their whole point is: on the board's
// own victory. `cascade.spec.mjs` asks whether the fade works, in the demo scene that
// exists to show it; this asks whether the two sliders in the menu are the fade *the
// game* uses, which is a different claim and one no unit test can make — it spans the
// menu's model, the driver's live ref, and a canvas a real win paints.
//
// Three things are load-bearing about them and all three are here: a knob reaches the
// next celebration, a knob reaches the one already falling, and nothing is remembered
// across a reload.
//
// The instrument is `getImageData` on the board's own overlay, as in `cascade.spec.mjs`
// and for the same reason: a screenshot is the composite and cannot tell what the canvas
// drew from the table showing through it.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"
import { openSettings } from "./lib/menu.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

// A sprite sheet is built at the moment of victory and CI runners are slow at the
// 52-card decode; two wins in a file is two of those, plus the cards to watch fall.
test.setTimeout(120_000)

/**
 * How much of the victory canvas is painted, and how much of it at full strength. The
 * ratio between them is the fade: with one running, all but the newest stamp has been
 * dimmed at least once; with it off, every painted pixel is a card at full alpha.
 */
const ink = (page) =>
  page.evaluate(() => {
    const canvas = document.querySelector(".table-cascade")
    if (!canvas) return { painted: 0, full: 0 }
    const { data } = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height)
    let painted = 0
    let full = 0
    for (let i = 3; i < data.length; i += 4) {
      if (data[i] > 0) painted++
      if (data[i] >= 250) full++
    }
    return { painted, full }
  })

/** Into the menu, down to Debug, and open the group the sliders are in. */
const openCascadeKnobs = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await openSettings(page)
  await page.getByRole("button", { name: "Debug" }).first().click()
  // A collapsed `<details>` keeps its contents in the document but not on screen, and
  // Playwright won't drag a control it can't see — so the group is opened rather than
  // the input reached for directly.
  await page.locator(".scene-menu__group-label", { hasText: "cascade" }).click()
  await expect(page.locator('input[data-knob="fade"]')).toBeVisible()
}

// The overlay stays in the document when it is put away — it is hidden, not unmounted —
// so what a closed menu is, to a test, is one that can't be seen.
const closeMenu = async (page) => {
  await page.getByRole("button", { name: "Close menu" }).click()
  await expect(page.locator("#menu-overlay")).not.toBeVisible()
}

/**
 * Win the board and wait until the same point in the run each time: `state=finish` opens
 * one press away from a victory, and `animate=off` collapses the sweep, so the press is
 * the win and what follows is the cascade alone.
 *
 * Counted in cards off the foundations rather than in seconds, because the wait that
 * matters is the sprite sheet's and that is the machine's business, not the run's.
 */
const winAndWatch = async (page, { cards = 8 } = {}) => {
  await page.locator(".finish-button").click()
  await expect(page.locator(".table-cascade")).toHaveCount(1)
  await expect
    .poll(() => page.locator(".stacking-card--flown").count(), { timeout: 60_000 })
    .toBeGreaterThanOrEqual(cards)
}

test("the fade the Debug screen holds is the fade the board's victory plays", async ({ page }) => {
  await page.goto("/?game=freecell&state=finish&animate=off")
  await settleBoard(page)
  await winAndWatch(page)
  const faded = await ink(page)
  // Something was drawn, and almost none of it is still at full strength: the trail
  // behind the cards has been dimmed.
  expect(faded.painted).toBeGreaterThan(0)
  expect(faded.full).toBeLessThan(faded.painted * 0.2)

  // The same victory with the fade dragged off before it starts. Nothing else about the
  // board, the deal or the run differs, so the brightness is the slider's doing.
  await page.goto("/?game=freecell&state=finish&animate=off")
  await settleBoard(page)
  await openCascadeKnobs(page)
  await page.locator('input[data-knob="fade"]').fill("0")
  await closeMenu(page)
  await winAndWatch(page)
  const flat = await ink(page)
  expect(flat.full).toBeGreaterThan(flat.painted * 0.9)
})

test("a slider dragged over a falling cascade lands on that cascade", async ({ page }) => {
  // The reason the knobs are on the menu rather than in a scene: the menu opens over a
  // celebration in progress, and forty seconds is a long time to watch the wrong one.
  await page.goto("/?game=freecell&state=finish&animate=off")
  await settleBoard(page)
  await openCascadeKnobs(page)
  await page.locator('input[data-knob="fade"]').fill("0")
  await closeMenu(page)
  await winAndWatch(page, { cards: 4 })

  const before = await ink(page)
  expect(before.full).toBeGreaterThan(before.painted * 0.9)

  // Now turn it up, with the cards still in the air. The run takes it on its next stamp
  // (`CascadePlayer.retune` through `controls.retuneCascade`), so the trail that was
  // uniformly bright starts sinking within a stamp or two.
  await openCascadeKnobs(page)
  await page.locator('input[data-knob="fade"]').fill("0.5")
  await expect
    .poll(
      async () => {
        const now = await ink(page)
        return now.painted === 0 ? 1 : now.full / now.painted
      },
      { timeout: 20_000 },
    )
    .toBeLessThan(0.5)
})

test("the knobs live in memory, so a reload is the reset", async ({ page }) => {
  // Deliberate: they are a debug aid rather than a preference, and nothing that tunes
  // the game's own celebration should be able to stay tuned without anyone meaning it.
  await page.goto("/?game=freecell&animate=off")
  await settleBoard(page)
  await openCascadeKnobs(page)
  const readout = page.locator('.menu-slider:has(input[data-knob="fade"]) .menu-slider__readout')
  await expect(readout).toHaveText("0.5 /s · half gone in 1s")

  await page.locator('input[data-knob="fade"]').fill("0")
  await expect(readout).toHaveText("off · nothing fades")

  await page.reload()
  await settleBoard(page)
  await openCascadeKnobs(page)
  await expect(readout).toHaveText("0.5 /s · half gone in 1s")
})
