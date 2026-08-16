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
  // Sharing falls back to the clipboard when the platform has no OS share sheet, which
  // is the case in headless Chromium — so that's the path under test, and reading the
  // result back needs the grant.
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

// Open the menu, where "Share Seed" sits beside "New" and Restart.
async function openMenu(page) {
  await page.getByRole("button", { name: "Open menu" }).click()
  return page.getByRole("button", { name: "Share Seed", exact: true })
}

// Press "Share Seed" and hand back the URL it put on the clipboard.
async function shareFromMenu(page) {
  const share = await openMenu(page)
  // The link is encoded when the menu opens, not on the press — the button stays
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

  const url = await shareFromMenu(page)
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
  const url = await shareFromMenu(page)

  await page.goto(url)
  await settleBoard(page)
  const adopted = await readBoard(page)

  await page.goto("/")
  await settleBoard(page)
  expect(await readBoard(page)).toEqual(adopted)
})

test("a corrupt link leaves an existing saved game alone", async ({ page }) => {
  // The failure path must not cost the player their game: nothing landed, so nothing
  // is written, and the save that was there survives. Set one up by adopting a
  // shared board first, then open a broken link over the top of it.
  await page.goto(MIDGAME)
  await settleBoard(page)
  const url = await shareFromMenu(page)
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

test("Share Seed is disabled on a scene with no game", async ({ page }) => {
  // A demo scene publishes no history hooks, so there's nothing to encode and the
  // button must say so rather than offering a link to a board that doesn't exist.
  await page.goto("/?scene=spinner")
  const share = await openMenu(page)
  await expect(share).toBeDisabled()
  await expect(page.getByText("No game on screen to share.")).toBeVisible()
})

test("Share Seed says nothing about a real game while its link encodes", async ({ page }) => {
  // The note under the buttons is for a link's fate or a scene that can't be shared —
  // it must not flash the demo-scene explanation at a board that's merely mid-encode
  // (`shareable` in the model exists precisely to tell those two apart).
  //
  // A plain `toHaveCount(0)` would be no test at all here: Playwright retries it, so
  // a note that appears for one frame and then clears still passes. The claim is
  // about a frame, so it needs a witness that was watching — a MutationObserver
  // armed before the menu opens, whose callback runs on every batch of DOM changes
  // the render makes.
  await page.goto(MIDGAME)
  await settleBoard(page)
  await page.evaluate(() => {
    // Only a *visible* note counts. The closed menu is `#menu-overlay[hidden]`, and
    // its panel is still rendered underneath, note and all — the model sits at
    // `shareable: false` at rest — so a plain text search would report a note nobody
    // could see. `offsetParent === null` under a `display: none` ancestor is what
    // separates the two. Attributes are observed as well as nodes, so dropping that
    // `hidden` attribute is itself a moment the note gets checked at.
    const showing = () => {
      const note = document.querySelector(".menu-buttons__note")
      return (
        note !== null &&
        note.offsetParent !== null &&
        note.textContent.includes("No game on screen to share.")
      )
    }
    window.__sawNoGameNote = showing()
    new MutationObserver(() => {
      window.__sawNoGameNote ||= showing()
    }).observe(document.body, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
    })
  })

  const share = await openMenu(page)
  // Waiting for the button to enable is waiting out the whole encode window — the
  // one the note must have stayed quiet through.
  await expect(share).toBeEnabled()
  expect(await page.evaluate(() => window.__sawNoGameNote)).toBe(false)
})
