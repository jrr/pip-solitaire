// The drop-down debug console (#271): press `` ` `` and the log the app already
// publishes (#213) drops over the board, live, with no devtools in sight.
//
// Browser-only by nature, on all three counts. The way in is a *physical key*
// (`event.code === "Backquote"`, so the panel opens on layouts where backtick is a
// dead key), the lines it shows come from a real pointer drag through `core`'s
// reducer, and the layering against the open menu is a paint-order question —
// `elementFromPoint` over a stacking context, which jsdom has neither of.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 800, height: 1000 } })

const FREECELL = "/?scene=freecell&animate=off"
// The one-move-from-won position (`Scenario.freecellAlmostWon`), the cheapest real
// move there is: the pending King in the first free cell goes home to the last
// foundation. The same drag `win.spec.mjs` and `share-win.spec.mjs` make.
const ALMOST_WON = "/?scene=freecell&state=almost-won&animate=off"

const consolePanel = (page) => page.locator("#debug-console")
const consoleLines = (page) => page.locator("#debug-console-lines li")
const consoleInput = (page) => page.locator("#debug-console-input")

// Open the console and wait for the prompt to have taken the keyboard — focus follows
// the panel (#273), so this is also the premise for every `type` below.
async function openConsole(page) {
  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeVisible()
  await expect(consoleInput(page)).toBeFocused()
}

// Type a command and run it, exactly as a person would: into whatever has focus.
async function runCommand(page, line) {
  await page.keyboard.type(line)
  await page.keyboard.press("Enter")
}

// ⇧` steps the console round its four placements (#275) — top, side, bottom, full. The
// console is keyboard-only, so its placement is too: same physical key as the toggle,
// shifted.
const pressPlace = (page) => page.keyboard.press("Shift+Backquote")

// Where the panel says it is, straight off the root attribute `ConsoleDock.reflect`
// publishes — absent (`null`) whenever the console is closed, which is the same fact as
// "a closed console holds no strip of the board".
const placement = (page) =>
  page.evaluate(() => document.documentElement.getAttribute("data-console-dock"))

// The card footprint the layout has settled on, straight off the custom property
// `applyScale` publishes. What "the board reflowed into the remaining width" means in a
// number: docking narrows the observed box, the `ResizeObserver` re-runs the layout, and
// the cards come out smaller.
const cardWidth = (page) =>
  page.evaluate(() =>
    parseFloat(
      getComputedStyle(document.querySelector(".stacking-playfield")).getPropertyValue(
        "--card-w",
      ),
    ),
  )

// Every label showing in the scrollback, in order — what the panel is actually
// narrating.
const labels = (page) =>
  page.locator("#debug-console-lines .debug-console__label").allTextContents()

// Play the single winning move by mouse, in incremental steps so `pointermove` fires
// as it crosses the board.
async function playTheWinningMove(page) {
  const cell = page.locator(".drop-zone").nth(0)
  const foundation = page.locator(".drop-zone").nth(7)
  const cellBox = await cell.boundingBox()
  const foundationBox = await foundation.boundingBox()
  const from = { x: cellBox.x + cellBox.width / 2, y: cellBox.y + cellBox.height / 2 }
  const to = {
    x: foundationBox.x + foundationBox.width / 2,
    y: foundationBox.y + foundationBox.height / 2,
  }

  await page.mouse.move(from.x, from.y)
  await page.mouse.down()
  for (let i = 1; i <= 6; i++) {
    await page.mouse.move(from.x + ((to.x - from.x) * i) / 6, from.y + ((to.y - from.y) * i) / 6)
  }
  await page.mouse.up()
}

test("the ` key drops the console over the board, and puts it away", async ({ page }) => {
  await page.goto(FREECELL)
  await settleBoard(page)

  // Closed on load, always — a rendered screenshot or link-preview image must never
  // catch one open.
  await expect(consolePanel(page)).toBeHidden()

  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeVisible()

  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeHidden()

  // Escape is the other way out (and is inert when nothing is showing).
  await page.keyboard.press("Escape")
  await expect(consolePanel(page)).toBeHidden()
  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeVisible()
  await page.keyboard.press("Escape")
  await expect(consolePanel(page)).toBeHidden()
})

test("a real move shows up in the console as it is played", async ({ page }) => {
  await page.goto(ALMOST_WON)
  await settleBoard(page)

  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeVisible()
  // Nothing has happened yet: the panel only listens while it's open.
  await expect(consoleLines(page)).toHaveCount(0)

  await playTheWinningMove(page)
  await expect(page.locator(".win-overlay")).toHaveCount(1)

  // The move the UI asked core to make, what core said back, and the win it reached —
  // the interactions `DebugLog` narrates, now readable without devtools.
  await expect(consoleLines(page).first()).toBeVisible()
  expect(await labels(page)).toContain("win")

  // One line for the move, in the board's own words: the card's face, the label printed
  // over the pile it went to, and the outcome on the end of it. (It used to be two — the
  // reducer's action as JSON, then `result: accepted` under it.)
  await expect(consoleLines(page).filter({ hasText: "move K♣ → F4 ✓" })).toHaveCount(1)

  // The scrollback survives a close: reopening resumes the log rather than wiping it.
  const count = await consoleLines(page).count()
  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeHidden()
  await page.keyboard.press("Backquote")
  await expect(consoleLines(page)).toHaveCount(count)
})

