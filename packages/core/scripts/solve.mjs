// `mise run solve` — think through a deal without playing it.
//
//   mise run solve                          # FreeCell deal 1
//   mise run solve -- 24680                 # a particular deal
//   mise run solve -- 1-25                  # a range, for soaking the solver
//   mise run solve -- --quiet 1-100         # just the summary line
//   mise run solve -- --game simplesimon 7  # another board, by `Game.t` id
//   mise run solve -- --game minifreecell 1-200 # …a short-deck one, likewise
//   mise run solve -- --limit 10 1-200      # give up on a deal after ten seconds
//   mise run solve -- --limit 10+10 147     # …then ask the same search for ten more
//   mise run solve -- --tier large 147      # the budget a large device gets
//   mise run solve -- --mb 2000 147         # …or a cap of your own, in megabytes
//   mise run solve -- --reroot 1-100        # …and what following a move and its undo costs
//   mise run solve -- --record r.json 1-100 # …and every deal's figures, for soak-summary
//
// What it's for, and what to measure with it: docs/solver.md § Measuring it. That
// section also says what the "held" figure is and isn't. A range ends with what its
// lines look like to a player (lib/lines.mjs), taken on the line a driver is handed
// rather than the one printed: docs/solver.md § The line a player is handed.
//
// `--limit` is the wait a *driver* would impose, in seconds, so a soak can be run the
// way a front end actually calls the solver — and so the boards whose stubborn deals
// cost the whole budget can be soaked in an evening rather than half a day. Left off,
// the search runs to its own budget, which is what the benchmark record measures.
// Several waits joined by `+` are asked one after another of the *same* search, the
// way a driver that ran out of patience would ask for more: each carries on from where
// the last stopped, and the effort reported is all of them together.
//
// `--tier` is the memory tier the search is capped at (`Solver.capOf`), `medium` when
// left off — what a caller that knows nothing about its device gets. `--mb` replaces the
// cap with one of its own, keeping the board's heaps: how a run that means to hold more,
// and wait longer, says so. Each deal reports what it held per position grown, which is
// how a tier is read as positions on a board (docs/solver.md § Memory tiers).
//
// `--reroot` times the walk a search pays on every move a player makes with it open
// (`Solver.Search.moved`): once the search has answered, the board moves one move — the
// line's first, or the first move offered where there is no line — and the next think
// re-roots there; then the move is taken back and it re-roots again. Each is timed with
// the nodes it kept. The per-node cost it prints is what docs/solver.md § Re-rooting
// records.
//
// `--record` writes each deal's outcome, moves, time and Held to a JSON file once the
// last deal is done — what a soak split across CI jobs is put back together from
// (soak-summary.mjs). A file that exists is a run that finished, whatever it exits.
//
// It runs core's *compiled* output directly (ReScript compiles in-source to
// `.res.mjs`), which is also the proof that the solver is reachable from plain
// Node — the same import the web-app's autoplay harness uses.
//
// Exits non-zero if any deal goes unsolved — a deal the search *proved* has no line
// (`Solver.provedUnwinnable`) counts as answered, not unsolved. A deal that ran out of
// the `--limit` is unsolved like any other: the limit is what the caller chose to spend,
// not a verdict on the board.

import { writeFileSync } from "node:fs"
import * as Game from "../src/Game.res.mjs"
import * as GameState from "../src/GameState.res.mjs"
import * as Position from "../src/Position.res.mjs"
import * as Solver from "../src/Solver.res.mjs"
import { quality, qualitySaid } from "./lib/lines.mjs"

function parseArgs(argv) {
  const opts = { seeds: [], quiet: false, game: "freecell", limits: null, tier: null, mb: null, reroot: false, record: null }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === "--quiet") opts.quiet = true
    else if (arg === "--reroot") opts.reroot = true
    else if (arg === "--game") opts.game = argv[++i]
    else if (arg === "--record") opts.record = argv[++i]
    else if (arg === "--tier") {
      opts.tier = argv[++i]
      if (!Solver.parseTier(opts.tier)) throw new Error("--tier takes small, medium or large")
    } else if (arg === "--mb") {
      opts.mb = Number(argv[++i])
      if (!(Number.isInteger(opts.mb) && opts.mb > 0)) throw new Error("--mb takes a whole number of megabytes")
    }
    else if (arg === "--limit") {
      opts.limits = String(argv[++i]).split("+").map(Number)
      if (!opts.limits.every((limit) => limit > 0))
        throw new Error("--limit takes a number of seconds, or several joined by +")
    } else if (/^\d+-\d+$/.test(arg)) {
      const [from, to] = arg.split("-").map(Number)
      for (let s = from; s <= to; s++) opts.seeds.push(s)
    } else if (/^\d+$/.test(arg)) opts.seeds.push(Number(arg))
    else throw new Error(`unrecognised argument: ${arg}`)
  }
  if (!opts.seeds.length) opts.seeds.push(1)
  return opts
}

