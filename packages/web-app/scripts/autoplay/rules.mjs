// A JavaScript mirror of the rules in `packages/core`, for the autoplay harness to
// think ahead with (see ./autoplay.mjs).
//
// **This is not a second source of truth.** The app is: every move the harness
// plans is played as a real drag, and the board is re-read from the page after
// each one. The mirror exists only because planning needs to ask "and then what?"
// thousands of times, which you cannot do by dragging. When the two disagree the
// harness believes the screen and re-plans — and since a disagreement means this
// file has drifted from `core`, `autoplay.spec.mjs` asserts it never happens.
//
// What it mirrors, and why each one is load-bearing for a plan that survives
// contact with the app:
//   - `Rules.cascade` / `Rules.foundation` — what a pile accepts.
//   - `Reducer.maxSupermove` — `(1 + emptyCells) × 2 ^ emptyCascades`, with the
//     destination excluded from the tally, so a planned run move is one the app
//     will actually take.
//   - `Reducer.autoCollect` / `isSafeToCollect` — on by `Options.default`, so the
//     board *after* a move usually isn't just that move applied.
//   - `Reducer.canFinish` — once it flips true the drivers suppress auto-collect
//     and the Finish button owns the sweep, which changes what the next board
//     looks like. It's also the harness's goal: from there the game is won.

// A card is an int 0..51: suit * 13 + (rank - 1). Suits C D H S; D and H are red.
export const SUITS = ["C", "D", "H", "S"]
export const RANK_CHARS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
export const suitOf = (c) => (c / 13) | 0
export const rankOf = (c) => (c % 13) + 1
export const isRed = (c) => suitOf(c) === 1 || suitOf(c) === 2
export const cardCode = (c) => RANK_CHARS[rankOf(c) - 1] + SUITS[suitOf(c)]
export function cardId(code) {
  const m = /^(10|[A2-9JQK])([CDHS])$/.exec(code)
  if (!m) throw new Error(`bad card code: ${code}`)
  return SUITS.indexOf(m[2]) * 13 + RANK_CHARS.indexOf(m[1])
}

/**
 * A position: `cells` (4 slots, `-1` when empty), `found` (the top rank reached
 * per suit, `0` for none), `casc` (8 columns, bottom-first like
 * `GameState.cardsInPile`).
 */
export const cloneState = (s) => ({
  cells: s.cells.slice(),
  found: s.found.slice(),
  casc: s.casc.map((c) => c.slice()),
})

export const emptyCells = (s) => s.cells.filter((c) => c < 0).length
export const foundationTotal = (s) => s.found.reduce((a, b) => a + b, 0)
export const hasWon = (s) => foundationTotal(s) === 52

/** `Rules.cascade`: build down in alternating colour. */
export const cascadeAccepts = (s, col, card) => {
  const pile = s.casc[col]
  if (pile.length === 0) return true
  const top = pile[pile.length - 1]
  return rankOf(top) === rankOf(card) + 1 && isRed(top) !== isRed(card)
}

/** `Rules.foundation`: an Ace onto an empty pile, then up by suit. */
export const foundationAccepts = (s, card) => s.found[suitOf(card)] === rankOf(card) - 1

/** How many cards form the ordered run at the top of a column (`Rules.isRun`). */
export function runLength(pile) {
  if (pile.length === 0) return 0
  let n = 1
  for (let i = pile.length - 1; i > 0; i--) {
    const above = pile[i]
    const below = pile[i - 1]
    if (rankOf(below) === rankOf(above) + 1 && isRed(below) !== isRed(above)) n++
    else break
  }
  return n
}

/** `Reducer.maxSupermove`, with the destination excluded from the empty tally. */
export function maxSupermove(s, destCol) {
  const empties = s.casc.filter((c, i) => c.length === 0 && i !== destCol).length
  return (1 + emptyCells(s)) * 2 ** empties
}

