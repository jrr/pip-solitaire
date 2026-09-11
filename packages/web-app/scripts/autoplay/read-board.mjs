// Reading the board back out of the rendered page — the "eyes" of the autoplay
// harness (see ./autoplay.mjs).
//
// Deliberately no privileged access: the app publishes no game state on `window`,
// and this doesn't ask for any. It reads what a sighted player reads — the
// `.drop-zone` boxes in board order (the game's pile order: FreeCell's 4 free cells,
// 4 foundations, 8 cascades; Simple Simon's 4 foundations and 10 cascades) and a
// `.stacking-card` per card carrying its name as the `aria-label` `Deck.cardName`
// writes — and works out the rest from where things sit. That's what makes a game
// played through this harness evidence about the *app* rather than about the
// harness.
//
// The last thing it does is hand what it read to `core` as a `Position` — the
// board the solver thinks with. Everything about *cards* below therefore
// speaks core's vocabulary: `CardText`'s two-character codes, and the card numbers
// `Position` packs them into.

import * as Game from "core/src/Game.res.mjs"
import * as Position from "core/src/Position.res.mjs"

/**
 * Which zone is which, for a game: its pile indices by role, straight from the
 * `Game.t` the app deals — so the reader and the board can't disagree about where the
 * cascades start — and the `Position.law` the solver reads that game under.
 */
export function layoutOf(gameId) {
  const game = Game.byId(gameId)
  if (!game) throw new Error(`no game called ${gameId}`)
  const law = Position.lawOf(game)
  if (!law) throw new Error(`${game.name} isn't a board the solver models`)
  return {
    id: gameId,
    law,
    cells: Game.pileIndices(game, "FreeCell"),
    foundations: Game.pileIndices(game, "Foundation"),
    cascades: Game.pileIndices(game, "Cascade"),
  }
}

/** The default: FreeCell's 4 cells, 4 foundations, 8 cascades. */
export const FREECELL = layoutOf("freecell")

// `CardText`'s alphabet, so a code read off the page is one core can parse back
// (`T` for the Ten, not `10`).
const RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K"]
const RANK_WORDS = {
  ace: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7,
  eight: 8, nine: 9, ten: 10, jack: 11, queen: 12, king: 13,
}
const SUIT_LETTERS = { clubs: "C", diamonds: "D", hearts: "H", spades: "S" }

/**
 * `Deck.cardName`'s prose, back to a short code: "ace of spades" -> "AS" — or `null`
 * for a name that isn't a card's, which is what a face-down card announces itself as
 * (`TableScene.faceDownLabel`): the board deliberately doesn't say what it is.
 */
export function cardCodeOf(name) {
  const m = /^(\w+) of (\w+)$/.exec(String(name).trim().toLowerCase())
  const rank = m && RANK_WORDS[m[1]]
  const suit = m && SUIT_LETTERS[m[2]]
  return rank && suit ? RANKS[rank - 1] + suit : null
}

/** The same, for a card that has to be one: FreeCell shows every face. */
export function parseCardName(name) {
  const code = cardCodeOf(name)
  if (!code) throw new Error(`unparseable card name: ${name}`)
  return code
}

