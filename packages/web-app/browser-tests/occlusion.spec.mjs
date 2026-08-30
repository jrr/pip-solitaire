// What a squared pile announces. Every card is a `role="img"`
// carrying the card's name (`CardArt` via `Deck.cardName`), and a `Squared` pile
// — the free cells and the foundations — draws its whole contents on one spot. So
// the covered cards were named to a screen reader as if they were on the table:
// six of the fifty-two mid-game, and forty-eight on a won board that shows four.
// Reflow now marks them `aria-hidden`.
//
// This belongs in the browser suite because the claim is about the *accessibility
// tree*, not about an attribute: `getByRole` resolves roles the way a browser
// does, so it counts what would actually be announced — and would keep counting a
// card that some later change put back in the tree by another route.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

// The cards a screen reader would be read: every `role="img"` inside the board,
// minus whatever `aria-hidden` takes out of the tree. Scoped to the cards so the
// chrome's own graphics can never be counted here.
const announcedCards = (page) => page.locator(".stacking-card").getByRole("img")

// `animate=off` skips the opening fly-in (see AppUrl), so the board is at its
// resting layout as soon as the cards exist.
test("a mid-game board announces only the cards it shows", async ({ page }) => {
  await page.goto("/?game=freecell&state=midgame&animate=off")
  await settleBoard(page)

  // All 52 are on the board...
  await expect(page.locator(".stacking-card")).toHaveCount(52)
  // ...but six of them aren't: the mid-game snapshot builds its foundations three,
  // four and two high (`Scenario.freecellMidgame`), which is nine cards showing
  // three tops. Nothing else on this board occludes anything — the cells hold one
  // card each and the cascades are fanned, every card of them still announced —
  // so the whole difference is those six.
  await expect(page.locator('.stacking-card[aria-hidden="true"]')).toHaveCount(6)
  await expect(announcedCards(page)).toHaveCount(46)
})

test("the win screen announces four cards, not fifty-two", async ({ page }) => {
  // One move short of a win, so the Finish shortcut is on offer: tapping it
  // sends every remaining card home and raises the overlay over four full
  // foundations — the whole deck, stacked into four visible cards.
  await page.goto("/?game=freecell&state=almost-won&animate=off")
  await settleBoard(page)

  await page.getByRole("button", { name: "Finish" }).click()
  await expect(page.locator(".win-overlay")).toHaveCount(1)
  await settleBoard(page)

  await expect(page.locator(".stacking-card")).toHaveCount(52)
  await expect(announcedCards(page)).toHaveCount(4)
})
