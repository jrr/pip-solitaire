// Play a full game of FreeCell in a real browser, by hand.
//
// The harness has three parts, and the split is the point:
//   - **eyes** — `read-board.mjs`, which reads the board off the rendered page
//     (`aria-label`s and geometry), never out of the app's state;
//   - **brain** — `rules.mjs` + `solver.mjs`, a mirror of `core`'s rules to plan
//     against, since planning means asking "and then what?" thousands of times;
//   - **hands** — this file, which plays each planned move as a real pointer drag
//     and then looks at the board again.
//
// The loop believes the screen. After every drag it re-reads the board and
// compares it to what the plan expected; on any difference it throws the rest of
// the plan away and solves again from what's actually there. So a wrong mirror
// costs moves, never correctness — which is what makes `autoplay.spec.mjs` able
// to assert the stronger thing: that a whole game goes by without a single
// disagreement between `core` and the model of it.
//
// Two things about the drags are worth knowing before changing them, both learned
// the hard way; they're commented at `grabPoint` and `dropPoint` below.

import {
  CASCADES, CELLS, FOUNDATIONS, assignPiles, parseCardName, readGeometry, settle,
} from "./read-board.mjs"
import {
  applyMove, canFinish, cardCode, describeMove, foundationTop, foundationTotal,
  hasWon, rankOf, stateFromPiles, stateKey, suitOf,
} from "./rules.mjs"
import { solve } from "./solver.mjs"

/**
 * The board as the page currently draws it: `geom` (raw boxes), `piles` (the
 * card elements, for aiming a drag), `cards` (each card's code and whether the
 * board announces it), `codes` (just the names, for reading), and `state` (the
 * position, for planning).
 */
export async function look(page) {
  const geom = await readGeometry(page)
  const piles = assignPiles(geom)
  const cards = piles.map((pile) =>
    pile.map((c) => ({ code: parseCardName(c.name), announced: c.announced })),
  )
  return { geom, piles, cards, codes: cards.map((p) => p.map((c) => c.code)), state: stateFromPiles(cards) }
}

/**
 * Where to press to pick a card up.
 *
 * A card buried in a `Fanned` cascade shows only the sliver above the next card —
 * 33px of a 142px card at desktop size — so pressing its *centre* presses the card
 * on top of it instead, and lifts the wrong span. Press the middle of whatever is
 * actually exposed, and remember how far that is from the card's centre, which
 * `dropPoint` needs.
 */
function grabPoint(view, code) {
  for (const pile of view.piles) {
    const idx = pile.findIndex((c) => parseCardName(c.name) === code)
    if (idx < 0) continue
    const card = pile[idx]
    const next = pile[idx + 1]
    const y = next ? card.y + Math.min((next.y - card.y) / 2, card.h / 2) : card.cy
    return { x: card.cx, y, offsetY: card.cy - y }
  }
  throw new Error(`no card named ${code} on the board`)
}

/**
 * Where to release, to land on `zone`.
 *
 * TableScene's `zoneAt` hit-tests the **grabbed card's** rect, not the pointer:
 * the card's centre x must fall in the zone's x-span, and its rect must overlap
 * the zone's vertically. The card tracks the pointer by the offset it was grabbed
 * at, so that offset has to come back off the target — aim the pointer where the
 * *card's centre* needs to be. Miss this and a card grabbed by its sliver lands a
 * row high, on a free cell instead of the cascade under it.
 */
const dropPoint = (zone, grab) => ({ x: zone.cx, y: zone.cy - grab.offsetY })

/** The pile a planned move targets, resolved against the board on screen. */
function targetZone(view, move) {
  if (move.to.col !== undefined) return CASCADES[move.to.col]
  if (move.to.cell !== undefined) {
    const free = CELLS.find((i) => view.codes[i].length === 0)
    if (free === undefined) throw new Error("no free cell available on the board")
    return free
  }
  // A foundation: the first one in board order that will take this card, which is
  // how `Reducer.foundationTarget` picks. Which card a foundation is showing comes
  // from `foundationTop` — the board's own answer, checked (see rules.mjs).
  const suit = suitOf(move.card)
  const rank = rankOf(move.card)
  const found = FOUNDATIONS.find((i) => {
    const top = foundationTop(view.cards[i])
    if (top < 0) return rank === 1 // an empty foundation takes an Ace
    return suitOf(top) === suit && rankOf(top) === rank - 1
  })
  if (found === undefined) throw new Error(`no foundation accepts ${cardCode(move.card)}`)
  return found
}

