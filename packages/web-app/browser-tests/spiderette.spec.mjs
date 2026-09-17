// Spiderette, in a real browser: the first board with a stock and cards lying face
// down. `Core_test` holds the rules — what a deal drops, what a face-down card refuses,
// which move turns it over. What only a browser can say is that a tap on the stock is
// what deals, that a refused tap says on the board which column refused it, that a back
// is drawn where the snapshot says one lies and the card under it is not announced, that
// a drag exposing a face-down card turns it up on screen, and that a run completed by a
// drag flies home and raises the overlay.
//
// The deal is played from `seed=1`, so the taps land on the same board every run; the
// exposing move is found against `core`'s own reducer from that same deal rather than
// recorded, so the test says which card it expects to see turned over.

import { expect, test } from "@playwright/test"
import { assignPiles, readGeometry, settle } from "../scripts/autoplay/read-board.mjs"
import { drag, moveOf } from "./lib/play-line.mjs"
import { quietWin } from "./lib/board.mjs"
import * as Game from "core/src/Game.res.mjs"
import * as GameState from "core/src/GameState.res.mjs"
import * as Reducer from "core/src/Reducer.res.mjs"
import * as CardText from "core/src/CardText.res.mjs"
import * as Scenario from "core/src/Scenario.res.mjs"

test.use({ viewport: { width: 900, height: 1100 } })
test.use(quietWin)