const mb = (bytes) => (bytes < 1e6 ? "<1 MB" : `${(bytes / 1e6).toFixed(0)} MB`)
const opts = parseArgs(process.argv.slice(2))
// The cap every deal is searched under: `--mb`'s, or the tier's.
const tier = Solver.parseTier(opts.tier ?? "medium")
const capBytes = opts.mb !== null ? opts.mb * 1e6 : Solver.capOf(tier)
const capSaid = opts.mb !== null ? `${opts.mb} MB` : `the ${opts.tier ?? "medium"} tier, ${mb(capBytes)}`
const budget = (position) => ({ ...Solver.budgetFor(tier, position), maxBytes: capBytes })
const game = Game.byId(opts.game)
if (!game) throw new Error(`no game called ${opts.game} — one of ${Game.all.map((g) => g.id).join(", ")}`)

// The waits `Solver.patience` is handed, one per ask — or one ask with no patience at
// all, which runs the search to its budget.
const asks = opts.limits === null ? [undefined] : opts.limits.map((s) => ({ ms: s * 1000, clock: Date.now }))
const limitSaid = opts.limits === null ? "" : `the ${opts.limits.join("+")}s limit ran out`

let solved = 0
let unwinnable = 0
let outOfTime = 0
let totalMs = 0
let totalMoves = 0
let worst = { seed: null, ms: 0 }
let totalHeld = 0
let most = { seed: null, bytes: 0 }
let totalArrays = 0
let totalPositions = 0
let costliest = { seed: null, each: 0 }
const lines = { park: 0, parkFree: 0, cellsFull: 0, lateHome: 0, joins: 0, swaps: 0, pairs: 0 }
const record = []

// The collector has to be callable to read a live heap rather than a live heap plus
// whatever garbage happened not to be swept yet — the mise task passes the flag.
if (typeof globalThis.gc !== "function") throw new Error("run with node --expose-gc (mise run solve does)")
// A typed array's contents live outside the JavaScript heap, in the backing stores
// `arrayBuffers` counts — which is where the search keeps its graph. A buffer the
// collector has found dead can still be counted there for a collection or two, so
// collect until two readings agree: a column outgrown just before the search stopped
// otherwise reads as held.
const liveHeap = () => {
  const read = () => {
    globalThis.gc()
    const { heapUsed, arrayBuffers } = process.memoryUsage()
    return heapUsed + arrayBuffers
  }
  let last = read()
  for (let i = 0; i < 5; i++) {
    const now = read()
    if (now === last) break
    last = now
  }
  return last
}

// Ask one search every wait in turn, stopping at the first that isn't cut short by the
// clock — and say what it cost, the most it held among that. A search never releases
// what it has grown, so it holds the most when it stops: the heap is read *after* the
// timed asks, with the search still in hand, so the collection is kept out of the time.
//
// Its own function so the search goes out of reach when it returns: left in the loop
// body below, the optimiser kept the last deal's alive into the next deal's baseline.
function think(position) {
  const baseline = liveHeap()
  const started = Date.now()
  // `~budget` and `~weights`, positionally — a ReScript optional argument is by the time
  // it reaches here. The board's own weights; its heaps at the tier's cap or `--mb`'s.
  const search = Solver.Search.make(position, budget(position), undefined)
  let line, effort
  let asked = 0
  do [line, effort] = Solver.solveOn(search, asks[asked++])
  while (Solver.ranOutOfTime(effort) && asked < asks.length)
  const took = Date.now() - started
  const held = liveHeap() - baseline
  if (search.grown !== effort.positions) throw new Error("the search and its effort disagree")
  const rerooted = opts.reroot ? reroot(search, position, line) : null
  return { line, effort, took, held, asked, rerooted }
}

// One move along, and back: the two re-roots `--reroot` measures, each as the nodes the
// graph held before, the nodes it kept, and the milliseconds the walk took. A think of
// nothing is the re-root alone.
function reroot(search, position, line) {
  const move = line?.[0] ?? Position.legalMoves(position)[0]
  if (move === undefined) return null
  const timed = (board) => {
    const before = search.graph.size
    Solver.Search.moved(search, board)
    const started = performance.now()
    Solver.Search.think(search, 0)
    return { before, kept: search.graph.size, ms: performance.now() - started }
  }
  const on = timed(Position.applyMove(position, move))
  const back = timed(position)
  return { on, back }
}

let rerootMs = 0
let rerootKept = 0
let rerootWorst = { seed: null, ms: 0 }
const rerootSaid = ({ before, kept, ms }) => `kept ${kept} of ${before} nodes in ${ms.toFixed(0)}ms`

