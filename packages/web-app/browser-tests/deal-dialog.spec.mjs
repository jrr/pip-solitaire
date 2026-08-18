// The deal-number dialog, end to end — the menu's Play Seed… destination.
//
// This is the inbound half of Share Seed (#98), and it exists because a shared
// `?seed=` link is not always followable: an installed PWA can't claim URLs on iOS, so
// a friend's link opens a browser beside the game rather than the game, and the number
// on screen needs a way back *in*. The claim it makes is therefore the same round trip
// share-deal.spec.mjs makes, run the other way: **the board you get by typing a number
// is the board that number's link deals.**
//
// Browser-only for three separate reasons, which is most of what's here:
//
//   - the field is a real DOM node the module owns, and typing into it — caret,
//     selection, replacing a prefill — is exactly the behaviour a vnode input would
//     lose; jsdom would happily "type" into a node no player could;
//   - the dialog covering the open menu is a *paint-order* question (`z-index: 30` over
//     the menu's 20), and jsdom has no paint order to ask;
//   - the console's window-level key bindings versus a focused field is an event
//     -routing question between two live listeners.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

// The board's card layout as plain data — the same reading share-deal.spec.mjs takes,
// and for the same reason: two boards are "the same deal" to a player when every card
// comes to rest in the same place. Sorted, because DOM order follows z-stacking.
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

async function openMenu(page) {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
}

const dialog = (page) => page.locator("#deal-dialog")
const field = (page) => page.locator("#deal-dialog-input")
const status = (page) => page.locator(".deal-dialog__status")

// Open the dialog from the menu's game section.
async function openDialog(page) {
  await openMenu(page)
  await page.getByRole("button", { name: "Play Seed…" }).click()
  await expect(dialog(page)).toBeVisible()
}

test("a typed deal number deals the board that number's link deals", async ({ page }) => {
  // The reference board, opened the way a followable link would open it.
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  const viaLink = await readBoard(page)
  expect(viaLink.length).toBe(52)

  // Now the way in that doesn't need the link to be followable: a different board on
  // the table, and the number typed by hand.
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)
  expect(await readBoard(page)).not.toEqual(viaLink)

  await openDialog(page)
  await field(page).fill("24680")
  await page.getByRole("button", { name: "Play", exact: true }).click()
  await settleBoard(page)

  expect(await readBoard(page)).toEqual(viaLink)
})

test("accepts the # the app's own victory message prints", async ({ page }) => {
  // `ShareLink.victoryMessage` writes "Pip FreeCell #24680", so `#24680` is what a
  // player copies out of the message they were sent. Refusing it would mean refusing
  // the app's own notation.
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  const viaLink = await readBoard(page)

  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)

  await openDialog(page)
  await field(page).fill("#24680")
  await field(page).press("Enter")
  await settleBoard(page)

  expect(await readBoard(page)).toEqual(viaLink)
})

test("opens prefilled with the deal on the table, selected so typing replaces it", async ({
  page,
}) => {
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)
  await openDialog(page)

  // Prefilled: the field says what shape of thing goes in it without a caption.
  await expect(field(page)).toHaveValue("13579")

  // …and selected, so a player transcribing a number they were given is never deleting
  // first. Typing one digit must leave one digit, not six with a digit stuck on.
  await page.keyboard.type("7")
  await expect(field(page)).toHaveValue("7")
})

test("a refusal keeps the dialog up, holding what was typed", async ({ page }) => {
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)
  const before = await readBoard(page)

  await openDialog(page)

  // The empty-but-present status slot: it holds its height, so the refusal below lands
  // without shoving the Cancel/Play row out from under the thumb reaching for it.
  await expect(status(page)).toHaveText("")
  const slot = await status(page).boundingBox()

  await field(page).fill("12abc")
  await field(page).press("Enter")

  // `parseInt("12abc")` is 12 — the whole reason the parse is hand-rolled. Dealing
  // board 12 here would silently put this player on a different board from the one
  // they were sent, which is the one failure this feature cannot have.
  await expect(status(page)).toContainText("Not a deal number")
  expect((await status(page).boundingBox()).height).toBe(slot.height)

  // Still up, still holding the text, so a mistyped digit is one keystroke from right.
  await expect(dialog(page)).toBeVisible()
  await expect(field(page)).toHaveValue("12abc")
  expect(await readBoard(page)).toEqual(before)
})

test("Escape cancels, leaving the board and the menu where they were", async ({ page }) => {
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)
  const before = await readBoard(page)

  await openDialog(page)
  await field(page).fill("24680")
  await field(page).press("Escape")

  await expect(dialog(page)).toBeHidden()
  expect(await readBoard(page)).toEqual(before)
  // The menu was left standing *behind* the dialog on purpose, so Cancel puts the
  // player back in the section they pressed the button from rather than on the board.
  await expect(page.locator("#menu-overlay")).toBeVisible()
})

test("the dialog covers the open menu it was opened from", async ({ page }) => {
  // A paint-order claim, the sibling of menu-layering.spec.mjs's: the chrome's numbers
  // are small and readable (console 15, menu 20, dialog 30) only because the board
  // isolates its own. What the player touches over the menu panel must be the dialog.
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)
  await openDialog(page)

  const panel = await page.locator(".menu-panel").boundingBox()
  const hit = await page.evaluate(
    ({ x, y }) => {
      const el = document.elementFromPoint(x, y)
      if (!el) return "nothing"
      if (el.closest("#deal-dialog")) return "dialog"
      if (el.closest("#menu-overlay")) return "menu"
      return "board"
    },
    { x: panel.x + panel.width / 2, y: panel.y + panel.height / 2 },
  )
  expect(hit).toBe("dialog")
})

test("a backtick typed into the field stays in the field", async ({ page }) => {
  // The console's ` and Escape are bound on the *window*, which was free while its own
  // prompt was the only field in the app. With a second field there, an unguarded
  // listener would toggle the console behind the dialog instead of typing a character —
  // and swallow it, since that binding calls preventDefault. See `inForeignField`.
  await page.goto("/?seed=13579&animate=off")
  await settleBoard(page)
  await openDialog(page)

  await field(page).fill("")
  await page.keyboard.press("Backquote")

  await expect(page.locator("#debug-console")).toBeHidden()
  await expect(field(page)).toHaveValue("`")
})
