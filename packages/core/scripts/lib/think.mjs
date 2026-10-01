// One solver build, thinking one deal at a time for whoever forked it
// (`startThinker` in thinkers.mjs):
//
//   node --expose-gc think.mjs <src dir>
//   → { game, seed, mb }   ← { seed, grown, tried, ending, line, ms }
//
// The search runs to its budget with no patience, so what it grows is a function of
// the code and the deal alone: two builds that answer a deal with the same `grown`,
// `tried`, ending and line ran the same search on it. `ms` is the only part that
// isn't, and it is taken after a collection so one deal's garbage isn't the next
// deal's time.
//
// It touches only `Game`, `GameState`, `Position` and `Solver` by names that have
// been stable across the solver's rewrites; a base build that renamed one fails here
// on the first deal, loudly.

import { join } from "node:path"
import { pathToFileURL } from "node:url"

const src = process.argv[2]
const load = (name) => import(pathToFileURL(join(src, `${name}.res.mjs`)).href)
const [Game, GameState, Position, Solver] = await Promise.all(
  ["Game", "GameState", "Position", "Solver"].map(load),
)

// A cap of `mb` megabytes, or the build's own budget when there is none.
const budgetOf = (position, mb) => (mb == null ? undefined : { ...Solver.budgetFor(undefined, position), maxBytes: mb * 1e6 })

process.on("message", ({ game: id, seed, mb }) => {
  try {
    const game = Game.byId(id)
    if (!game) throw new Error(`no game called ${id} in ${src}`)
    const deal = Game.dealt(game, seed)
    const position = Position.ofGameState(deal, GameState.initial(deal))
    if (!position) throw new Error(`${id} isn't a board this solver models`)
    const budget = budgetOf(position, mb)
    globalThis.gc?.()
    const started = performance.now()
    const search = Solver.Search.make(position, budget, undefined)
    const [line, effort] = Solver.solveOn(search, undefined)
    const ms = performance.now() - started
    process.send({
      seed,
      grown: effort.positions,
      tried: effort.moves,
      ending: JSON.stringify(effort.ending),
      line: line ? line.map((move) => JSON.stringify(move)) : null,
      ms,
    })
  } catch (error) {
    process.send({ seed, error: String(error?.stack ?? error) })
  }
})

process.send({ ready: true })
