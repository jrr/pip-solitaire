// Spiderette, in a real browser: the first board with a stock and cards lying face
// down. `Core_test` holds the rules — what a deal drops, what a face-down card refuses,
// which move turns it over. What only a browser can say is that a tap on the stock is
// what deals, that a back is drawn where the snapshot says one lies and the card under
// it is not announced, that a drag exposing a face-down card turns it up on screen,
// and that a run completed by a drag flies home and raises the overlay.
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

// The stock's top card is the one the board announces — reflow takes a squared pile's
// covered cards out of the accessible tree — so it is the one to tap.
async function tapStock(page) {
  const top = page.locator('.stacking-card--stock:not([aria-hidden="true"])')
  await expect(top).toHaveCount(1)
  const box = await top.boundingBox()
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
  await settle(page)
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
  for (const left of [17, 10, 3, 0]) {
    await tapStock(page)
    await expect(stock(page)).toHaveCount(left)
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