test("the menu wins over the console, on screen and in the model", async ({ page }) => {
  await page.goto(FREECELL)
  await settleBoard(page)

  // Only ever one of the two: the menu is the modal chrome, so opening it puts the
  // console away…
  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeVisible()
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
  await expect(consolePanel(page)).toBeHidden()

  // …and opening the console closes the menu.
  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeVisible()
  await expect(page.locator("#menu-overlay")).toBeHidden()

  // The layering underneath that rule, checked directly. Both are forced up at once
  // by poking the DOM — the model would never do it — and the console is given
  // pointer events for the length of the probe, since `elementFromPoint` skips a
  // pointer-transparent element and would answer "menu" without proving anything
  // about paint order. What's being asked is purely the z-index question: with the
  // two overlapping, which one is on top?
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.locator("#menu-overlay")).toBeVisible()
  const hitOverConsole = await page.evaluate(() => {
    const panel = document.getElementById("debug-console")
    panel.removeAttribute("hidden")
    panel.style.pointerEvents = "auto"
    const box = panel.getBoundingClientRect()
    const hit = document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2)
    const owner = hit?.closest("#menu-overlay")
      ? "menu"
      : hit?.closest("#debug-console")
        ? "console"
        : "board"
    panel.style.pointerEvents = ""
    panel.setAttribute("hidden", "")
    return owner
  })
  expect(hitOverConsole).toBe("menu")
})

test("an open console takes no input away from the board", async ({ page }) => {
  await page.goto(ALMOST_WON)
  await settleBoard(page)
  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeVisible()

  // The panel drops over the top of the board — the free cells, the foundations, and
  // the top bar with it — so if it took pointer events, the game underneath would be
  // half unplayable while you watched it being narrated. It doesn't: what's under the
  // console at that point is what a click reaches.
  const overCells = await page.evaluate(() => {
    const zone = document.querySelector(".drop-zone")
    const box = zone.getBoundingClientRect()
    const console_ = document.getElementById("debug-console").getBoundingClientRect()
    const point = { x: box.x + box.width / 2, y: box.y + box.height / 2 }
    return {
      covered: point.y < console_.bottom,
      hitsConsole: !!document.elementFromPoint(point.x, point.y)?.closest("#debug-console"),
    }
  })
  // The premise — the console really is over the cells — then the property.
  expect(overCells.covered).toBe(true)
  expect(overCells.hitsConsole).toBe(false)

  // And the whole move goes through, drag and all, with the panel up.
  await playTheWinningMove(page)
  await expect(page.locator(".win-overlay")).toHaveCount(1)
})

// --- The input line (#273) ---------------------------------------------------------
//
// The claim under test is that a typed command *plays the game* — not that it prints
// something plausible. So the assertions are about the board: a card ends up somewhere
// new, the win the move completes is raised, undo puts it back. All of it is browser-
// only for the same reasons the panel is: a physical key opens it, focus is a real
// focus, and "did the card move" is a rect.
//
// `KC` is the Clubs King the `almost-won` scenario parks in the first free cell, one
// move from a win — the same card the drag tests above pick up, addressed by name here
// instead of by pointer.
const PENDING_KING = "king of clubs"

// Where a named card's wrapper is sitting right now.
const cardBox = (page, name) =>
  page.locator(`.stacking-card:has([aria-label="${name}"])`).boundingBox()

// Is `inner` inside `outer` (with a pixel of slack for sub-pixel layout)?
const encloses = (outer, inner) =>
  inner.x >= outer.x - 1 &&
  inner.y >= outer.y - 1 &&
  inner.x + inner.width <= outer.x + outer.width + 1 &&
  inner.y + inner.height <= outer.y + outer.height + 1

test("a typed command moves the card, and the board ends where a drag would leave it", async ({
  page,
}) => {
  await page.goto(ALMOST_WON)
  await settleBoard(page)
  await openConsole(page)

  // The premise: the King is in the free cell, not on its foundation.
  const cell = await page.locator(".drop-zone").nth(0).boundingBox()
  const foundation = await page.locator(".drop-zone").nth(7).boundingBox()
  expect(encloses(cell, await cardBox(page, PENDING_KING))).toBe(true)

  await runCommand(page, "move KC 7")

  // The card is on the foundation…
  await expect
    .poll(async () => encloses(foundation, await cardBox(page, PENDING_KING)))
    .toBe(true)
  // …and because the command went through the same `dispatch` a drop does, the move
  // that completes every foundation raises the win exactly as a dragged one would.
  await expect(page.locator(".win-overlay")).toHaveCount(1)

  // The command echoed above its result, and the result is the ordinary instrumentation
  // — a typed move is narrated as the `Move` it is, not as a separate kind of event. The
  // narration names the pile `F4`, the label the board prints, though `7` was typed.
  const shown = await labels(page)
  expect(shown).toContain("> move KC 7")
  expect(shown).toContain("win")
  await expect(consoleLines(page).filter({ hasText: "move K♣ → F4 ✓" })).toHaveCount(1)
})

// The two destinations a *board* has to read, in the browser: the slot name printed
// above the column and the card to land on. `Command.resolveWhere` is shared with the
// CLI, so what's browser-only here is that the panel resolves against *its* board and
// the resolved move flies like any other — the same rect, the same win.
test("a slot name and a named card reach the same foundation a pile index does", async ({
  page,
}) => {
  await page.goto(ALMOST_WON)
  await settleBoard(page)
  await openConsole(page)

  const foundation = await page.locator(".drop-zone").nth(7).boundingBox()

  // `F4` is the fourth foundation — pile 7 on this board, the index the test above
  // types. `mv` is the same verb as `move`.
  await runCommand(page, "mv KC F4")
  await expect
    .poll(async () => encloses(foundation, await cardBox(page, PENDING_KING)))
    .toBe(true)
  await expect(page.locator(".win-overlay")).toHaveCount(1)

  // Step back out of the win and play it again by naming the card it lands on: the
  // Queen of Clubs is what that foundation is showing.
  await runCommand(page, "undo")
  await expect(page.locator(".win-overlay")).toHaveCount(0)
  await runCommand(page, "m KC QC")
  await expect(page.locator(".win-overlay")).toHaveCount(1)

  // A destination the board can't read is reported rather than played — and the panel
  // says the same sentence the terminal does.
  await runCommand(page, "undo")
  await runCommand(page, "mv KC T9")
  await expect(consoleLines(page).filter({ hasText: "No such tableau column: T9" })).toHaveCount(1)
})

