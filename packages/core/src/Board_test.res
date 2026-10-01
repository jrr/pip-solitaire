open Vitest

// `Board` against `Position`, its oracle, on every board the picker offers.
// `Position_test` holds `Position` against `Reducer`; this holds `Board` against
// `Position`, and the two together are the mirror.
//
// A walk is a solver's line through a deal with random excursions off it, each
// taken back to where it left. The line is what carries a walk as far as a finish —
// random play on a full pack collects almost nothing — and the excursions are what
// take it where no line goes. Both are repeatable: the line is found on a node budget
// with a stopped clock, and every random choice is drawn from `Cards.xorshift` started
// at a fixed number, so a failure names a board, a deal and a step that replay exactly.
//
// At every board a walk stands on, every legal move is played and taken straight back,
// so the checks cover each move the board offers, not only the one the walk took.

// What the walks reached, so the test can insist they reached it.
type reached = {
  mutable deals: int,
  mutable collections: int, // a card or a run went home with no move sending it there
  mutable flips: int, // a move turned a face-down card over
  mutable finishes: int,
}

// A budget cheap enough for a unit test, and every deal below has a line inside it.
let cheap: Solver.budget = {heaps: [8.], maxNodes: 15_000}
let stopped: Solver.patience = {ms: Solver.interactive, clock: () => 0.}

let deals = (game: Game.t): array<int> =>
  switch game.id {
  | "simplesimon" => [1, 6]
  | "spiderette2" => [2, 5]
  | "spiderette4" => [12, 15]
  | "spider1" => [6, 7]
  | "spider2" => [27]
  | _ => [1, 2]
  }

// **Four suits over two decks is the one board with no line inside the rung** — nor
// in twice its weight and budget, over sixty deals. Its walks are the greedy ones
// below, which deal and turn cards over but never lift a run; the collect they miss
// is the same `collectRuns` Spider's two-suit pack reaches, on the same law.
let lineless = ["spider4"]
let greedySteps = 400

let describeAll = (moves: array<Position.move>) => moves->Array.map(Position.describeMove)

// The same board with its cells and its columns in another order — a board
// `Position.key` says is the same one, so `Board.hash` has to as well.
let shuffled = (s: Position.t): Position.t => {
  let cells = s.cells->Array.toReversed
  let order = s.casc->Array.mapWithIndex((_, i) => i)->Array.toReversed
  {
    ...s,
    cells,
    casc: order->Array.map(i => s.casc->Array.getUnsafe(i)->Array.copy),
    down: order->Array.map(i => s.down->Array.getUnsafe(i)),
  }
}

let hidden = (s: Position.t) => s.down->Array.reduce(0, (a, b) => a + b)

