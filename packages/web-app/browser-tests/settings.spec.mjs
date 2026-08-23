// The Settings screen's switches, driven for real (issue #308).
//
// The screen holds its own state now — its `model`/`msg`/`update` live in
// `MenuSettingsScreen` rather than in `Main`'s model — and `MenuSettingsScreen_test`
// pins both halves of that in isolation: `update` as a pure function, and which
// message each row sends.
//
// What neither can reach is the half that makes a switch *mean* something. The
// screen's model is deliberately a **mirror**: the value that matters lives in
// `localStorage`, in the live refs the board reads, or in an attribute on the
// document root, and `update`'s effect is the only thing keeping the copy and the
// truth in step. A unit test sees the mirror move. This file is here to see the
// truth move with it, and to see the mirror come back in the right position on the
// next launch — which is exactly what would break if a flip stopped being written
// through.
//
// (`debug-console.spec.mjs` covers the same seam from the other side, for the one
// switch reachable by a typed command: `set autocollect off` goes through this
// screen's own message, and the tell is the saved preference.)

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

const FREECELL = "/?scene=freecell&animate=off"

// Open the menu and step into Settings.
async function openSettings(page) {
  await page.locator(".top-bar__button--menu").click()
  await page.getByRole("button", { name: "Settings", exact: true }).click()
  await expect(page.locator(".menu-title")).toHaveText("Settings")
}

// One settings row by its label — the switch is the row itself (`role="switch"`).
const row = (page, label) =>
  page.locator(".menu-toggle").filter({ has: page.getByText(label, { exact: true }) })

const isOn = async (page, label) => (await row(page, label).getAttribute("aria-checked")) === "true"

const stored = (page, key) => page.evaluate((k) => localStorage.getItem(k), key)

test("each switch writes its flip through to where the setting actually lives", async ({
  page,
}) => {
  await page.goto(FREECELL)
  await settleBoard(page)
  await openSettings(page)

  // The shipped defaults, so the flips below are all default → off.
  expect(await isOn(page, "Auto-collect")).toBe(true)
  expect(await isOn(page, "Sloppy placement")).toBe(true)
  expect(await isOn(page, "Display content around notch")).toBe(true)

  // Auto-collect: persisted, and the same key the driver's `options` ref is seeded
  // from on the next launch.
  await row(page, "Auto-collect").click()
  expect(await isOn(page, "Auto-collect")).toBe(false)
  await expect.poll(() => stored(page, "pip.autoCollect")).toBe("false")

  // The card tilt: persisted, and the board is asked to relay itself out so the
  // change shows now rather than on the next move. The relayout is what a crossed
  // effect would drop silently, so check the cards actually squared up.
  // The angle rides on each card wrapper's `--card-rot` custom property, which the
  // `.card-art` child rotates by (see `applyTilt` in TableScene) — with the look off
  // every card publishes `0deg`.
  const tilted = () =>
    page.evaluate(
      () =>
        [...document.querySelectorAll(".stacking-card")].filter((el) => {
          const rot = el.style.getPropertyValue("--card-rot").trim()
          return rot !== "" && parseFloat(rot) !== 0
        }).length,
    )
  expect(await tilted()).toBeGreaterThan(0)
  await row(page, "Sloppy placement").click()
  expect(await isOn(page, "Sloppy placement")).toBe(false)
  await expect.poll(() => stored(page, "pip.cardTilt")).toBe("false")
  await expect.poll(tilted).toBe(0)

  // Notch display: persisted, and published to the document root for the CSS.
  await row(page, "Display content around notch").click()
  expect(await isOn(page, "Display content around notch")).toBe(false)
  await expect.poll(() => stored(page, "pip.notchDisplay")).toBe("false")
  await expect
    .poll(() => page.evaluate(() => document.documentElement.getAttribute("data-notch-wings")))
    .toBe("off")
})

test("the switches open in the positions they were left in", async ({ page }) => {
  // The mirror's whole job. Seed storage directly rather than clicking through, so
  // this fails if `init` stops reading a key even when `update` still writes it.
  await page.goto(FREECELL)
  await page.evaluate(() => {
    localStorage.setItem("pip.autoCollect", "false")
    localStorage.setItem("pip.cardTilt", "false")
    localStorage.setItem("pip.notchDisplay", "false")
  })
  await page.reload()
  await settleBoard(page)
  await openSettings(page)

  expect(await isOn(page, "Auto-collect")).toBe(false)
  expect(await isOn(page, "Sloppy placement")).toBe(false)
  expect(await isOn(page, "Display content around notch")).toBe(false)
})

test("ten taps on the title reveal the hidden settings, and a part-finished run is forgotten", async ({
  page,
}) => {
  await page.goto(FREECELL)
  await settleBoard(page)
  await openSettings(page)

  const title = page.locator(".menu-title")
  const wiggle = row(page, "Wiggle Waggle")
  await expect(wiggle).toHaveCount(0)

  // Nine taps is nine taps.
  for (let i = 0; i < 9; i++) await title.click()
  await expect(wiggle).toHaveCount(0)

  // Leaving the screen abandons the run (`forgetTaps`), so the tenth tap of the
  // *previous* visit can't complete it hours later — the count starts over.
  await page.getByRole("button", { name: "Back to menu" }).click()
  await page.getByRole("button", { name: "Settings", exact: true }).click()
  await title.click()
  await expect(wiggle).toHaveCount(0)

  // A clean run of ten does reveal it, and the reveal is persisted.
  for (let i = 0; i < 9; i++) await title.click()
  await expect(wiggle).toHaveCount(1)
  await expect.poll(() => stored(page, "pip.revealHidden")).toBe("true")

  // It sits between Sloppy placement and the notch row rather than under either —
  // the three are independent settings (pinned in jsdom too, kept here because this
  // is the only place the ten taps that produce it are real clicks).
  await expect(page.locator('[aria-label="Settings"] .menu-toggle__label')).toHaveText([
    "Auto-collect",
    "Sloppy placement",
    "Wiggle Waggle",
    "Display content around notch",
  ])
})
