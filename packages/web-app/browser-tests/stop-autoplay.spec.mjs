// A press on the board stops a running autoplay where it stands, leaving the board
// playable: every card on its real square, the position the last committed step
// produced, the rest of the solver's plan abandoned.
//
// Browser-only on both counts. The gesture is a real press over cards that are *moving*,
// which needs a layout and a pointer; and what "playable" means here is what a cancelled
// flight would otherwise leave behind — a raised flight layer, a half-run transform, a
// rotation still scheduled — none of which exist without the Web Animations API and a
// resolved transform matrix. `TableScene_test` checks the wiring; this checks the board.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

// The run plays for a few seconds before the press, and again after it to prove it
// stayed stopped.
test.setTimeout(90_000)

// A whole deal rather than a posed position, so the solver has a long line to walk and
// the press lands in the middle of it. No `?animate=off` here, unlike most of this
// suite: that flag silences *every* flight, autoplay's included, and a line with nothing
// in the air is not the thing under test. The opening deal flies instead, which
// `settleBoard` waits out.
const DEAL = "/?game=freecell&seed=24680"

// Everything about a card a stopped board must have settled: where it rests, what layer
// it is *rendered* on, whether it is being carried, whether a rotation is still scheduled
// for it — and `offset`, how far its transform is currently carrying it away from that
// resting spot. A card at rest is not transform-*less* (every one of them is promoted to
// its own compositing layer with `translateZ(0)`), so the question is the translation in
// the resolved matrix, which a flight is the only thing that writes.
const cards = (page) =>
  page.evaluate(() =>
    [...document.querySelectorAll(".stacking-card")].map((el) => {
      const m = new DOMMatrixReadOnly(getComputedStyle(el).transform)
      return {
        label: el.querySelector("[aria-label]")?.getAttribute("aria-label") ?? "",
        left: el.style.left,
        top: el.style.top,
        z: getComputedStyle(el).zIndex,
        dragging: el.classList.contains("dragging"),
        rotDelay: el.style.getPropertyValue("--card-rot-delay"),
        offset: Math.round(Math.abs(m.m41) + Math.abs(m.m42)),
      }
    }),
  )

// Type the run in, and leave the console open: it publishes only while it is up (see
// `DebugConsole`), and what the run says as it stops is part of what's under test. It
// docks to one edge and the board reflows into what's left, which is why the press below
// takes its point from the board *after* this.
async function startAutoplay(page) {
  await page.keyboard.press("Backquote")
  await expect(page.locator("#debug-console-input")).toBeFocused()
  await page.keyboard.type("autoplay")
  await page.keyboard.press("Enter")
}

test("a press stops a running line, and leaves the board it stopped on playable", async ({
  page,
}) => {
  await page.goto(DEAL)
  await settleBoard(page)
  await startAutoplay(page)

  const inFlight = () =>
    page.evaluate(
      () =>
        [...document.querySelectorAll(".stacking-card")].flatMap((el) => el.getAnimations())
          .length,
    )
  // The solver thinks before it plays, so the run begins whenever it begins: wait for
  // cards to actually be in the air rather than for a guessed number of milliseconds…
  await page.waitForFunction(
    () =>
      [...document.querySelectorAll(".stacking-card")].some((el) => el.getAnimations().length > 0),
    null,
    { timeout: 30_000 },
  )
  // …and then let it play a while, so the press lands mid-line rather than on its first
  // move.
  await page.waitForTimeout(1500)
  expect(await inFlight()).toBeGreaterThan(0)

  // Somewhere a card is actually showing, so this is a press *on a card* — the case the
  // board has to take rather than each card, since the card under a finger may be one in
  // flight. Asked of the page rather than computed from a zone box, because the open
  // console has narrowed the board and a short cascade may not reach its zone's middle.
  const point = await page.evaluate(() => {
    for (const el of document.querySelectorAll(".stacking-card")) {
      const box = el.getBoundingClientRect()
      const p = { x: box.x + box.width / 2, y: box.y + box.height / 2 }
      if (document.elementFromPoint(p.x, p.y)?.closest(".stacking-card") === el) return p
    }
    return null
  })
  expect(point).not.toBeNull()
  await page.mouse.move(point.x, point.y)
  await page.mouse.down()
  await page.mouse.up()

  const stopped = await cards(page)
  // Nothing is carrying a dead flight: no card left raised above the board, no half-run
  // transform, no rotation scheduled for a movement that is no longer coming.
  expect(stopped.some((c) => Number(c.z) >= 100000)).toBe(false)
  expect(stopped.some((c) => c.offset !== 0)).toBe(false)
  expect(stopped.some((c) => c.rotDelay !== "")).toBe(false)
  // The press was the whole gesture: it lifted no card.
  expect(stopped.some((c) => c.dragging)).toBe(false)

  // …and it stays stopped: the rest of the plan is not played on behind the press. The
  // cards are compared by their inline left/top, which `reflowAll` writes at once — so
  // this is where they *rest*, whatever the snap transition is still catching up on.
  await page.waitForTimeout(2500)
  expect(await cards(page)).toEqual(stopped)
  expect(await inFlight()).toBe(0)
  await expect(page.locator(".win-overlay")).toHaveCount(0)

  // Said in the log, with where it got to.
  const said = await page.locator("#debug-console-lines .debug-console__label").allTextContents()
  expect(said.some((line) => /^autoplay stopped after \d+ of \d+ moves$/.test(line))).toBe(true)
})
