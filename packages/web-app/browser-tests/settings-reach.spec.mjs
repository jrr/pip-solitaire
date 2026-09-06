// Where each Settings switch actually reaches.
//
// The screen holds its own model (`MenuSettingsScreen`), and every field of it is a
// *mirror*: the value the app acts on lives in `localStorage`, in a ref the board reads
// at the moment of use, or in an attribute on the document root. `update`'s write-through
// is what keeps the mirror honest, and it is the half that can stop working with nothing
// on screen to show it — a switch that moves and persists nothing looks identical until
// the next launch.
//
// `MenuSettingsScreen_test` covers that against a recording env: which kinds of reach a
// message asks for. What it can't see is whether the live writers hit anything, and that
// needs a browser three times over — real storage, a real board to re-lay, and a real
// document root for the CSS to read.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

// A switch row by the label it leads with. The accessible name is the label *and* the
// line under it, so this anchors at the front rather than matching the whole thing.
const toggle = (page, label) => page.getByRole("switch", { name: new RegExp(`^${label}`) })

const stored = (page, key) => page.evaluate((k) => window.localStorage.getItem(k), key)

const openSettings = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
  await page.getByRole("button", { name: "Settings", exact: true }).click()
  await expect(page.getByRole("switch", { name: /^Auto-collect/ })).toBeVisible()
}

const openBoardAndSettings = async (page) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)
  await openSettings(page)
}

// The hidden settings are behind ten taps on the screen's title, and that gesture is
// itself one of the reaches under test — so it's performed rather than seeded here.
const revealHidden = async (page) => {
  for (let i = 0; i < 10; i++) {
    await page.locator(".menu-title").click()
  }
  await expect(toggle(page, "Wiggle Waggle")).toBeVisible()
}

test("a flip writes itself through to storage, and survives the reload", async ({ page }) => {
  await openBoardAndSettings(page)

  // Auto-collect ships on, and nothing is written until it's flipped.
  await expect(toggle(page, "Auto-collect")).toHaveAttribute("aria-checked", "true")
  expect(await stored(page, "pip.autoCollect")).toBe(null)

  await toggle(page, "Auto-collect").click()
  await expect(toggle(page, "Auto-collect")).toHaveAttribute("aria-checked", "false")
  expect(await stored(page, "pip.autoCollect")).toBe("false")

  // …and the next launch opens the switch from that stored value rather than the
  // shipped default, which is the read half of the same seam (`init`).
  await page.reload()
  await settleBoard(page)
  await openSettings(page)
  await expect(toggle(page, "Auto-collect")).toHaveAttribute("aria-checked", "false")
})

test("the tilt reaches the cards already on the table, without re-dealing them", async ({
  page,
}) => {
  await page.goto("/?seed=24680&animate=off")
  await settleBoard(page)

  // Mark the board that's up, so "the same board" is this very node rather than one
  // dealt identically — `?seed=` makes a re-deal look the same.
  await page.evaluate(() => {
    document.querySelector("#scene-container .table-board").dataset.pinned = "yes"
  })

  // The rendered angle, off the resolved matrix rather than the `--card-rot` property:
  // mid-transition the property already holds the destination value.
  const maxAngle = () =>
    page.evaluate(() =>
      [...document.querySelectorAll(".stacking-card .card-art")].reduce((max, el) => {
        const m = new DOMMatrixReadOnly(getComputedStyle(el).transform)
        return Math.max(max, Math.abs((Math.atan2(m.b, m.a) * 180) / Math.PI))
      }, 0),
    )

  await openSettings(page)
  expect(await maxAngle()).toBeGreaterThan(0)

  // Turning it off re-lays the resting cards in place: no move, no deal, no reload.
  await toggle(page, "Sloppy placement").click()
  await expect.poll(maxAngle, { timeout: 5000 }).toBeLessThan(0.01)
  expect(await stored(page, "pip.cardTilt")).toBe("false")

  // The game behind the menu is the one that was there before the flip.
  await expect(page.locator("#scene-container .table-board")).toHaveAttribute(
    "data-pinned",
    "yes",
  )
})

test("the notch preference reaches the document root, where the CSS reads it", async ({
  page,
}) => {
  await openBoardAndSettings(page)

  // Wings on is the default and carries no attribute at all: the base rules govern.
  await expect(page.locator("html")).not.toHaveAttribute("data-notch-wings")

  await toggle(page, "Display content around notch").click()
  await expect(page.locator("html")).toHaveAttribute("data-notch-wings", "off")
  expect(await stored(page, "pip.notchDisplay")).toBe("false")

  await toggle(page, "Display content around notch").click()
  await expect(page.locator("html")).not.toHaveAttribute("data-notch-wings")
  expect(await stored(page, "pip.notchDisplay")).toBe("true")
})

test("ten taps on the title reveal the hidden settings, and the reveal is remembered", async ({
  page,
}) => {
  await openBoardAndSettings(page)
  await expect(toggle(page, "Wiggle Waggle")).toHaveCount(0)

  await revealHidden(page)
  await expect(toggle(page, "Victory animation")).toBeVisible()
  expect(await stored(page, "pip.revealHidden")).toBe("true")

  // Persisted so the gesture is performed once per device, not once per launch.
  await page.reload()
  await settleBoard(page)
  await openSettings(page)
  await expect(toggle(page, "Wiggle Waggle")).toBeVisible()
})

test("the hidden switches write through like any other", async ({ page }) => {
  await openBoardAndSettings(page)
  await revealHidden(page)

  await toggle(page, "Victory animation").click()
  await expect(toggle(page, "Victory animation")).toHaveAttribute("aria-checked", "true")
  expect(await stored(page, "pip.victoryAnimation")).toBe("true")

  // Wiggle Waggle asks the OS as it goes on. Desktop Chromium is ungated, so the
  // request resolves listening and the *intent* — not the grant — is what's stored.
  await toggle(page, "Wiggle Waggle").click()
  await expect(toggle(page, "Wiggle Waggle")).toHaveAttribute("aria-checked", "true")
  expect(await stored(page, "pip.wantsShake")).toBe("true")

  await toggle(page, "Wiggle Waggle").click()
  await expect(toggle(page, "Wiggle Waggle")).toHaveAttribute("aria-checked", "false")
  expect(await stored(page, "pip.wantsShake")).toBe("false")
})
