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
  // The share dialog's Copy is the path under test, and reading what it wrote back
  // needs the grant.
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

const shareDialog = (page) => page.getByRole("dialog", { name: "Share game state" })

// Press "Share game state", then the dialog's Copy, and hand back the URL it put on
// the clipboard.
async function shareFromDebugScreen(page) {
  const share = await openDebugScreen(page)
  // The link is encoded when the screen opens, not on the press — the row stays
  // disabled until that resolves, so waiting for it to enable is also the assertion
  // that the encode succeeded.
  await expect(share).toBeEnabled()
  await share.click()
  await shareDialog(page).getByRole("button", { name: "Copy link" }).click()
  await expect(page.getByText("Link copied to clipboard.")).toBeVisible()
  return await page.evaluate(() => navigator.clipboard.readText())
}

test("the row raises the link as a QR code, and Copy copies it", async ({ page }) => {
  await page.goto(MIDGAME)
  await settleBoard(page)
  const url = await shareFromDebugScreen(page)
  await expect(shareDialog(page).getByRole("img", { name: /QR code/ })).toBeVisible()
  expect(url).toContain("#g=")

  // Close lands back on the Debug screen the dialog was raised from.
  await shareDialog(page).getByRole("button", { name: "Close" }).click()
  await expect(shareDialog(page)).toBeHidden()
  await expect(page.getByRole("button", { name: /Share game state/ })).toBeVisible()
})

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

// The two halves of what a recipient sees, which pull in opposite directions and so are
// one test: the board must arrive without being dealt in front of them, and it must then
// play like any other board. Recording what reached `Element.animate` rather than
// catching a flight mid-air, for the reason `debug-console.spec.mjs` records them that
// way — what's asserted is what the code asked the compositor for.
test("a shared board arrives without a fly-in, then moves like any other", async ({ page }) => {
  // Shared from the almost-won scenario so the reopened board has a move known to be
  // legal on it — the same one the console suite plays.
  await page.goto("/?game=freecell&state=almost-won&animate=off")
  await settleBoard(page)
  const url = await shareFromDebugScreen(page)

  // Armed before the navigation, because the thing under test happens during the load:
  // the fixed deal the board wears while the blob inflates, and the rebuild that
  // replaces it, are both over before a test body could patch anything.
  await page.addInitScript(() => {
    window.__flights = []
    const original = Element.prototype.animate
    Element.prototype.animate = function (frames, options) {
      if (this.classList?.contains("stacking-card")) window.__flights.push(JSON.stringify(frames))
      return original.call(this, frames, options)
    }
  })
  await page.goto(url)
  await settleBoard(page)
  expect(await page.evaluate(() => window.__flights.length)).toBe(0)

  // …and the suppression ends with the opening. A shared game is this device's game now,
  // so its moves fly: silencing them for the life of the page would leave a recipient
  // playing a board where nothing ever moves.
  await page.evaluate(() => (window.__flights = []))
  await page.keyboard.press("Backquote")
  await expect(page.locator("#debug-console-input")).toBeFocused()
  await page.keyboard.type("move KC 7")
  await page.keyboard.press("Enter")
  const flights = await page.evaluate(() => window.__flights)
  expect(flights.some((f) => f.includes("translate3d"))).toBe(true)
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

  // …and the default game's own save is untouched: FreeCell, opened by name — Mini is
  // now the remembered game, so a bare open would resume it — deals its own 52.
  await page.goto("/?game=freecell")
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

// A `#g=` blob and back, in the page, with the codec `Compression` uses — so the test
// can grow a real link's history past what a QR code holds.
const inflate = (page, url) =>
  page.evaluate(async (url) => {
    const blob = url.split("#g=")[1].replaceAll("-", "+").replaceAll("_", "/")
    const bytes = Uint8Array.from(atob(blob), (c) => c.charCodeAt(0))
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate-raw"))
    return JSON.parse(await new Response(stream).text())
  }, url)

const deflate = (page, save) =>
  page.evaluate(async (save) => {
    const bytes = new TextEncoder().encode(JSON.stringify(save))
    const stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream("deflate-raw"))
    const out = new Uint8Array(await new Response(stream).arrayBuffer())
    const blob = btoa(String.fromCharCode(...out))
    const url = blob.replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "")
    return `${location.origin}/#g=${url}`
  }, save)

test("a history too long for a QR code is trimmed in the code, and Copy keeps all of it", async ({
  page,
}) => {
  await page.goto(MIDGAME)
  await settleBoard(page)
  const save = await inflate(page, await shareFromDebugScreen(page))

  // Three hundred positions behind the present, each the board's piles in a different
  // order: far more history than a code holds, and none of it compressing to nothing.
  let seed = 1
  const random = () => (seed = (seed * 16807) % 2147483647) / 2147483647
  const shuffled = (piles) =>
    piles
      .map((pile) => [random(), pile])
      .sort((a, b) => a[0] - b[0])
      .map(([, pile]) => pile)
  const padding = Array.from({ length: 300 }, () => ({
    ...save.present,
    piles: shuffled(save.present.piles),
  }))
  save.past = [...save.past, ...padding]
  const long = await deflate(page, save)
  expect(long.length).toBeGreaterThan(2953)

  await page.goto(long)
  await settleBoard(page)
  const copied = await shareFromDebugScreen(page)
  await expect(shareDialog(page).getByRole("img", { name: /QR code/ })).toBeVisible()
  await expect(shareDialog(page).locator(".share-dialog__truncated")).toHaveText(
    new RegExp(`truncated to \\d+/${save.past.length} steps`),
  )
  expect((await inflate(page, copied)).past.length).toBe(save.past.length)
})
