// The web win flow, end to end (issue #121): load the near-won FreeCell position
// (`?state=almost-won`), play the single winning move by dragging the pending
// King onto its foundation, and confirm the win overlay appears — then that New
// Game tears it down.
//
// Needs a real browser for the input half: the move is a pointer drag across the
// board, which jsdom can't dispatch against a layout it doesn't have.
//
// Run twice, once per input path (issue #244). TableScene binds Pointer Events
// deliberately — "pointerdown/pointermove/pointerup instead of mouse + touch, so
// one code path covers phone and desktop" — and this is what checks that the
// claim holds: the same drag, once from a mouse on a roomy desktop viewport and
// once from a finger on an emulated iPhone, has to reach the same overlay.

import { devices, expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"
import { contextOptions } from "../scripts/lib/devices.mjs"
import { touchDrag } from "../scripts/lib/touch.mjs"

// The two input paths. The mouse case keeps the roomy portrait viewport the test
// has always used, so every zone is comfortably on screen and the drag is a
// straight line across the board. The touch case takes a real device descriptor
// instead — `hasTouch`/`isMobile`, so the page gets touch events, the meta
// viewport and the coarse-pointer media queries — and drags with a finger; a
// phone-*sized* desktop context would exercise none of that (see
// scripts/lib/devices.mjs).
const inputs = [
  {
    name: "mouse",
    context: { viewport: { width: 800, height: 1000 } },
    touchCapable: false,
    // A few incremental moves so pointermove fires and the hover highlight updates.
    drag: async (page, from, to) => {
      await page.mouse.move(from.x, from.y)
      await page.mouse.down()
      for (let i = 1; i <= 6; i++) {
        await page.mouse.move(
          from.x + ((to.x - from.x) * i) / 6,
          from.y + ((to.y - from.y) * i) / 6,
        )
      }
      await page.mouse.up()
    },
  },
  {
    name: "touch",
    // `contextOptions` drops the descriptor's `defaultBrowserType`, which
    // `test.use` rejects inside a describe group (it would force a new worker) —
    // and which we don't want anyway: the suite is Chromium, whatever engine the
    // device implies.
    context: contextOptions(devices["iPhone 13 Mini"]),
    touchCapable: true,
    drag: touchDrag,
  },
]

for (const input of inputs) {
  test.describe(`by ${input.name}`, () => {
    test.use(input.context)

    test("the winning move raises the overlay, and New Game tears it down", async ({ page }) => {
      // `animate=off` skips the opening fly-in (see AppUrl), so the board is at its
      // resting positions as soon as the cards exist — the drag then measures the
      // final footprints rather than racing the deal.
      await page.goto("/?scene=freecell&state=almost-won&animate=off")

      // Check the premise before the drag: a phone-sized desktop context reports
      // no touch at all (that was the old screenshot harness's bug, #244), and
      // this case would then be the mouse case with extra steps.
      const touchCapable = await page.evaluate(
        () => "ontouchstart" in window && navigator.maxTouchPoints > 0,
      )
      expect(touchCapable).toBe(input.touchCapable)

      // The pending King rests alone in the first free cell (drop zone 0); its
      // foundation is the last drop zone (4 cells, then 4 foundations, Clubs last —
      // zone 7). The King is centred in its cell, so grabbing from the cell's centre
      // picks it up.
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

      await input.drag(page, from, to)

      const overlay = page.locator(".win-overlay")
      await expect(overlay).toHaveCount(1)
      await expect(page.locator(".win-panel__title")).toBeVisible()
      await expect(page.locator(".win-panel__title")).not.toHaveText("")

      // …and what the game cost (#289). A `?state=` board starts a fresh tally, so the
      // single drag above is the whole game: one move, no undos. The counting rules
      // are `Stats_test`'s and the wiring is `TableScene_test`'s — what only a browser
      // can show is that a real drag on a real board reaches the counter at all.
      await expect(page.locator(".win-panel__stats")).toHaveText("1 move · 0 undos")

      // The panel's top and bottom breathing room have to match. They don't come
      // from the same place: above the title it's plain padding, while below the
      // buttons it's padding *minus* what the reserved-but-empty share status line
      // claws back (see `.win-panel__status`). Left uncompensated the bottom ran to
      // roughly twice the top, which is visible as a lopsided panel — and it's
      // arithmetic across two rules, so only a real layout can check it.
      const room = await page.evaluate(() => {
        const panel = document.querySelector(".win-panel")
        const box = panel.getBoundingClientRect()
        const first = panel.firstElementChild.getBoundingClientRect()
        const buttons = panel.querySelector(".win-panel__actions").getBoundingClientRect()
        return { above: first.top - box.top, below: box.bottom - buttons.bottom }
      })
      expect(Math.abs(room.above - room.below)).toBeLessThan(8)

      // By name, not by class: the panel grew a second button when the victory share
      // landed (#264), and this scenario carries a deal number so both are on offer
      // here. `share-win.spec.mjs` covers the other one.
      await page.getByRole("button", { name: "New Game" }).click()
      await expect(overlay).toHaveCount(0)
      // New Game deals a fresh board rather than just clearing the overlay.
      await expect(page.locator(".stacking-card").first()).toBeVisible()
    })
  })
}
