// `mise run solve-unasked` — what a tab spends thinking about a board nobody asked about.
//
//   mise run solve-unasked                                # FreeCell deals 1–20
//   mise run solve-unasked -- --game spiderette2 1-50     # another board, another range
//   mise run solve-unasked -- --allowance 30 1-20         # a per-board allowance of 30 s
//   mise run solve-unasked -- --chunk 250 1-20            # chunks of 250 ms (the default)
//
// The web app's `Thinker` thinks between asks: whenever the board has been still for a
// moment it hands the worker a short think, and another after each that comes back
// still going, until the search answers or the board's allowance (`Solver.unasked`) is
// spent. This replays that policy without a browser, over a *played game*: the line a
// patient solve of the deal finds, one board at a time, with a player who stops on every
// board long enough for the background to do all it would. That is the most the
// background can be given on a game a player wins by the solver's own line; a player who
// wanders off the line pays a fresh search wherever they leave it, and a deal with no
// line to play is played as its opening board alone.
//
// Each board's think is timed as the worker would spend it: the re-root the move costs
// (`Solver.Search.moved`, paid at the top of the next think), then chunks of `--chunk`
// milliseconds against the clock, until the search answers or the allowance is spent.
// What it prints per deal is the whole game's unasked thinking, and the boards that spent
// their whole allowance; the summary line is what docs/solver.md § What thinking unasked
// costs records.

import * as Game from "../src/Game.res.mjs"
import * as GameState from "../src/GameState.res.mjs"
import * as Position from "../src/Position.res.mjs"
import * as Solver from "../src/Solver.res.mjs"

function parseArgs(argv) {
  const opts = { seeds: [], game: "freecell", allowance: Solver.unasked / 1000, chunk: 250, quiet: false }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === "--game") opts.game = argv[++i]
    else if (arg === "--quiet") opts.quiet = true
    else if (arg === "--allowance") opts.allowance = Number(argv[++i])
    else if (arg === "--chunk") opts.chunk = Number(argv[++i])
    else if (/^\d+-\d+$/.test(arg)) {
      const [from, to] = arg.split("-").map(Number)
      for (let s = from; s <= to; s++) opts.seeds.push(s)
    } else if (/^\d+$/.test(arg)) opts.seeds.push(Number(arg))
    else throw new Error(`unrecognised argument: ${arg}`)
  }
  if (!(opts.allowance > 0)) throw new Error("--allowance takes a number of seconds")
  if (!(opts.chunk > 0)) throw new Error("--chunk takes a number of milliseconds")
  if (!opts.seeds.length) for (let s = 1; s <= 20; s++) opts.seeds.push(s)
  return opts
}

const opts = parseArgs(process.argv.slice(2))
const game = Game.byId(opts.game)
if (!game) throw new Error(`no game called ${opts.game} — one of ${Game.all.map((g) => g.id).join(", ")}`)
const allowanceMs = opts.allowance * 1000
// The tier a device that knows nothing about itself gets, as the worker's default does.
const budget = (position) => Solver.budgetFor(Solver.parseTier("medium"), position)
const clock = Date.now

// The game the player plays: a patient solve's line, as the boards it passes through.
function played(position) {
  const search = Solver.Search.make(position, budget(position), undefined)
  const [line] = Solver.solveOn(search, undefined)
  if (!line) return null
  const boards = []
  let at = position
  for (const move of line) {
    at = Solver.stepFor(at, move).after
    boards.push(at)
  }
  return boards
}

// One board thought about as `Thinker` would: chunk after chunk until the search answers
// or the allowance is spent. The first chunk carries the re-root a move left owing.
function background(search) {
  const started = performance.now()
  let ending
  do {
    const left = allowanceMs - (performance.now() - started)
    const [, effort] = Solver.solveOn(search, { ms: Math.min(opts.chunk, left), clock })
    ending = effort.ending
  } while (Solver.ranOutOfTime({ ending }) && performance.now() - started < allowanceMs)
  const ms = performance.now() - started
  return { ms, answered: !Solver.ranOutOfTime({ ending }) }
}

const sec = (ms) => (ms < 1000 ? `${ms.toFixed(0)}ms` : `${(ms / 1000).toFixed(1)}s`)
let total = 0
let worst = { seed: null, ms: 0 }
let spentWhole = 0
let boardsSeen = 0
let unplayed = 0
let firstTotal = 0

for (const seed of opts.seeds) {
  const deal = Game.dealt(game, seed)
  const opening = Position.ofGameState(deal, GameState.initial(deal))
  if (!opening) throw new Error(`${game.name} isn't a board the solver models`)
  const boards = played(opening)
  if (!boards) unplayed++
  // The tab's own search, grown only by the background, from the deal as it is laid.
  const search = Solver.Search.make(opening, budget(opening), undefined)
  let ms = 0
  let whole = 0
  let first = 0
  for (const [i, board] of [opening, ...(boards ?? [])].entries()) {
    if (i > 0) Solver.Search.moved(search, board)
    const spent = background(search)
    if (i === 0) first = spent.ms
    ms += spent.ms
    if (!spent.answered) whole++
  }
  const count = 1 + (boards?.length ?? 0)
  boardsSeen += count
  total += ms
  firstTotal += first
  spentWhole += whole
  if (ms > worst.ms) worst = { seed, ms }
  if (!opts.quiet)
    console.log(
      `deal ${seed}: ${sec(ms)} unasked over ${count} board${count === 1 ? "" : "s"}` +
        (boards ? "" : " (no line to play: the opening board only)") +
        ` — ${sec(first)} on the opening board` +
        (whole ? `, ${whole} spent the whole ${opts.allowance}s` : ""),
    )
}

const n = opts.seeds.length
console.log(
  `\n${game.id}, deals ${opts.seeds[0]}–${opts.seeds.at(-1)}: ${sec(total / n)} unasked a game on average` +
    ` (${sec(firstTotal / n)} of it on the opening board), worst deal #${worst.seed} at ${sec(worst.ms)}` +
    ` — ${spentWhole} of ${boardsSeen} boards spent the whole ${opts.allowance}s allowance` +
    (unplayed ? ` — ${unplayed} deal${unplayed === 1 ? "" : "s"} with no line, played as the opening board alone` : "") +
    ` — chunks of ${opts.chunk}ms`,
)
