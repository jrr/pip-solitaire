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
//
// That includes *which board*: the blob names its game, and a link shared
// from Mini has to bring Mini's scene forward on a cold open rather than dropping a
// ten-pile position onto the sixteen-pile board the app launches into.

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
const MIDGAME = "/?game=freecell&state=midgame&animate=off"

// A board of a *different* game, for the half of the round trip that only a second game
// can ask: the blob names the game it was shared from, and the link has to open
// that game rather than whichever board the app happens to launch into. Deal #1 of Mini,
// so the position is fixed and its 20 cards are unmistakably not FreeCell's 52.
const MINI = "/?game=mini&seed=1&animate=off"

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

test("a shared link takes over the saved game", async ({ page }) => {
  // A shared game is adopted, not borrowed: it becomes this device's saved game, so
  // a later plain load resumes it. Checked by loading the bare URL afterwards —
  // no fragment, no query — which only ever shows a board if one was saved.
  await page.goto(MIDGAME)
  await settleBoard(page)
  const url = await shareFromDebugScreen(page)

  await page.goto(url)
  await settleBoard(page)
  const adopted = await readBoard(page)

  await page.goto("/")
  await settleBoard(page)
  expect(await readBoard(page)).toEqual(adopted)
})

test("a shared link opens the game it was shared from", async ({ page }) => {
  // The link carries the cards *and* the name of the board they belong to.
  // Nothing in the URL says which game — no `?game=`, only the fragment — so opening it
  // on Mini is the app reading the name out of the blob and bringing that scene forward.
  // Without the name the position lands on whatever was mounted, which is the FreeCell
  // the app launches into: 52 cards under a 20-card game's history.
  await page.goto(MINI)
  await settleBoard(page)
  const shared = await readBoard(page)
  expect(shared.length).toBe(20) // Mini's short deck — the premise of the test

  const url = await shareFromDebugScreen(page)
  expect(new URL(url).search).toBe("")

  await page.goto(url)
  await settleBoard(page)
  expect(await readBoard(page)).toEqual(shared)
})

test("a shared link takes over the save of the game it names, and no other", async ({ page }) => {
  // Adoption follows the name too: a link shared from Mini becomes this device's saved
  // *Mini* game, and leaves the game it launches into alone. `SavedGame` is keyed by
  // game id, so getting this wrong would file someone's Mini board under FreeCell.
  await page.goto(MINI)
  await settleBoard(page)
  const url = await shareFromDebugScreen(page)

  await page.goto(url)
  await settleBoard(page)
  const adopted = await readBoard(page)

  // A plain open of that game resumes what the link left…
  await page.goto("/?game=mini")
  await settleBoard(page)
  expect(await readBoard(page)).toEqual(adopted)

  // …and the default game's own save is untouched: FreeCell deals its own 52.
  await page.goto("/")
  await settleBoard(page)
  expect((await readBoard(page)).length).toBe(52)
})

test("a corrupt link leaves an existing saved game alone", async ({ page }) => {
  // The failure path must not cost the player their game: nothing landed, so nothing
  // is written, and the save that was there survives. Set one up by adopting a
  // shared board first, then open a broken link over the top of it.
  await page.goto(MIDGAME)
  await settleBoard(page)
  const url = await shareFromDebugScreen(page)
  await page.goto(url)
  await settleBoard(page)
  const saved = await readBoard(page)

  await page.goto("/#g=this-is-not-a-real-blob")
  await settleBoard(page)
  // The broken link deals a normal game rather than showing an error…
  expect((await readBoard(page)).length).toBe(52)

  // …and the game that was already saved is still there.
  await page.goto("/")
  await settleBoard(page)
  expect(await readBoard(page)).toEqual(saved)
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
  await page.goto("/?scene=gallery")
  const share = await openDebugScreen(page)
  await expect(share).toBeDisabled()
  await expect(page.getByText("No game on screen to share.")).toBeVisible()
})