test("home finds the foundation itself, and undo/redo walk the same history", async ({ page }) => {
  await page.goto(ALMOST_WON)
  await settleBoard(page)
  await openConsole(page)

  // `home` names no destination — the board resolves one, through the very `validMoves`
  // the double-tap send-home uses.
  await runCommand(page, "home KC")
  await expect(page.locator(".win-overlay")).toHaveCount(1)

  // Undo is the top bar's undo, reached from the prompt: it steps back out of the
  // victory and puts the King back in its cell.
  const cell = await page.locator(".drop-zone").nth(0).boundingBox()
  await runCommand(page, "undo")
  await expect(page.locator(".win-overlay")).toHaveCount(0)
  await expect.poll(async () => encloses(cell, await cardBox(page, PENDING_KING))).toBe(true)

  // …and redo — which the web app has never surfaced anywhere else — steps forward into
  // the move again, win overlay and all.
  await runCommand(page, "redo")
  await expect(page.locator(".win-overlay")).toHaveCount(1)

  // Nothing left to redo, and the console says so rather than silently doing nothing.
  await runCommand(page, "redo")
  await expect(consoleLines(page).filter({ hasText: "Nothing to redo." })).toHaveCount(1)
})

test("a rejected command explains itself in the same words the CLI uses", async ({ page }) => {
  await page.goto(ALMOST_WON)
  await settleBoard(page)
  await openConsole(page)

  // The shared parser's prose, verbatim: this is the point of #273's split, checked from
  // the far side of it.
  await runCommand(page, "move XX 0")
  await expect(
    consoleLines(page).filter({ hasText: `Not a card or a place to move from: "XX"` }),
  ).toHaveCount(1)

  await runCommand(page, "frobnicate")
  await expect(
    consoleLines(page).filter({ hasText: "Unknown command: frobnicate" }),
  ).toHaveCount(1)

  // A legal-looking move the rules refuse comes back with the reducer's reason, not a
  // shrug — the Clubs King has no business on a full foundation. Two lines, and only
  // for a rejection: the mark says it bounced and the line under it says why, in the
  // phrase `core` gives the terminal's sentence (`Command.reason`).
  await runCommand(page, "move KC 4")
  await expect(consoleLines(page).filter({ hasText: "move K♣ → F1 ✗" })).toHaveCount(1)
  await expect(consoleLines(page).filter({ hasText: "can't stack there" })).toHaveCount(1)
  // …and the board hasn't moved: a rejection is not a move.
  const cell = await page.locator(".drop-zone").nth(0).boundingBox()
  expect(encloses(cell, await cardBox(page, PENDING_KING))).toBe(true)
})

// The mirror image of the CLI accepting `clear` as a no-op: the panel knows the
// terminal's session verb and answers it rather than forwarding it to the board, which
// would have said only "that isn't something the board can do".
test("quit is answered here, not forwarded to the board", async ({ page }) => {
  await page.goto(FREECELL)
  await settleBoard(page)
  await openConsole(page)

  await runCommand(page, "quit")
  await expect(consoleLines(page).filter({ hasText: "Nothing to quit" })).toHaveCount(1)
  // A panel is closed, not left: the console is still up and still holding the keyboard.
  await expect(consolePanel(page)).toBeVisible()
  await expect(consoleInput(page)).toBeFocused()
})

test("the prompt remembers what was typed, and clear empties the log", async ({ page }) => {
  await page.goto(FREECELL)
  await settleBoard(page)
  await openConsole(page)

  await runCommand(page, "help")
  await runCommand(page, "frobnicate")
  await expect(consoleInput(page)).toHaveValue("")

  // ↑ walks back through what was run, newest first; ↓ walks forward again and off the
  // end, back to the empty line you were typing.
  await page.keyboard.press("ArrowUp")
  await expect(consoleInput(page)).toHaveValue("frobnicate")
  await page.keyboard.press("ArrowUp")
  await expect(consoleInput(page)).toHaveValue("help")
  await page.keyboard.press("ArrowDown")
  await expect(consoleInput(page)).toHaveValue("frobnicate")
  await page.keyboard.press("ArrowDown")
  await expect(consoleInput(page)).toHaveValue("")

  // `help` listed the shared verbs, so the panel documents the same grammar the CLI does.
  const shown = await labels(page)
  expect(shown.some((line) => line.includes("moverun"))).toBe(true)

  // `clear` empties the scrollback — and the recall history is not the scrollback, so
  // ↑ still reaches what was run before it.
  expect(await consoleLines(page).count()).toBeGreaterThan(0)
  await runCommand(page, "clear")
  await expect(consoleLines(page)).toHaveCount(0)
  await page.keyboard.press("ArrowUp")
  await expect(consoleInput(page)).toHaveValue("clear")
})

