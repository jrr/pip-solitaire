// A whole game of FreeCell, played through the UI by the autoplay harness in
// `scripts/autoplay/`.
//
// This is the widest end-to-end check in the repo: one fixed deal, played from
// the opening layout to the win overlay, entirely by pointer drags on the
// rendered board. Nothing is stubbed and nothing is reached into — the harness
// reads the board off the DOM the way a player reads the screen, and every move
// is a drag TableScene's own pointer loop has to accept. So a pass exercises the
// lot in one go: the deal, the cascade and foundation rules, supermoves, safe
// auto-collect, the drag hit-testing, the Finish sweep, and win detection.
//
// Browser-only for the obvious reason — the moves are pointer drags against a
// real layout, which jsdom has neither of — and *slow* by the standards of this
// suite, hence the raised timeout. It earns that: the unit tests check the rules
// a position at a time, and this checks that a game of them holds together.
//
// A fixed deal, not a random one: this has to fail the same way twice.

import { expect, test } from "@playwright/test"
import { playGame } from "../scripts/autoplay/autoplay.mjs"

// Deal 7 — an ordinary winnable board that the solver takes in its stride, so the
// test spends its time dragging rather than thinking.
const SEED = 7

test.use({ viewport: { width: 900, height: 1100 } })

test("plays deal 7 from the opening layout to the win overlay", async ({ page }) => {
  // ~50 drags, each waiting for the board to settle, plus the finish sweep.
  test.setTimeout(180_000)

  const result = await playGame(page, { seed: SEED, log: (line) => console.log(line) })

  expect(result.won).toBe(true)
  expect(result.foundations).toBe(52)
  await expect(page.locator(".win-overlay")).toHaveCount(1)
  await expect(page.locator(".win-panel__title")).not.toHaveText("")

  // It was played, not shortcut: the plan and the drags agree, and there were
  // plenty of both.
  expect(result.played).toBeGreaterThan(20)
  expect(result.played).toBe(result.planned)

  // After every drag the harness re-reads the board and compares it against the board
  // `core` said the move would leave behind (`Solver.planSteps`, planned over
  // `Position`); `replans` counts the times they differed. Zero means the running app —
  // its pointer loop, its supermove limit, its auto-collect, the point where `canFinish`
  // suppresses it — behaved for a whole game exactly as the pure rules say it should. A
  // non-zero count is the interesting failure: the *app* is doing something its own core
  // doesn't predict. (The rules themselves are checked against the reducer in `core`'s
  // `Position_test`, which needs no browser.)
  expect(result.replans).toBe(0)
})
