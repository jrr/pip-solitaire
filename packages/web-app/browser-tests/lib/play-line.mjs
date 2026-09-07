// Playing a **recorded line** on the rendered board, one real pointer drag per move.
//
// Not a spec file — Playwright only collects `*.spec.mjs` from browser-tests/, so
// helpers live here beside them. `short-deck.spec.mjs` and `simple-simon.spec.mjs`
// both play a fixed script this way rather than searching: deals are deterministic,
// so a line found once is the same line every run, and the test stays a check on the
// app rather than a second solver.

import { assignPiles, parseCardName, readGeometry, settle } from "../../scripts/autoplay/read-board.mjs"
import * as Slot from "core/src/Slot.res.mjs"

/**
 * A `<card> <slot>` move against a board: the card's code and the pile it lands in.
 * Cards are `CardText` codes and slots are `Slot` labels — the vocabulary the console
 * and `Render` already speak — resolved against the board through `Slot` itself.
 */
export function moveOf(game, text) {
  const [card, label] = text.trim().split(/\s+/)
  const slot = Slot.parse(label)
  if (!slot) throw new Error(`unparseable slot in "${text}"`)
  const to = Slot.indexOf(game, slot[0], slot[1])
  if (to === undefined) throw new Error(`${label} is not a slot on this board`)
  return { card, to }
}

/**
 * Where to press to pick a card up — the middle of whatever is actually exposed,
 * since a buried card in a fan shows only the sliver above the next one. The offset
 * from the card's centre comes back with it, because the drop is decided by the
 * *card's* rect and not the pointer's (both learned in `autoplay.mjs`, which
 * comments them at length).
 */
export function grabPoint(piles, wanted) {
  for (const pile of piles) {
    const idx = pile.findIndex((c) => parseCardName(c.name) === wanted)
    if (idx < 0) continue
    const card = pile[idx]
    const next = pile[idx + 1]
    const y = next ? card.y + Math.min((next.y - card.y) / 2, card.h / 2) : card.cy
    return { x: card.cx, y, offsetY: card.cy - y }
  }
  throw new Error(`no card named ${wanted} on the board`)
}

/** One move, as a real pointer drag onto the zone at `to`. */
export async function drag(page, { card, to }) {
  const geom = await readGeometry(page)
  const grab = grabPoint(assignPiles(geom), card)
  const zone = geom.zones[to]
  const target = { x: zone.cx, y: zone.cy - grab.offsetY }

  await page.mouse.move(grab.x, grab.y)
  await page.mouse.down()
  // Incremental moves rather than a jump, so `pointermove` fires and the hover
  // highlight tracks the drag the way it does under a real hand.
  for (let i = 1; i <= 8; i++) {
    const at = (from, t) => from + ((t - from) * i) / 8
    await page.mouse.move(at(grab.x, target.x), at(grab.y, target.y))
  }
  await page.mouse.up()
  await settle(page)
}

/** Every move of a comma-separated line, in order. */
export async function playLine(page, game, line) {
  for (const text of line.split(",")) await drag(page, moveOf(game, text))
}