let walk = (~game: Game.t, ~seed: int, ~reached: reached, ~failures: array<string>) => {
  let fail = what => failures->Array.push(`${game.id} deal ${Int.toString(seed)}: ${what}`)
  switch Position.ofGameState(~game, GameState.initial(game)) {
  | None => fail("the opening doesn't pack")
  | Some(start) =>
    let board = Board.load(start)
    // Every board the walk stands on, the one it stands on now last.
    let history = [start]
    let here = () => history->Array.getUnsafe(Array.length(history) - 1)
    let rng = ref(Cards.seedState(seed * 7919 + String.length(game.id)))
    let draw = bound => {
      rng := Cards.xorshift(rng.contents)
      mod(rng.contents->Int.bitwiseAnd(0x7fffffff), bound)
    }
    let hashes = Map.make()
    let checkHash = (s: Position.t, (a, z)) => {
      let key = Position.key(s)
      let spelled = `${Int.toString(a)}:${Int.toString(z)}`
      switch hashes->Map.get(spelled) {
      | Some(other) if other != key => fail("two boards share a hash")
      | _ => hashes->Map.set(spelled, key)
      }
    }

    // Everything asked of the board the walk stands on, and of every move from it.
    // Returns the moves, and the one `Solver.heuristic` likes best among those that
    // lead somewhere the walk hasn't been.
    let visited = Set.make()
    let check = () => {
      let s = here()
      let at = `step ${Int.toString(Array.length(history) - 1)}`
      let offered = Board.legalMoves(board)
      if describeAll(offered->Array.map(Board.toMove)) != describeAll(Position.legalMoves(s)) {
        fail(`${at}: the legal moves differ`)
      }
      if offered->Array.map(Board.toMove)->Array.map(Board.ofMove) != offered {
        fail(`${at}: a move doesn't survive packing`)
      }
      if Board.canFinish(board) != Position.canFinish(s) {
        fail(`${at}: canFinish differs`)
      }
      let weights = Solver.weightsFor(s)
      if Board.heuristic(board, weights) != Solver.heuristic(s, weights) {
        fail(`${at}: the heuristic differs`)
      }
      let hash = Board.hash(board)
      checkHash(s, hash)
      if Board.hash(Board.load(shuffled(s))) != hash {
        fail(`${at}: the same board in another order hashes differently`)
      }
      let best = ref(None)
      offered->Array.forEach(move => {
        let said = `${at}, ${Position.describeMove(Board.toMove(move))}`
        let after = Position.applyMove(s, Board.toMove(move))
        Board.play(board, move)
        if Board.toPosition(board) != after {
          fail(`${said}: leaves another board`)
        }
        if Board.canFinish(board) != Position.canFinish(after) {
          fail(`${said}: canFinish differs`)
        }
        let h = Solver.heuristic(after, Solver.weightsFor(after))
        if Board.heuristic(board, Solver.weightsFor(after)) != h {
          fail(`${said}: the heuristic differs`)
        }
        checkHash(after, Board.hash(board))
        Board.takeBack(board)
        if Board.toPosition(board) != s {
          fail(`${said}: doesn't take back`)
        }
        switch best.contents {
        | _ if visited->Set.has(Position.key(after)) => ()
        | Some((_, bestH)) if bestH <= h => ()
        | _ => best := Some((move, h))
        }
      })
      (offered, best.contents->Option.map(Pair.first))
    }

    let advance = move => {
      let s = here()
      let m = Board.toMove(move)
      let after = Position.applyMove(s, m)
      Board.play(board, move)
      switch m {
      | Deal => reached.deals = reached.deals + 1
      | Play({destination}) =>
        let sent = destination == ToFoundation ? 1 : 0
        if Position.foundationTotal(after) > Position.foundationTotal(s) + sent {
          reached.collections = reached.collections + 1
        }
        if hidden(after) < hidden(s) {
          reached.flips = reached.flips + 1
        }
      }
      if Position.canFinish(after) {
        reached.finishes = reached.finishes + 1
      }
      visited->Set.add(Position.key(after))
      history->Array.push(after)
    }

    // Take back `n` moves, one at a time, through every board they passed.
    let retreat = n =>
      for _ in 1 to n {
        history->Array.pop->ignore
        Board.takeBack(board)
        if Board.toPosition(board) != here() {
          fail(
            `taking back to step ${Int.toString(Array.length(history) - 1)} leaves another board`,
          )
        }
      }

    visited->Set.add(Position.key(start))
    let line =
      lineless->Array.includes(game.id)
        ? None
        : Solver.solve(start, ~budget=cheap, ~patience=stopped)
    switch line {
    | Some(line) =>
      line->Array.forEach(next => {
        check()->ignore
        if draw(4) == 0 {
          let length = 1 + draw(8)
          let went = ref(0)
          let going = ref(true)
          while going.contents && went.contents < length {
            let (offered, _) = check()
            if Array.length(offered) == 0 {
              going := false
            } else {
              advance(offered->Array.getUnsafe(draw(Array.length(offered))))
              went := went.contents + 1
            }
          }
          check()->ignore
          retreat(went.contents)
        }
        advance(Board.ofMove(next))
      })
      check()->ignore
      if !Position.canFinish(here()) {
        fail("the line ends on a board that can't finish")
      }
    | None =>
      if !(lineless->Array.includes(game.id)) {
        fail("no line inside the rung")
      }
      // Mostly the best move to a board not yet visited, sometimes any such move.
      let stuck = ref(false)
      while !stuck.contents && Array.length(history) <= greedySteps {
        switch check() {
        | (_, None) => stuck := true
        | (offered, Some(best)) =>
          let fresh =
            offered->Array.filter(move =>
              !(visited->Set.has(Position.key(Position.applyMove(here(), Board.toMove(move)))))
            )
          advance(draw(5) == 0 ? fresh->Array.getUnsafe(draw(Array.length(fresh))) : best)
        }
      }
    }

    if Board.played(board) != Array.length(history) - 1 {
      fail("the board lost count of its moves")
    }
    retreat(Array.length(history) - 1)
    if Board.toPosition(board) != start {
      fail("the whole walk taken back isn't the opening")
    }
  }
}

