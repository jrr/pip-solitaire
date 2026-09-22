// `mise run profile` — where a throttled frame goes.
//
//   mise run profile                        # deal 1, 12 drags, 6× slower CPU
//   mise run profile -- 24680               # a particular deal
//   mise run profile -- --throttle 4 24680  # a less punishing device
//   mise run profile -- --moves 20 24680    # a longer sample
//   mise run profile -- --game simplesimon 3
//   mise run profile -- --headed 24680      # watch it drag
//
// What it's for: deciding what to move off the main thread, and then telling
// whether moving it helped. `mise run solve` is the equivalent for the solver —
// the thing you measure a change against before and after.
//
// It plays the opening drags of a deal against a build of the real site, under
// CPU throttling, with a trace running, and prints where the main thread's time
// went.
//
// `docs/profiling.md` has what the numbers mean, what they can't tell you, and
// the record to compare a change against. Read it before acting on a ranking.

import { assertBundled, launchChromium, startPreview } from "../lib/preview-app.mjs"
import { playGame } from "../autoplay/autoplay.mjs"
import { frameResolver } from "./frames.mjs"
import {
  byName, forcedStyleAndLayout, longTasks, mainThread, startRecording, timeline,
} from "./trace.mjs"

const OUT_DIR = "dist-profile"

function parseArgs(argv) {
  const opts = { seed: null, game: "freecell", throttle: 6, moves: 12, headed: false, top: 15 }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === "--headed") opts.headed = true
    else if (arg === "--game") opts.game = argv[++i]
    else if (arg === "--throttle") opts.throttle = Number(argv[++i])
    else if (arg === "--moves") opts.moves = Number(argv[++i])
    else if (arg === "--top") opts.top = Number(argv[++i])
    else if (/^\d+$/.test(arg)) {
      // One deal, unlike `autoplay`'s list and ranges: a profile is a
      // measurement of one board, and averaging several would hide the thing
      // it is for — that deal 24680's opening drags cost what they cost.
      if (opts.seed !== null) throw new Error(`profile takes one deal, got ${opts.seed} and ${arg}`)
      opts.seed = Number(arg)
    } else throw new Error(`unrecognised argument: ${arg}`)
  }
  if (opts.seed === null) opts.seed = 1
  if (!(opts.throttle >= 1)) throw new Error(`--throttle must be at least 1, got ${opts.throttle}`)
  if (!(opts.moves >= 1)) throw new Error(`--moves must be at least 1, got ${opts.moves}`)
  return opts
}

/** Microseconds, as a number a human compares: `312ms`, `7.52s`. */
const dur = (us) => (us >= 1_000_000 ? `${(us / 1e6).toFixed(2)}s` : `${Math.round(us / 1000)}ms`)

const opts = parseArgs(process.argv.slice(2))
assertBundled("profile", OUT_DIR)

const { base, close } = await startPreview({ outDir: OUT_DIR })
const browser = await launchChromium({ headless: !opts.headed })
// The same roomy desktop viewport `autoplay` uses, so a drag is the same
// straight line across the board and two runs measure the same gesture.
const page = await browser.newPage({ baseURL: base, viewport: { width: 900, height: 1100 } })
page.on("pageerror", (e) => console.error(`page error: ${e.message}`))
const cdp = await page.context().newCDPSession(page)

console.log(
  `\n=== ${opts.game} deal #${opts.seed} — ${opts.moves} drags at ${opts.throttle}× CPU throttle ===\n`,
)

let trace = null
let events = []
try {
  const report = await playGame(page, {
    seed: opts.seed,
    game: opts.game,
    maxMoves: opts.moves,
    log: (line) => console.log(line),
    onMove: ({ index, description }) => console.log(`  ${String(index).padStart(3)}. ${description}`),
    // A settled opening board, before the first drag: throttle from here, so the
    // page load isn't in the sample, and start recording from here for the same
    // reason. `setCPUThrottlingRate` slows the renderer only — the GPU runs at
    // full speed — so anything compositor-side is understated below, not
    // overstated.
    onReady: async () => {
      await cdp.send("Emulation.setCPUThrottlingRate", { rate: opts.throttle })
      trace = await startRecording(cdp)
    },
  })
  events = await trace.stop()
  trace = null
  if (report.played < opts.moves)
    console.log(`\n! the deal ran out of moves after ${report.played} of ${opts.moves}`)
} finally {
  if (trace) await trace.stop().catch(() => {})
  await browser.close()
  await close()
}

const thread = mainThread(events)
const main = timeline(events, thread)
if (!main.length) {
  console.error("\nno main-thread events in the trace — nothing to report")
  process.exit(1)
}

// Reduced rather than spread into `Math.max`: a longer `--moves` run puts tens
// of thousands of events here, and an argument list that long is a stack overflow.
const end = main.reduce((furthest, e) => Math.max(furthest, e.ts + (e.dur ?? 0)), 0)
const span = end - main[0].ts
const { self, total, count } = byName(main)
console.log(
  `\nmain thread: ${dur(span)} of trace, ${dur(total.get("RunTask") ?? 0)} of it in tasks\n`,
)
// Ranked by `total`, which is what a gesture's cost is: a `pointerup` dispatch
// is 500ms of work in its callees and almost nothing in itself, and ranking by
// `self` would file it below a GC. `self` is the second column rather than the
// order, for reading where the thread actually sat once the nesting is undone.
console.log("     total       self    count  event")
for (const [name, us] of [...total].sort((a, b) => b[1] - a[1]).slice(0, opts.top)) {
  const cells = [
    dur(us).padStart(10),
    dur(self.get(name) ?? 0).padStart(11),
    String(count.get(name)).padStart(9),
  ]
  console.log(`${cells.join("")}  ${name}`)
}

const long = longTasks(main)
const longTotal = long.reduce((sum, e) => sum + e.dur, 0)
console.log(
  long.length
    ? `\nlong tasks (≥50ms): ${long.length}, ${dur(longTotal)} in total, longest ${dur(long[0].dur)}`
    : "\nlong tasks (≥50ms): none",
)

const { forced, foreign, sites } = forcedStyleAndLayout(main, frameResolver({ base, outDir: OUT_DIR }))
const appForced = forced - foreign
const appUs = sites.reduce((sum, s) => sum + s.us, 0)
console.log(
  `\nstyle/layout forced from JS: ${forced} recalcs — ${appForced} from app code (${dur(appUs)}),` +
    ` ${foreign} from the harness's own board reads`,
)
if (sites.length) {
  console.log("\n    count      total  call site")
  for (const s of sites.slice(0, opts.top)) {
    console.log(`${String(s.count).padStart(9)}${dur(s.us).padStart(11)}  ${s.site}`)
    if (s.source) console.log(`${" ".repeat(22)}${s.source}`)
  }
  if (sites.length > opts.top)
    console.log(`\n  …and ${sites.length - opts.top} more call sites (--top ${sites.length})`)
}
