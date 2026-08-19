// A best-first FreeCell solver over `Position` — the "brain" a driver plays with.
//
// The goal isn't a completed board but `Position.canFinish`: the point where the
// app's own Finish button lights up and everything left is a foundation-only
// drain. That's the real end of the *thinking* part of a game, and stopping there
// keeps the search shallow.
//
// Good enough, not optimal: it looks for a line that wins, not the shortest one.
// Soaked over deals 1–1000 (dealt by `Game.freecellDeal`, so core's own shuffle)
// it solved all 1000, averaging ~160ms of thinking per deal and ~54 moves to the
// finishable board — but with a long tail, the worst deal taking ~13s. Nothing
// here promises a solution: FreeCell has unsolvable deals, and `solve` returns
// `None` when the ladder runs out rather than pretending otherwise.
//
// Ported from the JavaScript solver the autoplay harness carried (#269 → #290),
// so the search and the rules it searches are now one language in one package:
// the browser harness, the test suite and the game itself all reach it from here.

// --- The heuristic -----------------------------------------------------------

// Heuristic term weights, kept nameable so they can be measured rather than
// guessed — `search` takes them, which is how these were chosen.
//
// The two that earned their keep are the mobility terms: charging for a loaded
// free cell (`cell`) and paying for an empty column (`emptyColumn`). Without them
// the search cheerfully plays itself into positions with nowhere to move, and the
// stubborn deals cost tens of seconds instead of under one.
type weights = {
  remaining: int,
  buried: int,
  seam: int,
  cell: int,
  emptyColumn: int,
}

let defaultWeights = {remaining: 2, buried: 2, seam: 1, cell: 3, emptyColumn: 3}

// Distance-to-go estimate. Four things make a position bad: cards still off the
// foundations, cards sitting on top of one a foundation is waiting for, columns
// whose descending runs are broken, and a board with nowhere to put anything.
let heuristic = (s: Position.t, w: weights): int => {
  let h = ref((52 - Position.foundationTotal(s)) * w.remaining)
  for col in 0 to Array.length(s.casc) - 1 {
    let pile = s.casc->Array.getUnsafe(col)
    let depth = Array.length(pile)
    if depth == 0 {
      h := h.contents - w.emptyColumn // room to manoeuvre
    }
    for i in 0 to depth - 1 {
      let card = pile->Array.getUnsafe(i)

      // Buried where a foundation wants it: every card above it must move first.
      if s.found->Array.getUnsafe(Position.suitOf(card)) == Position.rankOf(card) - 1 {
        h := h.contents + (depth - 1 - i) * w.buried
      }

      // A break in the descending alternating run is a seam that has to be undone.
      if i > 0 {
        let below = pile->Array.getUnsafe(i - 1)
        if (
          !(
            Position.rankOf(below) == Position.rankOf(card) + 1 &&
              Position.isRed(below) != Position.isRed(card)
          )
        ) {
          h := h.contents + w.seam
        }
      }
    }
  }
  // A card parked in a cell is a card in the way.
  h.contents + (Position.cellCount - Position.emptyCells(s)) * w.cell
}

// --- A tiny binary heap, keyed by numeric priority ---------------------------
// Its own little module rather than a sorted array: the open list is pushed and
// popped hundreds of thousands of times per deal, and re-sorting it that often is
// the whole cost of the search.

