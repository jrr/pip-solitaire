// `mise run autoplay` — play the built web app, in a browser, to a win.
//
//   mise run autoplay                    # deal 1
//   mise run autoplay -- 24680           # a particular deal
//   mise run autoplay -- 1 7 24680       # several, in one browser
//   mise run autoplay -- 1-25            # a range, for soaking the harness
//   mise run autoplay -- --headed 24680  # watch it play
//   mise run autoplay -- --quiet 1-25    # just the summary table
//   mise run autoplay -- --shots out 42  # write deal/mid-game/win screenshots
//
// What it's for: driving the *real* app the way a player does — every move a
// pointer drag on the bundled site, nothing reaching into game state. That makes
// it an end-to-end exercise of the whole stack (rules, supermoves, auto-collect,
// the Finish sweep, win detection) in one command, and a way to see the game
// played without playing it. `browser-tests/autoplay.spec.mjs` runs the same
// harness on a fixed deal as a test; this is the interactive half.
//
// Exits non-zero if any deal fails to reach the win overlay.

import path from "node:path"
import fs from "node:fs"
import { assertBundled, launchChromium, startPreview } from "../lib/preview-app.mjs"
import { playGame } from "./autoplay.mjs"

function parseArgs(argv) {
  const opts = { seeds: [], headed: false, quiet: false, shots: null }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === "--headed") opts.headed = true
    else if (arg === "--quiet") opts.quiet = true
    else if (arg === "--shots") opts.shots = argv[++i]
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
assertBundled("autoplay")

const { base, close } = await startPreview()
const browser = await launchChromium({ headless: !opts.headed })
// A roomy desktop viewport, so every zone is comfortably on screen and a drag is a
// straight line across the board.
const page = await browser.newPage({ baseURL: base, viewport: { width: 900, height: 1100 } })
page.on("pageerror", (e) => console.error(`page error: ${e.message}`))

const shotDir = opts.shots ? path.resolve(opts.shots) : null
const results = []
try {
  for (const seed of opts.seeds) {
    console.log(`\n=== deal #${seed} ===`)
    const dir = shotDir ? path.join(shotDir, `deal-${seed}`) : null
    if (dir) fs.mkdirSync(dir, { recursive: true })

    let midShot = false
    const result = await playGame(page, {
      seed,
      log: (line) => console.log(line),
      onMove: async ({ index, description }) => {
        if (!opts.quiet) console.log(`  ${String(index).padStart(3)}. ${description}`)
        if (dir && index === 1) await page.screenshot({ path: path.join(dir, "01-deal.png") })
        if (dir && !midShot && index === 20) {
          await page.screenshot({ path: path.join(dir, "02-midgame.png") })
          midShot = true
        }
      },
    })
    if (dir) await page.screenshot({ path: path.join(dir, "03-win.png") })
    results.push(result)
  }
} finally {
  await browser.close()
  await close()
}

const won = results.filter((r) => r.won).length
console.log(`\n deal    plan  dragged  re-plans    time  result`)
for (const r of results) {
  const outcome = r.won ? `won — "${r.title}"` : `NOT WON — ${r.foundations}/52 home`
  console.log(
    ` ${String(r.seed).padEnd(7)} ${String(r.planned ?? "-").padStart(4)}  ${String(r.played).padStart(7)}  ${String(r.replans).padStart(8)}  ${`${r.seconds.toFixed(1)}s`.padStart(6)}  ${outcome}`,
  )
}
console.log(`\n${won}/${results.length} deals won`)
if (shotDir) console.log(`screenshots: ${shotDir}`)

process.exit(won === results.length ? 0 : 1)
