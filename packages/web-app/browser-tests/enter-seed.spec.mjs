// The menu's "Enter seed" field, end to end.
//
// It is the receiving end of Share Seed: a number that reached the player as digits
// rather than as a link — read off a screenshot, dictated over a phone, copied out of
// a message — has to open the identical board. `MenuSeedEntry_test` pins what the
// control reports, but "typing 24680 puts deal 24680 on the table" runs through a real
// field, a real submit and a whole board rebuild, so it only exists here.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

async function openMenu(page) {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

const seedField = (page) => page.getByRole("textbox", { name: "Deal number" })
const dealButton = (page) => page.getByRole("button", { name: "Deal", exact: true })
const shareButton = (page) => page.getByRole("button", { name: /^Share Seed/ })

// The board's cards by name and resting place — the same reading `share-deal` makes,
// and what "the same deal" means to a player. Sorted, since DOM order follows
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

test("deals the number typed in, and it's the same board the link would open", async ({ page }) => {
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)

  await openMenu(page)
  await seedField(page).fill("24680")
  await dealButton(page).click()

  // The menu gets out of the way, as Random and Restart do — the board is the answer.
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await settleBoard(page)
  const typed = await readBoard(page)

  // The deal the board now reports is the one asked for…
  await openMenu(page)
  await expect(shareButton(page)).toHaveText("Share Seed 24680")

  // …and it is card-for-card the board `?seed=24680` opens, which is the promise a
  // number handed between two people makes.
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  expect(await readBoard(page)).toEqual(typed)
})

test("takes Enter as the deal, since the keyboard is already up", async ({ page }) => {
  // On a phone the Go key is the submit within reach — dismissing the keyboard to
  // find a button is the difference between typing a number and fighting the form.
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)

  await openMenu(page)
  await seedField(page).fill("24680")
  await seedField(page).press("Enter")

  await expect(page.locator("#menu-overlay")).toBeHidden()
  await settleBoard(page)
  await openMenu(page)
  await expect(shareButton(page)).toHaveText("Share Seed 24680")
})

test("opens empty every time, rather than offering the last number back", async ({ page }) => {
  // The field belongs to the open menu, not to the session: a number already dealt is
  // on Share Seed, and a half-typed one that outlived the menu it was typed into would
  // be a press away from a board nobody asked for.
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)

  await openMenu(page)
  await seedField(page).fill("24680")
  await page.locator(".menu-overlay__backdrop").click()
  await expect(page.locator("#menu-overlay")).toBeHidden()

  await openMenu(page)
  await expect(seedField(page)).toHaveValue("")
  // Nothing to deal, so nothing to press.
  await expect(dealButton(page)).toBeDisabled()

  // …and the board never moved.
  await expect(shareButton(page)).toHaveText("Share Seed 13579")
})
