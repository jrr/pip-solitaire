// `mise run solve-same` — is this the same search as main's?
//
//   mise run solve-same                            # every board, its default sample
//   mise run solve-same -- --base HEAD~3           # against another commit
//   mise run solve-same -- --game freecell 1-1000  # one board, a range of your own
//
// Builds the base commit's solver (lib/baseline.mjs) and runs it and this tree's side
// by side, deal by deal, comparing what each search grew, the moves it tried, how it
// ended, and the line it found. A deal where any of those differ is printed; any such
// deal, or a deal either build couldn't think, exits non-zero. Times aren't compared:
// that's `solve-time`.
//
// What a match proves, and the sample it proves it over: docs/solver.md § Before you
// change the solver.

import { availableParallelism } from "node:os"
import { buildBaseline, resolveBase } from "./lib/baseline.mjs"
import { rangeOf, seedsOf } from "./lib/format.mjs"
import { headSrc, startThinker } from "./lib/thinkers.mjs"

// Each board's sample, costliest first so the slow deals start while the cheap ones
// fill the gaps. Sized so the whole plan is a few minutes on four cores. Spider deals
// nearly all run to the budget, so they are compared under a smaller cap: the same
// code grows the same positions up to it.
const plan = [
  { game: "spiderette4", seeds: seedsOf("1-30") },
  { game: "spiderette2", seeds: seedsOf("1-40") },
  { game: "spider4", seeds: seedsOf("1-3"), nodes: 100000 },
  { game: "spider2", seeds: seedsOf("1-3"), nodes: 100000 },
  { game: "spider1", seeds: seedsOf("1-3"), nodes: 100000 },
  { game: "simplesimon", seeds: seedsOf("1-150") },
  { game: "spiderette1", seeds: seedsOf("1-100") },
  { game: "freecell", seeds: seedsOf("1-300") },
  { game: "minifreecell", seeds: seedsOf("1-1000") },
  { game: "microfreecell", seeds: seedsOf("1-1000") },
]

function parseArgs(argv) {
  const opts = { base: "origin/main", game: null, seeds: [], nodes: null }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === "--base") opts.base = argv[++i]
    else if (arg === "--game") opts.game = argv[++i]
    else if (arg === "--nodes") opts.nodes = Number(argv[++i])
    else if (seedsOf(arg)) opts.seeds.push(...seedsOf(arg))
    else throw new Error(`unrecognised argument: ${arg}`)
  }
  if ((opts.seeds.length || opts.nodes !== null) && !opts.game) throw new Error("deals and --nodes need a --game")
  return opts
}

const opts = parseArgs(process.argv.slice(2))
const boards = opts.game
  ? [
      {
        ...(plan.find((b) => b.game === opts.game) ?? { game: opts.game, seeds: [1] }),
        ...(opts.seeds.length ? { seeds: opts.seeds } : {}),
        ...(opts.nodes !== null ? { nodes: opts.nodes } : {}),
      },
    ]
  : plan

const base = resolveBase(opts.base)
console.log(`base: ${base.sha.slice(0, 12)}, ${base.said}`)
const baseSrc = buildBaseline(base.sha)

// Half the cores to each build: a deal is asked of both at once, so the pair finishes
// together and neither queue runs ahead of the other.
const width = Math.max(1, Math.floor(availableParallelism() / 2))
const tasks = boards.flatMap(({ game, seeds, nodes }) => seeds.map((seed) => ({ game, seed, nodes })))
const outcome = new Map(boards.map((b) => [b.game, { left: b.seeds.length, differ: [] }]))
const started = Date.now()
let failed = false

// Where two answers part, said as the first field that does.
function differs(a, b) {
  for (const field of ["ending", "grown", "tried"])
    if (a[field] !== b[field]) return `${field} ${a[field]} → ${b[field]}`
  const [x, y] = [a.line ?? [], b.line ?? []]
  if ((a.line === null) !== (b.line === null)) return a.line ? "found a line → none" : "no line → found one"
  const at = x.findIndex((move, i) => move !== y[i])
  if (at >= 0 || x.length !== y.length) return `line parts at move ${(at >= 0 ? at : Math.min(x.length, y.length)) + 1}`
  return null
}

async function worker() {
  const old = startThinker(baseSrc)
  const now = startThinker(headSrc)
  try {
    for (let task = tasks.shift(); task; task = tasks.shift()) {
      const board = outcome.get(task.game)
      try {
        const [a, b] = await Promise.all([old.ask(task), now.ask(task)])
        const why = differs(a, b)
        if (why) board.differ.push(`#${task.seed}: ${why}`)
      } catch (error) {
        board.differ.push(`#${task.seed}: ${error.message}`)
      }
      if (--board.left === 0) report(task.game)
    }
  } finally {
    old.close()
    now.close()
  }
}

function report(game) {
  const { seeds, nodes } = boards.find((b) => b.game === game)
  const { differ } = outcome.get(game)
  const cap = nodes ? `, capped at ${nodes} nodes` : ""
  const secs = ((Date.now() - started) / 1000).toFixed(0)
  if (!differ.length) console.log(`same       ${game} ${rangeOf(seeds)}${cap}  (${secs}s)`)
  else {
    failed = true
    console.log(`DIFFERENT  ${game} ${rangeOf(seeds)}${cap}: ${differ.length} of ${seeds.length} deals`)
    for (const line of differ.sort((a, b) => parseInt(a.slice(1)) - parseInt(b.slice(1)))) console.log(`  ${line}`)
  }
}

await Promise.all(Array.from({ length: width }, worker))
console.log(
  failed
    ? `\nThe search differs from ${base.sha.slice(0, 12)}'s.`
    : `\nThe same search as ${base.sha.slice(0, 12)}'s on every deal compared.`,
)
process.exit(failed ? 1 : 0)