// The flight itself (#273). A card moved by a command must *fly* — over the fan it's
// leaving, not under it — rather than take the plain left/top slide `.stacking-card`
// would give it for free, because `reflowAll` relayers every pile the instant it runs
// and would drop the departing card behind cards it's still on top of.
//
// Asserted by recording the animations the move creates rather than by catching them
// mid-flight: `Element.animate` is patched before the command, so what's checked is
// what the code asked the compositor for, with no dependence on how fast the sample
// lands. This is the one console test without `animate=off` — that flag is exactly what
// suppresses the flight (see `flyCards`).
test("a commanded card flies to its new home, over the fan it leaves", async ({ page }) => {
  await page.goto("/?scene=freecell&state=almost-won")
  await settleBoard(page)
  await openConsole(page)

  await page.evaluate(() => {
    window.__flights = []
    const original = Element.prototype.animate
    Element.prototype.animate = function (frames, options) {
      if (this.classList?.contains("stacking-card")) {
        window.__flights.push(JSON.stringify(frames))
      }
      return original.call(this, frames, options)
    }
  })

  await runCommand(page, "move KC 7")
  const flights = await page.evaluate(() => window.__flights)

  // The travel: a transform animated from an offset back to zero — the inverse-offset
  // trick the deal and the finish sweep already fly on.
  expect(flights.some((f) => f.includes("translate3d"))).toBe(true)
  // …and the z-hold that carries it *above* the board for the trip. `finishFlightZBase`
  // is 100000; anything resting is a slot index.
  expect(flights.some((f) => f.includes("zIndex") && f.includes("100000"))).toBe(true)

  // And it did land: the flight is a visual catch-up over a model that already moved.
  const foundation = await page.locator(".drop-zone").nth(7).boundingBox()
  await expect
    .poll(async () => encloses(foundation, await cardBox(page, PENDING_KING)))
    .toBe(true)
})

test("deal <n> opens that deal number", async ({ page }) => {
  await page.goto(FREECELL)
  await settleBoard(page)
  await openConsole(page)

  await runCommand(page, "deal 24680")
  await settleBoard(page)

  // The board on the table really is deal 24680 — asked of the chrome that has to know,
  // the same place a Share would read it from.
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.getByRole("button", { name: /^Share Seed/ })).toHaveText("Share Seed 24680")
})

// The panel used to refuse any `deal` argument that wasn't a number — including the games
// its own `games` command listed. A game id now means here what it means in the CLI: that
// game's board, on screen. Scene ids are game ids, so this is the switcher's job.
test("deal <game> brings up that game's board", async ({ page }) => {
  await page.goto(FREECELL)
  await settleBoard(page)
  await openConsole(page)

  await runCommand(page, "deal four-fans")
  // Four fans, so four piles — a board FreeCell's sixteen zones can't be mistaken for —
  // and the demo's own caption under it.
  await expect(page.locator(".drop-zone")).toHaveCount(4)
  await expect(page.locator(".stacking-caption")).toContainText("they can only rest in a pile")

  // …and back, by name. FreeCell's canonical board is deal #1 in both front ends, so a
  // bare `deal freecell` is `deal 1` — which is what the chrome should now be offering.
  await runCommand(page, "deal freecell")
  await settleBoard(page)
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.getByRole("button", { name: /^Share Seed/ })).toHaveText("Share Seed 1")
})

// The second token is a named `Scenario` position — the same vocabulary `?state=` and the
// menu's debug-states rows use, and the same two steps behind them.
test("deal <game> <position> poses the board", async ({ page }) => {
  await page.goto(FREECELL)
  await settleBoard(page)
  await openConsole(page)

  await runCommand(page, "deal freecell almost-won")
  await settleBoard(page)

  // One move from won: the pending King is parked in the first free cell.
  const cell = await page.locator(".drop-zone").nth(0).boundingBox()
  expect(encloses(cell, await cardBox(page, PENDING_KING))).toBe(true)
  // And the deal it descends from is reported, exactly as the menu row reports it (#264).
  await page.getByRole("button", { name: "Open menu" }).click()
  await expect(page.getByRole("button", { name: /^Share Seed/ })).toHaveText("Share Seed 264")
})

// `redeal` is the menu's Restart button as a verb — same hook, so the same board comes
// back with a clean history.
test("redeal replays the deal on the table", async ({ page }) => {
  await page.goto(ALMOST_WON)
  await settleBoard(page)
  await openConsole(page)

  // Play the winning move, then restart: the King is back in its cell and the board is
  // no longer won.
  await runCommand(page, "move KC 7")
  await expect(page.locator(".win-overlay")).toHaveCount(1)

  await runCommand(page, "redeal")
  await settleBoard(page)
  await expect(page.locator(".win-overlay")).toHaveCount(0)
  // A restart goes to the *game's* deal, not back to the forced position — the rule the
  // Restart button already follows (`TableScene`'s `publishRestart`).
  await expect(page.getByRole("button", { name: "Undo" })).toBeDisabled()
})

// `print` draws the board into the log — the same board the CLI prints, from `core`'s
// renderer. It used to answer "the board is on screen", which was true and useless: the
// point is a snapshot you can read back. The colour it arrives in is the panel's own (see
// the ink test below); what `core` hands over is a document, not a painted string.
test("print draws the board into the log", async ({ page }) => {
  await page.goto("/?scene=freecell&seed=24680&animate=off")
  await settleBoard(page)
  await openConsole(page)

  await runCommand(page, "print")

  const lines = await consoleLines(page).allTextContents()
  // The title names the deal the chrome resolved — the number both Share buttons offer.
  expect(lines.some((l) => l.includes("FreeCell — deal #24680"))).toBe(true)
  // A board, drawn with the box characters and holding real cards.
  expect(lines.some((l) => l.includes("┌────┐"))).toBe(true)
  expect(lines.some((l) => /[♠♥♦♣]/.test(l))).toBe(true)
  // No escape codes, still: colour reaches this panel as CSS classes on spans, never as
  // the terminal's escapes, which it would show as garbage. Built from its char code, the
  // way `Render` builds it, rather than pasted into the source as a control character.
  const esc = String.fromCharCode(27)
  expect(lines.some((l) => l.includes(esc))).toBe(false)

  // Every column is headed by the name a typed move can address it by, so the board in
  // the log says how to play itself: `move 8H T3` is readable straight off the drawing.
  expect(lines.some((l) => l.includes("T1") && l.includes("T8"))).toBe(true)
  expect(lines.some((l) => l.includes("C1") && l.includes("F4"))).toBe(true)

  // The board is drawn in two role-grouped rows now — cells and foundations above the
  // tableau — which halves its width: ~70 columns rather than the ~150 of one long row,
  // so at this viewport it fits the panel outright instead of running off the side.
  const geometry = await page.evaluate(() => {
    const ol = document.getElementById("debug-console-lines")
    return { scrollWidth: ol.scrollWidth, clientWidth: ol.clientWidth }
  })
  expect(geometry.scrollWidth).toBeLessThanOrEqual(geometry.clientWidth)
})

