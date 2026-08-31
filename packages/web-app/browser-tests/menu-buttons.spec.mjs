// The main menu's game buttons, measured.
//
// Random · Enter Seed above Restart · Share Seed: four buttons in two sections that
// have to read as one grid, each half the pane wide, the lower pair's edges under the
// upper pair's. Nothing in a unit test can see that — it is entirely `.menu-buttons`'s
// two grid tracks (MenuGameButton.css), and a stylesheet is only evaluated by a
// browser. It goes wrong quietly, too: give the buttons their widths from their
// content and the rows still *look* like rows, just ones whose seam wanders by a few
// pixels per label.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

// Every game button, in the order the panel reads: the "new game" pair, then "this
// game"'s. `.menu-buttons` is the two grids and nothing else — the Settings button at
// the foot borrows the button class but stands alone in its section.
const gameButtons = (page) => page.locator(".menu-buttons button")

test("lays the four game buttons out as one grid, each half the pane", async ({ page }) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()

  const boxes = await gameButtons(page).evaluateAll((buttons) =>
    buttons.map((b) => {
      const { x, width } = b.getBoundingClientRect()
      return { x: Math.round(x), width: Math.round(width) }
    }),
  )
  expect(boxes).toHaveLength(4)

  // Column for column: Restart sits under Random, Share Seed under Enter Seed.
  expect(boxes[2]).toEqual(boxes[0])
  expect(boxes[3]).toEqual(boxes[1])

  // …and the two columns split the row evenly, rather than one label's length setting
  // the seam. Equal to the pixel, and the pair spans the section they sit in.
  expect(boxes[0].width).toBe(boxes[1].width)
  const section = await page.locator('[aria-label="new game"]').boundingBox()
  expect(boxes[0].x).toBe(Math.round(section.x))
  expect(boxes[1].x + boxes[1].width).toBe(Math.round(section.x + section.width))
})

test("keeps the columns still when the seed on the table changes", async ({ page }) => {
  // The reason the deal number is named on the section heading and not on Share Seed:
  // a button whose label grows by five digits on one board and not another can't hold
  // a column. Deal 1 and deal 24680 are the extremes a seed reaches.
  await page.goto("/?seed=1&animate=off")
  await settleBoard(page)
  await page.getByRole("button", { name: "Open menu" }).click()
  const narrow = await gameButtons(page).evaluateAll((b) =>
    b.map((el) => Math.round(el.getBoundingClientRect().width)),
  )

  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await page.getByRole("button", { name: "Open menu" }).click()
  expect(
    await gameButtons(page).evaluateAll((b) =>
      b.map((el) => Math.round(el.getBoundingClientRect().width)),
    ),
  ).toEqual(narrow)
})
