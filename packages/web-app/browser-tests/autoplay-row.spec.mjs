// The Debug screen's "Autoplay" row: the console's `autoplay`, pressed instead of
// typed. The board goes to the solver, and the menu that was covering it comes down so
// the line can be watched being played.
//
// Browser-only for the same reason the row exists at all. `MenuDebugScreen_test` pins
// what the row says and `TableScene_test` what the board answers; what neither can
// reach is the thing in between — a real search on a real worker thread, a menu that
// takes itself down when one comes back with a line, and a board that plays it through
// to a win with nobody typing anything.
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

// A whole deal rather than a posed position, so the solver is handed the board a player
// would be looking at. `?animate=off` because the flights are `stop-autoplay.spec.mjs`'s
// subject, not this file's — what is under test here is that the run happens at all.
const DEAL = "/?game=freecell&seed=24680&animate=off"

// A second deal, chosen for how long it thinks rather than for what it finds: four-suit
// Spiderette #147 beats the whole ladder in half a minute (`docs/solver.md`), so under
// the ten seconds a watched board gets it is a search that is *certainly* still running
// a moment after the press. That is what makes the painting test below race-free — a
// board that answered in 50 ms could pass it by accident.
const SLOW_DEAL = "/?game=spiderette4&seed=147&animate=off"

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

const autoplayRow = (page) =>
  page.locator(".menu-row--action", {
    has: page.locator('.menu-row__label:text-is("Autoplay")'),
  })

const openDebug = async (page) => {
  await page.getByRole("button", { name: "Open menu" }).click()
  await openSettings(page)
  await page.getByRole("button", { name: "Debug" }).first().click()
  await expect(autoplayRow(page)).toBeVisible()
}

test("the row hands the board to the solver, gets out of the way, and the line is played", async ({
  page,
}) => {
  await page.goto(DEAL)
  await settleBoard(page)
  await openDebug(page)
  await expect(autoplayRow(page)).toHaveText(/Solve the current game/)

  await autoplayRow(page).click()
  // The menu goes when — and only when — there is a line to watch, so this is the press's
  // answer as much as the cards are.
  await expect(page.locator("#menu-overlay")).toBeHidden()
  await expect(page.locator(".win-overlay")).toBeVisible({ timeout: 60_000 })
})

test("the page keeps painting while the solver thinks, and the row says so", async ({ page }) => {
  await page.goto(SLOW_DEAL)
  await settleBoard(page)
  await openDebug(page)

  await autoplayRow(page).click()
  // The complaint this whole arrangement answers: the row writes "Thinking…" and the
  // search used to take the thread before the paint carrying it ever happened, so the
  // word was never on screen. Now it is.
  await expect(autoplayRow(page)).toHaveText(new RegExp(THINKING))

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
  await expect(autoplayRow(page)).toHaveText(new RegExp(THINKING))
})

test("a scene with no board to solve says so, and the row can't be pressed", async ({ page }) => {
  // A demo scene publishes no board, which is the same nothing the console answers with
  // "no board on this scene" — and a row that can't act is dark rather than sorry.
  await page.goto("/?scene=gallery")
  await openDebug(page)
  await expect(autoplayRow(page)).toHaveText(/No game on screen to solve\./)
  await expect(autoplayRow(page)).toBeDisabled()
})