const RANK_WORDS = ["ace", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "jack", "queen", "king"]
const SUIT_WORDS = { Spades: "spades", Hearts: "hearts", Diamonds: "diamonds", Clubs: "clubs" }
const RANKS = ["Ace", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King"]
// `Deck.cardName`'s prose for a core card, so a test can name the card it expects to
// see turned over.
const nameOf = (card) => `${RANK_WORDS[RANKS.indexOf(card.rank)]} of ${SUIT_WORDS[card.suit]}`

const backs = (page) => page.locator(".stacking-card--down")
const stock = (page) => page.locator(".stacking-card--stock")
// The columns flashing at a deal they refused (`TableScene.css`'s `--refused`).
const refused = (page) => page.locator(".drop-zone--refused")

// The stock's top card is the one the board announces — reflow takes a squared pile's
// covered cards out of the accessible tree — so it is the one to tap.
async function tapStock(page) {
  const top = page.locator('.stacking-card--stock:not([aria-hidden="true"])')
  await expect(top).toHaveCount(1)
  await tapCentre(page, top)
}

// A tap in the middle of whatever `what` is. By coordinates rather than `locator.click`,
// since the slots below are `pointer-events: none` — the `.drop-zone` around them is the
// board's hit-test box — and a tap on a slot is exactly a tap a player aims there.
async function tapCentre(page, what) {
  const box = await what.boundingBox()
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
  await settle(page)
}

// Watch for the refusal flash rather than sampling for it: the class takes itself off
// when its animation ends, so a check that looked at the board afterwards would be
// racing a deliberately short-lived thing. Returns a reader of the zones it has landed
// on since (`{clear: true}` to start it over), each named by its pile index — zones are
// in the document in the board's own pile order, which is what `read-board.mjs` reads
// them by too.
async function watchFlashes(page) {
  await page.evaluate(() => {
    const zones = [...document.querySelectorAll(".drop-zone")]
    globalThis.flashed = new Set()
    new MutationObserver(() =>
      zones.forEach((el, i) => {
        if (el.classList.contains("drop-zone--refused")) globalThis.flashed.add(i)
      }),
    ).observe(document.body, { subtree: true, attributes: true, attributeFilter: ["class"] })
  })
  return async ({ clear = false } = {}) =>
    page.evaluate((reset) => {
      const seen = [...globalThis.flashed].sort((a, b) => a - b)
      if (reset) globalThis.flashed.clear()
      return seen
    }, clear)
}

test("spiderette turns a card over when it is exposed, and deals its stock by tap", async ({ page }) => {
  const game = Game.spideretteDeal(1)
  const cascades = Game.pileIndices(game, "Cascade")
  await page.goto("/?game=spiderette&seed=1&animate=off")
  await settle(page)

  // The board `Game.res` describes: a stock, four foundations, seven columns, and
  // forty-five of the fifty-two cards showing their backs — none of them named.
  await expect(page.locator(".drop-zone")).toHaveCount(12)
  expect(game.piles.length).toBe(12)
  await expect(page.locator(".stacking-card")).toHaveCount(52)
  await expect(page.locator(".drop-zone__slot--stock")).toHaveCount(1)
  await expect(backs(page)).toHaveCount(45)
  await expect(page.locator('.stacking-card--down .card-art[aria-label="face-down card"]')).toHaveCount(45)
  await expect(stock(page)).toHaveCount(24)

  // At the opening every column shows one card, so a top card another column will
  // take is lying on a face-down one: dragging it turns the card beneath over, and the
  // board says so by name. Found against core's reducer from the same deal. The pack
  // is two suits taken twice, so a name can be on the table twice: the dragged card is
  // one whose twin still lies face down, so the drag names one card.
  let state = GameState.initial(game)
  const faceUpTwin = (card) =>
    state.piles.flat().some(
      (c) => GameState.sameFace(c, card) && !GameState.sameCard(c, card) && !GameState.isFaceDown(state, c),
    )
  let move = null
  for (const from of cascades) {
    const cards = GameState.cardsInPile(state, from)
    if (cards.length < 2 || GameState.faceDownIn(state, from) !== cards.length - 1) continue
    const top = cards[cards.length - 1]
    if (faceUpTwin(top)) continue
    const to = cascades.find((i) => i !== from && Reducer.canDrop(game, state, top, i))
    if (to !== undefined) {
      move = { card: top, to, exposed: cards[cards.length - 2] }
      break
    }
  }
  expect(move, "deal #1 opens with a move that turns a card over").not.toBeNull()
  // The exposed card's twin may already be showing; what the flip adds is one more.
  const named = page.locator(`.card-art[aria-label="${nameOf(move.exposed)}"]`)
  const twinsShowing = faceUpTwin(move.exposed) ? 1 : 0
  await expect(named).toHaveCount(twinsShowing)
  await drag(page, { card: CardText.format(move.card), to: move.to })
  await settle(page)
  await expect(backs(page)).toHaveCount(44)
  await expect(named).toHaveCount(twinsShowing + 1)
  await expect(page.locator(`.stacking-card:not(.stacking-card--down) .card-art[aria-label="${nameOf(move.exposed)}"]`)).toHaveCount(twinsShowing + 1)
  state = Reducer.reduce(game, state, { TAG: "Move", card: move.card, to: { TAG: "ToPile", _0: move.to } })._0

  // Four taps: seven, seven, seven, then the last three onto the first three columns.
  // A deal the board accepts says nothing beyond dealing: no column is at fault.
  for (const left of [17, 10, 3, 0]) {
    await tapStock(page)
    await expect(stock(page)).toHaveCount(left)
    await expect(refused(page)).toHaveCount(0)
    state = Reducer.reduce(game, state, "Deal")._0
  }
  await expect(backs(page)).toHaveCount(20)
  const piles = assignPiles(await readGeometry(page))
  const expected = cascades.map((i) => GameState.cardsInPile(state, i).length)
  expect(expected.reduce((a, b) => a + b, 0)).toBe(52)
  expect(cascades.map((i) => piles[i].length)).toEqual(expected)
  // Nothing left to tap: the stock is empty, and its slot shows.
  await expect(page.locator('.stacking-card--stock')).toHaveCount(0)
})

// The refused deal, which is a rule a player can only learn from the board: the Spider
// family won't deal a row while a column stands empty, and the tap that does nothing is
// otherwise a tap that missed. `Core_test` has the rule and `Scenario_test` the posed
// position; what only a browser can say is which slots go red, that they stop, and that
// the board is otherwise exactly where it was.
test.describe("a deal refused by an empty column", () => {
  test("flashes every empty column, and nothing else", async ({ page }) => {
    const game = Game.spiderette
    const cascades = Game.pileIndices(game, "Cascade")
    await page.goto("/?game=spiderette&state=stuck&animate=off")
    await settle(page)

    // Two columns empty with the stock still full — the second and the fifth, so a
    // flash on "every empty column" can't pass as a flash on the first one found.
    const state = Scenario.forName(game, "stuck")
    const empty = cascades.filter((i) => GameState.cardsInPile(state, i).length === 0)
    expect(empty).toEqual([cascades[1], cascades[4]])
    await expect(stock(page)).toHaveCount(24)
    await expect(refused(page)).toHaveCount(0)

    const flashed = await watchFlashes(page)
    await tapStock(page)
    // The empty columns, and only them: not the stock, which is willing, and not a
    // column that holds cards.
    expect(await flashed()).toEqual(empty)

    // Refused means refused: no card moved, and the stock still holds all twenty-four.
    await expect(stock(page)).toHaveCount(24)
    const piles = assignPiles(await readGeometry(page))
    expect(cascades.map((i) => piles[i].length)).toEqual(
      cascades.map((i) => GameState.cardsInPile(state, i).length),
    )

    // The flash plays out and takes itself off, so the board comes back to rest — and
    // the next refused tap flashes again rather than going quiet.
    await expect(refused(page)).toHaveCount(0)
    await flashed({ clear: true })
    await tapStock(page)
    expect(await flashed()).toEqual(empty)
  })

  test("says nothing on a board whose stock is empty", async ({ page }) => {
    // Every run collected but the last: five columns stand empty and the stock is out,
    // so the deal is refused for a reason no column is to blame for — and there is no
    // stock card left to tap in the first place.
    await page.goto("/?game=spiderette&state=almost-won&animate=off")
    await settle(page)
    await expect(stock(page)).toHaveCount(0)
    const flashed = await watchFlashes(page)
    await tapCentre(page, page.locator(".drop-zone__slot--stock"))
    expect(await flashed()).toEqual([])
  })

  test("says nothing on a game that has no stock", async ({ page }) => {
    // FreeCell deals no rows, so nothing on its board can refuse one — including the
    // empty free cells and foundations, which look like the empty columns that do.
    await page.goto("/?game=freecell&animate=off")
    await settle(page)
    await expect(page.locator(".drop-zone__slot--stock")).toHaveCount(0)
    const flashed = await watchFlashes(page)
    await tapCentre(page, page.locator(".drop-zone__slot--cell").first())
    await tapCentre(page, page.locator(".drop-zone__slot--foundation").first())
    expect(await flashed()).toEqual([])
  })
})

test("a drag that completes the last run flies it home and wins", async ({ page }) => {
  await page.goto("/?game=spiderette&state=almost-won&animate=off")
  await settle(page)
  await expect(page.locator(".win-overlay")).toHaveCount(0)
  // The Ace alone on the second column: the last run's, whose face is also on top of a
  // collected run — the drag takes the copy a hand can lift.
  const ace = GameState.topOf(Scenario.spideretteAlmostWon(Game.spiderette), Game.pileIndices(Game.spiderette, "Cascade")[1])
  await drag(page, moveOf(Game.spiderette, `${CardText.format(ace)} T1`))
  await settle(page)
  // The run is collected on its own — nothing to finish — and the overlay rises.
  await expect(page.locator(".win-overlay")).toBeVisible()
  await expect(page.getByRole("button", { name: "Finish" })).toHaveCount(0)
})

// The deep column, in a window too short for it: the fan is compressed to stay on the
// board (`geometry.spec.mjs` measures it), and what has to still hold is that its zone
// grew with it — a drop on the last card of twenty lands, rather than falling short
// of a hit-test box that ended where the uncompressed fan would have.
test.describe("a compressed column", () => {
  test.use({ viewport: { width: 1280, height: 720 } })

  test("takes a drop on its last card", async ({ page }) => {
    const game = Game.spiderette
    const cascades = Game.pileIndices(game, "Cascade")
    await page.goto("/?game=spiderette&state=deep&animate=off")
    await settle(page)
    const before = assignPiles(await readGeometry(page))
    expect(before[cascades[0]].length).toBe(20)
    // The Hearts Ace on top of the second column, onto the Spades Two ending the first.
    const ace = GameState.topOf(Scenario.spideretteDeep(game), cascades[1])
    expect(ace.rank).toBe("Ace")
    await drag(page, moveOf(game, `${CardText.format(ace)} T1`))
    await settle(page)
    const after = assignPiles(await readGeometry(page))
    expect(after[cascades[0]].length).toBe(21)
    expect(after[cascades[0]][20].name).toBe(nameOf(ace))
    expect(after[cascades[1]].length).toBe(before[cascades[1]].length - 1)
    // A run of the other suit isn't completed by it: nothing flew home.
    await expect(page.locator(".stacking-card")).toHaveCount(52)
    await expect(page.locator(".win-overlay")).toHaveCount(0)
  })
})