module Heap = {
  type entry<'a> = {item: 'a, priority: float}
  type t<'a> = array<entry<'a>>

  let make = (): t<'a> => []
  let size = (heap: t<'a>): int => Array.length(heap)

  let swap = (heap: t<'a>, i: int, j: int) => {
    let atI = heap->Array.getUnsafe(i)
    heap->Array.setUnsafe(i, heap->Array.getUnsafe(j))
    heap->Array.setUnsafe(j, atI)
  }

  let push = (heap: t<'a>, item: 'a, ~priority: float) => {
    heap->Array.push({item, priority})
    let i = ref(Array.length(heap) - 1)
    let sifting = ref(true)
    while sifting.contents && i.contents > 0 {
      let parent = (i.contents - 1) / 2
      if (heap->Array.getUnsafe(parent)).priority <= (heap->Array.getUnsafe(i.contents)).priority {
        sifting := false
      } else {
        swap(heap, parent, i.contents)
        i := parent
      }
    }
  }

  let pop = (heap: t<'a>): option<'a> =>
    switch heap->Array.get(0) {
    | None => None
    | Some(top) =>
      switch heap->Array.pop {
      | Some(last) if Array.length(heap) > 0 =>
        heap->Array.setUnsafe(0, last)
        let i = ref(0)
        let sifting = ref(true)
        while sifting.contents {
          let left = 2 * i.contents + 1
          let right = left + 1
          let smallest = ref(i.contents)
          if (
            left < Array.length(heap) &&
              (heap->Array.getUnsafe(left)).priority <
              (heap->Array.getUnsafe(smallest.contents)).priority
          ) {
            smallest := left
          }
          if (
            right < Array.length(heap) &&
              (heap->Array.getUnsafe(right)).priority <
              (heap->Array.getUnsafe(smallest.contents)).priority
          ) {
            smallest := right
          }
          if smallest.contents == i.contents {
            sifting := false
          } else {
            swap(heap, smallest.contents, i.contents)
            i := smallest.contents
          }
        }
      | _ => () // the heap held one entry, and popping it emptied the array
      }
      Some(top.item)
    }
}

// --- The search --------------------------------------------------------------

// How hard one pass tries. `weight` scales the heuristic against depth: a high
// weight is greedy and dives, a low one searches wider and costs more per answer.
// `maxNodes` is the budget it gives up at.
type attempt = {weight: float, maxNodes: int}

// What a pass came back with: the moves to a finishable board, or `None` if it
// ran out of budget — and what it cost to get there, which is what makes the
// weights measurable. `nodes` counts the positions taken off the frontier and grown;
// `applied` the moves played out to see where they led, which is the bigger number
// and the one most of the time goes into (every one of them is an `applyMove`, a
// `key` and a `canFinish`).
type outcome = {path: option<array<Position.move>>, nodes: int, applied: int}

// One node of the open list: a position and the moves that reached it.
type node = {position: Position.t, path: array<Position.move>}

// Weighted best-first search from `start` to the first position that
// `Position.canFinish`.
let search = (start: Position.t, attempt: attempt, ~weights: weights=defaultWeights): outcome =>
  if Position.canFinish(start) {
    {path: Some([]), nodes: 0, applied: 0}
  } else {
    let frontier = Heap.make()
    let seen = Map.make()
    seen->Map.set(Position.key(start), 0)
    frontier->Heap.push(
      {position: start, path: []},
      ~priority=Int.toFloat(heuristic(start, weights)) *. attempt.weight,
    )
    let nodes = ref(0)
    let applied = ref(0)
    let found = ref(None)
    while (
      Option.isNone(found.contents) && Heap.size(frontier) > 0 && nodes.contents < attempt.maxNodes
    ) {
      switch Heap.pop(frontier) {
      | None => ()
      | Some({position, path}) =>
        nodes := nodes.contents + 1
        let moves = Position.legalMoves(position)
        let i = ref(0)
        while Option.isNone(found.contents) && i.contents < Array.length(moves) {
          let move = moves->Array.getUnsafe(i.contents)
          let next = Position.applyMove(position, move)
          applied := applied.contents + 1
          let key = Position.key(next)
          let g = Array.length(path) + 1
          // A position reached no more cheaply than before teaches nothing new.
          switch seen->Map.get(key) {
          | Some(prior) if prior <= g => ()
          | _ =>
            seen->Map.set(key, g)
            let nextPath = Array.concat(path, [move])
            if Position.canFinish(next) {
              found := Some(nextPath)
            } else {
              frontier->Heap.push(
                {position: next, path: nextPath},
                ~priority=Int.toFloat(g) +. Int.toFloat(heuristic(next, weights)) *. attempt.weight,
              )
            }
          }
          i := i.contents + 1
        }
      }
    }
    {path: found.contents, nodes: nodes.contents, applied: applied.contents}
  }

// The escalation ladder: a mildly greedy pass first, since almost every deal falls
// to it, then wider searches for the ones that don't. The rungs are capped
// deliberately — a rung that can't find it in its budget is usually a rung that
// never will, and the wasted nodes were most of the old worst case.
let ladder = [
  {weight: 2., maxNodes: 60_000},
  {weight: 1., maxNodes: 150_000},
  {weight: 4., maxNodes: 150_000},
  {weight: 0.5, maxNodes: 400_000},
]

// What a solve cost, totalled over every rung it climbed — for a front end that
// wants to say how hard the answer was to find, and not only what it was.
//
//   `positions` — boards taken off the frontier and grown.
//   `moves`     — moves played out to see where they led (the "and then what?"
//                 count; several per position, and the bigger number by far).
//   `passes`    — rungs of the ladder it took. One is an ordinary deal; more than
//                 one means the greedy pass gave up and a wider search found it.
//
// Deliberately no clock: how *long* it took is the caller's own measurement, taken
// around a call it made (`solve.mjs` already does exactly that, and both front ends
// now do). Keeping the number out of here is what lets a plan stay a value two runs
// can be expected to agree on — an ordinary `toEqual` in a test, rather than a
// timing-shaped hole in one.
type effort = {positions: int, moves: int, passes: int}

// Solve to the finishable position, escalating effort until it gives — or `None`
// when the whole ladder runs out, which is all this can honestly say about a deal
// (a rung that fails proves nothing about solvability). Reports what the climb cost
// alongside the line, since a rung that failed still spent its budget and a caller
// saying "found in 65ms" is describing all of them.
let solveWithEffort = (start: Position.t, ~ladder: array<attempt>=ladder): (
  option<array<Position.move>>,
  effort,
) => {
  let plan = ref(None)
  let rung = ref(0)
  let positions = ref(0)
  let moves = ref(0)
  while Option.isNone(plan.contents) && rung.contents < Array.length(ladder) {
    let {path, nodes, applied} = search(start, ladder->Array.getUnsafe(rung.contents))
    positions := positions.contents + nodes
    moves := moves.contents + applied
    plan := path
    rung := rung.contents + 1
  }
  (plan.contents, {positions: positions.contents, moves: moves.contents, passes: rung.contents})
}

// The line alone, for the callers that only ever wanted that.
let solve = (start: Position.t, ~ladder: array<attempt>=ladder): option<array<Position.move>> =>
  fst(solveWithEffort(start, ~ladder))

// --- On making this faster (measured, then deferred) -------------------------
// Asked in passing: would a WASM module be significantly faster? Profiled rather
// than guessed — `node --cpu-prof` over deals 1–60 plus 1848, about thirty seconds
// of solving — and the answer is "yes, but that isn't where the time is". Self-time
// as this stands:
//
//   24.8%  the garbage collector
//   19.2%  `search` itself — the loop, the visited map, the path array per node
//   31.3%  `Position.key` — nine strings built and sorted per generated position
//   ~15%   the game: `legalMoves`, `applyMove`, `canFinish`, `autoCollect`, `heuristic`
//
// So the arithmetic a rewrite in another language makes faster is about a seventh
// of the runtime. The rest is how a position is *represented*: string keys, a fresh
// path array per node (`Array.concat`), and the allocation those two imply.
//
// Changing only those two — an FNV-1a-per-column numeric key, and parent pointers
// instead of copied paths — measured ~1.9× over deals 1–60, finding the identical
// line on every one of them. Re-profiled after that, the collector is still ~23%,
// now behind `applyMove`'s `copy`; make/unmake against one mutable board would take
// most of that too. Call it 3–4× available without leaving the language, and the
// rules untouched by any of it.
//
// What WASM adds on top is the usual 1.2–2× of integer loops over an optimising
// JIT — and it costs the thing #290 bought. The search asks `legalMoves` /
// `applyMove` / `canFinish` millions of times a deal, so the boundary can't sit
// between the search and the rules: the rules move into the module too, in whatever
// language it's written in, and `Position` becomes a mirror no unit test can pin
// (`Position_test` holds it against `Reducer` precisely because both sides are one
// build). It would also put a second toolchain in `mise.toml`, and make
// `Solver.autoplay` async — browsers cap synchronous WebAssembly compilation at 4KB
// on the main thread, and both front ends call it from inside a command that
// answers synchronously.
//
// Deferred deliberately: nothing is waiting on it. A deal averages under 100ms and
// the worst of five hundred is under three seconds. If the budget is ever wanted,
// spend it at the cheap end of that list first — and note that the reason to want
// it is more likely a *shorter line* than a faster one, which is the trade `weight`
// above already makes.

// --- Playing the plan on a real board ----------------------------------------

// The moves to a finishable board from a real `GameState` — the game-facing entry
// point (a hint button, a demo that plays itself, a test that needs a game played
// through). `None` when the board isn't a FreeCell one or no rung of the ladder
// found a line.
//
// The plan is a plan for a game played with auto-collect *on* (`Options.default`,
// see `Position.applyMove`): with it off the moves stay legal, but the board after
// each one won't be the one the plan predicted.
let plan = (~game: Game.t, state: GameState.t): option<array<Position.move>> =>
  Position.ofGameState(~game, state)->Option.flatMap(position => solve(position))

// The next move to play, as the action a driver dispatches — the smallest useful
// thing to ask the solver, and the one the game itself will want first.
let hint = (~game: Game.t, state: GameState.t): option<Reducer.action> =>
  plan(~game, state)
  ->Option.flatMap(moves => moves->Array.get(0))
  ->Option.flatMap(move => Position.toAction(~game, state, move))

// --- Autoplay: the plan, played out (#291) ------------------------------------
// `plan` says which moves win from here and `Position.toAction` says one of them in
// the reducer's terms. What's left — running them one after another against a real
// `GameState` and keeping the board in step — is the part *both* front ends would
// otherwise write for themselves, so it's written here once and they play the same
// game (the rule the shared `Command` grammar exists for).
//
// The settling is core's rather than the caller's, and that's the load-bearing bit:
// a plan is a plan for a game played with auto-collect **on** (see
// `Position.applyMove`), so a driver with the flag off would leave the board a card
// behind the plan and every later move would bounce off a pile the plan thought was
// empty. Playing the line here keeps it exactly the line the search found, whatever
// the driver's own house rules say — the flag governs what the *player's* moves
// trigger, not what the solver's plan means.
//
// It stops where the search stops: at the first position `Reducer.canFinish` clears,
// which is where the app's own Finish button lights up. Sweeping the board home from
// there is the finish both drivers already have, so autoplay doesn't grow a second
// copy of it — it thinks, and hands over.

// One planned move, played: the move said in the reducer's own vocabulary, and the
// settled board it leaves behind. Enough for a driver to record one undoable step per
// move without re-deriving a position the plan already knows — and the `action` is
// what lets it *say* what it played, in the same words a typed move is logged in.
//
// `moved` is what a driver that *animates* the line needs: the cards this step
// displaces, in the order they moved — the ones the action names, then whatever the
// settle swept up behind them. It's core's to report for the same reason the settling
// is core's to do: the collection happens in here, so a driver reading only `state`
// would have to re-derive which cards it took to get there.
type played = {
  action: Reducer.action,
  state: GameState.t,
  moved: array<Card.card>,
}

// What autoplay found. The two refusals are different questions and read as
// different sentences (`Command.autoplayNotFreeCell` / `autoplayNoLine`): one board
// the solver doesn't understand, one it understands and can't win. A `Played` with no
// steps is neither — it's a board already finishable, where there was nothing left to
// think about.
//
// `Played` carries what the search cost alongside the line it found (`effort`), so a
// front end can say how hard the answer was to come by. It travels with the steps
// rather than being asked for separately because it's a fact about *this* answer —
// ask again and you'd be timing a second search.
type autoplayed =
  | Played({steps: array<played>, effort: effort})
  | NotFreeCell // not the four-cell, four-foundation, eight-column board the solver models
  | NoLine // the ladder ran out (which proves nothing about the deal — see `solve`)

// The post-move settle the plan assumes: safe auto-collect, standing aside once the
// board is finishable — `Position.applyMove`'s own rule, said against a real state.
// Reports the cards it sent home along with the settled board, so a step can say
// everything that moved and not just where the board ended up.
let settle = (~game: Game.t, state: GameState.t): (GameState.t, array<Card.card>) =>
  if Reducer.canFinish(~game, state) {
    (state, [])
  } else {
    Reducer.autoCollect(~game, state)
  }

// The cards an action names, bottom-first, which is the order they'd be lifted in.
// A column reorder names none — it moves whole piles rather than cards.
let namedCards = (action: Reducer.action): array<Card.card> =>
  switch action {
  | Reducer.Move({card}) => [card]
  | Reducer.MoveRun({cards}) => cards
  | Reducer.MoveColumn(_) => []
  }

let autoplay = (~game: Game.t, state: GameState.t): autoplayed =>
  switch Position.ofGameState(~game, state) {
  | None => NotFreeCell
  | Some(position) =>
    let (line, effort) = solveWithEffort(position)
    switch line {
    | None => NoLine
    | Some(moves) =>
      let steps = []
      let current = ref(state)
      // A plan generated from these very rules shouldn't come unstuck against them,
      // but a driver handed half a plan and told it was whole would play a board
      // nobody can explain. So a move that won't convert or won't reduce ends the
      // line *here*, and what comes back is the prefix that really was played.
      let stopped = ref(false)
      let i = ref(0)
      while !stopped.contents && i.contents < Array.length(moves) {
        switch Position.toAction(~game, current.contents, moves->Array.getUnsafe(i.contents)) {
        | None => stopped := true
        | Some(action) =>
          switch Reducer.reduce(~game, current.contents, action) {
          | Error(_) => stopped := true
          | Ok(next) =>
            let (settled, collected) = settle(~game, next)
            steps->Array.push({
              action,
              state: settled,
              moved: Array.concat(namedCards(action), collected),
            })
            current := settled
          }
        }
        i := i.contents + 1
      }
      Played({steps, effort})
    }
  }

// --- The plan, in the terms a driver outside ReScript plays it in ------------
// The browser autoplay harness (`web-app/scripts/autoplay/`) is JavaScript: it
// reads the board off a rendered page and plays each move as a pointer drag. It
// has no business unpacking a `Position.move`, so a plan is handed to it already
// said in its terms — which card to grab, what that grab should raise, where to
// drop it, and the board the move should leave behind.

// One planned move, ready to drag.
//   `card`        — the card to grab, as a `CardText` code.
//   `lifts`       — every card that grab should raise, bottom-first, so a driver
//                   can check that the board lifted what the plan meant.
//   `target`      — where it lands: "foundation", "cell" or "column".
//   `column`      — the destination column 0–7, or `-1` for the other targets.
//   `description` — the move in words, for a play-by-play.
//   `after`       — the position this move should leave behind, for a driver that
//                   re-reads the board and checks (`Position.key`).
type step = {
  card: string,
  lifts: array<string>,
  target: string,
  column: int,
  description: string,
  after: Position.t,
}

// One move said that way, against the position it's played from — for a driver
// that picked the move itself (playing a single move by hand, see the
// `play-in-browser` skill) rather than taking a whole plan.
let stepFor = (position: Position.t, move: Position.move): step => {
  card: Position.code(move.card),
  lifts: Position.lifted(position, move)->Array.map(Position.code),
  target: switch move.destination {
  | Position.ToFoundation => "foundation"
  | Position.ToCell(_) => "cell"
  | Position.ToColumn(_) => "column"
  },
  column: switch move.destination {
  | Position.ToColumn(col) => col
  | _ => -1
  },
  description: Position.describeMove(move),
  after: Position.applyMove(position, move),
}

// The plan from `start` as steps: `None` when the ladder ran out, and `Some([])`
// when the board is already finishable and there's nothing left to think about.
let planSteps = (start: Position.t): option<array<step>> =>
  solve(start)->Option.map(moves => {
    let position = ref(start)
    moves->Array.map(move => {
      let step = stepFor(position.contents, move)
      position := step.after
      step
    })
  })