// A narrower window than the board fits in — the log still has to be able to scroll
// sideways, or the right-hand columns are unreachable. Its own viewport rather than the
// file's, because the two-row board fits an 800px panel and this is the behaviour for
// when something doesn't.
test.describe("a log line wider than the panel", () => {
  test.use({ viewport: { width: 380, height: 900 } })

  test("scrolls sideways, wheel and all", async ({ page }) => {
    await page.goto("/?scene=freecell&seed=24680&animate=off")
    await settleBoard(page)
    await openConsole(page)

    await runCommand(page, "print")

    const geometry = await page.evaluate(() => {
      const ol = document.getElementById("debug-console-lines")
      return { scrollWidth: ol.scrollWidth, clientWidth: ol.clientWidth }
    })
    expect(geometry.scrollWidth).toBeGreaterThan(geometry.clientWidth)

    // In the overlay shape the panel takes no pointer events, so the sideways wheel is
    // hand-forwarded exactly as the vertical one already was.
    await page.mouse.move(190, 200)
    await page.mouse.wheel(200, 0)
    await expect
      .poll(() => page.evaluate(() => document.getElementById("debug-console-lines").scrollLeft))
      .toBeGreaterThan(0)
  })
})

// The driver's flags, typed. Auto-collect has a menu switch; the column-reorder house
// rule (#159) has no control anywhere, so the console is the only way to reach it.
test("set changes the driver's flags, through the app's own switch", async ({ page }) => {
  await page.goto(FREECELL)
  await settleBoard(page)
  await openConsole(page)

  // The two rows a `set` listing ends with — read off the foot of the scrollback, since
  // the echoed command and the one-line acknowledgement say the same words as the row.
  const settingsShown = async () =>
    (await consoleLines(page).allTextContents())
      .slice(-2)
      .map((line) => line.trim().replace(/\s+/g, " "))

  await runCommand(page, "set")
  expect(await settingsShown()).toEqual(["autocollect on", "reorder on"])

  // A typed auto-collect goes through the very action the Settings switch dispatches,
  // rather than writing the shared ref behind the UI's back. The tell is the *saved
  // preference*: the action persists it, a bare ref write wouldn't.
  await runCommand(page, "set autocollect off")
  await expect
    .poll(() => page.evaluate(() => localStorage.getItem("pip.autoCollect")))
    .toBe("false")

  // The house rule has no switch to keep in step, so it goes straight to the ref the
  // board reads at each move.
  await runCommand(page, "set reorder off")
  await runCommand(page, "set")
  expect(await settingsShown()).toEqual(["autocollect off", "reorder off"])

  // And a setting we don't have is refused in the words the CLI uses.
  await runCommand(page, "set frobnicate on")
  await expect(
    consoleLines(page).filter({ hasText: `Not a setting: "frobnicate"` }),
  ).toHaveCount(1)
})

test("the backtick still closes the console from inside the prompt", async ({ page }) => {
  await page.goto(FREECELL)
  await settleBoard(page)
  await openConsole(page)

  // Typed at a focused text field, the key that opens the panel has to keep closing it
  // — and must not land in the field as a character on its way out.
  await page.keyboard.press("Backquote")
  await expect(consolePanel(page)).toBeHidden()
  await page.keyboard.press("Backquote")
  await expect(consoleInput(page)).toHaveValue("")

  // Escape is the other way out, from in here too.
  await page.keyboard.press("Escape")
  await expect(consolePanel(page)).toBeHidden()
})

