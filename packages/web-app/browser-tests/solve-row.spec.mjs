// The Debug screen's "Solve" row: the console's `autoplay`, pressed instead of typed,
// with the playing held back. The board goes to the solver, the answer comes up in a
// modal, and its Autoplay button takes the menu down so the line can be watched being
// played.
//
// Browser-only for the same reason the row exists at all. `MenuDebugScreen_test` pins
// what the row says and `TableScene_test` what the board answers; what neither can
// reach is the thing in between — a real search on a real worker thread, a modal that
// comes up with its answer, and a board that plays it through to a win with nobody
// typing anything.
//
// Nor can either of them reach what a *thread* is for. jsdom has no `Worker` at all, so
// the unit suite is answered on the spot by `Thinker`'s fallback and a search there is
// something that has already happened. Only here is there a page to keep painting.

import { expect, test } from "@playwright/test"
import { quietWin, settleBoard } from "./lib/board.mjs"
import { openSettings } from "./lib/menu.mjs"

test.use({ viewport: { width: 800, height: 1000 }, ...quietWin })

// A real search, then forty-odd moves: slower than a test that only reads chrome.
test.setTimeout(90_000)

// Each case here times an ask, or counts what crosses to the worker across asks, from a
// search that starts when the row is pressed. Thinking between asks would start it
// earlier and talk to the worker in between, so it is off; `think-ahead.spec.mjs` is
// where it is on.
test.beforeEach(({ page }) => page.addInitScript(() => localStorage.setItem("pip.thinking", "false")))

// A whole deal rather than a posed position, so the solver is handed the board a player
// would be looking at. `?animate=off` because the flights are `stop-autoplay.spec.mjs`'s
// subject, not this file's — what is under test here is that the run happens at all.
const DEAL = "/?game=freecell&seed=24680&animate=off"

// A second deal, chosen for how long it thinks rather than for what it finds: four-suit
// Spiderette #147 spends the search's whole budget without an answer (`docs/solver.md`),
// so under the ten seconds a watched board gets it is a search that is *certainly* still
// running a moment after the press. That is what makes the painting test below race-free — a
// board that answered in 50 ms could pass it by accident.
const SLOW_DEAL = "/?game=spiderette4&seed=147&animate=off"

// `Command.autoplayMore` at `Solver.interactive`: the modal's offer of another wait.
const MORE = "10s more"

// `MenuDebugScreen.thinking`, which is what the row's description becomes the moment the
// press is taken and stays until the answer lands.
const THINKING = "Thinking…"

// How long to watch the page for frames, and how few would count as still painting. A
// live page draws about sixty in the second; a page whose thread is inside the search
// draws only the handful it managed before the search took it, and then none. The
// threshold sits far above that handful and far below a live page's count, so neither a
// slow runner nor a fast one decides the answer.
const WATCH_MS = 1000
const FRAMES_EXPECTED = 15

const solveRow = (page) =>
  page.locator(".menu-row--action", {
    has: page.locator('.menu-row__label:text-is("Solve")'),
  })

const solveDialog = (page) => page.locator("#solve-dialog")

const openDebug = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await openSettings(page)
  await page.getByRole("button", { name: "Debug" }).first().click()
  await expect(solveRow(page)).toBeVisible()
}

test("the row hands the board to the solver, says what it found, and plays it on request", async ({
  page,
}) => {
  await page.goto(DEAL)
  await settleBoard(page)
  await openDebug(page)
  await expect(solveRow(page)).toHaveText(/Look for a way to win/)

  await solveRow(page).click()
  // Found, not played: the answer is up over the menu, which is still there behind it.
  await expect(solveDialog(page)).toHaveText(/solution found/, { timeout: 30_000 })
  await expect(page.locator("#menu-overlay")).toBeVisible()

  await solveDialog(page).getByRole("button", { name: "Autoplay" }).click()
  await expect(solveDialog(page)).toBeHidden()
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await expect(page.locator(".win-overlay")).toBeVisible({ timeout: 60_000 })
})

test("an answer with no line to play offers no Autoplay, and Close goes back to the Debug screen", async ({
  page,
}) => {
  // Out of patience after ten seconds (see `SLOW_DEAL`), which is a refusal — and the one
  // refusal worth asking again about, so it offers more time beside Close.
  await page.goto(SLOW_DEAL)
  await settleBoard(page)
  await openDebug(page)
  await solveRow(page).click()
  await expect(solveDialog(page)).toHaveText(/gave up/, { timeout: 30_000 })
  await expect(solveDialog(page).getByRole("button")).toHaveText(["Close", MORE])
  await solveDialog(page).getByRole("button", { name: "Close" }).click()
  await expect(solveDialog(page)).toBeHidden()
  await expect(solveRow(page)).toBeVisible()
})

