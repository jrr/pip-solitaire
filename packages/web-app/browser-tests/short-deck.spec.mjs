// The short-deck boards, played to the win overlay in a real browser.
//
// `mini` and `micro` are FreeCell in every mechanic and differ only in deck and
// shape, and the claim that costs them nothing but two values in `Game.res` is
// exactly that: the view, the reducer and the rules all read the board rather than
// assume FreeCell's. Nothing short of playing one proves that end to end — a unit
// test asserts the `Game.t`, not that six-across zones lay out, that a drag lands
// where the hit-test says, that auto-collect stops on a five-rank foundation, or
// that a two-suit board can be won at all.
//
// So each is played here the way a player would: real pointer drags on the rendered
// board, no reaching into game state (`lib/play-line.mjs`). The line runs to the point
// the board is finishable (`Reducer.canFinish`), which is where the app takes over with
// its Finish button, same as `autoplay.spec.mjs` does for FreeCell.
//
// If a line ever stops working the failure is loud and specific: either a drag
// bounces and the Finish button never appears, or the overlay doesn't.

import { expect, test } from "@playwright/test"
import { settle } from "../scripts/autoplay/read-board.mjs"
import { playLine } from "./lib/play-line.mjs"
import * as Game from "core/src/Game.res.mjs"

test.use({ viewport: { width: 900, height: 1100 } })

const BOARDS = [
  {
    id: "mini",
    game: Game.mini,
    zones: 10, // 2 cells + 4 foundations + 4 cascades
    line: "2D C1, 5D C2, 2D T3, 5S C1, 3S F2, 3C F1, 4H T1, 4D T4, 5H T2, 4S F2, 4C F1, 5S F2, 4H C1",
  },
  {
    id: "micro",
    game: Game.micro,
    zones: 8, // 2 cells + 2 foundations + 4 cascades
    line: "2S T3, 2H C1, 6S C2, 8H C1, 5S T1, 4H F1, 5H F1, 6H F1, 8S T4",
  },
]

for (const { id, game, zones, line } of BOARDS) {
  test(`${id} deals its own shape and plays to the win overlay`, async ({ page }) => {
    await page.goto(`/?game=${id}&seed=1&animate=off`)
    await settle(page)

    // The board the app laid out is the one `Game.res` describes — every pile
    // rendered, and its own short deck dealt, rather than FreeCell's sixteen and 52.
    await expect(page.locator(".drop-zone")).toHaveCount(zones)
    expect(zones).toBe(game.piles.length)
    await expect(page.locator(".stacking-card")).toHaveCount(
      game.piles.reduce((n, p) => n + p.cards.length, 0),
    )

    await playLine(page, game, line)

    // From here the game is decided: auto-collect has stood aside and the Finish
    // button plays the rest home.
    await page.getByRole("button", { name: "Finish" }).click()
    await expect(page.locator(".win-overlay")).toBeVisible()
  })
}
