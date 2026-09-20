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
    | None => {
        Position.law: FreeCell,
        pack: Position.standardPack,
        cells: [],
        found: [],
        casc: [],
        down: [],
        stock: [],
      } // fails loudly in any test that uses it
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

  test("a board with nowhere to send a card home packs to nothing at all", () => {
    // The counts are the board's own — cells and columns alike — but a suit with no
    // foundation to climb can never come home, and `found` would count it up all the
    // same. Here: the same deal with the free cells and foundations taken away.
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
              ->Array.filter(
                m =>
                  switch m {
                  | Position.Play({n}) => n == 1
                  | Position.Deal => false
                  },
              )
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
                        // A stock is sealed, so the reducer never accepts a drop onto one,
                        // and the model has no word for it. Should either change, this
                        // is a line the model can't offer, so it lands in `missing`.
                        | Game.Stock => ("stock", false)
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
    let move = Position.Play({
      n: 3,
      source: Position.FromColumn(6),
      destination: Position.ToColumn(2),
      card: Position.idOf({suit: Hearts, rank: Ten}),
    })
    expect(Position.describeMove(move))->toBe("TH+2 from column 6 to column 2")
    expect(
      Position.describeMove(
        Position.Play({
          n: 1,
          source: Position.FromCell(1),
          destination: Position.ToFoundation,
          card: Position.idOf({suit: Spades, rank: Ace}),
        }),
      ),
    )->toBe("AS from cell 1 to foundation")
    // A deal names no card because it has none to name.
    expect(Position.describeMove(Position.Deal))->toBe("deal a row")
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

// The same discipline under the other law. What's different is what's worth
// pinning: a board with no cells and sealed foundations, a run law that isn't the
// landing law, and a collect that lifts thirteen cards at once — so the mirror is
// held against the reducer on exactly those.
describe("Position under Simple Simon", () => {
  let game = Game.simpleSimonDeal(~seed=1)
  let opening = GameState.initial(game)

  let settle = (~game, state) =>
    if Reducer.canFinish(~game, state) {
      state
    } else {
      let (collected, _moved) = Reducer.autoCollect(~game, state)
      collected
    }

  let mirrorKey = (~game, state) =>
    Position.ofGameState(~game, state)->Option.mapOr("(not a board the model reads)", Position.key)

  let packed = (~game, state) =>
    switch Position.ofGameState(~game, state) {
    | Some(position) => position
    | None => {
        Position.law: SimpleSimon,
        pack: Position.standardPack,
        cells: [],
        found: [],
        casc: [],
        down: [],
        stock: [],
      } // fails loudly in any test that uses it
    }

  test("an opening deal packs under Simple Simon's law: no cells, ten columns", () => {
    let position = packed(~game, opening)
    expect(position.law)->toEqual(Position.SimpleSimon)
    expect(position.cells)->toEqual([])
    expect(position.found)->toEqual([0, 0, 0, 0])
    expect(position.casc->Array.map(Array.length))->toEqual(Game.simpleSimonCounts)
  })

  test("the law is read off the rules, and the shape is checked apart from it", () => {
    // Spiderette plays by Simple Simon's laws, so the law reads the same on all three
    // of its packs, and all three are boards the model holds — stock, repeated cards
    // and all; Spider is the same shape on two packs, and holds the same way. What is
    // *not* a refusal either is a board of another size: Mini reads under the same law
    // as FreeCell and packs, counts and pack and all.
    [
      Game.spiderette1,
      Game.spiderette,
      Game.spiderette4,
      Game.spider1,
      Game.spider,
      Game.spider4,
    ]->Array.forEach(
      board => {
        expect(Position.lawOf(board))->toEqual(Some(Position.SimpleSimon))
        expect(Position.ofGameState(~game=board, GameState.initial(board))->Option.isSome)->toBe(
          true,
        )
      },
    )
    expect(Position.lawOf(Game.mini))->toEqual(Some(Position.FreeCell))
    expect(
      Position.ofGameState(~game=Game.mini, GameState.initial(Game.mini))->Option.isSome,
    )->toBe(true)
  })

  test("every move the model offers is a move the reducer accepts", () => {
    let refusals = []
    let real = ref(opening)
    let sampled = ref(0)
    switch Solver.plan(~game, opening) {
    | None => refusals->Array.push("deal 1 went unsolved")
    | Some(moves) =>
      moves->Array.forEach(
        move => {
          let state = real.contents
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
    expect(sampled.contents > 100)->toBe(true)
  })

  test("the model offers every run move the reducer would accept", () => {
    // Completeness under a law where a run is *not* what lands: every tail of every
    // column that `Reducer.canMoveRun` would take, against every other column. Two
    // prunings are deliberate and excluded — a run goes only to the *first* empty
    // column (the others are the same move), and a whole column never moves into one
    // (that only renames the column).
    let missing = []
    let real = ref(opening)
    switch Solver.plan(~game, opening) {
    | None => missing->Array.push("deal 1 went unsolved")
    | Some(moves) =>
      moves->Array.forEachWithIndex(
        (move, i) => {
          let state = real.contents
          if mod(i, 5) == 0 {
            let position = packed(~game, state)
            let offered = Position.legalMoves(position)->Array.map(Position.describeMove)
            let cascades = Game.pileIndices(game, Game.Cascade)
            let firstEmptyColumn = position.casc->Array.findIndex(pile => Array.length(pile) == 0)
            cascades->Array.forEachWithIndex(
              (pile, src) => {
                let cards = GameState.cardsInPile(state, pile)
                for n in 1 to Array.length(cards) {
                  let run = cards->Array.slice(~start=Array.length(cards) - n)
                  cascades->Array.forEachWithIndex(
                    (onto, dest) =>
                      if dest != src && Reducer.canMoveRun(~game, state, run, ~onto) {
                        let intoEmpty = Array.length(GameState.cardsInPile(state, onto)) == 0
                        let pruned =
                          intoEmpty && (dest != firstEmptyColumn || n == Array.length(cards))
                        let wanted = Position.describeMove(
                          Position.Play({
                            n,
                            source: Position.FromColumn(src),
                            destination: Position.ToColumn(dest),
                            card: Position.idOf(run->Array.getUnsafe(0)),
                          }),
                        )
                        if !pruned && !(offered->Array.includes(wanted)) {
                          missing->Array.push(wanted)
                        }
                      },
                  )
                }
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

  test("collecting a run, canFinish and the board after a move are the reducer's too", () => {
    // A whole game played twice, compared after every move — through four runs
    // lifted off the tableau, since the line runs to the win.
    let divergences = []
    switch Solver.plan(~game, opening) {
    | None => divergences->Array.push("deal 1 went unsolved")
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
      // Under this law the finishable board *is* the won one: nothing drains.
      expect(GameState.hasWon(game, real.contents))->toBe(true)
      expect(Position.hasWon(mirrored.contents))->toBe(true)
    }
    expect(divergences)->toEqual([])
  })
})

// A board with cards face down, which is the one board the model knows more about
// than the player does: the cards under a column's boundary are packed like every
// other card and the search reads them (`docs/solver.md` § What the solver sees).
// What has to be pinned is therefore not what the model *sees* but what it lets a
// hand take hold of, and what a move leaves behind when it uncovers something — both
// of which `Reducer` already answers, so every test here asks it the same question.
//
// The boards here are posed rather than dealt, so one column's boundary can be put
// exactly where a case needs it — Spiderette deals a board with forty-five cards face
// down, but every one of its columns shows exactly one card.
describe("Position with cards face down", () => {
  let settle = (~game, state) =>
    if Reducer.canFinish(~game, state) {
      state
    } else {
      let (collected, _moved) = Reducer.autoCollect(~game, state)
      collected
    }

  // A real deal, dealt Klondike-style: the bottom `under` cards of every column face
  // down, never so many that a column has nothing showing.
  let hiding = (game: Game.t, ~under: int): Game.t => {
    ...game,
    piles: game.piles->Array.map((pile: Game.pile) =>
      switch pile.role {
      | Game.Cascade => {...pile, faceDown: Math.Int.min(under, Array.length(pile.cards) - 1)}
      | _ => pile
      }
    ),
  }

  // A board posed column by column rather than dealt: `columns` on the cascades in
  // board order with `down` of each face down, everything else empty. A handful of
  // cards is enough to ask what a hand may lift, so these boards are not whole packs.
  let posed = (game: Game.t, ~columns: array<array<card>>, ~down: array<int>): GameState.t => {
    let cascades = Game.pileIndices(game, Game.Cascade)
    let forPile = (queue, i) =>
      switch cascades->Array.indexOf(i) {
      | -1 => None
      | col => queue->Array.get(col)
      }
    {
      GameState.piles: game.piles->Array.mapWithIndex((_, i) =>
        forPile(columns, i)->Option.getOr([])
      ),
      loose: [],
      faceDown: game.piles->Array.mapWithIndex((_, i) => forPile(down, i)->Option.getOr(0)),
    }
  }

  test("the cards under the boundary are packed like any other, and counted", () => {
    let game = hiding(Game.miniDeal(~seed=1), ~under=1)
    let opening = GameState.initial(game)
    switch Position.ofGameState(~game, opening) {
    | None => expect("a board with a card face down packs")->toBe("but it didn't")
    | Some(position) =>
      expect(position.down)->toEqual([1, 1, 1, 1])
      // Every column in full, hidden bottom card included: this is the decision of
      // what the solver may see, written as an assertion.
      Game.pileIndices(game, Game.Cascade)->Array.forEachWithIndex(
        (pile, col) =>
          expect(position.casc->Array.getUnsafe(col))->toEqual(
            GameState.cardsInPile(opening, pile)->Array.map(Position.idOf),
          ),
      )
    }
  })

  test("a card hidden anywhere else is a board the model declines", () => {
    // Face down is a fact about a column's *lower* cards. A hidden card in a free
    // cell, and a column with nothing showing at all, are both boards whose top card
    // no predicate here could name — and neither happens in play, since the reducer
    // turns over whatever a move uncovers.
    let game = Game.mini
    let cell = Game.pileIndices(game, Game.FreeCell)->Array.getUnsafe(0)
    let board = posed(game, ~columns=[[{suit: Clubs, rank: Five}]], ~down=[0])
    expect(Position.ofGameState(~game, board)->Option.isSome)->toBe(true)
    let inCell = {
      ...board,
      piles: board.piles->Array.mapWithIndex(
        (cards, i) => i == cell ? [{suit: Spades, rank: Ace}] : cards,
      ),
      faceDown: board.faceDown->Array.mapWithIndex((n, i) => i == cell ? 1 : n),
    }
    expect(Position.ofGameState(~game, inCell))->toEqual(None)
    let blind = posed(
      game,
      ~columns=[[{suit: Spades, rank: Five}, {suit: Diamonds, rank: Four}]],
      ~down=[2],
    )
    expect(Position.ofGameState(~game, blind))->toEqual(None)
  })

  test("a run reads up to the boundary and no further, as the reducer's span does", () => {
    // ♠5 ♦4 ♣3 is a run all three cards long, and the ♠5 lies face down — so a hand
    // can only take the two above it. The ♦2 under the ♠5 is what makes that worth
    // asserting: without it the three-card lift is the whole column, which the model
    // declines to move into an empty one anyway, and a boundary that did nothing
    // would look the same from here.
    let game = Game.mini
    let column = [
      {suit: Diamonds, rank: Two},
      {suit: Spades, rank: Five},
      {suit: Diamonds, rank: Four},
      {suit: Clubs, rank: Three},
    ]
    let run = column->Array.sliceToEnd(~start=1)
    let state = posed(game, ~columns=[column, [{suit: Clubs, rank: Five}]], ~down=[2, 0])
    let empty = Game.pileIndices(game, Game.Cascade)->Array.getUnsafe(2)
    switch Position.ofGameState(~game, state) {
    | None => expect("a posed board packs")->toBe("but it didn't")
    | Some(position) =>
      let packedColumn = position.casc->Array.getUnsafe(0)
      // The run really does carry on below the boundary: it is the count that stops
      // the reading, not the cards.
      expect(Position.runLength(Position.FreeCell, packedColumn, ~down=0))->toBe(3)
      expect(Position.runLength(Position.FreeCell, packedColumn, ~down=2))->toBe(2)
      // …so the deepest grab the model authorises from that column takes two cards.
      expect(
        Position.legalMoves(position)->Array.reduce(
          0,
          (most, move) =>
            switch move {
            | Position.Play({source: Position.FromColumn(0), n}) => Math.Int.max(most, n)
            | _ => most
            },
        ),
      )->toBe(2)
    }
    // And that is the reducer's own answer: the whole run is not a span it will lift,
    // and the refusal names the reason rather than calling the bottom card buried.
    expect(Reducer.canMoveRun(~game, state, run, ~onto=empty))->toBe(false)
    expect(
      Reducer.reduce(~game, state, Reducer.MoveRun({cards: run, to: Reducer.ToPile(empty)})),
    )->toEqual(Error(Reducer.CardFaceDown))
    expect(Reducer.canMoveRun(~game, state, run->Array.sliceToEnd(~start=1), ~onto=empty))->toBe(
      true,
    )
  })

  // The round trip, on a board with cards face down: a whole line played twice, once
  // through `Reducer` and once through the mirror, compared after every move. The
  // cards that get uncovered along the way are what this is here for — the reducer
  // turns one over as part of the move that exposes it, so a mirror that didn't would
  // diverge on the very next key. Both laws, since the flip is neither law's.
  [
    ("Mini", hiding(Game.miniDeal(~seed=1), ~under=1)),
    ("Simple Simon", hiding(Game.simpleSimonDeal(~seed=1), ~under=2)),
  ]->Array.forEach(((label, game)) =>
    test(
      `the board after a move, the card it turns over and canFinish are the reducer's on ${label}`,
      () => {
        let opening = GameState.initial(game)
        let divergences = []
        switch (Position.ofGameState(~game, opening), Solver.plan(~game, opening)) {
        | (None, _) => divergences->Array.push(`${label} face down isn't a board the model reads`)
        | (_, None) => divergences->Array.push(`${label} face down went unsolved`)
        | (Some(start), Some(moves)) =>
          let real = ref(opening)
          let mirrored = ref(start)
          moves->Array.forEachWithIndex(
            (move, i) =>
              switch Position.toAction(~game, real.contents, move) {
              | None => divergences->Array.push(`move ${Int.toString(i)}: no action for it`)
              | Some(action) =>
                switch Reducer.reduce(~game, real.contents, action) {
                | Error(_) =>
                  divergences->Array.push(`move ${Int.toString(i)}: the reducer refused it`)
                | Ok(next) =>
                  real := settle(~game, next)
                  mirrored := Position.applyMove(mirrored.contents, move)
                  let realKey =
                    Position.ofGameState(~game, real.contents)->Option.mapOr(
                      "(not a board the model reads)",
                      Position.key,
                    )
                  if realKey != Position.key(mirrored.contents) {
                    divergences->Array.push(
                      `move ${Int.toString(i)} (${Position.describeMove(move)}): boards differ`,
                    )
                  }
                  if (
                    Position.canFinish(mirrored.contents) != Reducer.canFinish(~game, real.contents)
                  ) {
                    divergences->Array.push(`move ${Int.toString(i)}: canFinish differs`)
                  }
                }
              },
          )
          expect(Reducer.canFinish(~game, real.contents))->toBe(true)
          // The line really did uncover cards, so the flip above was exercised rather
          // than merely available: a board that ended as hidden as it began would
          // have compared two models that never had to turn anything over.
          let hidden = (state: GameState.t) => state.faceDown->Array.reduce(0, (a, b) => a + b)
          expect(hidden(real.contents) < hidden(opening))->toBe(true)
        }
        expect(divergences)->toEqual([])
      },
    )
  )
})

// The same law as the first block, over a pack that isn't fifty-two cards. What's
// worth pinning is every place a 52 or a 13 used to be written down — a won board's
// total, the rank a foundation is done at, and which foundations a card waits on
// before it is safe to collect. Micro is the sharp one: its ♠♥ pack has *one* suit
// of the other colour, so a rule naming two by number stalls above the Twos.
describe("Position on a short pack", () => {
  let settle = (~game, state) =>
    if Reducer.canFinish(~game, state) {
      state
    } else {
      let (collected, _moved) = Reducer.autoCollect(~game, state)
      collected
    }

  test("the pack is the board's own deck, counts and all", () => {
    switch (
      Position.ofGameState(~game=Game.mini, GameState.initial(Game.mini)),
      Position.ofGameState(~game=Game.micro, GameState.initial(Game.micro)),
    ) {
    | (Some(mini), Some(micro)) =>
      expect(mini.pack)->toEqual({Position.suits: [0, 1, 2, 3], ranks: 5, size: 20, copies: 1})
      expect(mini.cells)->toEqual([-1, -1])
      expect(Array.length(mini.casc))->toBe(4)
      // Micro's two suits keep their numbers from the full pack — ♠ 0 and ♥ 1 — so
      // `isRed` and `suitOf` read a short deck with no case of their own.
      expect(micro.pack)->toEqual({Position.suits: [0, 1], ranks: 8, size: 16, copies: 1})
      expect(
        micro.casc
        ->Array.flatMap(pile => pile)
        ->Array.every(card => Position.suitOf(card) == 0 || Position.suitOf(card) == 1),
      )->toBe(true)
      // A won board totals the pack, not 52.
      expect(Position.hasWon({...micro, found: [8, 8, 0, 0]}))->toBe(true)
      expect(Position.hasWon({...mini, found: [5, 5, 5, 5]}))->toBe(true)
    | _ => expect("both short packs read")->toBe("but one of them didn't")
    }
  })

  // A whole game played twice, once through `Reducer` and once through the mirror,
  // for each of the two boards — the test that catches a predicate still counting to
  // thirteen. Deal #3 of each, so neither is the opening every screenshot uses.
  [Game.miniDeal(~seed=3), Game.microDeal(~seed=3)]->Array.forEach(game =>
    test(
      `auto-collect, canFinish and the board after a move are the reducer's on ${game.name}`,
      () => {
        let opening = GameState.initial(game)
        let divergences = []
        switch (Position.ofGameState(~game, opening), Solver.plan(~game, opening)) {
        | (None, _) => divergences->Array.push(`${game.name} isn't a board the model reads`)
        | (_, None) => divergences->Array.push(`${game.name} deal 3 went unsolved`)
        | (Some(start), Some(moves)) =>
          let real = ref(opening)
          let mirrored = ref(start)
          moves->Array.forEachWithIndex(
            (move, i) =>
              switch Position.toAction(~game, real.contents, move) {
              | None => divergences->Array.push(`move ${Int.toString(i)}: no action for it`)
              | Some(action) =>
                switch Reducer.reduce(~game, real.contents, action) {
                | Error(_) =>
                  divergences->Array.push(`move ${Int.toString(i)}: the reducer refused it`)
                | Ok(next) =>
                  real := settle(~game, next)
                  mirrored := Position.applyMove(mirrored.contents, move)
                  let realKey =
                    Position.ofGameState(~game, real.contents)->Option.mapOr(
                      "(not a board the model reads)",
                      Position.key,
                    )
                  if realKey != Position.key(mirrored.contents) {
                    divergences->Array.push(
                      `move ${Int.toString(i)} (${Position.describeMove(move)}): boards differ`,
                    )
                  }
                  if (
                    Position.canFinish(mirrored.contents) != Reducer.canFinish(~game, real.contents)
                  ) {
                    divergences->Array.push(`move ${Int.toString(i)}: canFinish differs`)
                  }
                }
              },
          )
          expect(Reducer.canFinish(~game, real.contents))->toBe(true)
        }
        expect(divergences)->toEqual([])
      },
    )
  )
})

// A board with a stock, where a move can be something other than a card leaving one
// pile for another. Everything the blocks above pin about the rules holds here
// unchanged — Spiderette between deals *is* Simple Simon — so these ask only about the
// deal: whether the model offers one exactly when the reducer would take one, and
// whether a row lands where the reducer lands it.
//
// The standard pack, because the deal is all these ask about and one pack answers it.
// What the other two variants add — the same card twice on the table — is the block
// after this one.
describe("Position with a stock to deal from", () => {
  let game = Game.spiderette4Deal(~seed=1)
  let opening = GameState.initial(game)
  let stockPile = Game.pileIndices(game, Game.Stock)->Array.getUnsafe(0)

  let settle = (~game, state) =>
    if Reducer.canFinish(~game, state) {
      state
    } else {
      let (collected, _moved) = Reducer.autoCollect(~game, state)
      collected
    }

  let mirrorKey = (~game, state) =>
    Position.ofGameState(~game, state)->Option.mapOr("(not a board the model reads)", Position.key)

  test("an opening deal packs its stock, and the board it deals onto", () => {
    switch Position.ofGameState(~game, opening) {
    | None => expect("a Spiderette board packs")->toBe("but it didn't")
    | Some(position) =>
      expect(position.law)->toEqual(Position.SimpleSimon)
      expect(Array.length(position.casc))->toBe(7)
      // Every column but the first lies partly face down, and the stock lies face down
      // in its entirety — which the model reads rather than refuses.
      expect(position.down)->toEqual([0, 1, 2, 3, 4, 5, 6])
      expect(position.stock)->toEqual(
        GameState.cardsInPile(opening, stockPile)->Array.map(Position.idOf),
      )
      expect(Array.length(position.stock))->toBe(24)
      // Its *end* is its top: the seven cards the next deal drops, in landing order,
      // are the last seven reversed — which is what `Reducer.nextDeal` says they are.
      expect(Position.dealCount(position))->toBe(7)
      expect(Reducer.nextDeal(~game, opening)->Array.map(Position.idOf))->toEqual(
        position.stock->Array.sliceToEnd(~start=17)->Array.toReversed,
      )
    }
  })

  test("a deal is offered exactly when the reducer would take one", () => {
    // `Reducer.dealRefusal` names three refusals and each board below raises a
    // different one — so a mirror that happened to agree by refusing everything, or by
    // reading only the stock, disagrees here.
    let stuck = Scenario.spideretteStuck(game)
    let out = Scenario.spideretteAlmostWon(game)
    let freecell = Game.freecell
    let dealsNothing = GameState.initial(freecell)
    expect(Reducer.dealRefusal(~game, opening))->toEqual(None)
    expect(Reducer.dealRefusal(~game, stuck))->toEqual(Some(Reducer.CascadeEmpty))
    expect(Reducer.dealRefusal(~game, out))->toEqual(Some(Reducer.StockEmpty))
    expect(Reducer.dealRefusal(~game=freecell, dealsNothing))->toEqual(Some(Reducer.NoStock))

    let disagreements = []
    [
      ("the opening", game, opening),
      ("a cascade standing empty", game, stuck),
      ("the stock out", game, out),
      ("no stock at all", freecell, dealsNothing),
    ]->Array.forEach(
      ((what, game, state)) =>
        switch Position.ofGameState(~game, state) {
        | None => disagreements->Array.push(`${what}: not a board the model reads`)
        | Some(position) =>
          let would = Reducer.dealRefusal(~game, state)->Option.isNone
          if Position.canDeal(position) != would {
            disagreements->Array.push(`${what}: canDeal disagrees with dealRefusal`)
          }

          // …and the answer reaches the search and a driver by the two routes they use.
          if Position.legalMoves(position)->Array.includes(Position.Deal) != would {
            disagreements->Array.push(`${what}: legalMoves disagrees`)
          }
          if Position.toAction(~game, state, Position.Deal)->Option.isSome != would {
            disagreements->Array.push(`${what}: toAction disagrees`)
          }
        },
    )
    expect(disagreements)->toEqual([])
  })

  test("a dealt row lands the cards the reducer lands, in the same places", () => {
    switch (Position.ofGameState(~game, opening), Reducer.reduce(~game, opening, Reducer.Deal)) {
    | (Some(position), Ok(dealt)) =>
      let mirrored = Position.applyMove(position, Position.Deal)
      expect(Position.key(mirrored))->toBe(mirrorKey(~game, settle(~game, dealt)))
      expect(Array.length(mirrored.stock))->toBe(17)
      // The face-down counts don't move: a dealt card lands face up above them.
      expect(mirrored.down)->toEqual(position.down)
    | _ => expect("the opening deals")->toBe("but it didn't")
    }
  })

  testWithin(
    "a whole game, four deals and all, is the same board in both models",
    () => {
      // The check the other blocks make, over the one line that takes a move nobody
      // else's board has. A won Spiderette has every card on the tableau at some
      // point, so a line that wins is a line that dealt the stock out — which is what
      // makes the count at the end worth asserting.
      let divergences = []
      switch (Position.ofGameState(~game, opening), Solver.plan(~game, opening)) {
      | (None, _) => divergences->Array.push("Spiderette · 4 suits isn't a board the model reads")
      | (_, None) => divergences->Array.push("deal 1 went unsolved")
      | (Some(start), Some(moves)) =>
        let real = ref(opening)
        let mirrored = ref(start)
        let deals = ref(0)
        moves->Array.forEachWithIndex((move, i) =>
          switch Position.toAction(~game, real.contents, move) {
          | None => divergences->Array.push(`move ${Int.toString(i)}: no action for it`)
          | Some(action) =>
            if action == Reducer.Deal {
              deals := deals.contents + 1
            }
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
            }
          }
        )
        expect(deals.contents)->toBe(4)
        expect(GameState.hasWon(game, real.contents))->toBe(true)
        expect(Position.hasWon(mirrored.contents))->toBe(true)
      }
      expect(divergences)->toEqual([])
    },
    ~timeout=120_000,
  )
})

// A board where the same face sits on the table more than once — Spiderette · 1 suit is
// ♠ taken four times, · 2 suits is ♠♥ taken twice. The packing **collapses the copies
// deliberately**: both Sevens of Spades are the int 6, because two boards differing only
// in which of them sits where are the same position and `key` already sorts to say so.
//
// So these ask about the one place the collapse would lose something real. `found` is
// four wide and indexed by suit, and a suit that repeats has several runs to put there
// — which works exactly as long as the entry counts *cards home* and `collectRuns` adds
// to it. Assigning `ranks` would leave a board with four ♠ runs collected reading as
// one, and a won game never winning.
describe("Position on a pack that repeats a card", () => {
  let cascadeAt = (game, k) => Game.pileIndices(game, Game.Cascade)->Array.getUnsafe(k)

  test("a suit's runs add up, and the last of them wins the board in both models", () => {
    let disagreements = []
    // `Scenario.spideretteAlmostWon` collects every run but the last, and leaves that
    // one's King→Two on the first cascade with its Ace alone on the second: one drag
    // completes it, and collecting it is the win. Its `found` before the drag is the
    // assertion — three runs of one suit read as 39 only if they were added.
    [
      (Game.spiderette1Deal(~seed=1), [39, 0, 0, 0], [52, 0, 0, 0]),
      (Game.spideretteDeal(~seed=1), [26, 13, 0, 0], [26, 26, 0, 0]),
    ]->Array.forEach(
      ((game, before, after)) => {
        let almost = Scenario.spideretteAlmostWon(game)
        let ace = GameState.topOf(almost, cascadeAt(game, 1))->Option.getOrThrow
        let drag = Reducer.Move({card: ace, to: Reducer.ToPile(cascadeAt(game, 0))})
        let play = Position.Play({
          n: 1,
          source: Position.FromColumn(1),
          destination: Position.ToColumn(0),
          card: Position.idOf(ace),
        })
        switch (Position.ofGameState(~game, almost), Reducer.reduce(~game, almost, drag)) {
        | (None, _) => disagreements->Array.push(`${game.id}: not a board the model reads`)
        | (_, Error(_)) => disagreements->Array.push(`${game.id}: the reducer refused the drag`)
        | (Some(position), Ok(dragged)) =>
          expect(position.found)->toEqual(before)
          expect(Position.foundationTotal(position))->toBe(before->Array.reduce(0, (a, b) => a + b))
          expect(Position.hasWon(position))->toBe(false)
          expect(GameState.hasWon(game, almost))->toBe(false)

          // The plan has to be a move the board would take, on a pack where `cardOf`
          // can't name which copy the plan meant.
          if !(Position.legalMoves(position)->Array.some(offered => offered == play)) {
            disagreements->Array.push(`${game.id}: the model doesn't offer the drag`)
          }
          if Position.toAction(~game, almost, play) != Some(drag) {
            disagreements->Array.push(`${game.id}: toAction resolves the drag to another card`)
          }

          let (settled, _moved) = Reducer.autoCollect(~game, dragged)
          let mirrored = Position.applyMove(position, play)
          expect(mirrored.found)->toEqual(after)
          expect(Position.foundationTotal(mirrored))->toBe(mirrored.pack.size)
          expect(Position.hasWon(mirrored))->toBe(true)
          expect(GameState.hasWon(game, settled))->toBe(true)
        }
      },
    )
    expect(disagreements)->toEqual([])
  })

  test("a repeated pack is refused under FreeCell's law, where `found` is a rank", () => {
    // The collapse costs nothing under Simple Simon's law because `found` counts runs
    // there. FreeCell's law reads the same entry as the rank its foundation has climbed
    // to — a second copy would carry it past the King — so the refusal stays, and stays
    // where the reading it protects is.
    //
    // The four extra foundations are what make this the *copies* refusal and not the
    // count one: a doubled deck has eight runs to send home, and a board with four
    // foundations would have been refused whatever its law.
    let spare: Game.pile = {
      role: Game.Foundation,
      stacking: Game.Squared,
      rule: Rules.foundation,
      capacity: None,
      cards: [],
      faceDown: 0,
    }
    let doubled: Game.t = {
      ...Game.freecell,
      deck: {suits: Cards.suits, ranks: Cards.ranks, copies: 2},
      piles: Game.freecell.piles->Array.concat(Array.make(~length=4, spare)),
    }
    expect(Position.lawOf(doubled))->toEqual(Some(Position.FreeCell))
    expect(Array.length(Game.pileIndices(doubled, Game.Foundation)))->toBe(8)
    expect(Position.ofGameState(~game=doubled, GameState.initial(doubled)))->toEqual(None)
  })
})
