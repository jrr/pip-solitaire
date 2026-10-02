// Thinking between asks: a board left still is thought about with nobody asking, so a
// Solve pressed later finds its answer already warm.
//
// Browser-only, because every part of it is something jsdom hasn't got: a worker to think
// on (the unit suite has none, so `Thinker` never thinks unasked there), a page that can
// be still or busy, and the conversation between them. That conversation is read off the
// page's own `Worker`, as `solve-row.spec.mjs` reads it: what is under test is what was
// sent to the solver and when, not how fast this machine grows positions.

import { expect, test } from "@playwright/test"
import { quietWin, settleBoard } from "./lib/board.mjs"
import { openSettings } from "./lib/menu.mjs"

test.use({ viewport: { width: 800, height: 1000 }, ...quietWin })
test.setTimeout(60_000)

// A FreeCell deal the solver answers in a few milliseconds, so the background has
// certainly answered it within a moment of the board going still.
const DEAL = "/?game=freecell&seed=24680&animate=off"

// Every message to and from the solver's worker, in order.
const listen = (page) =>
  page.addInitScript(() => {
    window.__worker = []
    const Base = window.Worker
    window.Worker = class extends Base {
      constructor(...args) {
        super(...args)
        this.addEventListener("message", (e) => window.__worker.push({ heard: e.data }))
      }
      postMessage(message) {
        window.__worker.push({ told: message.TAG ?? message, message })
        super.postMessage(message)
      }
    }
  })

const log = (page) => page.evaluate(() => window.__worker)

const solveDialog = (page) => page.locator("#solve-dialog")

const solve = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await openSettings(page)
  await page.getByRole("button", { name: "Debug" }).first().click()
  await page
    .locator(".menu-row--action", { has: page.locator('.menu-row__label:text-is("Solve")') })
    .click()
}

test("a still board is thought about unasked, and a Solve on it answers at once and says so", async ({
  page,
}) => {
  await listen(page)
  await page.goto(DEAL)
  await settleBoard(page)

  // Nobody has pressed anything, and the search has answered.
  await expect
    .poll(async () => (await log(page)).some((e) => e.heard?.TAG === "Answer"), { timeout: 15_000 })
    .toBe(true)
  const unasked = (await log(page)).filter((e) => e.told === "Think")
  expect(unasked.length).toBeGreaterThan(0)
  expect(unasked.every((e) => e.message.unasked)).toBe(true)
  // Short thinks, not a wait: what a Solve or a move might queue behind.
  expect(unasked.every((e) => e.message.ms <= 1000)).toBe(true)

  await solve(page)
  await expect(solveDialog(page)).toHaveText(/solution found/, { timeout: 15_000 })
  await expect(solveDialog(page)).toHaveText(/before you asked/)
  // The press asked about the board the background already holds: no `Open`, no `Moved`.
  const asked = (await log(page)).filter((e) => e.told === "Think" && !e.message.unasked)
  expect(asked).toHaveLength(1)
})

test("with Think ahead off, nothing is thought about until asked, and the switch is stored", async ({
  page,
}) => {
  await listen(page)
  await page.goto(DEAL)
  await settleBoard(page)
  await page.getByRole("button", { name: "Open menu" }).click()
  await openSettings(page)
  const toggle = page.getByRole("switch", { name: /^Think ahead/ })
  await expect(toggle).toHaveAttribute("aria-checked", "true")
  await toggle.click()
  expect(await page.evaluate(() => localStorage.getItem("pip.thinking"))).toBe("false")

  // A fresh page with the switch off, left still for well past the settle.
  await page.reload()
  await settleBoard(page)
  await page.waitForTimeout(4000)
  expect((await log(page)).filter((e) => e.told === "Think")).toHaveLength(0)

  await page.getByRole("button", { name: "Open menu" }).click()
  await openSettings(page)
  await expect(toggle).toHaveAttribute("aria-checked", "false")
})

test("the Debug screen's indicator and the console both say what thinking unasked is doing", async ({
  page,
}) => {
  await page.addInitScript(() => {
    localStorage.setItem("pip.thinkingDot", "true")
    localStorage.setItem("pip.debugLog", "true")
  })
  const said = []
  page.on("console", (message) => said.push(message.text()))
  await page.goto(DEAL)
  await settleBoard(page)

  // Settled: green, and the tooltip says how.
  const dot = page.locator("#thinking-dot")
  await expect(dot).toHaveAttribute("title", /^think ahead: found a line — /, { timeout: 15_000 })
  await expect(dot).toBeVisible()
  // Once per change, not once per chunk.
  expect(said.filter((line) => line.includes("think ahead: thinking about this board"))).toHaveLength(1)
  expect(said.some((line) => line.includes("think ahead: found a line"))).toBe(true)
})
