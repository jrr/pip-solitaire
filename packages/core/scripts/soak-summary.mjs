// `mise run soak-summary -- <record.json>…` — a soak's row for the benchmark record.
//
// Reads the files `mise run solve -- --record` wrote, one per slice of a range, and
// prints the row the record's table for that board takes (docs/solver.md § The
// benchmark record) — and, for a board that table is kept for, its row in § What the
// interactive wait costs — with its Environment cell left for the author to finish:
// the slices ran on separate machines at once, which is itself part of what that
// cell says. `--note <text>` is appended to it.

import { readFileSync } from "node:fs"
import { mb, rangeOf, time } from "./lib/format.mjs"

const files = []
let note = ""
const argv = process.argv.slice(2)
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === "--note") note = argv[++i]
  else files.push(argv[i])
}
if (!files.length) throw new Error("name the --record files to merge")

const records = files.map((f) => JSON.parse(readFileSync(f, "utf8")))
const [{ game, cap, limits, node }] = records
for (const r of records)
  if (r.game !== game || r.cap !== cap || String(r.limits) !== String(limits))
    throw new Error("these records aren't slices of one soak: game, cap and --limit must agree")

const deals = records.flatMap((r) => r.deals).sort((a, b) => a.seed - b.seed)
const n = deals.length
const count = (outcome) => deals.filter((d) => d.outcome === outcome).length
const solved = count("solved")
const mean = (xs) => xs.reduce((a, b) => a + b, 0) / Math.max(xs.length, 1)
const most = (key) => deals.reduce((w, d) => (d[key] > w[key] ? d : w))
const worst = most("ms")
const heaviest = most("held")

const environment = [
  `Node ${node}, CI runner, ${records.length} job${records.length > 1 ? "s" : ""} at once`,
  // The record names a cap only when it isn't the medium tier, which every soak in Node
  // runs at unless told otherwise.
  cap && !cap.startsWith("the medium tier") ? `capped at ${cap}` : null,
  limits ? `\`--limit ${limits.join("+")}\`` : null,
  note || null,
]
  .filter(Boolean)
  .join("; ")

// The tables differ by board: FreeCell's has no Unwinnable or Unsolved, and the short
// and repeated packs share a table with a Board column.
const boardColumn = {
  minifreecell: "Mini",
  microfreecell: "Micro",
  spiderette1: "1 suit",
  spiderette2: "2 suits",
}[game]
const cells = [
  new Date().toISOString().slice(0, 10),
  ...(boardColumn ? [boardColumn] : []),
  rangeOf(deals.map((d) => d.seed)),
  `${solved}/${n}`,
  ...(game === "freecell" ? [] : [count("unwinnable"), count("unsolved")]),
  time(mean(deals.map((d) => d.ms))),
  Math.round(mean(deals.filter((d) => d.moves !== null).map((d) => d.moves))),
  `#${worst.seed} at ${time(worst.ms)}`,
  `${mb(mean(deals.map((d) => d.held)))}, #${heaviest.seed} at ${mb(heaviest.held)}`,
  environment,
]

// § What the interactive wait costs: every board named, a Wait column, and no moves or
// Environment — a date's rows there share one sentence under the table instead.
const waitBoard = {
  simplesimon: "Simple Simon",
  spiderette1: "Spiderette · 1 suit",
  spiderette2: "Spiderette · 2 suits",
  spiderette4: "Spiderette · 4 suits",
}[game]
const waitCells = waitBoard && [
  cells[0],
  waitBoard,
  rangeOf(deals.map((d) => d.seed)),
  limits ? `${limits.join("+")} s` : "none",
  solved,
  count("unwinnable"),
  count("unsolved"),
  time(mean(deals.map((d) => d.ms))),
  `#${worst.seed} at ${time(worst.ms)}`,
  `${mb(mean(deals.map((d) => d.held)))}, #${heaviest.seed} at ${mb(heaviest.held)}`,
]

const outOfTime = deals.filter((d) => d.outOfTime).length
console.log(`${game}, ${n} deals over ${records.length} slice${records.length > 1 ? "s" : ""}:\n`)
console.log(`| ${cells.join(" | ")} |`)
if (waitCells) console.log(`\nIn § What the interactive wait costs:\n\n| ${waitCells.join(" | ")} |`)
if (outOfTime) console.log(`\n${outOfTime} of the unsolved ran out of the --limit rather than the budget.`)