/** `Reducer.isSafeToCollect`: never strand a card a cascade might still want. */
function isSafeToCollect(s, card) {
  if (!foundationAccepts(s, card)) return false
  const r = rankOf(card)
  if (r <= 2) return true // nothing is ever built down onto an Ace or a Two
  const opposite = isRed(card) ? [0, 3] : [1, 2]
  return opposite.every((suit) => s.found[suit] >= r - 1)
}

/** The accessible cards: the top of every free cell and every cascade. */
function tops(s) {
  const out = []
  for (let i = 0; i < 4; i++) if (s.cells[i] >= 0) out.push({ card: s.cells[i], cell: i })
  for (let i = 0; i < 8; i++) {
    const p = s.casc[i]
    if (p.length) out.push({ card: p[p.length - 1], col: i })
  }
  return out
}

function sendHome(s, spot) {
  s.found[suitOf(spot.card)] = rankOf(spot.card)
  if (spot.cell !== undefined) s.cells[spot.cell] = -1
  else s.casc[spot.col].pop()
}

/** `Reducer.autoCollect`: the fixpoint over the safe cards. Mutates and returns `s`. */
export function autoCollect(s) {
  for (;;) {
    const spot = tops(s).find((t) => isSafeToCollect(s, t.card))
    if (!spot) return s
    sendHome(s, spot)
  }
}

/**
 * A cheap necessary condition for finishability, to keep the real check off the
 * hot path of a search that asks after every generated move.
 *
 * In a foundation-only drain a column empties from the top, and a suit goes home
 * in ascending order — so of two cards of one suit in one column, the deeper one
 * must be the higher rank. A column that breaks that can never drain, whatever
 * the free cells hold.
 */
function couldFinish(s) {
  const seen = new Int8Array(4)
  for (const pile of s.casc) {
    seen.fill(0)
    for (let i = pile.length - 1; i >= 0; i--) {
      const suit = suitOf(pile[i])
      const rank = rankOf(pile[i])
      if (seen[suit] && rank < seen[suit]) return false
      seen[suit] = rank
    }
  }
  return true
}

/**
 * `Reducer.canFinish`: does the greedy foundation-only drain win from here?
 *
 * Written against scratch arrays rather than a cloned state, and behind the cheap
 * gate above — the search asks this of every position it generates, so both the
 * allocations and the drain itself showed up in the profile.
 */
export function canFinish(s) {
  if (!couldFinish(s)) return false
  const found = s.found.slice()
  const cells = s.cells.slice()
  const depth = s.casc.map((p) => p.length)
  let remaining = 52 - foundationTotal(s)
  for (let progressed = true; progressed; ) {
    progressed = false
    for (let i = 0; i < 4; i++) {
      const card = cells[i]
      if (card >= 0 && found[suitOf(card)] === rankOf(card) - 1) {
        found[suitOf(card)] = rankOf(card)
        cells[i] = -1
        remaining--
        progressed = true
      }
    }
    for (let i = 0; i < 8; i++) {
      while (depth[i] > 0) {
        const card = s.casc[i][depth[i] - 1]
        if (found[suitOf(card)] !== rankOf(card) - 1) break
        found[suitOf(card)] = rankOf(card)
        depth[i]--
        remaining--
        progressed = true
      }
    }
  }
  return remaining === 0
}

/**
 * Every legal move from here, in the app's terms.
 *
 * A move is `{ n, from: {cell}|{col}, to: {found}|{cell}|{col}, card }`, where
 * `card` is the one the player would grab — for a run of `n`, its bottom card,
 * since grabbing that is what lifts the whole span (TableScene's pointerdown).
 */