describe("Board", () => {
  Game.all->Array.forEach(game =>
    testWithin(
      `plays and takes back every move as Position does, on ${game.id}`,
      () => {
        let reached = {deals: 0, collections: 0, flips: 0, finishes: 0}
        let failures = []
        deals(game)->Array.forEach(
          seed => walk(~game=Game.dealt(game, ~seed), ~seed, ~reached, ~failures),
        )
        expect(failures->Array.slice(~start=0, ~end=5))->toEqual([])

        // …and the walks went where the rules are hardest to mirror.
        let opening = GameState.initial(game)
        let deals = Array.length(Game.pileIndices(game, Game.Stock)) > 0
        let flips = opening.faceDown->Array.some(n => n > 0)
        let lined = !(lineless->Array.includes(game.id))
        expect((
          deals && reached.deals == 0,
          flips && reached.flips == 0,
          lined && reached.collections == 0,
          lined && reached.finishes == 0,
        ))->toEqual((false, false, false, false))
      },
      ~timeout=60_000,
    )
  )

  test("one move that lifts two runs off one column takes both back", () => {
    // Only a deal stacks one complete run on another, so no walk is likely to find
    // this board: ♠K…♠A under ♠K…♠2, and the ♠A beside them that completes both.
    let spades = Array.fromInitializer(~length=13, i => 12 - i)
    let posed: Position.t = {
      law: SimpleSimon,
      pack: Position.packOf(Game.spiderette1Deck),
      cells: [],
      found: [0, 0, 0, 0],
      casc: [spades->Array.concat(spades->Array.slice(~start=0, ~end=12)), [0]],
      down: [0, 0],
      stock: [],
    }
    let board = Board.load(posed)
    let move = Position.Play({
      n: 1,
      source: FromColumn(1),
      destination: ToColumn(0),
      card: 0,
    })
    Board.play(board, Board.ofMove(move))
    let after = Position.applyMove(posed, move)
    expect(after.found)->toEqual([26, 0, 0, 0])
    expect(Board.toPosition(board))->toEqual(after)
    Board.takeBack(board)
    expect(Board.toPosition(board))->toEqual(posed)
  })

  test("a move packs into an int and back as the same move", () => {
    let moves = [
      Position.Deal,
      Position.Play({n: 1, source: FromCell(3), destination: ToFoundation, card: 51}),
      Position.Play({n: 1, source: FromColumn(9), destination: ToCell(3), card: 0}),
      Position.Play({n: 104, source: FromColumn(9), destination: ToColumn(8), card: 38}),
      Position.Play({n: 1, source: FromCell(0), destination: ToColumn(0), card: 13}),
    ]
    expect(moves->Array.map(m => Board.toMove(Board.ofMove(m))))->toEqual(moves)
  })
})