// Held, and beside it what the search says its own arrays hold (`effort.bytes`) — the
// two should agree to within what the arrays don't count.
// …and what that came to per position grown: the figure a tier is read through.
const perPosition = (effort) => `${(effort.bytes / Math.max(effort.positions, 1)).toFixed(0)} B a position`
const holding = (held, effort) => `holding ${mb(held)} (arrays ${mb(effort.bytes)}, ${perPosition(effort)})`

for (const seed of opts.seeds) {
  const deal = Game.dealt(game, seed)
  const position = Position.ofGameState(deal, GameState.initial(deal))
  if (!position) throw new Error(`${game.name} isn't a board the solver models`)
  const { line, effort, took, held, asked, rerooted } = think(position)
  if (rerooted) {
    for (const { kept, ms } of [rerooted.on, rerooted.back]) {
      rerootMs += ms
      rerootKept += kept
      if (ms > rerootWorst.ms) rerootWorst = { seed, ms, kept }
    }
  }
  // Which ask answered, when there was more than one to make.
  const onAsk = asks.length > 1 && !Solver.ranOutOfTime(effort) ? ` on ask ${asked} of ${asks.length}` : ""
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
  if (held > most.bytes) most = { seed, bytes: held, arrays: effort.bytes }
  totalArrays += effort.bytes
  totalPositions += effort.positions
  // Among the deals that grew enough to matter: a search's first arrays are sized ahead of
  // what it grows, so a deal answered in a few hundred positions reads as kilobytes each.
  const each = effort.bytes / Math.max(effort.positions, 1)
  if (effort.bytes >= 10e6 && each > costliest.each) costliest = { seed, each }
  // Three ways to come back without a line, and they are three different facts: a proof
  // the deal can't be won, the budget spent, and the caller's own limit reached.
  const proved = Solver.provedUnwinnable(effort)
  const ranOut = Solver.ranOutOfTime(effort)
  if (plan) {
    solved++
    totalMoves += plan.length
    // What the line a driver gets looks like to a player — the polished line, where
    // the one printed above is the search's own.
    const q = quality(Position, position, Solver.polished(position, line))
    for (const k in q) lines[k] += q[k]
  } else if (proved) unwinnable++
  else if (ranOut) outOfTime++

  record.push({
    seed,
    outcome: plan ? "solved" : proved ? "unwinnable" : "unsolved",
    outOfTime: !plan && ranOut,
    moves: plan ? plan.length : null,
    ms: took,
    held,
    arrays: effort.bytes,
    positions: effort.positions,
  })

  const why = proved ? "every line was tried" : ranOut ? limitSaid : "the budget ran out"
  if (!opts.quiet) {
    console.log(`\n=== deal #${seed} ===`)
    if (!plan) console.log(`  no solution — ${why}${onAsk}, ${took}ms of thinking ${holding(held, effort)}`)
    else {
      plan.forEach((step, i) => console.log(`  ${String(i + 1).padStart(3)}. ${step.description}`))
      console.log(
        `  ${plan.length} moves to a finishable board${onAsk}, ${took}ms of thinking ${holding(held, effort)}`,
      )
    }
    if (rerooted)
      console.log(`  re-rooted one move on: ${rerootSaid(rerooted.on)}; and back: ${rerootSaid(rerooted.back)}`)
  } else if (!plan)
    console.log(
      `deal ${seed}: ${proved ? "unwinnable" : ranOut ? "out of time" : "no solution"} (${took}ms, ${mb(held)}, arrays ${mb(effort.bytes)}, ${perPosition(effort)})`,
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
    ` — ${mb(totalHeld / Math.max(n, 1))} held a deal on average (arrays ${mb(totalArrays / Math.max(n, 1))})` +
    (most.seed === null ? "" : `, most by #${most.seed} at ${mb(most.bytes)} (arrays ${mb(most.arrays)})`) +
    ` — ${(totalArrays / Math.max(totalPositions, 1)).toFixed(0)} B a position grown over the range` +
    (costliest.seed === null ? "" : `, most by #${costliest.seed} at ${costliest.each.toFixed(0)} B of those holding 10 MB`) +
    ` — capped at ${capSaid}`,
)

const law = Position.lawOf(game)
if (solved > 0) console.log(qualitySaid(lines, solved, law))

if (opts.reroot && rerootKept > 0)
  console.log(
    `re-rooting: ${((rerootMs / rerootKept) * 1000).toFixed(1)}ms per thousand nodes kept, over ${rerootKept} nodes` +
      ` — worst deal #${rerootWorst.seed}, ${rerootWorst.ms.toFixed(0)}ms to keep ${rerootWorst.kept}`,
  )

if (opts.record)
  writeFileSync(
    opts.record,
    JSON.stringify({ game: game.id, cap: capSaid, limits: opts.limits, node: process.version, deals: record }),
  )

process.exit(unsolved === 0 ? 0 : 1)
