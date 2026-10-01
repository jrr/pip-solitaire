// `mise run solve-time` — is this tree's solver faster than main's?
//
//   mise run solve-time -- --game freecell 1-200
//   mise run solve-time -- --game spiderette4 1-20 --runs 2
//   mise run solve-time -- --base HEAD~1 --game simplesimon 1-100
//
// Two processes, one per build, each holding its solver warm. Every deal is thought by
// both, one after the other, the order swapping each time (old then new, new then old)
// so neither build always runs second on a warmer machine. Each deal's time is the
// mean over `--runs`. The pair is the measurement: the times printed here compare with
// each other and with nothing else (docs/solver.md § Before you change the solver).
//
// It also checks the two searches answered each deal alike, and says how many didn't:
// a speed-up that changed what's searched is timing different work.

import { buildBaseline, resolveBase } from "./lib/baseline.mjs"
import { rangeOf, seedsOf, time } from "./lib/format.mjs"
import { headSrc, startThinker } from "./lib/thinkers.mjs"

function parseArgs(argv) {
  const opts = { base: "origin/main", game: "freecell", seeds: [], runs: 1, mb: null }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === "--base") opts.base = argv[++i]
    else if (arg === "--game") opts.game = argv[++i]
    else if (arg === "--runs") opts.runs = Number(argv[++i])
    else if (arg === "--mb") opts.mb = Number(argv[++i])
    else if (seedsOf(arg)) opts.seeds.push(...seedsOf(arg))
    else throw new Error(`unrecognised argument: ${arg}`)
  }
  if (!(Number.isInteger(opts.runs) && opts.runs > 0)) throw new Error("--runs takes a whole number")
  if (!opts.seeds.length) opts.seeds = seedsOf("1-100")
  return opts
}

const opts = parseArgs(process.argv.slice(2))
const base = resolveBase(opts.base)
console.log(`base: ${base.sha.slice(0, 12)}, ${base.said}`)
const builds = [
  { name: "base", thinker: startThinker(buildBaseline(base.sha)), ms: new Map() },
  { name: "this", thinker: startThinker(headSrc), ms: new Map() },
]

// Each build thinks the first deal once untimed, so neither pays for its JIT warming up
// inside the pair.
const ask = (build, seed) => build.thinker.ask({ game: opts.game, seed, mb: opts.mb })
for (const build of builds) await ask(build, opts.seeds[0])

let unlike = 0
let turn = 0
for (const seed of opts.seeds) {
  for (let run = 0; run < opts.runs; run++) {
    const order = turn++ % 2 === 0 ? builds : [...builds].reverse()
    const answers = []
    for (const build of order) {
      const answer = await ask(build, seed)
      build.ms.set(seed, (build.ms.get(seed) ?? 0) + answer.ms / opts.runs)
      answers.push(answer)
    }
    const [a, b] = answers
    if (run === 0 && (a.grown !== b.grown || a.tried !== b.tried || a.ending !== b.ending)) unlike++
  }
}
for (const { thinker } of builds) thinker.close()

const summary = ({ ms }) => {
  const times = [...ms.values()]
  const [worstSeed, worstMs] = [...ms].reduce((w, d) => (d[1] > w[1] ? d : w))
  return { total: times.reduce((a, b) => a + b, 0), mean: times.reduce((a, b) => a + b, 0) / times.length, worstSeed, worstMs }
}
const [old, now] = builds.map(summary)
const ratios = opts.seeds.map((s) => builds[1].ms.get(s) / builds[0].ms.get(s))
const geomean = Math.exp(ratios.reduce((a, r) => a + Math.log(r), 0) / ratios.length)
const faster = ratios.filter((r) => r < 1).length
const n = opts.seeds.length

console.log(`\n${opts.game} ${rangeOf(opts.seeds)}, ${opts.runs} run${opts.runs > 1 ? "s" : ""} a deal${opts.mb ? `, capped at ${opts.mb} MB` : ""}`)
for (const [name, s] of [["base", old], ["this", now]])
  console.log(`  ${name}  mean ${time(s.mean).padStart(7)}, worst #${s.worstSeed} at ${time(s.worstMs)}`)
console.log(
  `  this/base: ${(now.total / old.total).toFixed(2)} of the time over the range;` +
    ` ${geomean.toFixed(2)} a deal (geometric mean); faster on ${faster} of ${n}`,
)
if (unlike) console.log(`  ${unlike} of ${n} deals were searched differently — the pair is timing different work there`)