/** One move, as a pointer drag. Returns the cards the press actually lifted. */
export async function dragMove(page, view, move) {
  const grab = grabPoint(view, cardCode(move.card))
  const to = dropPoint(view.geom.zones[targetZone(view, move)], grab)

  await page.mouse.move(grab.x, grab.y)
  await page.mouse.down()
  // What did the press pick up? The app raises the whole run the card heads.
  const lifted = await page.evaluate(() =>
    [...document.querySelectorAll(".stacking-card.dragging")].map((el) =>
      el.querySelector("[aria-label]")?.getAttribute("aria-label"),
    ),
  )
  // Incremental moves rather than a jump, so pointermove fires and the hover
  // highlight tracks the drag the way it does under a real hand.
  for (let i = 1; i <= 8; i++) {
    await page.mouse.move(grab.x + ((to.x - grab.x) * i) / 8, grab.y + ((to.y - grab.y) * i) / 8)
  }
  await page.mouse.up()
  await settle(page)
  return lifted.map(parseCardName)
}

/**
 * Play deal `seed` through to the win overlay.
 *
 * `page` needs a `baseURL` (the Playwright fixture has one; the CLI sets one on
 * the context). Returns a report: how many drags it took, how many times the
 * screen disagreed with the plan, and whether the app declared a win.
 */
export async function playGame(page, { seed, log = () => {}, onMove = () => {} } = {}) {
  // `animate=off` skips the opening fly-in (see `AppUrl`), so the board is at its
  // resting positions as soon as the cards exist and the first grab measures the
  // real footprints instead of racing the deal.
  await page.goto(`/?scene=freecell&seed=${seed}&animate=off`)
  await settle(page)

  const started = Date.now()
  let played = 0
  let replans = 0
  let planned = null
  let view = await look(page)

  for (;;) {
    view = await look(page)
    if (hasWon(view.state)) break

    // From here the game is decided: `Reducer.canFinish` is true, the Finish
    // button is up, and it plays the rest home (#132/#160).
    if (canFinish(view.state)) {
      log(`  finishable after ${played} moves — pressing Finish`)
      await page.getByRole("button", { name: "Finish" }).click()
      await page.locator(".win-overlay").waitFor({ timeout: 15_000 })
      await settle(page)
      break
    }

    const plan = solve(view.state)
    if (!plan) throw new Error(`deal ${seed}: no solution from the position on screen`)
    if (planned === null) {
      planned = plan.length
      log(`  planned ${plan.length} moves to a finishable board`)
    }

    let model = view.state
    for (const move of plan) {
      const lifted = await dragMove(page, view, move)
      played++

      // `.dragging` comes back in z-order rather than pile order, so compare as a set.
      const expected =
        model.casc[move.from.col]?.slice(-move.n).map(cardCode) ?? [cardCode(move.card)]
      const sameCards = (a, b) => [...a].sort().join() === [...b].sort().join()
      if (!sameCards(lifted, expected))
        log(`  ! grabbed ${lifted.join("+") || "nothing"}, meant to grab ${expected.join("+")}`)
      onMove({ index: played, move, description: describeMove(move) })

      model = applyMove(model, move)
      view = await look(page)
      // The check that makes this harness evidence about the app: does the board
      // now look the way the mirrored rules said it would?
      if (stateKey(view.state) !== stateKey(model)) {
        log(`  ! screen diverged from the plan after move ${played} — re-planning`)
        replans++
        break
      }
      if (canFinish(model) || hasWon(model)) break
    }
  }

  const won = (await page.locator(".win-overlay").count()) > 0
  const title = won ? await page.locator(".win-panel__title").textContent() : null
  const finalState = (await look(page)).state
  return {
    seed,
    planned,
    played,
    replans,
    seconds: (Date.now() - started) / 1000,
    won: won && hasWon(finalState),
    title,
    foundations: foundationTotal(finalState),
  }
}
