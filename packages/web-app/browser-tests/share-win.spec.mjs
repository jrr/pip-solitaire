// The win overlay's Share button, end to end (#264).
//
// What the feature promises is a *boast that's also an invitation*: when you win, the
// button hands over a message naming the deal you beat and a link that deals that same
// board to whoever reads it. The unit tests pin each half — the message's wording
// (`ShareLink_test`), the board offering the button only when there's a deal to name
// (`TableScene_test`), and the deal that the almost-won position descends from
// (`Scenario_test`) — but the three only meet in a real browser, which is also the
// only place with a clipboard for the link to land on.
//
// `?state=almost-won` is the way in, and it's honest rather than a test fixture: that
// scenario carries deal **264**, proved by replaying the line through the reducer in
// `Scenario_test`. So the link this test reads off the clipboard really does deal the
// board the position came from — which is the property being checked.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

// The deal `Scenario`'s almost-won position was played from.
const ALMOST_WON_DEAL = "264"

test.use({
  viewport: { width: 800, height: 1000 },
  // Headless Chromium has no OS share sheet, so `ShareLink.deliver` falls through to
  // the clipboard — the path under test, and reading it back needs the grant.
  permissions: ["clipboard-read", "clipboard-write"],
})

// Play the single winning move: the pending King rests alone in the first free cell
// (drop zone 0) and its foundation is the last zone (4 cells, then 4 foundations,
// Clubs last). The same drag `win.spec.mjs` makes, by mouse.
async function playTheWinningMove(page) {
  const cell = page.locator(".drop-zone").nth(0)
  const foundation = page.locator(".drop-zone").nth(7)
  await settleBoard(page)
  await expect(foundation).toBeVisible()

  const cellBox = await cell.boundingBox()
  const foundationBox = await foundation.boundingBox()
  const from = { x: cellBox.x + cellBox.width / 2, y: cellBox.y + cellBox.height / 2 }
  const to = {
    x: foundationBox.x + foundationBox.width / 2,
    y: foundationBox.y + foundationBox.height / 2,
  }

  await page.mouse.move(from.x, from.y)
  await page.mouse.down()
  for (let i = 1; i <= 6; i++) {
    await page.mouse.move(from.x + ((to.x - from.x) * i) / 6, from.y + ((to.y - from.y) * i) / 6)
  }
  await page.mouse.up()
}

const shareButton = (page) => page.locator(".win-panel__button--share")
const shareStatus = (page) => page.locator(".win-panel__status")

// The board's card layout as plain data, for checking that a link reopens the deal it
// names. Sorted, because DOM order follows z-stacking rather than layout.
async function readBoard(page) {
  return await page.evaluate(() =>
    [...document.querySelectorAll(".stacking-card")]
      .map((card) => {
        const art = card.querySelector("[aria-label]")
        const { left, top } = getComputedStyle(card)
        return `${art?.getAttribute("aria-label") ?? "?"} @ ${left},${top}`
      })
      .sort(),
  )
}

test("a won game shares the deal it came from, and that link deals it", async ({ page }) => {
  // What deal 264 actually lays out, for the round trip at the end.
  await page.goto(`/?seed=${ALMOST_WON_DEAL}&animate=off`)
  await settleBoard(page)
  const dealt = await readBoard(page)
  expect(dealt.length).toBe(52)

  await page.goto("/?game=freecell&state=almost-won&animate=off")
  await playTheWinningMove(page)
  await expect(page.locator(".win-overlay")).toHaveCount(1)

  // The status line is present but empty before the press, holding its height so the
  // confirmation lands without pushing the buttons around — the same reserved slot the
  // menu's share line uses.
  await expect(shareStatus(page)).toHaveText("")
  const before = await shareStatus(page).boundingBox()

  await shareButton(page).click()
  await expect(shareStatus(page)).toHaveText("Link copied to clipboard.")
  expect((await shareStatus(page).boundingBox()).height).toBe(before.height)

  const shared = await page.evaluate(() => navigator.clipboard.readText())

  // The message: the suits that make it recognisable in a chat, the game it was won on
  // and the deal that was beaten, and what it cost — one move, since a forced position
  // starts a fresh tally (#289). No undos were used, so the message says nothing about
  // them. The game's name is read off the game since #353, not spelled into the string,
  // so what's checked here is that the board on the table is the one being named.
  expect(shared).toContain(`♣️♥️♠️♦️ Pip FreeCell #${ALMOST_WON_DEAL}`)
  expect(shared).toContain("Solved in 1 move")
  expect(shared).not.toContain("undo")

  // …and the link. It has to be the *deal*, not the position: a link to the board as
  // it stands would hand the recipient a solved game, which is the one thing this share
  // must never do. It's the same link the menu's Share Seed builds, down to leaving
  // `?game=` out for the default game (#353) — one function builds both.
  const url = new URL(shared.slice(shared.indexOf("http")))
  expect(url.searchParams.get("seed")).toBe(ALMOST_WON_DEAL)
  expect(url.searchParams.get("game")).toBe(null)
  expect(url.search).toBe(`?seed=${ALMOST_WON_DEAL}`)
  expect(url.hash).toBe("")

  // The round trip, as the recipient makes it: the link deals the board the sender's
  // position was played from, unplayed.
  await page.goto(url.toString())
  await settleBoard(page)
  await expect(page.locator(".win-overlay")).toHaveCount(0)
  expect(await readBoard(page)).toEqual(dealt)
})

test("the deal it hands over reads the same spelled out in full", async ({ page }) => {
  // The other half of #353, from the victory share's side: the link is short because
  // FreeCell is the game a nameless deal number belongs to, not because a deal number
  // can only mean FreeCell. Spelled out — `?game=freecell&seed=264`, the shape a
  // *second* game's link would take — it opens the very same board, so the two forms
  // are one link and the short one is a shortening.
  await page.goto(`/?seed=${ALMOST_WON_DEAL}&animate=off`)
  await settleBoard(page)
  const bare = await readBoard(page)

  await page.goto(`/?game=freecell&seed=${ALMOST_WON_DEAL}&animate=off`)
  await settleBoard(page)
  expect(await readBoard(page)).toEqual(bare)

  // …and the board that opened names deal 264 back, so the round trip closes on a game
  // that knows which deal it is rather than merely on identical card positions.
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.getByRole("button", { name: /^Share Seed/ })).toHaveText(
    `Share Seed ${ALMOST_WON_DEAL}`,
  )
})

test("a scenario with no deal behind it offers no share", async ({ page }) => {
  // Only `almost-won` has had a line to it proved (`Scenario_test`); the rest are posed
  // layouts with no established provenance, and a board with no deal to name offers no
  // Share button rather than guessing at one. `midgame` stands in for all of them — it
  // can't be won, so this checks the menu's Share Seed, which reads the same number.
  await page.goto("/?game=freecell&state=midgame&animate=off")
  await settleBoard(page)

  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.getByRole("button", { name: "Share Seed", exact: true })).toBeDisabled()
  await expect(page.locator(".menu-share-line")).toHaveText("No seed for this board.")
})

test("the almost-won board names its deal on the menu too", async ({ page }) => {
  // Both share buttons read the same number, so the menu is where it can be seen
  // without winning first.
  await page.goto("/?game=freecell&state=almost-won&animate=off")
  await settleBoard(page)

  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.getByRole("button", { name: /^Share Seed/ })).toHaveText(
    `Share Seed ${ALMOST_WON_DEAL}`,
  )
})