test("ten more seconds carries on with the same search rather than starting another", async ({
  page,
}) => {
  test.setTimeout(90_000)
  // What crosses to the worker, and what it says back, read off the page's own `Worker`:
  // whether a second ask continues the first is a fact about that conversation, where a
  // line found or not depends on how fast the machine grows positions.
  await page.addInitScript(() => {
    window.__worker = []
    const Base = window.Worker
    window.Worker = class extends Base {
      constructor(...args) {
        super(...args)
        this.addEventListener("message", (e) => window.__worker.push({ heard: e.data }))
      }
      postMessage(message) {
        window.__worker.push({ told: message.TAG ?? message, ask: message.ask })
        super.postMessage(message)
      }
    }
  })
  await page.goto(SLOW_DEAL)
  await settleBoard(page)
  await openDebug(page)

  await solveRow(page).click()
  await expect(solveDialog(page)).toHaveText(/gave up after/, { timeout: 30_000 })
  const firstAsk = await page.evaluate(() => window.__worker.length)
  await solveDialog(page).getByRole("button", { name: MORE }).click()
  // Said to be the same search, and only Close to press while it is.
  await expect(solveDialog(page)).toHaveText(/same search/)
  await expect(solveDialog(page).getByRole("button")).toHaveText(["Close"])
  await expect(solveDialog(page)).not.toHaveText(/same search/, { timeout: 30_000 })

  const log = await page.evaluate(() => window.__worker)
  const progress = (entries, ask) =>
    entries.filter((e) => e.heard?.TAG === "Progress" && e.heard.ask === ask).map((e) => e.heard.positions)
  const [first, second] = [log.slice(0, firstAsk), log.slice(firstAsk)]
  const ask = second.find((e) => e.told === "Think").ask
  // The second ask is a `Think` and nothing else — no `Open` to start the board again…
  expect(second.filter((e) => e.told).map((e) => e.told)).toEqual(["Think"])
  // …and its first slice grows on from the positions the first ask left.
  expect(progress(second, ask)[0]).toBeGreaterThan(progress(first, ask - 1).at(-1))
  // The sentence counts both waits, whichever answer it is.
  const said = await solveDialog(page).locator(".solve-dialog__message").innerText()
  const [, seconds] = said.match(/(?:gave up after|found in) ([\d.]+)s/) ?? []
  if (seconds !== undefined) expect(Number(seconds), said).toBeGreaterThan(10)
})

test("the page keeps painting while the solver thinks, and the row says so", async ({ page }) => {
  await page.goto(SLOW_DEAL)
  await settleBoard(page)
  await openDebug(page)

  await solveRow(page).click()
  // The complaint this whole arrangement answers: the row writes "Thinking…" and the
  // search used to take the thread before the paint carrying it ever happened, so the
  // word was never on screen. Now it is.
  await expect(solveRow(page)).toHaveText(new RegExp(THINKING))

  // Counted from inside the page, because the question is about the page's own main
  // thread: `requestAnimationFrame` only fires between tasks, so a thread sitting in the
  // search cannot tick this — and could not have run this `evaluate` at all.
  const frames = await page.evaluate(
    ([ms]) =>
      new Promise((resolve) => {
        let drawn = 0
        const tick = () => {
          drawn++
          requestAnimationFrame(tick)
        }
        requestAnimationFrame(tick)
        setTimeout(() => resolve(drawn), ms)
      }),
    [WATCH_MS],
  )
  expect(frames).toBeGreaterThan(FRAMES_EXPECTED)
  // …and the search those frames were drawn during is the one still running, rather than
  // one that finished before the counting started.
  await expect(solveRow(page)).toHaveText(new RegExp(THINKING))
})

test("a scene with no board to solve says so, and the row can't be pressed", async ({ page }) => {
  // A demo scene publishes no board, which is the same nothing the console answers with
  // "no board on this scene" — and a row that can't act is dark rather than sorry.
  await page.goto("/?scene=gallery")
  await openDebug(page)
  await expect(solveRow(page)).toHaveText(/No game on screen to solve\./)
  await expect(solveRow(page)).toBeDisabled()
})

// A load that finds the last solve's mark still set reads it as the tab having been taken
// down by that solve: it says so once, over the board, and holds less from then on. The
// mark is planted before the first load, since no test can make a tab run out of memory —
// and a reload can't stand in for the crash, because `pagehide` clears the mark, which is
// the point of it. Which tier the test's browser lands in is not this test's business, only
// that the next one down is stored.
test("a solve that never finished lowers the memory tier and says so once", async ({ page }) => {
  await page.addInitScript(() => {
    if (!sessionStorage.getItem("planted")) {
      sessionStorage.setItem("planted", "yes")
      localStorage.setItem("pip.solving", "true")
    }
  })
  await page.goto(DEAL)
  await settleBoard(page)
  await expect(solveDialog(page)).toContainText("The last solve closed the page")
  expect(await page.evaluate(() => localStorage.getItem("pip.solving"))).toBe(null)
  const ceiling = await page.evaluate(() => localStorage.getItem("pip.memoryCeiling"))
  expect(["small", "medium"]).toContain(ceiling)

  // Said once: the next load has nothing to say.
  await page.reload()
  await settleBoard(page)
  await expect(solveDialog(page)).toHaveCount(0)
})
