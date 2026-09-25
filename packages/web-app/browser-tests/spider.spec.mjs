// Spider, in a real browser: Spiderette's board on two packs. `Core_test` holds the
// rules — the counts, the five rows in the stock, the eight runs. What only a browser
// can say is that a hundred and four cards lay out on the stage at all, with the
// opening's backs where the snapshot says and the stock a tap deals from until it is
// out; the compressed column is judged on Spiderette (`spiderette.spec.mjs`) and Spider
// is laid out by the same fan. And that a press on a column's backs picks up the run
// below them, which only a pointer on a laid-out fan can try.
//
// The deal is played from `seed=1`, so every tap lands on the same board.

import { expect, test } from "@playwright/test"
import { assignPiles, cardCodeOf, readGeometry, settle } from "../scripts/autoplay/read-board.mjs"
import * as Command from "core/src/Command.res.mjs"
import * as Game from "core/src/Game.res.mjs"
import * as CardText from "core/src/CardText.res.mjs"
import * as Scenario from "core/src/Scenario.res.mjs"
import * as GameState from "core/src/GameState.res.mjs"

test.use({ viewport: { width: 1280, height: 900 } })

const cards = (page) => page.locator(".stacking-card")
const stock = (page) => page.locator(".stacking-card--stock")
const backs = (page) => page.locator(".stacking-card--down:not(.stacking-card--stock)")

// The stock's top card is the one the board announces — reflow takes a squared pile's
// covered cards out of the accessible tree — so it is the one to tap.
async function tapStock(page) {
  const top = page.locator('.stacking-card--stock:not([aria-hidden="true"])')
  await expect(top).toHaveCount(1)
  const box = await top.boundingBox()
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
  await settle(page)
}

test("deals 54 cards with only the tops up, and the stock deals its five rows by tap", async ({
  page,
}) => {
  await page.goto("/?game=spider&seed=1&animate=off")
  await settle(page)
  await expect(cards(page)).toHaveCount(104)
  await expect(page.locator(".drop-zone")).toHaveCount(19)
  await expect(stock(page)).toHaveCount(50)
  // Six and five to a column, all but the top face down: 44 backs on the tableau.
  await expect(backs(page)).toHaveCount(44)

  // Every tap drops a row of ten; the fifth empties the stock, and its slot shows.
  for (let row = 1; row <= 5; row++) {
    await tapStock(page)
    await expect(stock(page)).toHaveCount(50 - 10 * row)
  }
  await expect(page.locator(".drop-zone__slot--stock")).toBeVisible()
  // Dealt cards land face up, over the backs the opening left.
  await expect(backs(page)).toHaveCount(44)
  await expect(cards(page)).toHaveCount(104)
})

// A cascade's backs are a handle for the run the column shows: a press on one lifts
// what `moverun` would off that place (`Command.runShowing`), onto the back that was
// pressed, so the drop lands where the finger aims rather than a fan-step below it.
test.describe("a press on a column's backs", () => {
  const game = Game.spider
  const cascades = Game.pileIndices(game, "Cascade")
  const posed = Scenario.spideretteDeep(game)
  const headOf = (i) => Command.runShowing(game, posed, i)
  // Where a hand presses a back: the middle of the strip the next card leaves showing.
  const pressOn = (pile, idx) => {
    const card = pile[idx]
    return { x: card.cx, y: card.y + Math.min((pile[idx + 1].y - card.y) / 2, card.h / 2) }
  }

  test.beforeEach(async ({ page }) => {
    await page.goto("/?game=spider&state=deep&animate=off")
    await settle(page)
  })

  test("carries the run of twelve under the six backs, from under the finger", async ({ page }) => {
    const run = headOf(cascades[0])
    expect(run.length).toBe(12)
    const deep = assignPiles(await readGeometry(page))[cascades[0]]
    expect(deep.slice(0, 6).every((c) => c.name === "face-down card")).toBe(true)
    const back = deep[2]
    const at = pressOn(deep, 2)

    await page.mouse.move(at.x, at.y)
    await page.mouse.down()
    for (let i = 1; i <= 4; i++) await page.mouse.move(at.x + 10 * i, at.y)
    const dragging = page.locator(".stacking-card.dragging")
    await expect(dragging).toHaveCount(12)
    // The head sits where the pressed back does, moved only as far as the pointer.
    const carried = await readGeometry(page)
    const head = carried.cards.find((c) => cardCodeOf(c.name) === CardText.format(run[0]))
    expect(Math.abs(head.cy - back.cy)).toBeLessThan(6)
    expect(Math.abs(head.cx - (back.cx + 40))).toBeLessThan(6)
    // Released over its own column, the run goes back where it lay.
    await page.mouse.up()
    await settle(page)
    await expect(dragging).toHaveCount(0)
    const after = assignPiles(await readGeometry(page))[cascades[0]]
    expect(after.map((c) => c.name)).toEqual(deep.map((c) => c.name))
  })

  test("drops a run of one where the finger aims, as a press on the card itself would", async ({
    page,
  }) => {
    // The second column's head is the Ace alone, and the first column ends in a Two.
    const run = headOf(cascades[1])
    expect(run.map(CardText.format)).toEqual([CardText.format(GameState.topOf(posed, cascades[1]))])
    const geom = await readGeometry(page)
    const piles = assignPiles(geom)
    const column = piles[cascades[1]]
    expect(column[0].name).toBe("face-down card")
    const at = pressOn(column, 0)
    // The Ace arrives on the back, so the finger holds it where it held the back.
    const target = geom.zones[cascades[0]]
    const aim = { x: target.cx, y: target.cy - (column[0].cy - at.y) }

    await page.mouse.move(at.x, at.y)
    await page.mouse.down()
    for (let i = 1; i <= 8; i++) {
      await page.mouse.move(at.x + ((aim.x - at.x) * i) / 8, at.y + ((aim.y - at.y) * i) / 8)
    }
    await expect(page.locator(".drop-zone--over")).toHaveCount(1)
    await page.mouse.up()
    await settle(page)

    const after = assignPiles(await readGeometry(page))
    expect(after[cascades[0]].length).toBe(piles[cascades[0]].length + 1)
    expect(cardCodeOf(after[cascades[0]].at(-1).name)).toBe(CardText.format(run[0]))
    expect(after[cascades[1]].length).toBe(column.length - 1)
  })
})
