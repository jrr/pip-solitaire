// The share link, round-tripped through a real browser (`ShareLink`).
//
// Browser-only by necessity. The unit tests (`Compression_test`, `ShareLink_test`)
// already pin the codec and prove a whole `History.t` survives the encoding — that
// part is exact, and jsdom can host it. What only a real engine has is the rest of
// the path: a real clipboard to write the URL into, real fragment navigation to
// carry it, and `SaveState` decoding into a board that actually lays cards out.
//
// So the check here is the plumbing end to end, as a player would use it: take a
// board, share it, then open the resulting link cold and confirm the same position
// comes back — card for card, in the same place.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({
  viewport: { width: 800, height: 1000 },
  // The share row falls back to the clipboard when the platform has no OS share
  // sheet, which is the case in headless Chromium — so that's the path under test,
  // and reading the result back needs the grant.
  permissions: ["clipboard-read", "clipboard-write"],
})

// A fixed, non-trivial starting position, so "the same board came back" is a claim
// with content — a fresh random deal would also match itself.
const MIDGAME = "/?scene=freecell&state=midgame&animate=off"

// The board as comparable data: every card by name, with where it came to rest.
// Cards are absolutely positioned siblings rather than children of their zones, so
// the resting coordinates *are* the pile structure; the viewport is fixed, which
// makes them stable across loads. The name comes off the card art's `aria-label`
// (`Deck.cardName`), so this compares the actual deck rather than pixels alone.
// Sorted, because DOM order follows z-stacking rather than layout.
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

// Walk the menu down to the Debug screen, which is where the share row lives.
async function openDebugScreen(page) {
  await page.getByRole("button", { name: "Open menu" }).click()
  await page.getByRole("button", { name: "Settings" }).click()
  await page.getByRole("button", { name: "Debug" }).first().click()
  return page.getByRole("button", { name: /Share game state/ })
}

// Press "Share game state" and hand back the URL it put on the clipboard.
async function shareFromDebugScreen(page) {
  const share = await openDebugScreen(page)
  // The link is encoded when the screen opens, not on the press — the row stays
  // disabled until that resolves, so waiting for it to enable is also the assertion
  // that the encode succeeded.
  await expect(share).toBeEnabled()
  await share.click()
  await expect(page.getByText("Link copied to clipboard.")).toBeVisible()
  return await page.evaluate(() => navigator.clipboard.readText())
}

test("a shared link reopens the same board", async ({ page }) => {
  await page.goto(MIDGAME)
  await settleBoard(page)
  const shared = await readBoard(page)
  // The premise: this position actually has a boardful of cards to compare.
  expect(shared.length).toBe(52)

  const url = await shareFromDebugScreen(page)
  expect(url).toContain("#g=")
  // The payload rides in the fragment, so none of the board reaches the server —
  // which is what keeps it clear of any request-line limit.
  expect(new URL(url).search).toBe("")

  // Open the link cold, as a recipient would: a fresh load with no query pinning
  // the deal, and none of the first page's state.
  await page.goto(url)
  await settleBoard(page)
  expect(await readBoard(page)).toEqual(shared)
})

test("a corrupt link opens a playable board instead of failing", async ({ page }) => {
  // Links get truncated in chat clients and mangled in mail. The contract is that a
  // bad blob is ignored — the app deals a normal game rather than showing nothing.
  await page.goto("/#g=this-is-not-a-real-blob")
  await settleBoard(page)
  expect((await readBoard(page)).length).toBe(52)
})

test("the share row is disabled on a scene with no game", async ({ page }) => {
  // A demo scene publishes no history hooks, so there's nothing to encode and the
  // row must say so rather than offering a link to a board that doesn't exist.
  await page.goto("/?scene=spinner")
  const share = await openDebugScreen(page)
  await expect(share).toBeDisabled()
  await expect(page.getByText("No game on screen to share.")).toBeVisible()
})
