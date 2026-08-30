// The open menu must cover the board's floating controls.
//
// The board stacks in the large — cards on an imperative counter, the Finish
// button at 900, the win overlay at 1000, the finish sweep at 100000 — while the
// chrome stacks small (`#menu-overlay` at 20). Those two scales only coexist
// because `.table-board` is a stacking context (`isolation: isolate`), which keeps
// the board's numbers from being read against the menu's in the root context.
// Without it the Finish button floated *over* the open menu, mid-panel.
//
// Browser-only by nature: stacking contexts are a paint-order question, so the
// check is "what does the player actually touch at that point on screen"
// (`elementFromPoint`) — jsdom has no layout and no paint order to ask.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

// `?state=finish` is the finishable position (`Scenario.freecellFinish`), the one
// board state that shows the Finish button; `animate=off` skips the deal's fly-in.
const FINISHABLE = "/?game=freecell&state=finish&animate=off"

// What the player would hit at the centre of the Finish button: the topmost
// element painted there, walked up to whichever of the two contenders owns it.
async function topmostOverFinishButton(page) {
  const box = await page.locator(".finish-button").boundingBox()
  return await page.evaluate(
    ({ x, y }) => {
      const hit = document.elementFromPoint(x, y)
      if (!hit) return "nothing"
      if (hit.closest("#menu-overlay")) return "menu"
      if (hit.closest(".finish-button")) return "finish-button"
      return "board"
    },
    { x: box.x + box.width / 2, y: box.y + box.height / 2 },
  )
}

test("the open menu covers the Finish button", async ({ page }) => {
  await page.goto(FINISHABLE)
  await settleBoard(page)

  // The premise: this position offers the one-tap win, and the button is on top
  // of the board while the menu is closed.
  const finish = page.locator(".finish-button")
  await expect(finish).toBeVisible()
  expect(await topmostOverFinishButton(page)).toBe("finish-button")

  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()

  // The button is still in the DOM (the board hasn't changed) — it just must not
  // be what's painted, or tapped, over the menu.
  await expect(finish).toHaveCount(1)
  expect(await topmostOverFinishButton(page)).toBe("menu")

  // …and it comes back when the menu closes.
  await page.getByRole("button", { name: "Close menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  expect(await topmostOverFinishButton(page)).toBe("finish-button")
})
