// `mise run solve` — think through a deal without playing it.
//
//   mise run solve                          # FreeCell deal 1
//   mise run solve -- 24680                 # a particular deal
//   mise run solve -- 1-25                  # a range, for soaking the solver
//   mise run solve -- --quiet 1-100         # just the summary line
//   mise run solve -- --game simplesimon 7  # another board, by `Game.t` id
//   mise run solve -- --game mini 1-200     # …a short-deck one, likewise
//   mise run solve -- --limit 10 1-200      # give up on a deal after ten seconds
//
// What it's for, and what to measure with it: docs/solver.md § Measuring it. That
// section also says what the "held" figure is and isn't, and why each deal is solved
// twice to take it.
//
// `--limit` is the wait a *driver* would impose, in seconds, so a soak can be run the
// way a front end actually calls the solver — and so the boards whose stubborn deals
// cost the whole ladder can be soaked in an evening rather than half a day. Left off,
// the ladder runs to its own end, which is what the benchmark record measures.
//
// It runs core's *compiled* output directly (ReScript compiles in-source to
// `.res.mjs`), which is also the proof that the solver is reachable from plain
// Node — the same import the web-app's autoplay harness uses.
//
// Exits non-zero if any deal goes unsolved — a deal the search *proved* has no line
// (`Solver.provedUnwinnable`) counts as answered, not unsolved. A deal that ran out of
// the `--limit` is unsolved like any other: the limit is what the caller chose to spend,
// not a verdict on the board.

import * as Game from "../src/Game.res.mjs"
import * as GameState from "../src/GameState.res.mjs"
import * as Position from "../src/Position.res.mjs"
import * as Solver from "../src/Solver.res.mjs"

function parseArgs(argv) {
  const opts = { seeds: [], quiet: false, game: "freecell", limit: null }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === "--quiet") opts.quiet = true
    else if (arg === "--game") opts.game = argv[++i]
    else if (arg === "--limit") {
      opts.limit = Number(argv[++i])
      if (!(opts.limit > 0)) throw new Error("--limit takes a number of seconds")
    } else if (/^\d+-\d+$/.test(arg)) {
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

// The wait `Solver.patience` is handed, in milliseconds. The clock beside it is a
// deal's own, below.
const ms = opts.limit === null ? Infinity : opts.limit * 1000
const limitSaid = opts.limit === null ? "" : `the ${opts.limit}s limit ran out`

let solved = 0
let unwinnable = 0
let outOfTime = 0
let totalMs = 0
let totalMoves = 0
let worst = { seed: null, ms: 0 }
let totalHeld = 0
let most = { seed: null, bytes: 0 }

// The collector has to be callable to read a live heap rather than a live heap plus
// whatever garbage happened not to be swept yet — the mise task passes the flag.
if (typeof globalThis.gc !== "function") throw new Error("run with node --expose-gc (mise run solve does)")
const liveHeap = () => {
  globalThis.gc()
  return process.memoryUsage().heapUsed
}

// The most the search held, read from inside the call. The solver reads the clock it
// is handed once at the start, once as each rung begins and once every
// `Solver.clockEvery` positions, and a rung's frontier and visited set only grow — so
// its graph is largest at its last read, within that many positions of where it
// stopped. A collection there would be charged to the timed run, so the solve is
// repeated with the first run's clock replayed: the same readings make the same search,
// whatever the limit, and only the repeat is collected.
//
// Every rung, not just the one that answered: a rung that spends its budget is released
// for the next, and the next may be stopped by the limit a few thousand positions in —
// so the heap at the answer can be a tenth of what the climb held a second earlier.
function heldBy(position, readings, passes) {
  // Which reads end a rung. Every rung before the last spent its whole budget, so its
  // count of reads is known; the last rung's final read is the call's.
  const ends = new Set([readings.length - 1])
  let read = 0
  for (const { maxNodes } of Solver.ladderFor(position).slice(0, passes - 1)) {
    read += 1 + Math.floor(maxNodes / Solver.clockEvery)
    ends.add(read)
  }
  let i = 0
  let held = 0
  const replay = () => {
    if (ends.has(i)) held = Math.max(held, liveHeap())
    return readings[i++]
  }
  const baseline = liveHeap()
  Solver.solveWithEffort(position, undefined, { ms, clock: replay })
  if (i !== readings.length) throw new Error(`the repeat read the clock ${i} times, the solve ${readings.length}`)
  return held - baseline
}

const mb = (bytes) => `${(bytes / 1e6).toFixed(0)} MB`

for (const seed of opts.seeds) {
  const deal = Game.dealt(game, seed)
  const position = Position.ofGameState(deal, GameState.initial(deal))
  if (!position) throw new Error(`${game.name} isn't a board the solver models`)
  const readings = []
  const clock = () => {
    const now = Date.now()
    readings.push(now)
    return now
  }
  const started = Date.now()
  // The middle argument is `~ladder`, left to the board's own: a ReScript optional
  // argument is positional by the time it reaches here. No `--limit` is a wait of
  // `Infinity`, which the search never reaches — the clock is still read, for `heldBy`.
  const [line, effort] = Solver.solveWithEffort(position, undefined, { ms, clock })
  const took = Date.now() - started
  const held = heldBy(position, readings, effort.passes)
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

  totalMs += took
  if (took > worst.ms) worst = { seed, ms: took }
  totalHeld += held
  if (held > most.bytes) most = { seed, bytes: held }
  // Three ways to come back without a line, and they are three different facts: a proof
  // the deal can't be won, the ladder spent, and the caller's own limit reached.
  const proved = Solver.provedUnwinnable(effort)
  const ranOut = Solver.ranOutOfTime(effort)
  if (plan) {
    solved++
    totalMoves += plan.length
  } else if (proved) unwinnable++
  else if (ranOut) outOfTime++

  const why = proved ? "every line was tried" : ranOut ? limitSaid : "the ladder ran out"
  if (!opts.quiet) {
    console.log(`\n=== deal #${seed} ===`)
    if (!plan) console.log(`  no solution — ${why}, ${took}ms of thinking holding ${mb(held)}`)
    else {
      plan.forEach((step, i) => console.log(`  ${String(i + 1).padStart(3)}. ${step.description}`))
      console.log(`  ${plan.length} moves to a finishable board, ${took}ms of thinking holding ${mb(held)}`)
    }
  } else if (!plan)
    console.log(
      `deal ${seed}: ${proved ? "unwinnable" : ranOut ? "out of time" : "no solution"} (${took}ms, ${mb(held)})`,
    )
}

const n = opts.seeds.length
const per = (x) => (x / Math.max(n, 1)).toFixed(0)
const unsolved = n - solved - unwinnable
console.log(
  `\n${solved}/${n} solved` +
    (unwinnable ? `, ${unwinnable} unwinnable` : "") +
    (unsolved ? `, ${unsolved} unsolved` : "") +
    (outOfTime ? ` (${outOfTime} out of time)` : "") +
    ` — ${per(totalMs)}ms and ${(totalMoves / Math.max(solved, 1)).toFixed(0)} moves a deal on average` +
    (worst.seed === null ? "" : `, worst deal #${worst.seed} at ${worst.ms}ms`) +
    ` — ${mb(totalHeld / Math.max(n, 1))} held a deal on average` +
    (most.seed === null ? "" : `, most by #${most.seed} at ${mb(most.bytes)}`),
)

process.exit(unsolved === 0 ? 0 : 1)
