// The main menu's paired buttons, measured.
//
// Restart · Share, New Deal · Enter Seed, Settings · About: six buttons in three
// sections that have to read as one grid, each half the pane wide, every row's seam
// under the one above it. Nothing in a unit test can see that — it is entirely
// `.menu-buttons`'s two grid tracks (MenuGameButton.css), and a stylesheet is only
// evaluated by a browser. It goes wrong quietly, too: give the buttons their widths
// from their content and the rows still *look* like rows, just ones whose seam wanders
// by a few pixels per label.
//
// The bottom row is the one most likely to drift, because it is the one section a
// `margin-top: auto` moves (`.menu-section--bottom`) — so a fix that reached for the
// buttons' own widths there would go unnoticed from the top of the panel.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

// Every paired button, in the order the panel reads: the "this game" pair, "new game"'s,
// then Settings · About at the foot.
const gridButtons = (page) => page.locator(".menu-buttons button")

test("lays the six paired buttons out as one grid, each half the pane", async ({ page }) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()

  const boxes = await gridButtons(page).evaluateAll((buttons) =>
    buttons.map((b) => {
      const { x, width } = b.getBoundingClientRect()
      return { x: Math.round(x), width: Math.round(width) }
    }),
  )
  expect(boxes).toHaveLength(6)

  // Column for column, all the way down: New Deal and Settings under Restart, Enter
  // Seed and About under Share.
  expect(boxes[2]).toEqual(boxes[0])
  expect(boxes[3]).toEqual(boxes[1])
  expect(boxes[4]).toEqual(boxes[0])
  expect(boxes[5]).toEqual(boxes[1])

  // …and the two columns split the row evenly, rather than one label's length setting
  // the seam. Equal to the pixel, and the pair spans the section they sit in.
  expect(boxes[0].width).toBe(boxes[1].width)
  const section = await page.locator('[aria-label="this game"]').boundingBox()
  expect(boxes[0].x).toBe(Math.round(section.x))
  expect(boxes[1].x + boxes[1].width).toBe(Math.round(section.x + section.width))
})

test("keeps the columns still when the seed on the table changes", async ({ page }) => {
  // The reason the deal number is named on the section heading and not on Share:
  // a button whose label grows by five digits on one board and not another can't hold
  // a column. Deal 1 and deal 24680 are the extremes a seed reaches.
  await page.goto("/?seed=1&animate=off")
  await settleBoard(page)
  await page.getByRole("button", { name: "Open menu" }).click()
  const narrow = await gridButtons(page).evaluateAll((b) =>
    b.map((el) => Math.round(el.getBoundingClientRect().width)),
  )

  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await page.getByRole("button", { name: "Open menu" }).click()
  expect(
    await gridButtons(page).evaluateAll((b) =>
      b.map((el) => Math.round(el.getBoundingClientRect().width)),
    ),
  ).toEqual(narrow)
})
