open Vitest
open Card

// `Position` is a *mirror* of the rules, not a second set of them — so what
// has to be tested is the mirroring itself. Every test here holds the packed model
// up against `Rules`/`Reducer` on the same board and insists they say the same thing.
//
// This is the check the old JavaScript mirror could only make in a browser, by
// playing a whole game through the DOM and counting the times the screen surprised
// it (`browser-tests/autoplay.spec.mjs`). In one language it's an ordinary unit
// test, so a rules change that the mirror hasn't caught up with turns `mise run
// test` red in seconds instead of surviving until someone runs the browser suite.
describe("Position", () => {
  let game = Game.freecellDeal(~seed=3)
  let opening = GameState.initial(game)

  // The board a driver is left with after an accepted move: the reducer's result,
  // then the same post-move auto-collect the drivers run — on by `Options.default`,
  // and suppressed once the board is finishable, from where the Finish button owns
  // the sweep (`Repl.settle`, `TableScene`'s `autoCollectIfEnabled`). This is
  // exactly what `Position.applyMove` claims to mirror.
  let settle = (~game, state) =>
    if Reducer.canFinish(~game, state) {
      state
    } else {
      let (collected, _moved) = Reducer.autoCollect(~game, state)
      collected
    }

  // The real board as a packed position, spelled out — what the two sides are
  // compared as, since `Position.key` is canonical (cells and columns sorted) and
  // two states that rest every card the same way share one.
  let mirrorKey = (~game, state) =>
    Position.ofGameState(~game, state)->Option.mapOr("(not a FreeCell board)", Position.key)

  let packed = (~game, state) =>
    switch Position.ofGameState(~game, state) {
    | Some(position) => position
    | None => {Position.cells: [], found: [], casc: []} // fails loudly in any test that uses it
    }

  test("a card packs into an int and comes back the same card", () => {
    Cards.all->Array.forEach(card => expect(Position.cardOf(Position.idOf(card)))->toEqual(card))
    // …and every card gets its own number, 0–51 with none spare.
    let ids = Cards.all->Array.map(Position.idOf)
    ids->Array.sort(Int.compare)
    expect(ids)->toEqual(Array.fromInitializer(~length=52, i => i))
  })

  test("the packed suit and rank are the ones `Rules` reads", () => {
    Cards.all->Array.forEach(
      card => {
        let id = Position.idOf(card)
        expect(Position.rankOf(id))->toBe(Rules.rankValue(card.rank))
        expect(Position.isRed(id))->toBe(Rules.color(card.suit) == Rules.Red)
      },
    )
    // Cards of one suit share a suit number, and no two suits share one.
    let suits = Cards.suits->Array.map(suit => Position.suitOf(Position.idOf({suit, rank: Ace})))
    expect(suits)->toEqual([0, 1, 2, 3])
  })

  test("a card's code is the one everything else in the repo names it by", () => {
    Cards.all->Array.forEach(
      card => {
        let code = Position.code(Position.idOf(card))
        expect(code)->toBe(CardText.format(card))
        expect(Position.idOfCode(code))->toEqual(Some(Position.idOf(card)))
      },
    )
    expect(Position.idOfCode("not a card"))->toEqual(None)
  })

  test("an opening deal packs to the board it was dealt", () => {
    let position = packed(~game, opening)
    expect(position.cells)->toEqual([-1, -1, -1, -1]) // four empty free cells
    expect(position.found)->toEqual([0, 0, 0, 0]) // nothing home yet
    expect(Array.length(position.casc))->toBe(8)
    // Each column holds what `GameState` says it holds, bottom-first and in order.
    Game.pileIndices(game, Game.Cascade)->Array.forEachWithIndex(
      (pile, col) =>
        expect(position.casc->Array.getUnsafe(col))->toEqual(
          GameState.cardsInPile(opening, pile)->Array.map(Position.idOf),
        ),
    )
    expect(Position.foundationTotal(position))->toBe(0)
    expect(Position.hasWon(position))->toBe(false)
  })

  test("a board that isn't FreeCell-shaped packs to nothing at all", () => {
    // The model can only say four cells, four foundations and eight columns, so a
    // board of any other shape gets an honest `None` rather than one with pieces
    // missing. Here: the same deal with the free cells and foundations taken away.
    let cascadesOnly: Game.t = {
      ...game,
      piles: Game.pilesOf(game, Game.Cascade),
    }
    expect(Position.ofGameState(~game=cascadesOnly, GameState.initial(cascadesOnly)))->toEqual(None)
  })

  test("every move the model offers is a move the reducer accepts", () => {
    // Soundness: the plan can only contain moves the real game will take. Checked
    // along a whole played game, not just the opening, so the run moves and the
    // supermove limit get exercised too.
    let refusals = []
    let real = ref(opening)
    let sampled = ref(0)
    switch Solver.plan(~game, opening) {
    | None => refusals->Array.push("deal 3 went unsolved")
    | Some(moves) =>
      moves->Array.forEach(
        move => {
          let state = real.contents
          // Every legal move from here, weighed by the reducer rather than the mirror.
          Position.legalMoves(packed(~game, state))->Array.forEach(
            candidate =>
              switch Position.toAction(~game, state, candidate) {
              | None =>
                refusals->Array.push(Position.describeMove(candidate) ++ " — no such action")
              | Some(action) =>
                sampled := sampled.contents + 1
                switch Reducer.reduce(~game, state, action) {
                | Ok(_) => ()
                | Error(_) =>
                  refusals->Array.push(Position.describeMove(candidate) ++ " — refused")
                }
              },
          )
          // …then play the planned move, so the next position is a real one.
          switch Position.toAction(~game, state, move) {
          | Some(action) =>
            switch Reducer.reduce(~game, state, action) {
            | Ok(next) => real := settle(~game, next)
            | Error(_) => ()
            }
          | None => ()
          }
        },
      )
    }
    expect(refusals)->toEqual([])
    expect(sampled.contents > 100)->toBe(true) // it really did weigh a game's worth
  })

  test("the model offers every single-card move the reducer would accept", () => {
    // Completeness, the other direction: a move the reducer would take but the
    // model never generates is a move the solver can't plan, so the mirror has to
    // list them all. Three prunings are deliberate and excluded here — the model
    // sends a card only to the *first* empty free cell (the others are the same
    // move), won't move a whole column into an empty one (that only renames the
    // column), and won't shuffle a card between free cells (that changes nothing
    // about what can be played next).
    let missing = []
    let real = ref(opening)
    switch Solver.plan(~game, opening) {
    | None => missing->Array.push("deal 3 went unsolved")
    | Some(moves) =>
      moves->Array.forEachWithIndex(
        (move, i) => {
          let state = real.contents
          if mod(i, 5) == 0 {
            let position = packed(~game, state)
            let offered =
              Position.legalMoves(position)
              ->Array.filter(m => m.n == 1)
              ->Array.map(Position.describeMove)
            let cells = Game.pileIndices(game, Game.FreeCell)
            let cascades = Game.pileIndices(game, Game.Cascade)
            let firstEmptyCell = position.cells->Array.indexOf(-1)
            // Every accessible card — the top of each cell and each column — against
            // every pile the reducer would let it land on.
            let accessible =
              cells
              ->Array.mapWithIndex((pile, cell) => (pile, `cell ${Int.toString(cell)}`, true))
              ->Array.concat(
                cascades->Array.mapWithIndex(
                  (pile, col) => (pile, `column ${Int.toString(col)}`, false),
                ),
              )
            accessible->Array.forEach(
              ((pile, from, fromCell)) =>
                switch GameState.topOf(state, pile) {
                | None => ()
                | Some(card) =>
                  let alone = Array.length(GameState.cardsInPile(state, pile)) == 1
                  game.piles->Array.forEachWithIndex(
                    (destination: Game.pile, dest) =>
                      if dest != pile && Reducer.canDrop(~game, state, card, ~onto=dest) {
                        let (to_, pruned) = switch destination.role {
                        | Game.Foundation => ("foundation", false)
                        | Game.FreeCell => (`cell ${Int.toString(firstEmptyCell)}`, fromCell)
                        | Game.Cascade => (
                            `column ${Int.toString(cascades->Array.indexOf(dest))}`,
                            alone && Array.length(GameState.cardsInPile(state, dest)) == 0,
                          )
                        }
                        let wanted = `${Position.code(Position.idOf(card))} from ${from} to ${to_}`
                        if !pruned && !(offered->Array.includes(wanted)) {
                          missing->Array.push(wanted)
                        }
                      },
                  )
                },
            )
          }
          switch Position.toAction(~game, state, move) {
          | Some(action) =>
            switch Reducer.reduce(~game, state, action) {
            | Ok(next) => real := settle(~game, next)
            | Error(_) => ()
            }
          | None => ()
          }
        },
      )
    }
    expect(missing)->toEqual([])
  })

  test("the supermove limit is the reducer's, destination and all", () => {
    let position = packed(~game, opening)
    Game.pileIndices(game, Game.Cascade)->Array.forEachWithIndex(
      (pile, col) =>
        expect(Position.maxSupermove(position, ~ignoring=col))->toBe(
          Reducer.maxSupermove(~game, opening, ~ignoring=pile),
        ),
    )
  })

  test("auto-collect, canFinish and the board after a move are the reducer's too", () => {
    // The one that matters most: a whole game played twice — once through
    // `Reducer`, once through the mirror — comparing the board after every single
    // move. A drift of any kind shows up here as a differing key.
    let divergences = []
    switch Solver.plan(~game, opening) {
    | None => divergences->Array.push("deal 3 went unsolved")
    | Some(moves) =>
      let real = ref(opening)
      let mirrored = ref(packed(~game, opening))
      moves->Array.forEachWithIndex(
        (move, i) =>
          switch Position.toAction(~game, real.contents, move) {
          | None => divergences->Array.push(`move ${Int.toString(i)}: no action for it`)
          | Some(action) =>
            switch Reducer.reduce(~game, real.contents, action) {
            | Error(_) => divergences->Array.push(`move ${Int.toString(i)}: the reducer refused it`)
            | Ok(next) =>
              real := settle(~game, next)
              mirrored := Position.applyMove(mirrored.contents, move)
              if mirrorKey(~game, real.contents) != Position.key(mirrored.contents) {
                divergences->Array.push(
                  `move ${Int.toString(i)} (${Position.describeMove(move)}): boards differ`,
                )
              }
              if Position.canFinish(mirrored.contents) != Reducer.canFinish(~game, real.contents) {
                divergences->Array.push(`move ${Int.toString(i)}: canFinish differs`)
              }
            }
          },
      )
      // And the plan did what it set out to: from here the Finish button wins it.
      expect(Reducer.canFinish(~game, real.contents))->toBe(true)
    }
    expect(divergences)->toEqual([])
  })

  test("a move's description names the card, the run and both ends", () => {
    let move: Position.move = {
      n: 3,
      source: Position.FromColumn(6),
      destination: Position.ToColumn(2),
      card: Position.idOf({suit: Hearts, rank: Ten}),
    }
    expect(Position.describeMove(move))->toBe("TH+2 from column 6 to column 2")
    expect(
      Position.describeMove({
        n: 1,
        source: Position.FromCell(1),
        destination: Position.ToFoundation,
        card: Position.idOf({suit: Spades, rank: Ace}),
      }),
    )->toBe("AS from cell 1 to foundation")
  })

  test("two boards that rest every card the same way share a key", () => {
    let position = packed(~game, opening)
    // Which free cell holds a card, and which column is which, are not part of the
    // position a search has already seen — so a key sorts both.
    let swapped = {
      ...Position.copy(position),
      cells: [3, -1, -1, -1],
      casc: position.casc->Array.copy->Array.toReversed,
    }
    let other = {...Position.copy(position), cells: [-1, -1, 3, -1]}
    expect(Position.key(swapped))->toBe(Position.key(other))
    expect(Position.key(position) == Position.key(other))->toBe(false)
  })
})