// --- The four placements (#275) ---------------------------------------------------
//
// ⇧` steps the panel through top → side → bottom → full and round again. The side dock is
// the one with an argument behind it: the top overlay is the wrong axis for FreeCell in a
// desktop window, because `TableScene` fits the tallest cascade fan plus the top row into
// the available *height*, so a band across the top eats the scarce dimension and shrinks
// every card, while past a point the layout throws surplus *width* away as equal
// left/right margins. Docked, the console is built out of that discard — and the board is
// told about it in exactly one way: `.table-board`, the box its `ResizeObserver` watches
// (#172), gets narrower. The other three cover the board rather than displacing it, so
// what they have to prove is what they cover and whether the game underneath is still
// reachable through them.
//
// All of which is a layout claim, so all of which is measured here rather than in jsdom:
// the board's rect, the panel's rect, and the card footprint the two produce between them.
test.describe("docked beside the board", () => {
  // Wide enough to clear the refusal test with room over: an eight-column board needs
  // ~427px to keep cards above `minScale`, and the dock takes 340.
  test.use({ viewport: { width: 1440, height: 900 } })

  test("docking narrows the board rather than covering it", async ({ page }) => {
    // The first ⇧` from the shipped placement, so this is also the cycle's first step.
    await page.goto(FREECELL)
    await settleBoard(page)

    const board = page.locator(".table-board")
    const undocked = await board.boundingBox()
    const undockedCard = await cardWidth(page)

    await page.keyboard.press("Backquote")
    await expect(consolePanel(page)).toBeVisible()
    // The premise: overlaid across the top, the panel lies *over* an untouched board.
    expect(await placement(page)).toBe("top")
    expect((await board.boundingBox()).width).toBeCloseTo(undocked.width, 0)

    await pressPlace(page)
    await expect(page.locator("html")).toHaveAttribute("data-console-dock", "side")

    // The board gives up the dock's width and reflows into what's left — cards and all.
    await expect
      .poll(async () => (await board.boundingBox()).width)
      .toBeLessThan(undocked.width)
    const docked = await board.boundingBox()
    const panel = await consolePanel(page).boundingBox()
    expect(docked.width).toBeCloseTo(undocked.width - panel.width, 0)
    // In *this* window the cards don't move at all, and that's the point of the whole
    // exercise: the board is already ceiling-bound (`maxScale`), so the width the dock
    // takes is width `applyScale` was discarding as equal left/right margins anyway. The
    // console arrives for free. (The narrower window below is where the reflow shows.)
    expect(await cardWidth(page)).toBeCloseTo(undockedCard, 1)

    // …and nothing is hidden under anything: the two rects don't intersect, so every
    // zone on the board is somewhere the console isn't.
    expect(docked.x + docked.width).toBeLessThanOrEqual(panel.x + 0.5)
    const zonesClear = await page.evaluate(() => {
      const panelLeft = document.getElementById("debug-console").getBoundingClientRect().left
      return [...document.querySelectorAll(".drop-zone")].every(
        (zone) => zone.getBoundingClientRect().right <= panelLeft + 0.5,
      )
    })
    expect(zonesClear).toBe(true)

    // Stepping on hands the width straight back: the next placement is an overlay again,
    // and the board is never told it exists.
    await pressPlace(page)
    await expect(page.locator("html")).toHaveAttribute("data-console-dock", "bottom")
    await expect
      .poll(async () => (await board.boundingBox()).width)
      .toBeCloseTo(undocked.width, 0)
  })

  test("a closed console stops holding the board's width", async ({ page }) => {
    await page.goto(FREECELL)
    await settleBoard(page)
    const board = page.locator(".table-board")
    const undocked = (await board.boundingBox()).width

    await pressPlace(page)
    await expect(consolePanel(page)).toBeVisible()
    await expect.poll(async () => (await board.boundingBox()).width).toBeLessThan(undocked)

    // Closing puts the strip back: the placement is remembered, but a console nobody is
    // looking at must not go on taking a slice of the playfield with it.
    await page.keyboard.press("Escape")
    await expect(consolePanel(page)).toBeHidden()
    expect(await placement(page)).toBe(null)
    await expect.poll(async () => (await board.boundingBox()).width).toBeCloseTo(undocked, 0)
  })

  test("the placement survives a reload", async ({ page }) => {
    await page.goto(FREECELL)
    await settleBoard(page)
    await pressPlace(page)
    await expect(page.locator("html")).toHaveAttribute("data-console-dock", "side")

    await page.reload()
    await settleBoard(page)
    // Closed on load as always — the placement is remembered, the panel isn't.
    await expect(consolePanel(page)).toBeHidden()
    expect(await placement(page)).toBe(null)

    // …and the plain toggle brings it back docked, without having to say so again.
    await page.keyboard.press("Backquote")
    await expect(consolePanel(page)).toBeVisible()
    await expect(page.locator("html")).toHaveAttribute("data-console-dock", "side")
  })

  test("the menu and a docked console are up together", async ({ page }) => {
    await page.goto(FREECELL)
    await settleBoard(page)
    await pressPlace(page)
    await expect(consolePanel(page)).toBeVisible()

    // The overlay's exclusion doesn't apply here — it exists because a band across the
    // top covers the Menu button — so the log stays up beside the open menu.
    await page.getByRole("button", { name: "Open menu" }).click()
    await expect(page.locator("#menu-overlay")).toBeVisible()
    await expect(consolePanel(page)).toBeVisible()

    // Readable, not merely present: the dimming backdrop stops at the dock edge rather
    // than washing over the log.
    const rects = await page.evaluate(() => {
      const box = (el) => {
        const r = el.getBoundingClientRect()
        return { left: r.left, right: r.right, top: r.top, height: r.height, width: r.width }
      }
      return {
        backdrop: box(document.querySelector(".menu-overlay__backdrop")),
        panel: box(document.getElementById("debug-console")),
      }
    })
    expect(rects.backdrop.right).toBeLessThanOrEqual(rects.panel.left + 0.5)

    // And the console is still just a panel: a click in it doesn't dismiss the menu.
    await page.mouse.click(
      rects.panel.left + rects.panel.width / 2,
      rects.panel.top + rects.panel.height / 2,
    )
    await expect(page.locator("#menu-overlay")).toBeVisible()
  })
})

test.describe("docked into a window with nothing to spare", () => {
  // Wide enough to dock, but not wide enough to do it out of discarded margin: the board
  // is at its `maxScale` ceiling undocked and drops below it once the dock is taken, so
  // here the cards really do rescale — the `ResizeObserver` path (#172) doing its work.
  test.use({ viewport: { width: 1000, height: 900 } })

  test("the board reflows into the remaining width", async ({ page }) => {
    await page.goto(FREECELL)
    await settleBoard(page)
    const before = await cardWidth(page)

    await pressPlace(page)
    await expect(page.locator("html")).toHaveAttribute("data-console-dock", "side")
    await expect.poll(() => cardWidth(page)).toBeLessThan(before)

    // The cards shrank, and they shrank *into* the board — the whole row still clears
    // the dock rather than sliding under it.
    const clear = await page.evaluate(() => {
      const panelLeft = document.getElementById("debug-console").getBoundingClientRect().left
      return [...document.querySelectorAll(".stacking-card, .drop-zone")].every(
        (el) => el.getBoundingClientRect().right <= panelLeft + 0.5,
      )
    })
    expect(clear).toBe(true)

    // …and back up again when the dock is given up for the next placement.
    await pressPlace(page)
    await expect.poll(() => cardWidth(page)).toBeCloseTo(before, 1)
  })
})

