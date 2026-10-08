// What a line looks like to a player — the figures docs/solver.md § The line a player
// is handed keeps, taken on the line a driver is handed (`Solver.polished`), never on
// the search's own. `mise run solve` prints them over its range.
//
// Each is a count a skilled player would hold against a line, and each is taken on the
// position the move is played from:
//
//   park       — the line opens with a card parked in a cell, and `parkFree` when a move
//                that spends nothing (to a foundation, or onto a card in a column) was
//                there to make instead. The Hint shows that first move.
//   cellsFull  — positions on the line with every cell loaded.
//   lateHome   — cards that could go to a foundation and are sent there later on the
//                line, without moving in between.
//   joins      — positions where a whole run could join its own suit's next rank and the
//                line did something else. Simple Simon's law only.
//   swaps      — neighbouring moves that could be played in either order to the same
//                board, of `pairs` neighbouring pairs: how much of the order is still
//                nobody's choice.
//   moves      — the line's length as handed over, and `shortenedBy` the moves the polish
//                took out of the search's line.

const isPlay = (move) => move !== "Deal"
const toColumn = (move) => (isPlay(move) && move.destination.TAG === "ToColumn" ? move.destination._0 : -1)
const toCell = (move) => isPlay(move) && move.destination.TAG === "ToCell"
const toFoundation = (move) => isPlay(move) && move.destination === "ToFoundation"
const fromColumn = (move) => (isPlay(move) && move.source.TAG === "FromColumn" ? move.source._0 : -1)
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b)

export function quality(Position, start, line) {
  const q = { park: 0, parkFree: 0, cellsFull: 0, lateHome: 0, joins: 0, swaps: 0, pairs: 0, moves: line.length }
  const positions = [start]
  for (const move of line) positions.push(Position.applyMove(positions[positions.length - 1], move))
  const legal = (position, move) => Position.legalMoves(position).some((x) => same(x, move))
  const free = (position, move) =>
    isPlay(move) && (toFoundation(move) || (toColumn(move) >= 0 && position.casc[toColumn(move)].length > 0))
  if (line.length && toCell(line[0])) {
    q.park = 1
    if (Position.legalMoves(start).some((move) => free(start, move))) q.parkFree = 1
  }
  const late = new Set()
  for (let i = 0; i < line.length; i++) {
    const move = line[i]
    const position = positions[i]
    if (position.cells.length && position.cells.every((card) => card >= 0)) q.cellsFull++
    if (i + 1 < line.length && isPlay(move) && isPlay(line[i + 1])) {
      q.pairs++
      const next = line[i + 1]
      if (legal(position, next)) {
        const swapped = Position.applyMove(position, next)
        if (legal(swapped, move) && Position.key(Position.applyMove(swapped, move)) === Position.key(positions[i + 2]))
          q.swaps++
      }
    }
    if (!isPlay(move)) continue
    const moves = Position.legalMoves(position)
    if (position.law === "SimpleSimon") {
      const joins = moves.filter((x) => {
        const from = fromColumn(x)
        const to = toColumn(x)
        if (from < 0 || to < 0 || position.casc[to].length === 0) return false
        const whole = x.n === Position.runLength(position.law, position.casc[from], position.down[from])
        return whole && Position.suitOf(position.casc[to].at(-1)) === Position.suitOf(x.card)
      })
      if (joins.length && !joins.some((x) => same(x, move))) q.joins++
    } else if (!toFoundation(move)) {
      for (const x of moves) {
        if (!toFoundation(x) || late.has(x.card)) continue
        const later = line.slice(i + 1).find((y) => isPlay(y) && y.card === x.card)
        if (later && toFoundation(later)) late.add(x.card)
      }
    }
  }
  q.lateHome = late.size
  return q
}

// The figures over a range, one line. `law` is the board's; FreeCell's cells have
// nothing to say under Simple Simon's, and its joins nothing under FreeCell's.
export function qualitySaid(sum, solved, law) {
  if (!solved) return ""
  const per = (x) => (x / solved).toFixed(1)
  const pct = (x, of) => `${Math.round((100 * x) / Math.max(of, 1))}%`
  const swaps =
    `${pct(sum.swaps, sum.pairs)} of neighbouring moves could swap` +
    `, ${per(sum.moves)} moves a line (${per(sum.shortenedBy)} fewer than the search's)` +
    `, polished in ${per(sum.polishMs)}ms a line (worst ${sum.polishWorst.toFixed(0)}ms)`
  return law === "FreeCell"
    ? `lines as handed over: ${pct(sum.park, solved)} open with a park (${pct(sum.parkFree, solved)} with a free move waiting)` +
        `, every cell full at ${per(sum.cellsFull)} positions a line, ${per(sum.lateHome)} cards a line sent home late, ${swaps}`
    : `lines as handed over: ${per(sum.joins)} same-suit joins a line passed over, ${swaps}`
}