/** A code as the card number `Position` packs it into (`Position.idOfCode`). */
export function cardId(code) {
  const id = Position.idOfCode(code)
  if (id === undefined) throw new Error(`bad card code: ${code}`)
  return id
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
        // `aria-hidden` by reflow, which is what lets a squared pile say
        // which of its cards is the live one. `closest`, not the card's own
        // attribute, so a card hidden by an ancestor counts as hidden too.
        announced: el.closest('[aria-hidden="true"]') === null,
        // Could a hand pick it up? Reflow marks every card that doesn't head a legal
        // run `--buried`, sealed piles' cards included — so on a two-pack board this
        // is what tells the copy a drag can take from the one it can't.
        liftable: !el.classList.contains("stacking-card--buried"),
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
 * *not* recoverable from geometry — but the board says which card is the live
 * one by leaving only that one in the accessible tree. See
 * `foundationTop` below.
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
 * The live card of a foundation, read two independent ways that must agree.
 *
 * A foundation is `Squared` — every card at identical coordinates, DOM order is
 * z-order — so its order can't be read from geometry, and it once came back as
 * `3H AH 4H 2H`. What can be read is which card the board *shows*: reflow leaves
 * only the top card of a squared pile in the accessible tree, so
 * exactly one card here is announced, and that one is the top.
 *
 * That's the first reading. The second is the pile's contents, which must be one
 * suit's run up to that top card: under `Rules.foundation` an ascending run from the
 * Ace, and under Simple Simon's sealed foundations the whole suit, King to Ace, so
 * the Ace is what shows. Checking the two readings against each other is the point,
 * and the reason not to shortcut to the simpler one: *inferring* the top as the
 * pile's highest rank is sound only because core's rule says so, so a foundation
 * that had gone wrong would read back as a tidy, plausible, wrong board and the
 * harness would launder the bug into a pass. Taking the app's own claim and
 * checking it makes a disagreement loud instead.
 *
 * Returns the card number, or `-1` for an empty foundation.
 */
export function foundationTop(pile, law = "FreeCell") {
  if (!pile.length) return -1
  const announced = pile.filter((c) => c.announced)
  if (announced.length !== 1) {
    throw new Error(
      `a foundation holding ${pile.length} cards announces ${announced.length} of them ` +
        `(expected exactly one): ${pile.map((c) => c.code).join(" ")}`,
    )
  }
  const top = cardId(announced[0].code)
  const held = pile.map((c) => cardId(c.code)).sort((a, b) => a - b)
  const suit = Position.suitOf(top)
  const run = (length) => Array.from({ length }, (_, i) => suit * 13 + i)
  if (law === "SimpleSimon") {
    if (Position.rankOf(top) !== 1 || held.join() !== run(13).join()) {
      throw new Error(
        `a foundation shows ${Position.code(top)} but holds ${held.map(Position.code).join(" ")} — ` +
          `not the whole suit, King to Ace, that a Simple Simon foundation collects`,
      )
    }
  } else if (held.join() !== run(Position.rankOf(top)).join()) {
    throw new Error(
      `a foundation shows ${Position.code(top)} but holds ${held.map(Position.code).join(" ")} — ` +
        `not the ascending same-suit run from the Ace that Rules.foundation builds`,
    )
  }
  return top
}

/**
 * Build the `Position` the solver thinks with from the piles `assignPiles` returns,
 * each a list of `{ code, announced }` bottom-first, laid out as `layout` says.
 *
 * A `Position` is a plain record of arrays — `law` (which game's rules), `cells`
 * (one slot per free cell, `-1` when empty; none under Simple Simon), `found` (how
 * many of each suit are home, indexed by `Position.suitOf`), `casc` (the columns,
 * bottom-first like `GameState.cardsInPile`) — so a driver outside ReScript can
 * build one; see `core/src/Position.res`.
 *
 * Cascades are `Fanned`, so the reader's geometric order is the pile order.
 * Foundations go through `foundationTop` above. Free cells hold one card by
 * capacity, so there's nothing to disambiguate — but a second card in one would
 * mean the board had broken its own rule, so say so rather than quietly taking
 * the first.
 */
export function stateFromPiles(piles, layout = FREECELL) {
  const cells = layout.cells.map((i) => {
    const pile = piles[i]
    if (!pile.length) return -1
    if (pile.length > 1)
      throw new Error(`a free cell holds ${pile.length} cards: ${pile.map((c) => c.code).join(" ")}`)
    return cardId(pile[0].code)
  })
  const found = [0, 0, 0, 0]
  for (const i of layout.foundations) {
    const top = foundationTop(piles[i], layout.law)
    if (top >= 0) found[Position.suitOf(top)] = piles[i].length
  }
  return {
    law: layout.law,
    cells,
    found,
    casc: layout.cascades.map((i) => piles[i].map((c) => cardId(c.code))),
  }
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
