// Reading the board back out of the rendered page — the "eyes" of the autoplay
// harness (see ./autoplay.mjs).
//
// Deliberately no privileged access: the app publishes no game state on `window`,
// and this doesn't ask for any. It reads what a sighted player reads — the sixteen
// `.drop-zone` boxes in board order (`Game.freecellDeal`'s pile order: 4 free
// cells, 4 foundations, 8 cascades) and a `.stacking-card` per card carrying its
// name as the `aria-label` `Deck.cardName` writes — and works out the rest from
// where things sit. That's what makes a game played through this harness evidence
// about the *app* rather than about the harness.

/** Pile indices by role, matching `Game.freecellDeal`'s board order. */
export const CELLS = [0, 1, 2, 3]
export const FOUNDATIONS = [4, 5, 6, 7]
export const CASCADES = [8, 9, 10, 11, 12, 13, 14, 15]

const RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const RANK_WORDS = {
  ace: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7,
  eight: 8, nine: 9, ten: 10, jack: 11, queen: 12, king: 13,
}
const SUIT_LETTERS = { clubs: "C", diamonds: "D", hearts: "H", spades: "S" }

/** `Deck.cardName`'s prose, back to a short code: "ace of spades" -> "AS". */
export function parseCardName(name) {
  const m = /^(\w+) of (\w+)$/.exec(String(name).trim().toLowerCase())
  const rank = m && RANK_WORDS[m[1]]
  const suit = m && SUIT_LETTERS[m[2]]
  if (!rank || !suit) throw new Error(`unparseable card name: ${name}`)
  return RANKS[rank - 1] + suit
}

/** Every drop zone and every card, in page coordinates. */
export async function readGeometry(page) {
  return await page.evaluate(() => {
    const box = (el) => {
      const r = el.getBoundingClientRect()
      return {
        x: r.x, y: r.y, w: r.width, h: r.height,
        cx: r.x + r.width / 2, cy: r.y + r.height / 2,
      }
    }
    return {
      zones: [...document.querySelectorAll(".drop-zone")].map((el, i) => ({ i, ...box(el) })),
      cards: [...document.querySelectorAll(".stacking-card")].map((el) => ({
        name: el.querySelector("[aria-label]")?.getAttribute("aria-label") ?? null,
        // Is this card in the accessible tree — i.e. would a screen reader be told
        // about it? A card the board draws underneath another is marked
        // `aria-hidden` by reflow (#267), which is what lets a squared pile say
        // which of its cards is the live one. `closest`, not the card's own
        // attribute, so a card hidden by an ancestor counts as hidden too.
        announced: el.closest('[aria-hidden="true"]') === null,
        ...box(el),
      })),
    }
  })
}

/**
 * Which pile is each card resting in?
 *
 * Cards are absolutely positioned siblings rather than children of their zones
 * (the same fact `share-link.spec.mjs` leans on), so the answer has to come from
 * the geometry. A card belongs to the zone it is stacked on: same column — its
 * centre falls within the zone's x-span — and at or below that zone's top. A
 * `Fanned` cascade can trail hundreds of pixels below its zone, but the *lowest*
 * zone still above a card is always the one it came from, which is what tells a
 * card in cascade 3 apart from one squared in the free cell directly above it.
 *
 * Within a pile the cards come back top-of-screen first, which for a `Fanned`
 * cascade is bottom-of-pile first — the order `GameState.cardsInPile` uses.
 * `Squared` piles stack every card at identical coordinates, so their order is
 * *not* recoverable from geometry — but since #267 the board says which card is
 * the live one by leaving only that one in the accessible tree. See
 * `foundationTop` in rules.mjs.
 */
export function assignPiles(geom) {
  const piles = geom.zones.map(() => [])
  for (const card of geom.cards) {
    const over = geom.zones.filter(
      (z) => card.cx >= z.x - 2 && card.cx <= z.x + z.w + 2 && card.y >= z.y - 2,
    )
    if (over.length === 0) throw new Error(`card "${card.name}" sits over no drop zone`)
    piles[over.reduce((a, b) => (b.y > a.y ? b : a)).i].push(card)
  }
  return piles.map((cards) => cards.sort((a, b) => a.y - b.y))
}

/**
 * Wait for the board to reach its resting layout — cards present, then every
 * animation on them finished.
 *
 * The same wait `browser-tests/lib/board.mjs` does, reimplemented rather than
 * imported: that one is a test helper built on `expect`, and `scripts/` doesn't
 * depend on the test suite (the dependency runs the other way).
 */
export async function settle(page, { timeout = 3000 } = {}) {
  await page.locator(".stacking-card").first().waitFor()
  await page.evaluate(async (cap) => {
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))
    // Scoped to the cards, not `document.getAnimations()`: a rejected drop carries
    // a deliberately infinite pulse that would never settle.
    const running = [...document.querySelectorAll(".stacking-card")].flatMap((el) =>
      el.getAnimations(),
    )
    await Promise.race([
      Promise.all(running.map((a) => a.finished.catch(() => {}))),
      new Promise((r) => setTimeout(r, cap)),
    ])
  }, timeout)
}