test.describe("too narrow to dock", () => {
  // Below the width at which the board would still clear `minScale` after giving up the
  // dock (`TableScene.minStageWidth` is ~284px for eight columns, and the dock takes
  // 340), so the cycle has to step over that placement rather than squeeze into it.
  test.use({ viewport: { width: 500, height: 900 } })

  test("the cycle steps over the dock and says why", async ({ page }) => {
    await page.goto(FREECELL)
    await settleBoard(page)
    const board = page.locator(".table-board")
    const before = (await board.boundingBox()).width

    await pressPlace(page)
    // The console comes up regardless — a refusal you can't see is indistinguishable
    // from a key that did nothing — and it comes up in the placement *past* the dock,
    // having said why it isn't in the dock.
    await expect(consolePanel(page)).toBeVisible()
    expect(await placement(page)).toBe("bottom")
    expect((await board.boundingBox()).width).toBeCloseTo(before, 0)
    await expect(consoleLines(page).filter({ hasText: "too narrow to dock" })).toHaveCount(1)

    // …and the rest of the cycle is still reachable, which is the point of stepping over
    // rather than sticking: a key that went inert here would strand the two placements
    // beyond the dock as well.
    await pressPlace(page)
    expect(await placement(page)).toBe("full")
    await pressPlace(page)
    expect(await placement(page)).toBe("top")
    // Round again, and the dock is skipped again — never landed on in this window.
    await pressPlace(page)
    expect(await placement(page)).toBe("bottom")
    expect((await board.boundingBox()).width).toBeCloseTo(before, 0)
  })
})

// The bottom band: the top overlay's mirror, and the placement for watching the row the
// top band hides — the free cells and the foundations, which is the state most `dispatch`
// lines are about. Same bargain as the top band, so the same two things have to hold: the
// board doesn't move, and a drag aimed through the panel still reaches the game.
test.describe("along the bottom", () => {
  test.use({ viewport: { width: 1440, height: 900 } })

  // Two steps from the shipped placement: top → side → bottom.
  async function placeAtBottom(page) {
    await pressPlace(page)
    await pressPlace(page)
    await expect(page.locator("html")).toHaveAttribute("data-console-dock", "bottom")
  }

  test("the band sits at the foot of the window over an untouched board", async ({ page }) => {
    await page.goto(FREECELL)
    await settleBoard(page)
    const board = page.locator(".table-board")
    const before = await board.boundingBox()

    await placeAtBottom(page)
    const panel = await consolePanel(page).boundingBox()
    const viewport = page.viewportSize()

    // At the bottom edge, not the top one — the whole difference between this placement
    // and the one the console opens in.
    expect(panel.y + panel.height).toBeCloseTo(viewport.height, 0)
    expect(panel.y).toBeGreaterThan(viewport.height / 2)

    // The board is never told about an overlay: same box, same cards as before.
    const after = await board.boundingBox()
    expect(after.width).toBeCloseTo(before.width, 0)
    expect(after.height).toBeCloseTo(before.height, 0)

    // And the row it was moved off is clear: the free cells and foundations along the top
    // are nowhere near it.
    const topRowClear = await page.evaluate(() => {
      const panelTop = document.getElementById("debug-console").getBoundingClientRect().top
      return [...document.querySelectorAll(".drop-zone")]
        .slice(0, 8)
        .every((zone) => zone.getBoundingClientRect().bottom <= panelTop + 0.5)
    })
    expect(topRowClear).toBe(true)
  })

  test("the game stays playable through the band", async ({ page }) => {
    await page.goto(ALMOST_WON)
    await settleBoard(page)
    await placeAtBottom(page)

    // Pointer-transparent, exactly like the top band: what lies under the panel is
    // whatever the board put there, so a drag aimed at a card reaches the card.
    const overBoard = await page.evaluate(() => {
      const panel = document.getElementById("debug-console").getBoundingClientRect()
      const hit = document.elementFromPoint(panel.left + panel.width / 2, panel.top + 4)
      return hit?.closest("#debug-console") === null
    })
    expect(overBoard).toBe(true)

    // The proof of it: the winning move still plays, and the panel narrates it from down
    // there.
    await playTheWinningMove(page)
    await expect(page.locator(".win-overlay")).toHaveCount(1)
    expect(await labels(page)).toContain("win")
  })
})

// The full window: for the times the board isn't what you're reading. `print` draws a
// ~150-column text board and `help` an aligned table, and neither fits a 340px dock or a
// 40vh band without a scroller in each axis.
test.describe("over the whole window", () => {
  test.use({ viewport: { width: 1440, height: 900 } })

  // Three steps from the shipped placement: top → side → bottom → full.
  async function placeFull(page) {
    await pressPlace(page)
    await pressPlace(page)
    await pressPlace(page)
    await expect(page.locator("html")).toHaveAttribute("data-console-dock", "full")
  }

  test("the panel takes the window, and takes its pointer events", async ({ page }) => {
    await page.goto(FREECELL)
    await settleBoard(page)
    const board = page.locator(".table-board")
    const before = await board.boundingBox()

    await placeFull(page)
    const panel = await consolePanel(page).boundingBox()
    const viewport = page.viewportSize()
    expect(panel.x).toBeCloseTo(0, 0)
    expect(panel.y).toBeCloseTo(0, 0)
    expect(panel.width).toBeCloseTo(viewport.width, 0)
    expect(panel.height).toBeCloseTo(viewport.height, 0)

    // Still an overlay as far as the board is concerned — covering is not displacing, so
    // stepping back round the cycle finds the board exactly as it was.
    const after = await board.boundingBox()
    expect(after.width).toBeCloseTo(before.width, 0)
    expect(after.height).toBeCloseTo(before.height, 0)

    // The inverse of the overlays' trick: there's no visible board left to protect, so
    // the log takes pointer events and can be clicked, selected and scrolled natively.
    const hitsConsole = await page.evaluate(() => {
      const hit = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2)
      return hit?.closest("#debug-console") !== null
    })
    expect(hitsConsole).toBe(true)
  })

  test("a printed board fits the window the band cropped it in", async ({ page }) => {
    await page.goto("/?scene=freecell&seed=24680&animate=off")
    await settleBoard(page)
    await openConsole(page)

    // The reason this placement exists, measured: a printed board is some 20 rows deep,
    // which the 40vh band reads through a letterbox…
    await runCommand(page, "print")
    await expect(consoleLines(page).filter({ hasText: "FreeCell" }).first()).toBeVisible()
    const overflow = () =>
      page.evaluate(() => {
        const lines = document.getElementById("debug-console-lines")
        return lines.scrollHeight - lines.clientHeight
      })
    expect(await overflow()).toBeGreaterThan(0)

    // …and the whole window doesn't. Same scrollback, same board, no scroller.
    await placeFull(page)
    await expect.poll(overflow).toBeLessThanOrEqual(1)
  })
})

