// The "Enter seed" dialog, end to end.
//
// It is the receiving end of Share Seed: a number that reached the player as digits
// rather than as a link — read off a screenshot, dictated over a phone, copied out of
// a message — has to open the identical board. `SeedDialog_test` pins what the control
// reports, but "typing 24680 puts deal 24680 on the table" runs through a real field, a
// real submit and a whole board rebuild, so it only exists here — as does the modal's
// own arrangement: what it is raised over, and what each way out of it leaves behind.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

async function openMenu(page) {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

async function openSeedDialog(page) {
  await openMenu(page)
  await page.getByRole("button", { name: "Enter Seed" }).click()
  await expect(page.locator("#seed-dialog")).toBeVisible()
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

  await openSeedDialog(page)
  await seedField(page).fill("24680")
  await dealButton(page).click()

  // The whole chrome gets out of the way, as Random and Restart do — the board is the
  // answer, and a dialog left standing over it would hide the thing it just dealt.
  await expect(page.locator("#seed-dialog")).toBeHidden()
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

  await openSeedDialog(page)
  await seedField(page).fill("24680")
  await seedField(page).press("Enter")

  await expect(page.locator("#seed-dialog")).toBeHidden()
  await settleBoard(page)
  await openMenu(page)
  await expect(shareButton(page)).toHaveText("Share Seed 24680")
})

test("opens focused, so a number can be typed without aiming at the field first", async ({
  page,
}) => {
  // The dialog exists to be typed into. On a phone the focus is also what raises the
  // keyboard, so an unfocused field costs a tap before the first digit.
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)

  await openSeedDialog(page)
  await page.keyboard.type("24680")
  await expect(seedField(page)).toHaveValue("24680")
})

test("leaves the board and the menu alone when it's dismissed", async ({ page }) => {
  // Both ways out. The dialog is raised *over* the open menu, so cancelling puts the
  // player back where they pressed Enter Seed rather than on a bare board — and the
  // deal on the table never moved.
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)

  await openSeedDialog(page)
  await seedField(page).fill("24680")
  await page.getByRole("button", { name: "Cancel" }).click()
  await expect(page.locator("#seed-dialog")).toBeHidden()
  await expect(page.locator("#menu-overlay")).toBeVisible()
  await expect(shareButton(page)).toHaveText("Share Seed 13579")

  // The dim behind the panel dismisses too, and lands in the same place. A corner
  // rather than the default centre, which the panel is sitting on.
  await page.getByRole("button", { name: "Enter Seed" }).click()
  await page.locator(".seed-dialog__backdrop").click({ position: { x: 10, y: 10 } })
  await expect(page.locator("#seed-dialog")).toBeHidden()
  await expect(page.locator("#menu-overlay")).toBeVisible()
})

test("opens empty every time, rather than offering the last number back", async ({ page }) => {
  // The field belongs to the open dialog, not to the session: a number already dealt is
  // on Share Seed, and a half-typed one that outlived the dialog it was typed into would
  // be a press away from a board nobody asked for.
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)

  await openSeedDialog(page)
  await seedField(page).fill("24680")
  await page.getByRole("button", { name: "Cancel" }).click()

  await page.getByRole("button", { name: "Enter Seed" }).click()
  await expect(seedField(page)).toHaveValue("")
  // Nothing to deal, so nothing to press.
  await expect(dealButton(page)).toBeDisabled()
})
