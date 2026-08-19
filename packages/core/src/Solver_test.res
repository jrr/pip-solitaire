open Vitest

// The solver (#290, ported from #269's JavaScript). `Position_test` pins the rules
// it searches against the real reducer; what's left for here is the search itself:
// that it finds a line, that the line it finds is one the *game* will play (every
// move dispatched into `Reducer`, the board compared after each), and that the
// plan it hands a driver says the right things.
//
// Deals are named, never random: a solver test that picks its own board can't fail
// the same way twice.
describe("Solver", () => {
  let game = Game.freecellDeal(~seed=1)
  let opening = GameState.initial(game)

  let settle = (~game, state) =>
    if Reducer.canFinish(~game, state) {
      state
    } else {
      let (collected, _moved) = Reducer.autoCollect(~game, state)
      collected
    }

  // Play a plan on the real board, the way a driver would: convert each move to
  // the action it is, dispatch it, and settle. Returns the state it reached, or
  // the move it came unstuck on.
  let play = (~game, state, moves: array<Position.move>): result<GameState.t, string> =>
    moves->Array.reduceWithIndex(Ok(state), (carried, move, i) =>
      switch carried {
      | Error(_) as failed => failed
      | Ok(state) =>
        switch Position.toAction(~game, state, move) {
        | None => Error(`move ${Int.toString(i)}: ${Position.describeMove(move)} isn't an action`)
        | Some(action) =>
          switch Reducer.reduce(~game, state, action) {
          | Error(_) =>
            Error(`move ${Int.toString(i)}: the reducer refused ${Position.describeMove(move)}`)
          | Ok(next) => Ok(settle(~game, next))
          }
        }
      }
    )

  testWithin(
    "plays deal #1 to a board the Finish button wins",
    () =>
      switch Solver.plan(~game, opening) {
      | None => expect("deal 1 solved")->toBe("but the ladder ran out")
      | Some(moves) =>
        expect(Array.length(moves) > 20)->toBe(true) // a real game, not a shortcut
        switch play(~game, opening, moves) {
        | Error(why) => expect("the game played out")->toBe(why)
        | Ok(finished) =>
          // The goal of the search: not a won board, but one that a
          // foundation-only drain wins from — where the app's Finish button lights
          // up and the thinking is over.
          expect(Reducer.canFinish(~game, finished))->toBe(true)
          let (swept, _moved) = Reducer.finishSequence(~game, finished)
          expect(GameState.hasWon(game, swept))->toBe(true)
        }
      },
    ~timeout=60_000,
  )

  testWithin(
    "solves a spread of deals, and every plan is one the game will play",
    () => {
      // A soak, deliberately over deals with nothing special about them: the
      // solver is a heuristic search, so what's worth pinning is that it keeps
      // working across boards rather than on one lucky layout. (The full run —
      // deals 1–1000 — lives in `mise run solve`, which needs no test runner.)
      let unsolved = []
      for seed in 1 to 12 {
        let game = Game.freecellDeal(~seed)
        let opening = GameState.initial(game)
        switch Solver.plan(~game, opening) {
        | None => unsolved->Array.push(`deal ${Int.toString(seed)}: no plan`)
        | Some(moves) =>
          switch play(~game, opening, moves) {
          | Error(why) => unsolved->Array.push(`deal ${Int.toString(seed)}: ${why}`)
          | Ok(finished) =>
            if !Reducer.canFinish(~game, finished) {
              unsolved->Array.push(`deal ${Int.toString(seed)}: the plan ended short of a finish`)
            }
          }
        }
      }
      expect(unsolved)->toEqual([])
    },
    ~timeout=120_000,
  )

  test("a board that's already finishable needs no moves at all", () => {
    // `canFinish` is the goal, so a position that already meets it is solved by
    // the empty plan — not by `None`, which would mean "no line from here".
    switch Solver.plan(~game, opening) {
    | None => expect("deal 1 solved")->toBe("but the ladder ran out")
    | Some(moves) =>
      switch play(~game, opening, moves) {
      | Error(why) => expect("the game played out")->toBe(why)
      | Ok(finished) =>
        switch Solver.plan(~game, finished) {
        | Some(more) => expect(more)->toEqual([])
        | None => expect("an empty plan")->toBe("but got None")
        }
      }
    }
  })

  test("a board the model can't hold has no plan", () => {
    // Not "unsolvable" — unrepresentable. A card-table demo isn't FreeCell, and
    // the solver says so rather than searching some board it made up.
    expect(Solver.plan(~game=Game.stacking, GameState.initial(Game.stacking)))->toEqual(None)
  })

  test("a hint is the next move, as an action the reducer takes", () => {
    // The seam the game itself will use (a hint button, a demo that plays itself):
    // ask for one move, get something dispatchable.
    switch Solver.hint(~game, opening) {
    | None => expect("a hint")->toBe("but got None")
    | Some(action) =>
      switch Reducer.reduce(~game, opening, action) {
      | Ok(next) => expect(GameState.equal(next, opening))->toBe(false) // it moved something
      | Error(_) => expect("the reducer took the hint")->toBe("but it refused")
      }
    }
  })

  test("a plan is handed to a driver in the terms it plays moves in", () => {
    // What the browser autoplay harness reads: which card to grab, what that grab
    // should raise, where to drop it, and the board the move should leave behind.
    switch Position.ofGameState(~game, opening)->Option.flatMap(Solver.planSteps) {
    | None => expect("a plan")->toBe("but got None")
    | Some(steps) =>
      let problems = []
      steps->Array.forEach(
        step => {
          // The grabbed card is a real card…
          if Option.isNone(Position.idOfCode(step.card)) {
            problems->Array.push(`${step.card} isn't a card`)
          }

          // …and it leads the lift, since a run is grabbed by its bottom card.
          if step.lifts->Array.get(0) != Some(step.card) {
            problems->Array.push(`${step.card} doesn't lead the cards its own grab lifts`)
          }
          switch step.target {
          | "column" =>
            if step.column < 0 || step.column >= 8 {
              problems->Array.push(`${step.description}: no column ${Int.toString(step.column)}`)
            }
          | "cell" | "foundation" =>
            if step.column != -1 {
              problems->Array.push(`${step.description}: a ${step.target} has no column`)
            }
          | other => problems->Array.push(`${other} isn't a place to drop a card`)
          }
          if step.description->String.length == 0 {
            problems->Array.push("a move with nothing to say for itself")
          }
        },
      )
      expect(problems)->toEqual([])
      // The last board a plan leaves behind is the finishable one it was aiming at.
      switch steps->Array.last {
      | Some(last) => expect(Position.canFinish(last.after))->toBe(true)
      | None => expect("a plan with moves in it")->toBe("but it was empty")
      }
    }
  })

  // Autoplay (#291): the plan, played. `plan` is tested above as a *line*; what's
  // pinned here is that playing it is a real sequence of reducer moves ending on the
  // board the search was aiming at — the thing both front ends' `autoplay` verb hands
  // to their history, one recorded step at a time.
  describe("autoplay", () => {
    testWithin(
      "plays deal #1 out to a board the Finish button wins",
      () =>
        switch Solver.autoplay(~game, opening) {
        | Solver.NotFreeCell => expect("a FreeCell board")->toBe("but the solver didn't know it")
        | Solver.NoLine => expect("deal 1 played")->toBe("but the ladder ran out")
        | Solver.Played(steps) =>
          expect(Array.length(steps) > 20)->toBe(true) // a real game, not a shortcut
          // Every step's state is the one the step before it left, reduced by the
          // action it carries — so a driver that adopts these states in order is
          // playing the very moves it's recording, not two things that agree by luck.
          let problems = []
          let before = ref(opening)
          steps->Array.forEachWithIndex(
            (step: Solver.played, i) => {
              switch Reducer.reduce(~game, before.contents, step.action) {
              | Error(_) => problems->Array.push(`step ${Int.toString(i)}: the reducer refused it`)
              | Ok(next) =>
                if !GameState.equal(settle(~game, next), step.state) {
                  problems->Array.push(`step ${Int.toString(i)}: the state doesn't follow`)
                }
              }
              // …and each step says what it *moved*, which is what a driver animating
              // the line flies (#291): the card the action named first, so the move
              // leads and the collection follows it home, and every card in the list
              // somewhere new by the time the step is over. A step that claimed a card
              // that stayed put would fly it nowhere, in front of everything else.
              switch (step.action, step.moved->Array.get(0)) {
              | (Reducer.Move({card}), Some(first)) =>
                if !GameState.sameCard(card, first) {
                  problems->Array.push(`step ${Int.toString(i)}: the move doesn't lead`)
                }
              | (_, None) => problems->Array.push(`step ${Int.toString(i)}: it moved nothing`)
              | _ => ()
              }
              step.moved->Array.forEach(
                card =>
                  if (
                    GameState.locationOf(before.contents, card) ==
                      GameState.locationOf(step.state, card)
                  ) {
                    problems->Array.push(
                      `step ${Int.toString(i)}: ${CardText.format(card)} didn't move`,
                    )
                  },
              )
              before := step.state
            },
          )
          expect(problems)->toEqual([])
          // …and it stops where the search does: at the board the Finish sweep wins.
          expect(Reducer.canFinish(~game, before.contents))->toBe(true)
        },
      ~timeout=60_000,
    )

    test(
      "a board that's already finishable is played by doing nothing",
      () => {
        // `Played([])` and `NoLine` are different answers, and a driver treats them
        // differently: one hands over to the finish sweep, the other says it couldn't.
        let finishable = Scenario.freecellFinish(game)
        expect(Solver.autoplay(~game, finishable))->toEqual(Solver.Played([]))
      },
    )

    test(
      "a board the model can't hold is refused, not searched",
      () => {
        expect(Solver.autoplay(~game=Game.stacking, GameState.initial(Game.stacking)))->toEqual(
          Solver.NotFreeCell,
        )
      },
    )
  })

  test("the heuristic prefers the board that's closer to done", () => {
    // Not a number anyone should pin, but a direction: cards home are progress,
    // and a card parked in a free cell is a card in the way.
    switch Position.ofGameState(~game, opening) {
    | None => expect("a packed board")->toBe("but got None")
    | Some(position) =>
      // The same deal with two Aces home — taken off the columns they were lying
      // in, so it's a board that could really have happened.
      let ahead = {
        ...position,
        found: [1, 1, 0, 0],
        casc: position.casc->Array.map(
          pile => pile->Array.filter(c => !(Position.rankOf(c) == 1 && Position.suitOf(c) <= 1)),
        ),
      }
      // …and the same deal with a card parked in a free cell.
      let clogged = Position.copy(position)
      switch clogged.casc->Array.getUnsafe(0)->Array.pop {
      | Some(card) => clogged.cells->Array.setUnsafe(0, card)
      | None => ()
      }
      expect(
        Solver.heuristic(ahead, Solver.defaultWeights) <
        Solver.heuristic(position, Solver.defaultWeights),
      )->toBe(true)
      expect(
        Solver.heuristic(clogged, Solver.defaultWeights) >
        Solver.heuristic(position, Solver.defaultWeights),
      )->toBe(true)
    }
  })
})
