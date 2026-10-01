open Vitest

// The solver. `Position_test` pins the rules it searches against the real reducer;
// what's left for here is the search itself. A line is checked by playing it — every
// move dispatched into `Reducer`, the board compared after each — so a plan the game
// wouldn't accept can't pass by merely looking like a plan.
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
      | None => expect("deal 1 solved")->toBe("but the budget ran out")
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
    | None => expect("deal 1 solved")->toBe("but the budget ran out")
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
    // Not "unsolvable" — unrepresentable. A board without FreeCell's cells and
    // foundations isn't FreeCell, and the solver says so rather than searching some
    // board it made up.
    let cascadesOnly: Game.t = {...game, piles: Game.pilesOf(game, Game.Cascade)}
    expect(Solver.plan(~game=cascadesOnly, GameState.initial(cascadesOnly)))->toEqual(None)
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
    switch Position.ofGameState(~game, opening)->Option.flatMap(start => Solver.planSteps(start)) {
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

  // Autoplay: the plan, played. `plan` is tested above as a *line*; what's
  // pinned here is that playing it is a real sequence of reducer moves ending on the
  // board the search was aiming at — the thing both front ends' `autoplay` verb hands
  // to their history, one recorded step at a time.
  describe("autoplay", () => {
    testWithin(
      "plays deal #1 out to a board the Finish button wins",
      () =>
        switch Solver.autoplay(~game, opening) {
        | Solver.UnknownBoard => expect("a FreeCell board")->toBe("but the solver didn't know it")
        | Solver.OutOfRoom(_) | Solver.Unwinnable | Solver.OutOfPatience =>
          expect("deal 1 played")->toBe("but no line was found")
        | Solver.Played({steps, effort}) =>
          expect(Array.length(steps) > 20)->toBe(true) // a real game, not a shortcut
          // …and it says what the thinking cost, which is a fact about the search
          // rather than about the clock: a deal takes positions off the frontier, and
          // several moves out of each.
          expect(effort.positions > 0)->toBe(true)
          expect(effort.moves > effort.positions)->toBe(true)
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
              // the line flies: the card the action named first, so the move
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
        // A `Played` with no steps and `OutOfRoom` are different answers, and a driver
        // treats them differently: one hands over to the finish sweep, the other says
        // it couldn't. Spelled out in full because the effort is part of the answer,
        // and because it's the one board where every number in it is knowable: the
        // search recognises a finishable position before it grows anything, so it
        // returns having spent nothing.
        let finishable = Scenario.freecellFinish(game)
        expect(Solver.autoplay(~game, finishable))->toEqual(
          Solver.Played({
            steps: [],
            effort: {positions: 0, moves: 0, ending: Solver.Found, bytes: 0},
          }),
        )
      },
    )

    test(
      "a board the model can't hold is refused, not searched",
      () => {
        let cascadesOnly: Game.t = {...game, piles: Game.pilesOf(game, Game.Cascade)}
        expect(Solver.autoplay(~game=cascadesOnly, GameState.initial(cascadesOnly)))->toEqual(
          Solver.UnknownBoard,
        )
      },
    )
  })

  // What the caller is willing to wait. The solver keeps no clock of its own — it is
  // handed one — and that is exactly what makes a wait testable: hand it a clock this
  // file drives, and "ten seconds went by" is a fact rather than a race. Nothing below
  // reads a real clock, so none of it can fail on a slow machine.
  describe("patience", () => {
    // Readings in order, the last one repeating. The first read is the wait being
    // resolved into a deadline; every one after it is a look to see whether it is over.
    let clockOf = (readings: array<float>) => {
      let i = ref(0)
      () => {
        let at =
          readings->Array.get(i.contents)->Option.getOr(readings->Array.last->Option.getOr(0.))
        i := i.contents + 1
        at
      }
    }

    // Asked at 0 with a second to spend, and ten seconds gone by the first look.
    let spent = (): Solver.patience => {ms: 1000., clock: clockOf([0., 10_000.])}

    test(
      "a caller already out of time is told so, not charged for a rung",
      () => {
        // It reads as its own refusal so that a front end doesn't report "no way to win"
        // about a board nobody finished looking at: the answer is about the wait.
        expect(Solver.autoplay(~game, ~patience=spent(), opening))->toEqual(Solver.OutOfPatience)
      },
    )

    testWithin(
      "a stopped clock never runs out, however little patience it is given",
      () =>
        // The property the rest of this file rests on — and why a wait puts no
        // timing-shaped hole in the suite. A caller that hands over a stopped clock gets
        // the plan the budget alone would find, so a plan stays a value two runs
        // can be expected to agree on.
        expect(Solver.plan(~game, ~patience={ms: 1., clock: () => 0.}, opening))->toEqual(
          Solver.plan(~game, opening),
        ),
      ~timeout=60_000,
    )

    test(
      "a spent clock and a spent budget are two different endings",
      () =>
        switch Position.ofGameState(~game, opening) {
        | None => expect("a FreeCell board packs")->toBe("but it didn't")
        | Some(start) =>
          // Room for the arrays a search starts with and not a byte more, so the first
          // column to grow fills it — far too small to find anything on a full deal.
          let empty = Solver.Search.bytes(
            Solver.Search.make(start, ~budget={heaps: [2.], maxBytes: Solver.capOf(Solver.Small)}),
          )
          let budget: Solver.budget = {heaps: [2.], maxBytes: empty + 1}
          // With time to spare, the search grows until it holds its budget and says it is
          // full.
          let (_, full) = Solver.solveWithEffort(start, ~budget)
          expect(full.positions > 0)->toBe(true)
          expect(full.bytes > empty)->toBe(true)
          expect(full.ending)->toEqual(Solver.Full)
          // Out of time, it never grows a position — and a more patient caller could
          // still have had those, which is why the two aren't one ending.
          let (_, clock) = Solver.solveWithEffort(start, ~budget, ~patience=spent())
          expect(clock.positions)->toBe(0)
          expect(clock.ending)->toEqual(Solver.OutOfTime)
        },
    )

    test(
      "a full search is autoplay's out of room, carrying what it held, and not a verdict",
      () => {
        let effort: Solver.effort = {positions: 9, moves: 40, ending: Solver.Full, bytes: 12_345}
        expect(Solver.autoplayedOf(~game, opening, ~line=None, ~effort))->toEqual(
          Solver.OutOfRoom({bytes: 12_345}),
        )
      },
    )

    test(
      "a cap lowered under what a search holds is full at the next think, and raised, grows on",
      () =>
        switch {
          let simon = Game.simpleSimonDeal(~seed=957)
          Position.ofGameState(~game=simon, GameState.initial(simon))
        } {
        | None => expect("a Simple Simon board packs")->toBe("but it didn't")
        | Some(start) =>
          let search = Solver.Search.make(start)
          expect(Solver.Search.think(search, ~nodes=2_000))->toEqual(Solver.Search.Paused)
          Solver.Search.limit(search, ~maxBytes=Solver.Search.bytes(search))
          let grown = search.grown
          expect(Solver.Search.think(search, ~nodes=2_000))->toEqual(Solver.Search.Full)
          expect(search.grown)->toBe(grown)
          Solver.Search.limit(search, ~maxBytes=Solver.capOf(Solver.Small))
          expect(Solver.Search.think(search, ~nodes=2_000))->toEqual(Solver.Search.Paused)
          expect(search.grown)->toBe(grown + 2_000)
        },
    )

    test(
      "a search asked again carries on from where the wait stopped it",
      () =>
        switch Position.ofGameState(~game, opening) {
        | None => expect("a FreeCell board packs")->toBe("but it didn't")
        | Some(start) =>
          let search = Solver.Search.make(start)
          let (none, first) = Solver.solveOn(search, ~patience=spent())
          expect((none, first.ending))->toEqual((None, Solver.OutOfTime))
          // The second ask reports both asks' effort, and finds the line one uninterrupted
          // solve does.
          let (line, both) = Solver.solveOn(search)
          let (once, alone) = Solver.solveWithEffort(start)
          expect(line)->toEqual(once)
          expect(both)->toEqual(alone)
        },
    )

    test(
      "a proof outranks the clock",
      () => {
        // A rung that empties its frontier has seen everything there was to see, so the
        // answer is the proof it is — with however much of the wait left unspent.
        let dead = Game.simpleSimonDeal(~seed=2)
        expect(
          Solver.autoplay(
            ~game=dead,
            ~patience={ms: 60_000., clock: () => 0.},
            GameState.initial(dead),
          ),
        )->toEqual(Solver.Unwinnable)
      },
    )
  })

  // The search as a value. Everything above asks it through `solveOn`; what's pinned
  // here is the property that makes asking twice mean anything.
  describe("Search", () => {
    // Everything a search holds, as one comparable value.
    let graphOf = (search: Solver.Search.t) => (
      search.grown,
      search.tried,
      search.line,
      search.frontiers,
      search.turn,
      search.graph,
    )

    let startOf = (game: Game.t) =>
      Position.ofGameState(~game, GameState.initial(game))->Option.getOrThrow

    test(
      "thinking twice reaches the graph thinking once for the sum does",
      () =>
        [Game.freecellDeal(~seed=582), Game.simpleSimonDeal(~seed=1)]->Array.forEach(
          game => {
            let start = startOf(game)
            let twice = Solver.Search.make(start)
            expect(twice->Solver.Search.think(~nodes=300))->toEqual(Solver.Search.Paused)
            expect(twice->Solver.Search.think(~nodes=700))->toEqual(Solver.Search.Paused)
            let once = Solver.Search.make(start)
            expect(once->Solver.Search.think(~nodes=1000))->toEqual(Solver.Search.Paused)
            expect(graphOf(twice))->toEqual(graphOf(once))
          },
        ),
    )

    testWithin(
      "and so reaches the answer thinking once does, however the thinking is sliced",
      () => {
        let start = startOf(game)
        let sliced = Solver.Search.make(start)
        let answer = ref(Solver.Search.Paused)
        while answer.contents == Solver.Search.Paused {
          answer := sliced->Solver.Search.think(~nodes=777)
        }
        let whole = Solver.Search.make(start)
        expect(whole->Solver.Search.think(~nodes=1_000_000))->toEqual(answer.contents)
        expect(answer.contents)->toEqual(Solver.Search.Found)
        expect(graphOf(sliced))->toEqual(graphOf(whole))
      },
      ~timeout=60_000,
    )

    test(
      "a search that knows its answer gives it again without growing",
      () => {
        let dead = Solver.Search.make(startOf(Game.simpleSimonDeal(~seed=2)))
        expect(dead->Solver.Search.think(~nodes=1_000_000))->toEqual(Solver.Search.Exhausted)
        let grown = dead.grown
        expect(dead->Solver.Search.think(~nodes=1_000_000))->toEqual(Solver.Search.Exhausted)
        expect(dead.grown)->toBe(grown)
      },
    )

    test(
      "a hash that matches is not taken for seen until the boards are compared",
      () => {
        // Two boards filed under one hash, as a collision would file them: the second
        // must find an empty slot, not the first board's node.
        let start = startOf(Game.freecellDeal(~seed=1))
        let other = Position.applyMove(start, Position.legalMoves(start)->Array.getUnsafe(0))
        let graph = Graph.make(start)
        let board = Graph.load(graph, start)
        let hash = Graph.hash(board)
        let slot = Graph.slotOf(graph, board, ~hash)
        let root = graph->Graph.add(~parent=-1, ~move=0, ~depth=0, ~h=0, ~hash)
        graph->Graph.file(slot, root)
        let slotFor = s => Graph.slotOf(graph, Graph.load(graph, s), ~hash)
        expect(Graph.nodeAt(graph, slotFor(start)))->toBe(root)
        expect(Graph.nodeAt(graph, slotFor(other)))->toBe(-1)
      },
    )

    test(
      "every node's position reads back as its line from the start plays out, kept or not",
      () =>
        [Game.freecellDeal(~seed=582), Game.spideretteDeal(~seed=3)]->Array.forEach(
          game => {
            let start = startOf(game)
            let search = Solver.Search.make(start)
            ignore(search->Solver.Search.think(~nodes=2000))
            let graph = search.graph
            let wrong = ref(0)
            for node in 0 to graph.size - 1 {
              let played =
                Graph.lineTo(graph, node)->Array.reduce(
                  start,
                  (s, move) => Position.applyMove(s, move),
                )
              if Graph.positionOf(graph, node) != played {
                wrong := wrong.contents + 1
              }
            }
            expect(wrong.contents)->toBe(0)
          },
        ),
    )

    test(
      "the bytes an effort reports are the search's own arrays, and grow as it does",
      () => {
        let search = Solver.Search.make(startOf(Game.freecellDeal(~seed=582)))
        let spent = {Solver.ms: 0., clock: () => 0.}
        let (_, first) = Solver.solveOn(search, ~patience=spent)
        expect(first.bytes)->toBe(Solver.Search.bytes(search))
        ignore(search->Solver.Search.think(~nodes=1000))
        let (_, second) = Solver.solveOn(search, ~patience=spent)
        expect(second.bytes)->toBe(Solver.Search.bytes(search))
        expect(second.bytes > first.bytes)->toBe(true)
      },
    )

    // `moved`, and the `think` after it that makes the new board the root. A position is
    // told by its `key` here, because a re-root renumbers every node it keeps.
    describe(
      "re-rooting",
      () => {
        let keyOf = (search: Solver.Search.t, node) =>
          Position.key(Graph.positionOf(search.graph, node))

        // The positions a search holds grown, by key.
        let closedKeys = (search: Solver.Search.t) => {
          let keys = Set.make()
          for node in 0 to search.graph.size - 1 {
            if Graph.isClosed(search.graph, node) {
              keys->Set.add(keyOf(search, node))
            }
          }
          keys
        }

        // The positions grown since `before`, that `before` already held grown.
        let regrown = (search: Solver.Search.t, ~before: Set.t<string>, ~kept: Set.t<string>) => {
          let again = ref(0)
          closedKeys(search)->Set.forEach(
            key =>
              if !(kept->Set.has(key)) && before->Set.has(key) {
                again := again.contents + 1
              },
          )
          again.contents
        }

        // The move from `start` whose subtree holds the most grown positions — the branch
        // a re-root onto it has the most to keep from.
        let busiest = (search: Solver.Search.t, start: Position.t) => {
          let graph = search.graph
          let under = node => {
            let n = ref(0)
            for other in 0 to graph.size - 1 {
              let cursor = ref(other)
              while cursor.contents >= 0 && graph.parent->Graph.at(cursor.contents) != node {
                cursor := graph.parent->Graph.at(cursor.contents)
              }
              if cursor.contents >= 0 && Graph.isClosed(graph, other) {
                n := n.contents + 1
              }
            }
            n.contents
          }
          let root = ref(0)
          while graph.parent->Graph.at(root.contents) >= 0 {
            root := root.contents + 1
          }
          let best = ref((-1, start))
          for node in 0 to graph.size - 1 {
            if graph.parent->Graph.at(node) == root.contents {
              let n = under(node)
              if n > Pair.first(best.contents) {
                best := (n, Graph.positionOf(graph, node))
              }
            }
          }
          Pair.second(best.contents)
        }

        test(
          "a move along a grown branch keeps it, and nothing under it is grown again",
          () =>
            [Game.freecellDeal(~seed=582), Game.simpleSimonDeal(~seed=1)]->Array.forEach(
              game => {
                let start = startOf(game)
                let search = Solver.Search.make(start)
                ignore(search->Solver.Search.think(~nodes=3000))
                let before = closedKeys(search)
                let bytes = Solver.Search.bytes(search)
                let next = busiest(search, start)
                search->Solver.Search.moved(next)
                ignore(search->Solver.Search.think(~nodes=0))
                let kept = closedKeys(search)
                expect(kept->Set.size > 0)->toBe(true)
                expect(Solver.Search.bytes(search) <= bytes)->toBe(true)
                kept->Set.forEach(key => expect(before->Set.has(key))->toBe(true))
                ignore(search->Solver.Search.think(~nodes=2000))
                expect(regrown(search, ~before, ~kept))->toBe(0)
              },
            ),
        )

        test(
          "an undo keeps everything under the move it takes back, and grows none of it again",
          () =>
            [Game.freecellDeal(~seed=582), Game.spideretteDeal(~seed=3)]->Array.forEach(
              game => {
                let start = startOf(game)
                let search = Solver.Search.make(start)
                ignore(search->Solver.Search.think(~nodes=1000))
                let next = busiest(search, start)
                search->Solver.Search.moved(next)
                ignore(search->Solver.Search.think(~nodes=2000))
                let before = closedKeys(search)
                search->Solver.Search.moved(start)
                ignore(search->Solver.Search.think(~nodes=0))
                let kept = closedKeys(search)
                before->Set.forEach(key => expect(kept->Set.has(key))->toBe(true))
                ignore(search->Solver.Search.think(~nodes=2000))
                expect(regrown(search, ~before, ~kept))->toBe(0)
              },
            ),
        )

        test(
          "a board the graph has never seen starts the search again, as `make` would",
          () => {
            let search = Solver.Search.make(startOf(Game.freecellDeal(~seed=582)))
            ignore(search->Solver.Search.think(~nodes=1500))
            let elsewhere = startOf(Game.freecellDeal(~seed=7))
            search->Solver.Search.moved(elsewhere)
            let fresh = Solver.Search.make(elsewhere)
            expect(search->Solver.Search.think(~nodes=800))->toEqual(
              fresh->Solver.Search.think(~nodes=800),
            )
            expect(search.graph)->toEqual(fresh.graph)
            expect(search.frontiers)->toEqual(fresh.frontiers)
            expect(search.line)->toEqual(fresh.line)
          },
        )

        test(
          "a moved board with nothing thought since is followed by the answer, too",
          () => {
            let start = startOf(Game.microDeal(~seed=1))
            let search = Solver.Search.make(start)
            expect(search->Solver.Search.think(~nodes=1_000_000))->toEqual(Solver.Search.Found)
            let after = Position.applyMove(
              start,
              Option.getOrThrow(search.line)->Array.getUnsafe(0),
            )
            search->Solver.Search.moved(after)
            expect(Solver.Search.answer(search))->toEqual(Solver.Search.Found)
            expect(Array.length(Option.getOrThrow(search.line)) > 0)->toBe(true)
          },
        )

        // The property the proof rests on, over boards small enough to search to the end:
        // a search walked along a game and back agrees with one opened where the game
        // stands, on whether there is a line — and its line plays on the real board.
        testWithin(
          "a search moved along a game agrees with a fresh one opened where it stands",
          () => {
            let seed = ref(12345)
            let random = n => {
              seed := (Math.Int.imul(seed.contents, 1103515245) + 12345)->Int.bitwiseAnd(0x7fffffff)
              mod(seed.contents / 65536, n)
            }
            let budget = {Solver.heaps: [2., 1.], maxBytes: 2_000_000_000}
            let toEnd = search => {
              let answer = ref(Solver.Search.Paused)
              while answer.contents == Solver.Search.Paused {
                answer := search->Solver.Search.think(~nodes=100_000)
              }
              answer.contents
            }
            let problems = []
            let walks = ref(0)
            for deal in 1 to 20 {
              [Game.miniDeal(~seed=deal), Game.microDeal(~seed=deal)]->Array.forEach(
                game => {
                  let opening = GameState.initial(game)
                  let positionOf = state => Position.ofGameState(~game, state)->Option.getOrThrow
                  let search = Solver.Search.make(positionOf(opening), ~budget)
                  ignore(search->Solver.Search.think(~nodes=random(400)))
                  let history = [opening]
                  for _ in 1 to 1 + random(8) {
                    let state = history->Array.getUnsafe(Array.length(history) - 1)
                    let moves = Position.legalMoves(positionOf(state))
                    if Array.length(history) > 1 && (random(3) == 0 || Array.length(moves) == 0) {
                      history->Array.pop->ignore // an undo
                    } else if Array.length(moves) > 0 {
                      let move = moves->Array.getUnsafe(random(Array.length(moves)))
                      switch Position.toAction(~game, state, move) {
                      | None => ()
                      | Some(action) =>
                        switch Reducer.reduce(~game, state, action) {
                        | Error(_) => ()
                        | Ok(next) => history->Array.push(settle(~game, next))
                        }
                      }
                    }
                    let state = history->Array.getUnsafe(Array.length(history) - 1)
                    search->Solver.Search.moved(positionOf(state))
                    ignore(search->Solver.Search.think(~nodes=random(300)))
                  }
                  walks := walks.contents + 1
                  let here = history->Array.getUnsafe(Array.length(history) - 1)
                  let followed = toEnd(search)
                  let fresh = toEnd(Solver.Search.make(positionOf(here), ~budget))
                  let said = `${game.name} #${Int.toString(deal)}`
                  if followed != fresh {
                    problems->Array.push(`${said}: re-rooted and fresh searches disagree`)
                  }
                  switch search.line {
                  | None => ()
                  | Some(line) =>
                    switch play(~game, here, line) {
                    | Error(why) => problems->Array.push(`${said}: ${why}`)
                    | Ok(finished) =>
                      if !Reducer.canFinish(~game, finished) {
                        problems->Array.push(`${said}: the line ended short of a finish`)
                      }
                    }
                  }
                },
              )
            }
            expect(problems)->toEqual([])
            expect(walks.contents)->toBe(40)
          },
          ~timeout=60_000,
        )

        test(
          "every node a re-rooted search holds is reached by its line, played on the real board",
          () =>
            [Game.freecellDeal(~seed=582), Game.spideretteDeal(~seed=3)]->Array.forEach(
              game => {
                let opening = GameState.initial(game)
                let search = Solver.Search.make(startOf(game))
                ignore(search->Solver.Search.think(~nodes=2000))
                // Two moves along the game, a think, and both taken back. Each is the last
                // move offered, which on a Spiderette's opening is the deal: an undo of a
                // deal stands on a longer stock than the search was opened on.
                let states = [opening]
                for _ in 1 to 2 {
                  let state = states->Array.getUnsafe(Array.length(states) - 1)
                  let position = Position.ofGameState(~game, state)->Option.getOrThrow
                  let move = Position.legalMoves(position)->Array.last->Option.getOrThrow
                  let action = Position.toAction(~game, state, move)->Option.getOrThrow
                  switch Reducer.reduce(~game, state, action) {
                  | Ok(next) => states->Array.push(settle(~game, next))
                  | Error(_) => ()
                  }
                }
                let here = states->Array.getUnsafe(Array.length(states) - 1)
                search->Solver.Search.moved(Position.ofGameState(~game, here)->Option.getOrThrow)
                ignore(search->Solver.Search.think(~nodes=1000))
                let back = opening
                search->Solver.Search.moved(Position.ofGameState(~game, back)->Option.getOrThrow)
                ignore(search->Solver.Search.think(~nodes=1000))
                let graph = search.graph
                let wrong = []
                let node = ref(0)
                while node.contents < graph.size {
                  switch play(~game, back, Graph.lineTo(graph, node.contents)) {
                  | Error(why) => wrong->Array.push(why)
                  | Ok(reached) =>
                    if (
                      !Position.alike(
                        Position.ofGameState(~game, reached)->Option.getOrThrow,
                        Graph.positionOf(graph, node.contents),
                      )
                    ) {
                      wrong->Array.push(`node ${Int.toString(node.contents)} reads back wrong`)
                    }
                  }
                  node := node.contents + 37
                }
                expect(wrong)->toEqual([])
              },
            ),
        )
      },
    )
  })

  // The other game the solver plays. The line runs to the win itself — there is no
  // drain and no Finish button under this law — and a deal with no line is common
  // enough that telling "none exists" from "none found" is part of the answer.
  describe("Simple Simon", () => {
    let game = Game.simpleSimonDeal(~seed=1)
    let opening = GameState.initial(game)

    testWithin(
      "plays deal #1 to the win, one reducer move at a time",
      () =>
        switch Solver.autoplay(~game, opening) {
        | Solver.UnknownBoard =>
          expect("a Simple Simon board")->toBe("but the solver didn't know it")
        | Solver.OutOfRoom(_) | Solver.Unwinnable | Solver.OutOfPatience =>
          expect("deal 1 played")->toBe("but no line was found")
        | Solver.Played({steps, effort}) =>
          expect(Array.length(steps) > 40)->toBe(true) // a real game, not a shortcut
          expect(effort.positions > 0)->toBe(true)
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
              before := step.state
            },
          )
          expect(problems)->toEqual([])
          // …and the last step is the fourth run collected, since nothing finishes a
          // Simple Simon board short of the win.
          expect(GameState.hasWon(game, before.contents))->toBe(true)
        },
      ~timeout=60_000,
    )

    test(
      "a deal with no line is told apart from one the budget gave up on",
      () => {
        // Deal #2 is stuck within a few dozen positions: every one reachable from it is
        // searched, and none wins. That's a proof, and it reads differently from a
        // budget running out.
        let dead = Game.simpleSimonDeal(~seed=2)
        expect(Solver.autoplay(~game=dead, GameState.initial(dead)))->toEqual(Solver.Unwinnable)
      },
    )

    testWithin(
      "solves a spread of deals or proves them unwinnable — never merely gives up",
      () => {
        let problems = []
        for seed in 1 to 12 {
          let game = Game.simpleSimonDeal(~seed)
          switch Solver.autoplay(~game, GameState.initial(game)) {
          | Solver.UnknownBoard => problems->Array.push(`deal ${Int.toString(seed)}: not read`)
          | Solver.OutOfRoom(_) =>
            problems->Array.push(`deal ${Int.toString(seed)}: the budget ran out`)
          | Solver.OutOfPatience =>
            problems->Array.push(`deal ${Int.toString(seed)}: the patience ran out`)
          | Solver.Unwinnable => ()
          | Solver.Played({steps}) =>
            switch steps->Array.last {
            | Some(last) if GameState.hasWon(game, last.state) => ()
            | _ =>
              problems->Array.push(`deal ${Int.toString(seed)}: the line ended short of the win`)
            }
          }
        }
        expect(problems)->toEqual([])
      },
      ~timeout=120_000,
    )

    // A few cards are enough to show a direction; the heuristic never needs the
    // whole pack to be on the board.
    let position = (columns: array<array<string>>): Position.t => {
      law: Position.SimpleSimon,
      pack: Position.standardPack,
      cells: [],
      found: [0, 0, 0, 0],
      casc: columns->Array.map(
        column => column->Array.map(code => Position.idOfCode(code)->Option.getOr(-1)),
      ),
      down: columns->Array.map(_ => 0),
      stock: [],
    }
    let h = p => Solver.heuristic(p, Solver.simonWeights)

    test(
      "the heuristic prefers a join made, a column freed, and a wanted card uncovered",
      () => {
        // A 7♠ on its own 8♠ is a run; on the 8♥ it's a lawful drop that heads no run.
        expect(h(position([["8S", "7S"], ["8H"]])) < h(position([["8S"], ["8H", "7S"]])))->toBe(
          true,
        )
        // A column freed is worth the seam it costs to free it: room to manoeuvre.
        expect(h(position([["8H", "7S"], []])) < h(position([["8H"], ["7S"]])))->toBe(true)
        // A card sat on the 8♠ the 7♠ is waiting for is a card in the way.
        expect(
          h(position([["8S", "3D"], ["7S"], ["4C"]])) > h(position([["8S"], ["7S"], ["4C", "3D"]])),
        )->toBe(true)
      },
    )
  })

  // Spiderette: Simple Simon's law with twenty-four cards still to come. What is new to
  // the search is a move that deals, so what's pinned is that it takes one when it
  // should, that the line still plays move-for-move against the reducer, and that a step
  // that deals can say which cards it dropped — an animating driver has no other way to
  // know, since the action names none.
  //
  // The four-suit pack for those, because the deal is what they are about and every pack
  // deals alike. The repeated packs get a run of their own below, for the one thing only
  // they can say.
  describe("Spiderette", () => {
    let game = Game.spiderette4Deal(~seed=1)
    let opening = GameState.initial(game)

    testWithin(
      "plays deal #1 to the win, dealing the stock out on the way",
      () =>
        switch Solver.autoplay(~game, opening) {
        | Solver.UnknownBoard => expect("a Spiderette board")->toBe("but the solver didn't know it")
        | Solver.OutOfRoom(_) | Solver.Unwinnable | Solver.OutOfPatience =>
          expect("deal 1 played")->toBe("but no line was found")
        | Solver.Played({steps}) =>
          let problems = []
          let deals = []
          let before = ref(opening)
          steps->Array.forEachWithIndex(
            (step: Solver.played, i) => {
              if step.action == Reducer.Deal {
                deals->Array.push((Reducer.nextDeal(~game, before.contents), step.moved))
              }
              switch Reducer.reduce(~game, before.contents, step.action) {
              | Error(_) => problems->Array.push(`step ${Int.toString(i)}: the reducer refused it`)
              | Ok(next) =>
                if !GameState.equal(settle(~game, next), step.state) {
                  problems->Array.push(`step ${Int.toString(i)}: the state doesn't follow`)
                }
              }
              before := step.state
            },
          )
          expect(problems)->toEqual([])
          // A card is collected from the tableau, so every card has to get there: a
          // line that wins is a line that dealt the stock out, three rows of seven and
          // a last of three.
          expect(deals->Array.map(((dropped, _)) => Array.length(dropped)))->toEqual([7, 7, 7, 3])
          // …and each of those steps reports the cards it dropped, ahead of whatever
          // the settle swept up behind them.
          deals->Array.forEach(
            ((dropped, moved)) =>
              expect(moved->Array.slice(~start=0, ~end=Array.length(dropped)))->toEqual(dropped),
          )
          expect(GameState.hasWon(game, before.contents))->toBe(true)
        },
      ~timeout=120_000,
    )

    test(
      "the stock is weighed, so most of what a deal costs is paid back",
      () =>
        switch Position.ofGameState(~game, opening) {
        | None => expect("a Spiderette board packs")->toBe("but it didn't")
        | Some(start) =>
          let weights = Solver.weightsFor(start)
          let dealt = Position.applyMove(start, Position.Deal)
          let cost = w => Solver.heuristic(dealt, w) - Solver.heuristic(start, w)
          // Seven cards land on seven columns and land mostly as seams, so by every
          // other term the board just got worse: under Simple Simon's own weights the
          // opening deal is pure damage, and a search weighed that way never takes one.
          expect(cost(Solver.simonWeights) > 40)->toBe(true)
          // Charging for the undealt cards pays back exactly the seven that left the
          // stock, and that is most of it.
          expect(cost(weights))->toBe(cost(Solver.simonWeights) - 7 * weights.stock)
          expect(cost(weights) < cost(Solver.simonWeights) / 3)->toBe(true)
        },
    )

    // The packs where the same face is on the table more than once. The model collapses
    // the copies — both Sevens of Spades are one int — so what has to be shown is that a
    // *plan* made on the collapsed board still names real cards: every step is an action
    // the reducer takes, on a board where naming the wrong Seven would be refused or
    // would move the other one. And the win is the model's own, since a suit with four
    // runs to send home is the case `found` had to start counting for.
    testWithin(
      "plays a repeated pack out, each step naming a card the reducer will move",
      () => {
        let problems = []
        [Game.spiderette1Deal(~seed=3), Game.spideretteDeal(~seed=2)]->Array.forEach(
          game => {
            let opening = GameState.initial(game)
            switch Solver.autoplay(~game, opening) {
            | Solver.UnknownBoard => problems->Array.push(`${game.id}: not a board it read`)
            | Solver.OutOfRoom(_) | Solver.Unwinnable | Solver.OutOfPatience =>
              problems->Array.push(`${game.id}: the deal went unplayed`)
            | Solver.Played({steps}) =>
              let before = ref(opening)
              steps->Array.forEachWithIndex(
                (step: Solver.played, i) => {
                  switch Reducer.reduce(~game, before.contents, step.action) {
                  | Error(_) =>
                    problems->Array.push(
                      `${game.id} step ${Int.toString(i)}: the reducer refused it`,
                    )
                  | Ok(next) =>
                    if !GameState.equal(settle(~game, next), step.state) {
                      problems->Array.push(
                        `${game.id} step ${Int.toString(i)}: the state doesn't follow`,
                      )
                    }
                  }
                  before := step.state
                },
              )
              if !GameState.hasWon(game, before.contents) {
                problems->Array.push(`${game.id}: the line ended short of the win`)
              }
            }
          },
        )
        expect(problems)->toEqual([])
      },
      ~timeout=120_000,
    )
  })

  // FreeCell's law over twenty cards or sixteen. Nothing about the search changes:
  // what's pinned is that a board whose deck and counts are its own gets played
  // through to the finish, and that on a pack this small "there is no line" is an
  // ordinary answer the search has to *prove* rather than shrug at.
  describe("the short-deck FreeCells", () => {
    testWithin(
      "plays a spread of Mini and Micro deals, or proves them unwinnable",
      () => {
        let problems = []
        for seed in 1 to 12 {
          [Game.miniDeal(~seed), Game.microDeal(~seed)]->Array.forEach(
            game => {
              let opening = GameState.initial(game)
              let deal = `${game.name} #${Int.toString(seed)}`
              switch Solver.autoplay(~game, opening) {
              | Solver.UnknownBoard => problems->Array.push(`${deal}: not a board it read`)
              | Solver.OutOfRoom(_) => problems->Array.push(`${deal}: the budget ran out`)
              | Solver.OutOfPatience => problems->Array.push(`${deal}: the patience ran out`)
              | Solver.Unwinnable => ()
              | Solver.Played({steps}) =>
                let finished =
                  steps->Array.last->Option.mapOr(opening, (step: Solver.played) => step.state)
                if !Reducer.canFinish(~game, finished) {
                  problems->Array.push(`${deal}: the line ended short of a finish`)
                }
              }
            },
          )
        }
        expect(problems)->toEqual([])
      },
      ~timeout=60_000,
    )

    test(
      "a deal with no line is proved, not merely given up on",
      () => {
        // Both of these are stuck: every position reachable from them is searched in
        // milliseconds and none finishes. Twenty cards and two cells leave that
        // answer common enough — eight of the first thousand Mini deals — that it has
        // to read as the proof it is rather than as the ladder giving up.
        let mini = Game.miniDeal(~seed=10)
        expect(Solver.autoplay(~game=mini, GameState.initial(mini)))->toEqual(Solver.Unwinnable)
        let micro = Game.microDeal(~seed=43)
        expect(Solver.autoplay(~game=micro, GameState.initial(micro)))->toEqual(Solver.Unwinnable)
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
        Solver.heuristic(ahead, Solver.freecellWeights) <
        Solver.heuristic(position, Solver.freecellWeights),
      )->toBe(true)
      expect(
        Solver.heuristic(clogged, Solver.freecellWeights) >
        Solver.heuristic(position, Solver.freecellWeights),
      )->toBe(true)
    }
  })
})
