// The menu's "Share Seed" button, end to end.
//
// The claim the feature makes is a *round trip*: the link this button hands over,
// opened anywhere, deals the identical board. Every link in that chain has a unit
// test — the deal is deterministic (`Core_test`), the URL is shaped right
// (`ShareLink_test`), the menu shows the number it shares (`Menu_test`) — but the
// chain itself only exists in a real browser, because it runs through the clipboard
// and a page load.
//
// Browser-only for a second reason: `navigator.clipboard` doesn't exist in jsdom at
// all, so "the link actually reaches the player" is unaskable there. Here it's the
// whole point, and Playwright can grant the permission a real user grants.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({
  viewport: { width: 800, height: 1000 },
  // With no OS share sheet in headless Chromium, `ShareLink.deliver` falls back to
  // the clipboard — so that's the path under test, and reading the result back needs
  // the grant.
  permissions: ["clipboard-read", "clipboard-write"],
})

// The board's card layout as plain data: every card by name, with where it came to
// rest. Two boards dealt from the same number must produce identical lists — that's
// what "the same deal" means to a player. Sorted, because DOM order follows
// z-stacking rather than layout.
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

// Share Seed lives on the main menu, one tap in, beside New and Restart.
async function openMenu(page) {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

// The Share Seed button, which names the seed it would hand out.
const shareButton = (page) => page.getByRole("button", { name: /^Share Seed/ })

// The line under the buttons: where a link just went, or why the button is dark.
const shareLine = (page) => page.locator(".menu-share-line")

// Press Share Seed and hand back the link it put on the clipboard.
async function shareDeal(page) {
  await shareButton(page).click()
  await expect(shareLine(page)).toHaveText("Link copied to clipboard.")
  return await page.evaluate(() => navigator.clipboard.readText())
}

test("shares a link to the deal on the table, and that link reopens it", async ({ page }) => {
  // Open a known deal, so the assertion can name the number the menu must show.
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  const dealt = await readBoard(page)
  expect(dealt.length).toBe(52)

  await openMenu(page)
  await expect(shareButton(page)).toHaveText("Share Seed 24680")
  // The line beneath is empty until there's something to report, but present: the
  // confirmation below takes a slot that's already holding its height, so nothing
  // below it moves when it appears.
  await expect(shareLine(page)).toHaveText("")
  const before = await shareLine(page).boundingBox()

  const url = await shareDeal(page)
  // …and it appeared in that same slot, without resizing it.
  expect((await shareLine(page).boundingBox()).height).toBe(before.height)

  // The link says which board to deal and nothing else — legible, and short enough
  // to be read off one screen and typed into another. FreeCell is the game a deal
  // number belongs to when none is named, so the link doesn't spend characters saying
  // so: `?game=` appears only for another game.
  expect(new URL(url).searchParams.get("seed")).toBe("24680")
  expect(new URL(url).searchParams.get("game")).toBe(null)
  // …and it never says it the other way either: `?scene=` names a scene now, and a
  // deal link has nothing to say about which scene to mount.
  expect(new URL(url).searchParams.get("scene")).toBe(null)
  expect(new URL(url).hash).toBe("")

  // The round trip, as the recipient makes it: open what was shared, cold.
  await page.goto(url)
  await settleBoard(page)
  expect(await readBoard(page)).toEqual(dealt)
})

test("offers the fresh deal after a New Game", async ({ page }) => {
  // The regression this guards: the line must track the board actually on the table,
  // not the deal the page opened with. A stale number here would be the worst kind of
  // bug for a share feature — it sends someone to a board you're not playing.
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)

  await openMenu(page)
  await expect(shareButton(page)).toHaveText("Share Seed 13579")

  // New Game deals a fresh random seed and closes the menu; reopen and look again.
  await page.getByRole("button", { name: "New", exact: true }).click()
  await settleBoard(page)
  const afterNewGame = await readBoard(page)

  await openMenu(page)
  await expect(shareButton(page)).not.toHaveText("Share Seed 13579")

  // …and whatever it now offers is a link to *this* board.
  const url = await shareDeal(page)
  await page.goto(url)
  await settleBoard(page)
  expect(await readBoard(page)).toEqual(afterNewGame)
})

