// `mise run solve` — think through a deal without playing it.
//
//   mise run solve                          # FreeCell deal 1
//   mise run solve -- 24680                 # a particular deal
//   mise run solve -- 1-25                  # a range, for soaking the solver
//   mise run solve -- --quiet 1-100         # just the summary line
//   mise run solve -- --game simplesimon 7  # a Simple Simon deal
//
// What it's for, and what to measure with it: docs/solver.md § Measuring it.
//
// It runs core's *compiled* output directly (ReScript compiles in-source to
// `.res.mjs`), which is also the proof that the solver is reachable from plain
// Node — the same import the web-app's autoplay harness uses.
//
// Exits non-zero if any deal goes unsolved — a deal the search *proved* has no line
// (`effort.exhausted`) counts as answered, not unsolved.

import * as Game from "../src/Game.res.mjs"
import * as GameState from "../src/GameState.res.mjs"
import * as Position from "../src/Position.res.mjs"
import * as Solver from "../src/Solver.res.mjs"

function parseArgs(argv) {
  const opts = { seeds: [], quiet: false, game: "freecell" }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === "--quiet") opts.quiet = true
    else if (arg === "--game") opts.game = argv[++i]
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
const game = Game.byId(opts.game)
if (!game) throw new Error(`no game called ${opts.game} — one of ${Game.all.map((g) => g.id).join(", ")}`)

let solved = 0
let unwinnable = 0
let totalMs = 0
let totalMoves = 0
let worst = { seed: null, ms: 0 }

for (const seed of opts.seeds) {
  const deal = Game.dealt(game, seed)
  const position = Position.ofGameState(deal, GameState.initial(deal))
  if (!position) throw new Error(`${game.name} isn't a board the solver models`)
  const started = Date.now()
  const [line, effort] = Solver.solveWithEffort(position)
  const ms = Date.now() - started
  // The line as steps, the way `planSteps` says them — built here so the effort
  // (and with it whether a missing line was *proved* missing) is still to hand.
  let at = position
  const plan =
    line &&
    line.map((move) => {
      const step = Solver.stepFor(at, move)
      at = step.after
      return step
    })

  totalMs += ms
  if (ms > worst.ms) worst = { seed, ms }
  if (plan) {
    solved++
    totalMoves += plan.length
  } else if (effort.exhausted) unwinnable++

  if (!opts.quiet) {
    console.log(`\n=== deal #${seed} ===`)
    if (!plan) console.log(`  no solution — ${effort.exhausted ? "every line was tried" : "the ladder ran out"}`)
    else {
      plan.forEach((step, i) => console.log(`  ${String(i + 1).padStart(3)}. ${step.description}`))
      console.log(`  ${plan.length} moves to a finishable board, ${ms}ms of thinking`)
    }
  } else if (!plan) console.log(`deal ${seed}: ${effort.exhausted ? "unwinnable" : "no solution"} (${ms}ms)`)
}

const n = opts.seeds.length
const per = (x) => (x / Math.max(n, 1)).toFixed(0)
const unsolved = n - solved - unwinnable
console.log(
  `\n${solved}/${n} solved` +
    (unwinnable ? `, ${unwinnable} unwinnable` : "") +
    (unsolved ? `, ${unsolved} unsolved` : "") +
    ` — ${per(totalMs)}ms and ${(totalMoves / Math.max(solved, 1)).toFixed(0)} moves a deal on average` +
    (worst.seed === null ? "" : `, worst deal #${worst.seed} at ${worst.ms}ms`),
)

process.exit(unsolved === 0 ? 0 : 1)