export function legalMoves(s) {
  const moves = []
  for (let i = 0; i < 4; i++) {
    const card = s.cells[i]
    if (card < 0) continue
    if (foundationAccepts(s, card))
      moves.push({ n: 1, from: { cell: i }, to: { found: true }, card })
    for (let col = 0; col < 8; col++)
      if (cascadeAccepts(s, col, card)) moves.push({ n: 1, from: { cell: i }, to: { col }, card })
  }
  const firstEmptyCell = s.cells.indexOf(-1)
  for (let src = 0; src < 8; src++) {
    const pile = s.casc[src]
    if (!pile.length) continue
    const top = pile[pile.length - 1]
    if (foundationAccepts(s, top))
      moves.push({ n: 1, from: { col: src }, to: { found: true }, card: top })
    if (firstEmptyCell >= 0)
      moves.push({ n: 1, from: { col: src }, to: { cell: firstEmptyCell }, card: top })
    for (let n = 1; n <= runLength(pile); n++) {
      const bottom = pile[pile.length - n]
      for (let dest = 0; dest < 8; dest++) {
        if (dest === src) continue
        if (!cascadeAccepts(s, dest, bottom)) continue
        // Moving a whole column into an empty one only renames it.
        if (s.casc[dest].length === 0 && n === pile.length) continue
        if (n > maxSupermove(s, dest)) continue
        moves.push({ n, from: { col: src }, to: { col: dest }, card: bottom })
      }
    }
  }
  return moves
}

/** Apply a move, then the app's post-move auto-collect. Returns a fresh state. */
export function applyMove(s, move) {
  const t = cloneState(s)
  let cards
  if (move.from.cell !== undefined) {
    cards = [t.cells[move.from.cell]]
    t.cells[move.from.cell] = -1
  } else {
    cards = t.casc[move.from.col].splice(t.casc[move.from.col].length - move.n)
  }
  if (move.to.found) t.found[suitOf(cards[0])] = rankOf(cards[0])
  else if (move.to.cell !== undefined) t.cells[move.to.cell] = cards[0]
  else t.casc[move.to.col].push(...cards)
  // TableScene runs auto-collect after an accepted move, but stands aside once the
  // board is finishable — from there the Finish button owns the sweep.
  if (!canFinish(t)) autoCollect(t)
  return t
}

/** A canonical key for the visited set: columns and cells are interchangeable. */
export function stateKey(s) {
  const cells = s.cells.filter((c) => c >= 0).sort((a, b) => a - b)
  const cols = s.casc.map((c) => c.join(",")).sort()
  return `${s.found.join(".")}|${cells.join(",")}|${cols.join("/")}`
}

/**
 * Build a position from the sixteen piles `read-board.mjs` returns.
 *
 * The foundations need care. Cascades are `Fanned`, so the reader's order is the
 * pile order — but foundations are `Squared`: every card sits at identical
 * coordinates, there is no visual "on top", and DOM order there is z-order, not
 * pile order. Reading the last element as the top gets it wrong (which is exactly
 * how this went wrong the first time — a foundation read as `[2D, AD]`). A
 * foundation is an ascending same-suit run from the Ace, so its top is simply its
 * highest rank; that's recoverable no matter what order the cards come back in.
 */
export function stateFromPiles(piles) {
  const cells = [0, 1, 2, 3].map((i) => (piles[i].length ? cardId(piles[i][0]) : -1))
  const found = [0, 0, 0, 0]
  for (const pile of piles.slice(4, 8)) {
    if (!pile.length) continue
    const ids = pile.map(cardId)
    found[suitOf(ids[0])] = Math.max(...ids.map(rankOf))
  }
  return { cells, found, casc: piles.slice(8, 16).map((p) => p.map(cardId)) }
}

/** A move in words, for the play-by-play. */
export function describeMove(m) {
  const where = (spot) =>
    spot.found ? "foundation" : spot.cell !== undefined ? `cell ${spot.cell}` : `column ${spot.col}`
  const what = m.n > 1 ? `${cardCode(m.card)}+${m.n - 1}` : cardCode(m.card)
  return `${what} from ${where(m.from)} to ${where(m.to)}`
}
