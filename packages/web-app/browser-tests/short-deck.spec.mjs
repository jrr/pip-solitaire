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
// board, no reaching into game state. The moves are a **recorded line** rather than a
// search — deals are deterministic, so deal #1 of each is the same board every time,
// and a fixed script keeps this a check on the app rather than a second solver. The
// line runs to the point the board is finishable (`Reducer.canFinish`), which is where
// the app takes over with its Finish button, same as `autoplay.spec.mjs` does for
// FreeCell.
//
// If a line ever stops working the failure is loud and specific: either a drag
// bounces and the Finish button never appears, or the overlay doesn't.

import { expect, test } from "@playwright/test"
import { assignPiles, parseCardName, readGeometry, settle } from "../scripts/autoplay/read-board.mjs"
import * as Game from "core/src/Game.res.mjs"
import * as Slot from "core/src/Slot.res.mjs"

test.use({ viewport: { width: 900, height: 1100 } })

// Each move is `<card> <slot>` in the vocabulary the console and `Render` already
// speak (`CardText` codes, `Slot` labels) — so a line reads as moves rather than as
// pile indices, and the labels are resolved against the board through `Slot` itself.
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

/** A `<card> <slot>` move against a board: the card's code and the pile it lands in. */
function moveOf(game, text) {
  const [card, label] = text.trim().split(/\s+/)
  const slot = Slot.parse(label)
  if (!slot) throw new Error(`unparseable slot in "${text}"`)
  const to = Slot.indexOf(game, slot[0], slot[1])
  if (to === undefined) throw new Error(`${label} is not a slot on this board`)
  return { card, to }
}

/**
 * Where to press to pick a card up — the middle of whatever is actually exposed,
 * since a buried card in a fan shows only the sliver above the next one. The offset
 * from the card's centre comes back with it, because the drop is decided by the
 * *card's* rect and not the pointer's (both learned in `autoplay.mjs`, which
 * comments them at length).
 */
function grabPoint(piles, wanted) {
  for (const pile of piles) {
    const idx = pile.findIndex((c) => parseCardName(c.name) === wanted)
    if (idx < 0) continue
    const card = pile[idx]
    const next = pile[idx + 1]
    const y = next ? card.y + Math.min((next.y - card.y) / 2, card.h / 2) : card.cy
    return { x: card.cx, y, offsetY: card.cy - y }
  }
  throw new Error(`no card named ${wanted} on the board`)
}

/** One move, as a real pointer drag onto the zone at `to`. */
async function drag(page, { card, to }) {
  const geom = await readGeometry(page)
  const grab = grabPoint(assignPiles(geom), card)
  const zone = geom.zones[to]
  const target = { x: zone.cx, y: zone.cy - grab.offsetY }

  await page.mouse.move(grab.x, grab.y)
  await page.mouse.down()
  // Incremental moves rather than a jump, so `pointermove` fires and the hover
  // highlight tracks the drag the way it does under a real hand.
  for (let i = 1; i <= 8; i++) {
    const at = (from, t) => from + ((t - from) * i) / 8
    await page.mouse.move(at(grab.x, target.x), at(grab.y, target.y))
  }
  await page.mouse.up()
  await settle(page)
}

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

    for (const text of line.split(",")) await drag(page, moveOf(game, text))

    // From here the game is decided: auto-collect has stood aside and the Finish
    // button plays the rest home.
    await page.getByRole("button", { name: "Finish" }).click()
    await expect(page.locator(".win-overlay")).toBeVisible()
  })
}
