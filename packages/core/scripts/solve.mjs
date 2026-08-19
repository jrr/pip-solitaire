// `mise run solve` — think through a deal without playing it.
//
//   mise run solve                 # deal 1
//   mise run solve -- 24680        # a particular deal
//   mise run solve -- 1-25         # a range, for soaking the solver
//   mise run solve -- --quiet 1-100  # just the summary line
//
// What it's for: the solver (`core/src/Solver.res`) with nothing else attached —
// no browser, no bundle, no drags. `mise run autoplay` is the same brain playing
// the real app through the DOM and takes a minute a deal; this takes milliseconds,
// so it's what you measure a heuristic change with, and how you find out whether a
// deal is one the ladder can't crack.
//
// It runs core's *compiled* output directly (ReScript compiles in-source to
// `.res.mjs`), which is also the proof that the solver is reachable from plain
// Node — the same import the web-app's autoplay harness uses.
//
// Exits non-zero if any deal goes unsolved.

import * as Game from "../src/Game.res.mjs"
import * as GameState from "../src/GameState.res.mjs"
import * as Position from "../src/Position.res.mjs"
import * as Solver from "../src/Solver.res.mjs"

function parseArgs(argv) {
  const opts = { seeds: [], quiet: false }
  for (const arg of argv) {
    if (arg === "--quiet") opts.quiet = true
    else if (/^\d+-\d+$/.test(arg)) {
      const [from, to] = arg.split("-").map(Number)
      for (let s = from; s <= to; s++) opts.seeds.push(s)
    } else if (/^\d+$/.test(arg)) opts.seeds.push(Number(arg))
    else throw new Error(`unrecognised argument: ${arg}`)
  }
  if (!opts.seeds.length) opts.seeds.push(1)
  return opts
}

const opts = parseArgs(process.argv.slice(2))

let solved = 0
let totalMs = 0
let totalMoves = 0
let worst = { seed: null, ms: 0 }

for (const seed of opts.seeds) {
  const game = Game.freecellDeal(seed)
  const position = Position.ofGameState(game, GameState.initial(game))
  const started = Date.now()
  const plan = Solver.planSteps(position)
  const ms = Date.now() - started

  totalMs += ms
  if (ms > worst.ms) worst = { seed, ms }
  if (plan) {
    solved++
    totalMoves += plan.length
  }

  if (!opts.quiet) {
    console.log(`\n=== deal #${seed} ===`)
    if (!plan) console.log("  no solution — the ladder ran out")
    else {
      plan.forEach((step, i) => console.log(`  ${String(i + 1).padStart(3)}. ${step.description}`))
      console.log(`  ${plan.length} moves to a finishable board, ${ms}ms of thinking`)
    }
  } else if (!plan) console.log(`deal ${seed}: no solution (${ms}ms)`)
}

const n = opts.seeds.length
const per = (x) => (x / Math.max(n, 1)).toFixed(0)
console.log(
  `\n${solved}/${n} solved — ${per(totalMs)}ms and ${(totalMoves / Math.max(solved, 1)).toFixed(0)} moves a deal on average` +
    (worst.seed === null ? "" : `, worst deal #${worst.seed} at ${worst.ms}ms`),
)

process.exit(solved === n ? 0 : 1)