// The panel paints the board itself (#282). `core` names the *role* each run of characters
// plays — a red suit's face, a title, the board's furniture — and each front end answers in
// its own alphabet: ANSI escapes in the terminal, these classes here. So the check is that
// the roles arrive intact and reach the right glyphs, not that any particular colour was
// used; the stylesheet owns that, and its choices are the panel's rather than the card
// table's or the terminal's.
test("print paints the board in the panel's own colours", async ({ page }) => {
  await page.goto("/?scene=freecell&seed=24680&animate=off")
  await settleBoard(page)
  await openConsole(page)

  await runCommand(page, "print")

  // Every red-inked span holds a red suit's face, and every black-inked one a black
  // suit's — the model's own notion of card colour, carried through untouched.
  const reds = await page.locator("#debug-console-lines .debug-console__ink--red").allTextContents()
  const blacks = await page
    .locator("#debug-console-lines .debug-console__ink--black")
    .allTextContents()
  expect(reds.length).toBeGreaterThan(0)
  expect(blacks.length).toBeGreaterThan(0)
  expect(reds.every((t) => /[♥♦]/.test(t))).toBe(true)
  expect(blacks.every((t) => /[♠♣]/.test(t))).toBe(true)
  // A full FreeCell deal shows all 52 faces at once, half of each colour.
  expect(reds.length).toBe(26)
  expect(blacks.length).toBe(26)

  // The heading is inked apart from the cards, so the panel can style it without parsing
  // the text back out of the row.
  const title = await page
    .locator("#debug-console-lines .debug-console__ink--title")
    .allTextContents()
  expect(title).toEqual(["FreeCell — deal #24680"])

  // The frames are furniture and stay plain — nothing but the faces is inked as a suit.
  const plain = await page
    .locator("#debug-console-lines .debug-console__ink--plain")
    .allTextContents()
  expect(plain.length).toBeGreaterThan(0)
  expect(plain.some((t) => /[♠♥♦♣]/.test(t))).toBe(false)

  // …and the roles actually resolve to different paint. Reading computed colour rather
  // than asserting a hex keeps the stylesheet free to retune the palette.
  const colours = await page.evaluate(() => {
    const colourOf = (cls) => {
      const el = document.querySelector(`#debug-console-lines .${cls}`)
      return el ? getComputedStyle(el).color : null
    }
    return {
      red: colourOf("debug-console__ink--red"),
      black: colourOf("debug-console__ink--black"),
      plain: colourOf("debug-console__ink--plain"),
    }
  })
  expect(colours.red).not.toBe(colours.black)
  expect(colours.plain).not.toBe(colours.black)

  // Only what `core` inked is painted. An ordinary reply is words, not a drawing, so it
  // stays in the log's own voice — the label styling every reply had before the panel
  // could paint anything — rather than being restyled as board furniture.
  await runCommand(page, "help")
  const helpIsPainted = await page.evaluate(() => {
    const rows = [...document.querySelectorAll("#debug-console-lines li")]
    const help = rows.filter((li) => li.textContent.includes("moverun"))
    return {
      found: help.length,
      painted: help.some((li) => li.classList.contains("debug-console__line--rendered")),
      labelled: help.every((li) => li.querySelector(".debug-console__label") !== null),
    }
  })
  expect(helpIsPainted.found).toBeGreaterThan(0)
  expect(helpIsPainted.painted).toBe(false)
  expect(helpIsPainted.labelled).toBe(true)

  // The drawing survives being cut into spans. A board row is one continuous run of
  // characters, so the line must not be a flex row — its 0.5rem gap between children
  // would land between every card and its frame and pull the columns out of true.
  const rowGap = await page.evaluate(() => {
    const li = document.querySelector("#debug-console-lines .debug-console__line--rendered")
    const style = getComputedStyle(li)
    return { display: style.display, gap: style.columnGap }
  })
  expect(rowGap.display).toBe("block")

  // The proof that alignment held: the board's rows still measure as `core` laid them out,
  // so the frames line up column for column exactly as they do in the terminal.
  const aligned = await page.evaluate(() => {
    const rows = [...document.querySelectorAll("#debug-console-lines .debug-console__line--rendered")]
      .map((li) => li.textContent)
      .filter((t) => t.includes("┌────┐"))
    // Every pile row starts its first frame at the same column…
    const firstFrame = rows.map((t) => t.indexOf("┌"))
    return { rows: rows.length, distinctStarts: new Set(firstFrame).size }
  })
  expect(aligned.rows).toBeGreaterThan(1)
  expect(aligned.distinctStarts).toBe(1)
})