test("a resumed game can still say which seed it is", async ({ page }) => {
  // The case that made the seed worth persisting (`SavedGame.saveSeed`): a
  // resumed board restores its *positions* from storage, and the deal that produced
  // them is long gone by then. Without the number saved beside the game, the Share
  // button would be dark on the most ordinary open there is — start the app, carry on
  // with the game you had.
  await page.goto("/?animate=off")
  await settleBoard(page)
  await openMenu(page)
  const dealt = await shareButton(page).textContent()
  expect(dealt).toMatch(/^Share Seed \d+$/)

  // Reload with a bare URL: no seed to pin the deal, so the board that comes back is
  // the saved one, resumed.
  await page.goto("/")
  await settleBoard(page)
  await openMenu(page)
  await expect(shareButton(page)).toHaveText(dealt)
})

test("a bare `?seed=` opens FreeCell — the short form `urlForDeal` writes", async ({ page }) => {
  // **The receiving half of omitting the game.** A deal link is `?game=<id>&seed=<n>`
  // with the game left out for the default one, so `?seed=7` is the *current* spelling
  // for FreeCell rather than a shorthand being tolerated — and it has to land on
  // FreeCell for the link to mean what it says. It holds because `SceneSwitcher`'s
  // `~default` is `Game.default.id` and that's the same game `urlForDeal` omits the
  // parameter for, not because anything branches on a missing one.
  await page.goto("/?seed=7&animate=off")
  await settleBoard(page)
  const bare = await readBoard(page)
  expect(bare.length).toBe(52)

  // Spelled out in full, the same link opens the same board — the two forms are one
  // link, which is what makes omitting the game a shortening rather than a meaning.
  // (`?game=freecell&seed=7` is the shape a second game's link takes.)
  await page.goto("/?game=freecell&seed=7&animate=off")
  await settleBoard(page)
  expect(await readBoard(page)).toEqual(bare)

  // …and it's FreeCell that opened, not merely *a* board: the menu's Share Seed offers
  // deal 7 back, and hands over the short form again.
  await openMenu(page)
  await expect(shareButton(page)).toHaveText("Share Seed 7")
  const url = new URL(await shareDeal(page))
  expect(url.searchParams.get("seed")).toBe("7")
  expect(url.searchParams.get("game")).toBe(null)
  expect(url.search).toBe("?seed=7")
})

test("a `?game=` that isn't a game falls through rather than forcing a scene", async ({ page }) => {
  // `?game=` is resolved against `Game.byId`, so a name that isn't a game is turned
  // away in `AppUrl` instead of travelling on as a scene id. `gallery` is the sharp
  // case: it *is* a real scene, so an unresolved `?game=` would mount the card gallery
  // and leave no board at all. `?scene=` is what mounts that, and this isn't it.
  await page.goto("/?game=gallery&animate=off")
  await settleBoard(page)

  await expect(page.locator(".card-gallery")).toHaveCount(0)
  expect((await readBoard(page)).length).toBe(52) // the launch default, FreeCell
})

test("says so on a board with no seed, rather than offering one", async ({ page }) => {
  // A posed position only names a deal it has been *proved* to descend from, and
  // `midgame` is assembled from the deck rather than played to — so it has no deal
  // number. The button is disabled and the line explains, rather than offering a link
  // to a board the sender isn't looking at.
  await page.goto("/?game=freecell&state=midgame&animate=off")
  await settleBoard(page)

  await openMenu(page)
  await expect(page.getByRole("button", { name: "Share Seed", exact: true })).toBeDisabled()
  await expect(shareLine(page)).toHaveText("No seed for this board.")
})
