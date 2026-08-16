// A best-first FreeCell solver over the mirrored rules — the "brain" of the
// autoplay harness (see ./autoplay.mjs).
//
// The goal isn't a completed board but `canFinish`: the point where the app's own
// Finish button lights up and everything left is a foundation-only drain. That's
// the real end of the *thinking* part of a game, and stopping there keeps the
// search shallow.
//
// Good enough, not optimal: it looks for a line that wins, not the shortest one.
// Soaked over deals 1–1000 (dealt by `Game.freecellDeal`, so core's own shuffle)
// it solved all 1000, averaging ~160ms of thinking per deal and ~54 moves to the
// finishable board — but with a long tail, the worst deal taking ~13s. Nothing
// here promises a solution: FreeCell has unsolvable deals, and `solve` returns
// `null` when the ladder runs out rather than pretending otherwise.

import {
  applyMove, canFinish, emptyCells, foundationTotal, isRed, legalMoves, rankOf,
  stateKey, suitOf,
} from "./rules.mjs"

/**
 * Heuristic term weights, kept nameable so they can be measured rather than
 * guessed — `search` takes them as `hWeights`, which is how these were chosen.
 *
 * The two that earned their keep are the mobility terms: charging for a loaded
 * free cell (`cell`) and paying for an empty column (`emptyColumn`). Without
 * them the search cheerfully plays itself into positions with nowhere to move,
 * and the stubborn deals cost tens of seconds instead of under one.
 */
export const WEIGHTS = { remaining: 2, buried: 2, seam: 1, cell: 3, emptyColumn: 3 }

/**
 * Distance-to-go estimate. Four things make a position bad: cards still off the
 * foundations, cards sitting on top of one a foundation is waiting for, columns
 * whose descending runs are broken, and a board with nowhere to put anything.
 */
export function heuristic(s, w = WEIGHTS) {
  let h = (52 - foundationTotal(s)) * w.remaining
  for (const pile of s.casc) {
    for (let i = 0; i < pile.length; i++) {
      const card = pile[i]
      // Buried where a foundation wants it: every card above it must move first.
      if (s.found[suitOf(card)] === rankOf(card) - 1) h += (pile.length - 1 - i) * w.buried
      // A break in the descending alternating run is a seam that has to be undone.
      if (i > 0) {
        const below = pile[i - 1]
        if (!(rankOf(below) === rankOf(card) + 1 && isRed(below) !== isRed(card))) h += w.seam
      }
    }
  }
  h += (4 - emptyCells(s)) * w.cell // a card parked in a cell is a card in the way
  h -= s.casc.filter((p) => p.length === 0).length * w.emptyColumn // room to manoeuvre
  return h
}

/** A tiny binary heap, keyed by numeric priority. */
class Heap {
  #a = []
  get size() { return this.#a.length }
  push(item, pri) {
    const a = this.#a
    a.push({ item, pri })
    let i = a.length - 1
    while (i > 0) {
      const p = (i - 1) >> 1
      if (a[p].pri <= a[i].pri) break
      ;[a[p], a[i]] = [a[i], a[p]]
      i = p
    }
  }
  pop() {
    const a = this.#a
    const top = a[0]
    const last = a.pop()
    if (a.length) {
      a[0] = last
      let i = 0
      for (;;) {
        const l = 2 * i + 1, r = l + 1
        let m = i
        if (l < a.length && a[l].pri < a[m].pri) m = l
        if (r < a.length && a[r].pri < a[m].pri) m = r
        if (m === i) break
        ;[a[m], a[i]] = [a[i], a[m]]
        i = m
      }
    }
    return top.item
  }
}

/**
 * Weighted best-first search. `weight` scales the heuristic against depth: a high
 * weight is greedy and dives, a low one searches wider and costs more per answer.
 */
export function search(start, { weight, maxNodes, hWeights = WEIGHTS }) {
  if (canFinish(start)) return { path: [], nodes: 0 }
  const open = new Heap()
  const seen = new Map([[stateKey(start), 0]])
  open.push({ state: start, path: [] }, heuristic(start, hWeights) * weight)
  let nodes = 0
  while (open.size && nodes < maxNodes) {
    const { state, path } = open.pop()
    nodes++
    for (const move of legalMoves(state)) {
      const next = applyMove(state, move)
      const key = stateKey(next)
      const g = path.length + 1
      const prior = seen.get(key)
      if (prior !== undefined && prior <= g) continue
      seen.set(key, g)
      const nextPath = [...path, move]
      if (canFinish(next)) return { path: nextPath, nodes }
      open.push({ state: next, path: nextPath }, g + heuristic(next, hWeights) * weight)
    }
  }
  return { path: null, nodes }
}

/**
 * The escalation ladder: a mildly greedy pass first, since almost every deal
 * falls to it, then wider searches for the ones that don't. The rungs are capped
 * deliberately — a rung that can't find it in its budget is usually a rung that
 * never will, and the wasted nodes were most of the old worst case.
 */
export const LADDER = [
  { weight: 2, maxNodes: 60_000 },
  { weight: 1, maxNodes: 150_000 },
  { weight: 4, maxNodes: 150_000 },
  { weight: 0.5, maxNodes: 400_000 },
]

/** Solve to the finishable position, escalating effort until it gives. */
export function solve(start, { ladder = LADDER, onAttempt } = {}) {
  for (const attempt of ladder) {
    const { path, nodes } = search(start, attempt)
    onAttempt?.({ ...attempt, nodes, solved: !!path })
    if (path) return path
  }
  return null
}

