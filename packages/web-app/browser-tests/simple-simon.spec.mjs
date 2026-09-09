// Simple Simon, played to the win overlay in a real browser.
//
// The first board here from outside the FreeCell family, and the one whose claim is
// hardest to make from a unit test: that the view reads Spider's laws off the board
// rather than assuming FreeCell's. `Core_test` replays this same line through the
// session and proves the *rules* compose into a win. What only a browser can say is
// that a ten-column board lays out, that a same-suit run lifts under the pointer as
// one span where a mixed-suit tail doesn't, that a card of another suit still drops,
// that a completed run flies home on its own, and that the fourth doing so raises
// the overlay — with no Finish button in the way, since there is nothing to finish.
//
// A recorded line, as in `short-deck.spec.mjs`: deal #1 is the same board every
// time. Ninety-odd drags, hence the raised timeout.

import { expect, test } from "@playwright/test"
import { settle } from "../scripts/autoplay/read-board.mjs"
import { playLine } from "./lib/play-line.mjs"
import { quietWin } from "./lib/board.mjs"
import * as Game from "core/src/Game.res.mjs"

test.use({ viewport: { width: 1000, height: 1100 } })
test.use(quietWin)

// Each move is the card that heads the run to lift, and the column it lands in.
const LINE =
  "JH T9, TC T9, 7S T1, 8S T9, AC T8, 3C T3, 6H T9, 4H T10, QH T5, 5C T9, 4H T9, QH T6, KD T10, AC T5, 2H T3, 3D T9, 2H T9, 2C T3, TS T8, AD T9, QS T10, JC T6, TS T6, 4C T2, 4D T8, 9D T1, 9S T6, 6S T4, 7H T3, 8H T5, 9H T7, 8D T1, TD T3, AD T1, JD T10, 5S T4, 4D T4, TH T3, 7C T10, AH T9, AS T5, 2H T7, 3D T4, 2S T4, 4H T5, 4C T9, 4H T2, 2D T5, 6D T10, 5H T10, KH T2, TS T1, TH T6, 5C T3, 6H T6, 8S T1, 5H T6, 5C T10, TH T3, TC T6, TH T9, JC T3, JH T6, JS T9, QH T2, KS T1, JC T6, QC T1, 3S T2, 8C T1, 3S T6, 2S T6, 2D T4, 4D T3, 4S T4, 6S T9, 7D T1, 4D T4, 5D T3, 2H T4, 3H T2, 6C T1, 5C T1, 5D T10, 6C T2, 6D T1, 6C T10, 7D T2, 7C T1, 7D T10, JS T2, JD T9, JS T10, QC T2, QS T1, QD T10, QC T9"

test("simple simon deals ten columns and plays deal #1 to the win overlay", async ({ page }) => {
  test.setTimeout(180_000)
  await page.goto("/?game=simplesimon&seed=1&animate=off")
  await settle(page)

  // The board `Game.res` describes: four foundations and ten cascades, no cells,
  // and the whole pack dealt face up across the columns.
  await expect(page.locator(".drop-zone")).toHaveCount(14)
  expect(Game.simpleSimon.piles.length).toBe(14)
  await expect(page.locator(".stacking-card")).toHaveCount(52)
  await expect(page.locator(".drop-zone__slot--cell")).toHaveCount(0)

  await playLine(page, Game.simpleSimon, LINE)

  // The last drag completes the fourth run; collecting it is the win, so the overlay
  // rises without a Finish button ever appearing.
  await expect(page.locator(".win-overlay")).toBeVisible()
  await expect(page.getByRole("button", { name: "Finish" })).toHaveCount(0)
})
