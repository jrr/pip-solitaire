open Vitest
open Card

test("greeting returns the expected message", () => {
  expect(Core.greeting())->toBe("Hello from ReScript core!")
})

// The modelled games (#62): assert the rules the presentation layer reads back.
describe("Game", () => {
  test(
    "the stacking demo is two piles (squared, then fanned), free, dealt an Ace→King run",
    () => {
      expect(Game.stacking.piles->Array.map(p => p.stacking))->toEqual([Game.Squared, Game.Fanned])
      expect(Game.stacking.free)->toBe(true)
      // The whole run is dealt loose, low-to-high, so it can be assembled onto a
      // pile: thirteen cards, Ace→King, each the opposite colour of the one below.
      expect(Game.stacking.loose->Array.map(c => c.rank))->toEqual([
        Ace,
        Two,
        Three,
        Four,
        Five,
        Six,
        Seven,
        Eight,
        Nine,
        Ten,
        Jack,
        Queen,
        King,
      ])
      let colours = Game.stacking.loose->Array.map(c => Rules.color(c.suit))
      expect(colours->Array.every(c => c == Rules.Red || c == Rules.Black))->toBe(true)
      // No two neighbours share a colour, so every step up the run is a legal drop.
      let alternates =
        colours
        ->Array.mapWithIndex((c, i) => i == 0 || c != colours->Array.getUnsafe(i - 1))
        ->Array.every(x => x)
      expect(alternates)->toBe(true)
    },
  )

  test("the stacking demo confines drops to a legal Ace→King run", () => {
    // Both piles enforce the tableau rule; take the first and stack the dealt run
    // end-to-end onto it: each card lands on the one below it (an empty pile
    // founds the run).
    let rule = (Game.stacking.piles->Array.getUnsafe(0)).rule
    let run = Game.stacking.loose
    let legal =
      run->Array.mapWithIndex(
        (c, i) => Rules.accepts(rule, c, i == 0 ? None : Some(run->Array.getUnsafe(i - 1))),
      )
    expect(legal->Array.every(x => x))->toBe(true)
    // A same-colour or non-consecutive drop is rejected.
    expect(Rules.accepts(rule, {suit: Spades, rank: Two}, Some({suit: Clubs, rank: Ace})))->toBe(
      false,
    )
    expect(Rules.accepts(rule, {suit: Hearts, rank: Four}, Some({suit: Clubs, rank: Ace})))->toBe(
      false,
    )
  })

  test("foundations pairs a same-suit foundation with an alternating tableau", () => {
    let piles = Game.foundations.piles
    expect(piles->Array.map(p => p.rule))->toEqual([Rules.foundation, Rules.tableau])
    // The dealt Hearts Ace→King run stacks end-to-end onto the foundation and
    // completes it, ending on the King.
    let hearts = Game.foundations.loose->Array.filter(c => c.suit == Hearts)
    let foundationRule = (piles->Array.getUnsafe(0)).rule
    let legal =
      hearts->Array.mapWithIndex(
        (c, i) =>
          Rules.accepts(foundationRule, c, i == 0 ? None : Some(hearts->Array.getUnsafe(i - 1))),
      )
    expect(legal->Array.every(x => x))->toBe(true)
    expect(Rules.isCompleteRun(hearts))->toBe(true)
    // The foundation rejects an off-suit card even when the rank ascends, and
    // opens accepting only an Ace.
    expect(
      Rules.accepts(foundationRule, {suit: Spades, rank: Two}, Some({suit: Hearts, rank: Ace})),
    )->toBe(false)
    expect(Rules.accepts(foundationRule, {suit: Hearts, rank: King}, None))->toBe(false)
  })

  test("four-fans is free-arrangement: any card lands on any pile", () => {
    // The un-ordered demo uses the permissive rule, so no drop is rejected.
    let rule = (Game.fourFans.piles->Array.getUnsafe(0)).rule
    expect(Rules.accepts(rule, {suit: Spades, rank: King}, Some({suit: Spades, rank: Two})))->toBe(
      true,
    )
  })

  test("four-fans is four fanned piles, not free, opening with cards in each pile", () => {
    expect(Game.fourFans.piles->Array.map(p => p.stacking))->toEqual([
      Game.Fanned,
      Game.Fanned,
      Game.Fanned,
      Game.Fanned,
    ])
    expect(Game.fourFans.free)->toBe(false)
    // Every pile opens holding a few cards, and nothing is dealt loose.
    expect(Game.fourFans.piles->Array.every(p => Array.length(p.cards) > 0))->toBe(true)
    expect(Game.fourFans.loose)->toEqual([])
  })

  test("every game is listed with a stable id and a non-empty name", () => {
    expect(Game.all->Array.map(g => g.id))->toEqual([
      "stacking",
      "foundations",
      "four-fans",
      "free-cells",
      "mixed-roles",
      "cascade",
      "shuffled-deal",
      "freecell",
    ])
    expect(Game.all->Array.every(g => g.name != ""))->toBe(true)
  })

  test("free-cells is four capacity-1 Free cells, free, with loose cards to park", () => {
    // Each cell is a permissive (`Free`) pile capped at one card of any suit.
    expect(Game.freeCells.piles->Array.map(p => p.rule))->toEqual([
      Rules.Free,
      Rules.Free,
      Rules.Free,
      Rules.Free,
    ])
    expect(Game.freeCells.piles->Array.map(p => p.capacity))->toEqual([
      Some(1),
      Some(1),
      Some(1),
      Some(1),
    ])
    // Free drops are allowed, the cells open empty, and there are loose cards to
    // park (no more than there are cells, so the whole deal can be stored).
    expect(Game.freeCells.free)->toBe(true)
    expect(Game.freeCells.piles->Array.every(p => Array.length(p.cards) == 0))->toBe(true)
    expect(Array.length(Game.freeCells.loose) > 0)->toBe(true)
  })

  test("the cascade demo confines drops to a legal King→Ace descending run", () => {
    // Both piles enforce the cascade rule (build *down*); take the first and
    // stack the dealt run end-to-end onto it: each card lands on the one below it
    // (an empty pile founds the run).
    let rule = (Game.cascade.piles->Array.getUnsafe(0)).rule
    let run = Game.cascade.loose
    // The run descends King→Ace in alternating colours, so every step down is a
    // legal drop.
    expect(run->Array.map(c => c.rank))->toEqual([
      King,
      Queen,
      Jack,
      Ten,
      Nine,
      Eight,
      Seven,
      Six,
      Five,
      Four,
      Three,
      Two,
      Ace,
    ])
    let legal =
      run->Array.mapWithIndex(
        (c, i) => Rules.accepts(rule, c, i == 0 ? None : Some(run->Array.getUnsafe(i - 1))),
      )
    expect(legal->Array.every(x => x))->toBe(true)
    // A same-colour or non-descending drop is rejected.
    expect(Rules.accepts(rule, {suit: Spades, rank: Jack}, Some({suit: Clubs, rank: Queen})))->toBe(
      false,
    )
    expect(Rules.accepts(rule, {suit: Hearts, rank: Ten}, Some({suit: Clubs, rank: Queen})))->toBe(
      false,
    )
  })

  test("the shuffled-deal demo lays a whole reproducible deck across eight piles", () => {
    // Eight permissive cascades, free, nothing loose — every card is dealt into a
    // pile.
    expect(Game.shuffledDeal.piles->Array.length)->toBe(8)
    expect(Game.shuffledDeal.piles->Array.map(p => p.rule))->toEqual([
      Rules.Free,
      Rules.Free,
      Rules.Free,
      Rules.Free,
      Rules.Free,
      Rules.Free,
      Rules.Free,
      Rules.Free,
    ])
    expect(Game.shuffledDeal.free)->toBe(true)
    expect(Game.shuffledDeal.loose)->toEqual([])
    // The whole 52-card deck is dealt out, none lost or duplicated: the pooled
    // pile cards are a permutation of `Cards.all`.
    let dealt = Game.shuffledDeal.piles->Array.flatMap(p => p.cards)
    expect(dealt->Array.length)->toBe(52)
    expect(
      Cards.all->Array.every(card => dealt->Array.some(c => GameState.sameCard(c, card))),
    )->toBe(true)
    // Round-robin across eight piles spreads 52 as 7,7,7,7,6,6,6,6.
    expect(Game.shuffledDeal.piles->Array.map(p => Array.length(p.cards)))->toEqual([
      7,
      7,
      7,
      7,
      6,
      6,
      6,
      6,
    ])
  })

  // The assembled FreeCell board (#97): the four enablers (#93 capacity, #94
  // roles, #95 the cascade rule, #96 the seeded deck) converge into one 16-pile
  // `Game.t`, dealt from a seed and playable through the existing reducer.
  describe("freecell", () => {
    test(
      "is sixteen piles: 4 free cells, 4 foundations, then 8 cascades",
      () => {
        let board = Game.freecell
        expect(Array.length(board.piles))->toBe(16)
        // The roles, in board order: four cells and four foundations across the
        // top, eight cascades below.
        expect(board.piles->Array.map(p => p.role))->toEqual([
          Game.FreeCell,
          Game.FreeCell,
          Game.FreeCell,
          Game.FreeCell,
          Game.Foundation,
          Game.Foundation,
          Game.Foundation,
          Game.Foundation,
          Game.Cascade,
          Game.Cascade,
          Game.Cascade,
          Game.Cascade,
          Game.Cascade,
          Game.Cascade,
          Game.Cascade,
          Game.Cascade,
        ])
        // `pileIndices` addresses each group by role (#94).
        expect(Game.pileIndices(board, Game.FreeCell))->toEqual([0, 1, 2, 3])
        expect(Game.pileIndices(board, Game.Foundation))->toEqual([4, 5, 6, 7])
        expect(Game.pileIndices(board, Game.Cascade))->toEqual([8, 9, 10, 11, 12, 13, 14, 15])
      },
    )

    test(
      "each role carries its FreeCell rule and capacity",
      () => {
        let board = Game.freecell
        // Free cells: capacity-1 `Free` slots.
        Game.pilesOf(board, Game.FreeCell)->Array.forEach(
          p => {
            expect(p.rule)->toEqual(Rules.Free)
            expect(p.capacity)->toEqual(Some(1))
          },
        )
        // Foundations: same-suit ascending, unbounded.
        Game.pilesOf(board, Game.Foundation)->Array.forEach(
          p => {
            expect(p.rule)->toEqual(Rules.foundation)
            expect(p.capacity)->toEqual(None)
          },
        )
        // Cascades: build down in alternating colour, unbounded, fanned.
        Game.pilesOf(board, Game.Cascade)->Array.forEach(
          p => {
            expect(p.rule)->toEqual(Rules.cascade)
            expect(p.capacity)->toEqual(None)
            expect(p.stacking)->toEqual(Game.Fanned)
          },
        )
        // Cards only ever rest in piles — no loose table.
        expect(board.free)->toBe(false)
      },
    )

    test(
      "deals the whole 52-card deck across the cascades, 7/7/7/7/6/6/6/6, cells and foundations empty",
      () => {
        let board = Game.freecell
        let cascades = Game.pilesOf(board, Game.Cascade)
        // The classic FreeCell split: the first four columns hold seven, the rest
        // six.
        expect(cascades->Array.map(p => Array.length(p.cards)))->toEqual([7, 7, 7, 7, 6, 6, 6, 6])
        // The pooled cascade cards are the full 52-card deck — every card exactly
        // once, none dropped or duplicated.
        let dealt = cascades->Array.flatMap(p => p.cards)
        expect(Array.length(dealt))->toBe(52)
        expect(
          Cards.all->Array.every(card => dealt->Array.some(c => GameState.sameCard(c, card))),
        )->toBe(true)
        // The free cells and foundations open empty.
        expect(
          Game.pilesOf(board, Game.FreeCell)->Array.every(p => Array.length(p.cards) == 0),
        )->toBe(true)
        expect(
          Game.pilesOf(board, Game.Foundation)->Array.every(p => Array.length(p.cards) == 0),
        )->toBe(true)
        expect(board.loose)->toEqual([])
      },
    )

    test(
      "the deal is reproducible: the same seed lays out the same cascades",
      () => {
        // The default board is deal #1, and rebuilding that seed reproduces it
        // exactly (the basis for shareable deal numbers, #96).
        let byDefault = Game.freecell.piles->Array.map(p => p.cards)
        let rebuilt = Game.freecellDeal(~seed=1).piles->Array.map(p => p.cards)
        expect(rebuilt)->toEqual(byDefault)
        // A different seed deals a different board.
        let other = Game.freecellDeal(~seed=2)
        let differs =
          Game.pileIndices(other, Game.Cascade)->Array.some(
            i =>
              GameState.cardsInPile(GameState.initial(other), i) !=
                GameState.cardsInPile(GameState.initial(Game.freecell), i),
          )
        expect(differs)->toBe(true)
      },
    )

    test(
      "plays a scripted sequence of legal and illegal single-card moves through the reducer",
      () => {
        let board = Game.freecell
        let cell = Game.pileIndices(board, Game.FreeCell)->Array.getUnsafe(0)
        let foundation = Game.pileIndices(board, Game.Foundation)->Array.getUnsafe(0)
        let state = GameState.initial(board)

        // Park a card in an empty free cell — a `Free`, capacity-1 slot takes any
        // single card. (The reducer reaches a card wherever it rests, so the
        // script is robust to the shuffle.)
        let afterPark = switch Reducer.reduce(
          ~game=board,
          state,
          Move({card: {suit: Spades, rank: King}, to: ToPile(cell)}),
        ) {
        | Ok(s) =>
          expect(GameState.topOf(s, cell))->toEqual(Some({suit: Spades, rank: King}))
          s
        | Error(_) =>
          expect(true)->toBe(false) // parking in an empty free cell should succeed
          state
        }

        // A second card onto the full cell bounces with `PileFull` (#93).
        expect(
          Reducer.reduce(
            ~game=board,
            afterPark,
            Move({card: {suit: Hearts, rank: King}, to: ToPile(cell)}),
          ),
        )->toEqual(Error(Reducer.PileFull))

        // Only an Ace founds a foundation: a non-Ace is `Rejected` (#95/#76).
        expect(
          Reducer.reduce(
            ~game=board,
            afterPark,
            Move({card: {suit: Hearts, rank: Two}, to: ToPile(foundation)}),
          ),
        )->toEqual(Error(Reducer.Rejected))

        // The Ace of Spades founds the foundation, then the Two of Spades builds
        // up by suit…
        let afterAce = switch Reducer.reduce(
          ~game=board,
          afterPark,
          Move({card: {suit: Spades, rank: Ace}, to: ToPile(foundation)}),
        ) {
        | Ok(s) => s
        | Error(_) =>
          expect(true)->toBe(false) // an Ace should found an empty foundation
          afterPark
        }
        let afterTwo = switch Reducer.reduce(
          ~game=board,
          afterAce,
          Move({card: {suit: Spades, rank: Two}, to: ToPile(foundation)}),
        ) {
        | Ok(s) =>
          expect(GameState.topOf(s, foundation))->toEqual(Some({suit: Spades, rank: Two}))
          s
        | Error(_) =>
          expect(true)->toBe(false) // the same-suit next rank should build the foundation up
          afterAce
        }
        // …but an off-suit card of the right rank is refused.
        expect(
          Reducer.reduce(
            ~game=board,
            afterTwo,
            Move({card: {suit: Hearts, rank: Three}, to: ToPile(foundation)}),
          ),
        )->toEqual(Error(Reducer.Rejected))

        // A loose drop is refused outright — FreeCell isn't `free`.
        expect(
          Reducer.reduce(
            ~game=board,
            afterPark,
            Move({card: {suit: Clubs, rank: Five}, to: ToTable}),
          ),
        )->toEqual(Error(Reducer.LooseNotAllowed))

        // The cascade rule builds *down* in alternating colour: derive a legal
        // follow-up (and an illegal same-colour one) from a cascade's own top
        // card, so the check holds for whatever the shuffle dealt.
        let cascade = Game.pileIndices(board, Game.Cascade)->Array.getUnsafe(0)
        switch GameState.topOf(state, cascade) {
        | Some(top) if Rules.rankValue(top.rank) > 1 =>
          // One rank lower, opposite colour — a legal descending step.
          let lowerRank = Cards.ranks->Array.getUnsafe(Rules.rankValue(top.rank) - 2)
          let oppositeSuit = Rules.color(top.suit) == Rules.Red ? Spades : Hearts
          expect(
            Reducer.canDrop(
              ~game=board,
              state,
              {suit: oppositeSuit, rank: lowerRank},
              ~onto=cascade,
            ),
          )->toBe(true)
          // The same colour, same rank — rejected (wrong colour).
          let sameColourSuit = Rules.color(top.suit) == Rules.Red ? Hearts : Spades
          expect(
            Reducer.canDrop(
              ~game=board,
              state,
              {suit: sameColourSuit, rank: lowerRank},
              ~onto=cascade,
            ),
          )->toBe(false)
        | _ => () // an Ace-topped (or empty) cascade has no lower step to test
        }
      },
    )
  })

  // Pile roles (#94): each pile declares its FreeCell role, and `Game` addresses
  // a group by role. Existing scenes are tagged (no behaviour change), and the
  // mixed-roles scene shows the three roles on one board.
  describe("roles", () => {
    test(
      "existing scenes tag their piles by role",
      () => {
        // The stacking demo is two cascades.
        expect(Game.stacking.piles->Array.map(p => p.role))->toEqual([Game.Cascade, Game.Cascade])
        // Foundations pairs a Foundation with a Cascade.
        expect(Game.foundations.piles->Array.map(p => p.role))->toEqual([
          Game.Foundation,
          Game.Cascade,
        ])
        // Four-fans is four free-arrangement cascades.
        expect(Game.fourFans.piles->Array.map(p => p.role))->toEqual([
          Game.Cascade,
          Game.Cascade,
          Game.Cascade,
          Game.Cascade,
        ])
        // Free-cells is four FreeCell cells.
        expect(Game.freeCells.piles->Array.map(p => p.role))->toEqual([
          Game.FreeCell,
          Game.FreeCell,
          Game.FreeCell,
          Game.FreeCell,
        ])
      },
    )

    test(
      "mixed-roles shows Cascade / FreeCell / Foundation on one board",
      () => {
        // A Foundation and two FreeCell cells across the top, a Cascade below.
        expect(Game.mixedRoles.piles->Array.map(p => p.role))->toEqual([
          Game.Foundation,
          Game.FreeCell,
          Game.FreeCell,
          Game.Cascade,
        ])
        expect(Game.mixedRoles.free)->toBe(true)
      },
    )

    test(
      "pileIndices returns the positions of every pile with a role, in board order",
      () => {
        expect(Game.pileIndices(Game.mixedRoles, Game.Foundation))->toEqual([0])
        expect(Game.pileIndices(Game.mixedRoles, Game.FreeCell))->toEqual([1, 2])
        expect(Game.pileIndices(Game.mixedRoles, Game.Cascade))->toEqual([3])
        // A role absent from a board yields no indices.
        expect(Game.pileIndices(Game.stacking, Game.Foundation))->toEqual([])
      },
    )

    test(
      "pilesOf returns the piles with a role, in board order",
      () => {
        let cells = Game.pilesOf(Game.mixedRoles, Game.FreeCell)
        expect(cells->Array.length)->toBe(2)
        // Every returned pile is a FreeCell, and they are the capacity-1 cells.
        expect(cells->Array.every(p => p.role == Game.FreeCell))->toBe(true)
        expect(cells->Array.map(p => p.capacity))->toEqual([Some(1), Some(1)])
        // A role absent from a board yields no piles.
        expect(Game.pilesOf(Game.stacking, Game.Foundation))->toEqual([])
      },
    )
  })
})

// The immutable game-state snapshot (#77): where each card rests, derived from a
// board definition and read back through pure queries — no view, no behaviour.
describe("GameState", () => {
  test("initial places each pile's dealt cards and the loose deal", () => {
    // four-fans opens with cards already dealt into every pile and nothing loose.
    let state = GameState.initial(Game.fourFans)
    expect(GameState.cardsInPile(state, 0))->toEqual([
      {suit: Clubs, rank: Two},
      {suit: Diamonds, rank: Five},
    ])
    expect(state.loose)->toEqual([])
    // the stacking demo opens with empty piles and the whole run dealt loose.
    let stacking = GameState.initial(Game.stacking)
    expect(GameState.cardsInPile(stacking, 0))->toEqual([])
    expect(GameState.cardsInPile(stacking, 1))->toEqual([])
    expect(Array.length(stacking.loose))->toBe(13)
  })

  test("cardsInPile preserves the dealt order, bottom-first", () => {
    let state = GameState.initial(Game.fourFans)
    expect(GameState.cardsInPile(state, 2))->toEqual([
      {suit: Clubs, rank: Queen},
      {suit: Hearts, rank: Three},
    ])
  })

  test("cardsInPile returns a copy, so mutating it can't corrupt the snapshot", () => {
    let state = GameState.initial(Game.fourFans)
    let cards = GameState.cardsInPile(state, 0)
    cards->Array.push({suit: Spades, rank: King})
    // the snapshot is unchanged by the caller's mutation.
    expect(Array.length(GameState.cardsInPile(state, 0)))->toBe(2)
  })

  test("topOf is the last card of a pile, None when empty or out of range", () => {
    let state = GameState.initial(Game.fourFans)
    expect(GameState.topOf(state, 0))->toEqual(Some({suit: Diamonds, rank: Five}))
    let stacking = GameState.initial(Game.stacking)
    expect(GameState.topOf(stacking, 0))->toEqual(None) // an empty pile has no top
    expect(GameState.topOf(state, 99))->toEqual(None) // out-of-range index
  })

  test("locationOf round-trips a card to its pile and slot", () => {
    let state = GameState.initial(Game.fourFans)
    // pile 1 opens holding Hearts Nine (bottom) then Spades Jack (top).
    expect(GameState.locationOf(state, {suit: Hearts, rank: Nine}))->toEqual(
      Some(GameState.InPile(1, 0)),
    )
    expect(GameState.locationOf(state, {suit: Spades, rank: Jack}))->toEqual(
      Some(GameState.InPile(1, 1)),
    )
  })

  test("locationOf reports a loose card as Loose and an absent card as None", () => {
    let stacking = GameState.initial(Game.stacking)
    expect(GameState.locationOf(stacking, {suit: Spades, rank: Ace}))->toEqual(
      Some(GameState.Loose),
    )
    // Diamonds King is dealt nowhere in the stacking demo.
    expect(GameState.locationOf(stacking, {suit: Diamonds, rank: King}))->toEqual(None)
  })

  test("every dealt card round-trips: locationOf then back through cardsInPile", () => {
    let state = GameState.initial(Game.fourFans)
    state.piles->Array.forEachWithIndex(
      (cards, i) =>
        cards->Array.forEachWithIndex(
          (card, slot) => {
            expect(GameState.locationOf(state, card))->toEqual(Some(GameState.InPile(i, slot)))
            expect(GameState.cardsInPile(state, i)->Array.getUnsafe(slot))->toEqual(card)
          },
        ),
    )
  })
})

// The stackability rules (#76): pure predicates over `rule` data, tested without
// any view.
describe("Rules", () => {
  test("suits map to their two colours", () => {
    expect(Rules.color(Hearts))->toBe(Rules.Red)
    expect(Rules.color(Diamonds))->toBe(Rules.Red)
    expect(Rules.color(Spades))->toBe(Rules.Black)
    expect(Rules.color(Clubs))->toBe(Rules.Black)
  })

  // The #75 rule, now expressed as data (`Rules.tableau`) and weighed by the one
  // shared `accepts` predicate.
  describe("tableau (alternating colour, ascending)", () => {
    let accepts = (c, onto) => Rules.accepts(Rules.tableau, c, onto)

    test(
      "any card founds an empty pile",
      () => {
        expect(accepts({suit: Spades, rank: King}, None))->toBe(true)
        expect(accepts({suit: Hearts, rank: Ace}, None))->toBe(true)
      },
    )

    test(
      "the opposite colour, one rank higher, stacks",
      () => {
        // black Ace ← red Two, red Two ← black Three.
        expect(accepts({suit: Hearts, rank: Two}, Some({suit: Spades, rank: Ace})))->toBe(true)
        expect(accepts({suit: Clubs, rank: Three}, Some({suit: Hearts, rank: Two})))->toBe(true)
      },
    )

    test(
      "same colour is rejected even when the rank ascends",
      () => {
        expect(accepts({suit: Clubs, rank: Two}, Some({suit: Spades, rank: Ace})))->toBe(false)
      },
    )

    test(
      "a non-consecutive rank is rejected even when the colour alternates",
      () => {
        expect(accepts({suit: Hearts, rank: Three}, Some({suit: Spades, rank: Ace})))->toBe(false)
      },
    )

    test(
      "a descending or equal rank is rejected",
      () => {
        expect(accepts({suit: Hearts, rank: Ace}, Some({suit: Spades, rank: Two})))->toBe(false)
        expect(accepts({suit: Hearts, rank: Two}, Some({suit: Spades, rank: Two})))->toBe(false)
      },
    )
  })

  // A foundation (`Rules.foundation`): build up by suit from the Ace.
  describe("foundation (same suit, ascending from Ace)", () => {
    let accepts = (c, onto) => Rules.accepts(Rules.foundation, c, onto)

    test(
      "only an Ace founds an empty pile",
      () => {
        expect(accepts({suit: Hearts, rank: Ace}, None))->toBe(true)
        expect(accepts({suit: Spades, rank: Ace}, None))->toBe(true)
        // No higher card may open the pile.
        expect(accepts({suit: Hearts, rank: Two}, None))->toBe(false)
        expect(accepts({suit: Hearts, rank: King}, None))->toBe(false)
      },
    )

    test(
      "the same suit, one rank higher, stacks",
      () => {
        expect(accepts({suit: Hearts, rank: Two}, Some({suit: Hearts, rank: Ace})))->toBe(true)
        // The King completes the run: Queen ← King, same suit.
        expect(accepts({suit: Hearts, rank: King}, Some({suit: Hearts, rank: Queen})))->toBe(true)
      },
    )

    test(
      "a different suit is rejected even when the rank ascends",
      () => {
        // Same colour, different suit (both red) is still rejected.
        expect(accepts({suit: Diamonds, rank: Two}, Some({suit: Hearts, rank: Ace})))->toBe(false)
        expect(accepts({suit: Spades, rank: Two}, Some({suit: Hearts, rank: Ace})))->toBe(false)
      },
    )

    test(
      "a non-consecutive or descending rank is rejected within the suit",
      () => {
        expect(accepts({suit: Hearts, rank: Three}, Some({suit: Hearts, rank: Ace})))->toBe(false)
        expect(accepts({suit: Hearts, rank: Ace}, Some({suit: Hearts, rank: Two})))->toBe(false)
      },
    )
  })

  // A FreeCell cascade (`Rules.cascade`): build *down* in alternating colour.
  // The first exercise of the `Down` direction (#95).
  describe("cascade (alternating colour, descending)", () => {
    let accepts = (c, onto) => Rules.accepts(Rules.cascade, c, onto)

    test(
      "any card founds an empty pile",
      () => {
        expect(accepts({suit: Spades, rank: King}, None))->toBe(true)
        expect(accepts({suit: Hearts, rank: Ace}, None))->toBe(true)
      },
    )

    test(
      "the opposite colour, one rank lower, stacks",
      () => {
        // red Seven ← black Six, black Six ← red Five.
        expect(accepts({suit: Spades, rank: Six}, Some({suit: Hearts, rank: Seven})))->toBe(true)
        expect(accepts({suit: Hearts, rank: Five}, Some({suit: Spades, rank: Six})))->toBe(true)
      },
    )

    test(
      "same colour is rejected even when the rank descends",
      () => {
        expect(accepts({suit: Clubs, rank: Six}, Some({suit: Spades, rank: Seven})))->toBe(false)
      },
    )

    test(
      "a non-consecutive rank is rejected even when the colour alternates",
      () => {
        expect(accepts({suit: Hearts, rank: Five}, Some({suit: Spades, rank: Seven})))->toBe(false)
      },
    )

    test(
      "an ascending or equal rank is rejected",
      () => {
        expect(accepts({suit: Hearts, rank: Eight}, Some({suit: Spades, rank: Seven})))->toBe(false)
        expect(accepts({suit: Hearts, rank: Seven}, Some({suit: Spades, rank: Seven})))->toBe(false)
      },
    )
  })

  test("Free accepts anything", () => {
    expect(
      Rules.accepts(Rules.Free, {suit: Spades, rank: Two}, Some({suit: Spades, rank: King})),
    )->toBe(true)
    expect(Rules.accepts(Rules.Free, {suit: Spades, rank: Two}, None))->toBe(true)
  })

  // A legal ordered run (#123): the maximal tail a supermove may lift, decided
  // pairwise by `accepts`. Exercised against the cascade rule (build down in
  // alternating colour), the rule a FreeCell run is built on.
  describe("isRun (cascade)", () => {
    let isRun = cards => Rules.isRun(Rules.cascade, cards)

    test(
      "a descending-alternating run is a run",
      () => {
        // 8♥ 7♠ 6♥ 5♠ — red/black/red/black, each one rank lower.
        expect(
          isRun([
            {suit: Hearts, rank: Eight},
            {suit: Spades, rank: Seven},
            {suit: Hearts, rank: Six},
            {suit: Spades, rank: Five},
          ]),
        )->toBe(true)
      },
    )

    test(
      "an empty run and a single card are trivially runs",
      () => {
        expect(isRun([]))->toBe(true)
        expect(isRun([{suit: Hearts, rank: Eight}]))->toBe(true)
      },
    )

    test(
      "a same-colour neighbour breaks the run",
      () => {
        // 8♥ 7♥ — right rank step, but both red.
        expect(isRun([{suit: Hearts, rank: Eight}, {suit: Hearts, rank: Seven}]))->toBe(false)
      },
    )

    test(
      "a rank gap breaks the run",
      () => {
        // 8♥ 6♠ — opposite colour, but skips the Seven.
        expect(isRun([{suit: Hearts, rank: Eight}, {suit: Spades, rank: Six}]))->toBe(false)
      },
    )

    test(
      "an ascending order is not a (descending) run",
      () => {
        expect(isRun([{suit: Spades, rank: Five}, {suit: Hearts, rank: Six}]))->toBe(false)
      },
    )
  })

  describe("isCompleteRun", () => {
    // A full Ace→King run in one suit, built low-to-high.
    let fullRun =
      [Ace, Two, Three, Four, Five, Six, Seven, Eight, Nine, Ten, Jack, Queen, King]->Array.map(
        rank => {suit: Hearts, rank},
      )

    test(
      "a full Ace→King run is complete",
      () => {
        expect(Rules.isCompleteRun(fullRun))->toBe(true)
      },
    )

    test(
      "an empty pile is not complete",
      () => {
        expect(Rules.isCompleteRun([]))->toBe(false)
      },
    )

    test(
      "a pile short of the King is not complete",
      () => {
        // Ace→Queen: twelve cards, not yet done.
        let almost = fullRun->Array.slice(~start=0, ~end=12)
        expect(Rules.isCompleteRun(almost))->toBe(false)
      },
    )
  })
})

// The action variant + pure reducer (#82): transitions `GameState` and enforces
// the rules, tested without any view. The central roadmap principle —
// immutable state + action + pure reducer, illegal actions rejected — as tests.
describe("Reducer", () => {
  // A tiny hand-built board so the tests own their setup: a foundation (Ace-only,
  // same-suit ascending) then a tableau (alternating colour, ascending), free
  // drops allowed. Piles open empty; the cards under test are dealt loose.
  let game: Game.t = {
    id: "test",
    name: "Test",
    piles: [
      {role: Foundation, stacking: Squared, rule: Rules.foundation, capacity: None, cards: []},
      {role: Cascade, stacking: Fanned, rule: Rules.tableau, capacity: None, cards: []},
    ],
    free: true,
    // Everything the moves below reach for is dealt loose, so a rejection is the
    // *rule* refusing a present card — never a missing one.
    loose: [
      {suit: Hearts, rank: Ace},
      {suit: Hearts, rank: Two},
      {suit: Hearts, rank: Three},
      {suit: Diamonds, rank: Two},
      {suit: Spades, rank: Ace},
      {suit: Spades, rank: Ten},
      {suit: Hearts, rank: Nine},
    ],
    caption: None,
  }

  // The reducer must never mutate its input; assert the source snapshot is
  // unchanged after every transition below by re-deriving it fresh per test.
  let fresh = () => GameState.initial(game)

  test("a legal pile move succeeds and lands the card on top", () => {
    let state = fresh()
    // Hearts Ace founds the foundation (empty pile, AceOnly).
    switch Reducer.reduce(~game, state, Move({card: {suit: Hearts, rank: Ace}, to: ToPile(0)})) {
    | Ok(next) =>
      expect(GameState.topOf(next, 0))->toEqual(Some({suit: Hearts, rank: Ace}))
      expect(GameState.locationOf(next, {suit: Hearts, rank: Ace}))->toEqual(
        Some(GameState.InPile(0, 0)),
      )
      // the card is lifted off the loose table…
      expect(next.loose->Array.some(c => GameState.sameCard(c, {suit: Hearts, rank: Ace})))->toBe(
        false,
      )
      // …and the input snapshot is untouched: a fresh value was returned, with
      // the card still resting loose where it began and the pile still empty.
      expect(GameState.topOf(state, 0))->toEqual(None)
      expect(GameState.locationOf(state, {suit: Hearts, rank: Ace}))->toEqual(Some(GameState.Loose))
    | Error(_) => expect(true)->toBe(false) // should have succeeded
    }
  })

  test("an off-suit card is rejected by the foundation (colour/suit)", () => {
    // Build the foundation up to Hearts Two, then try a Diamonds Three: right
    // rank, wrong suit — rejected.
    let state = fresh()
    let afterAce = switch Reducer.reduce(
      ~game,
      state,
      Move({card: {suit: Hearts, rank: Ace}, to: ToPile(0)}),
    ) {
    | Ok(s) => s
    | Error(_) => state
    }
    expect(
      Reducer.reduce(~game, afterAce, Move({card: {suit: Diamonds, rank: Two}, to: ToPile(0)})),
    )->toEqual(Error(Reducer.Rejected))
  })

  test("a non-consecutive rank is rejected (wrong step)", () => {
    // Foundation topped by Hearts Ace; a Hearts Three skips Two — rejected.
    let state = fresh()
    let afterAce = switch Reducer.reduce(
      ~game,
      state,
      Move({card: {suit: Hearts, rank: Ace}, to: ToPile(0)}),
    ) {
    | Ok(s) => s
    | Error(_) => state
    }
    expect(
      Reducer.reduce(~game, afterAce, Move({card: {suit: Hearts, rank: Three}, to: ToPile(0)})),
    )->toEqual(Error(Reducer.Rejected))
  })

  test("only an Ace may open the foundation (empty-pile rule)", () => {
    // Hearts Two onto the empty foundation is rejected; the tableau (AnyCard)
    // would take it, proving the empty-pile rule is per-pile.
    let state = fresh()
    expect(
      Reducer.reduce(~game, state, Move({card: {suit: Hearts, rank: Two}, to: ToPile(0)})),
    )->toEqual(Error(Reducer.Rejected))
  })

  test("descending onto an ascending pile is rejected (wrong direction)", () => {
    // Tableau founded with Spades Ten; a red Nine is the opposite colour but one
    // rank *lower* — the tableau only climbs, so the descending step is rejected.
    let state = fresh()
    let afterTen = switch Reducer.reduce(
      ~game,
      state,
      Move({card: {suit: Spades, rank: Ten}, to: ToPile(1)}),
    ) {
    | Ok(s) => s
    | Error(_) => state
    }
    expect(
      Reducer.reduce(~game, afterTen, Move({card: {suit: Hearts, rank: Nine}, to: ToPile(1)})),
    )->toEqual(Error(Reducer.Rejected))
  })

  test("a loose drop is rejected when the game isn't free", () => {
    // four-fans confines cards to piles (`free: false`): dropping a card loose is
    // rejected outright, whatever the card.
    let state = GameState.initial(Game.fourFans)
    expect(
      Reducer.reduce(
        ~game=Game.fourFans,
        state,
        Move({card: {suit: Clubs, rank: Two}, to: ToTable}),
      ),
    )->toEqual(Error(Reducer.LooseNotAllowed))
  })

  test("a loose drop succeeds when the game is free", () => {
    // Move a card from a pile out onto the table (`free: true`).
    let state = fresh()
    let onPile = switch Reducer.reduce(
      ~game,
      state,
      Move({card: {suit: Spades, rank: Ace}, to: ToPile(1)}),
    ) {
    | Ok(s) => s
    | Error(_) => state
    }
    switch Reducer.reduce(~game, onPile, Move({card: {suit: Spades, rank: Ace}, to: ToTable})) {
    | Ok(next) =>
      expect(GameState.locationOf(next, {suit: Spades, rank: Ace}))->toEqual(Some(GameState.Loose))
      expect(GameState.topOf(next, 1))->toEqual(None) // lifted back off the pile
    | Error(_) => expect(true)->toBe(false)
    }
  })

  test("moving a card to where it already rests is an identity Ok", () => {
    // Found the foundation with Hearts Ace, then re-drop it onto pile 0: a no-op
    // that returns Ok with the same resting places (mirrors the view's re-drop).
    let state = fresh()
    switch Reducer.reduce(~game, state, Move({card: {suit: Hearts, rank: Ace}, to: ToPile(0)})) {
    | Ok(afterAce) =>
      switch Reducer.reduce(
        ~game,
        afterAce,
        Move({card: {suit: Hearts, rank: Ace}, to: ToPile(0)}),
      ) {
      | Ok(same) =>
        expect(GameState.topOf(same, 0))->toEqual(Some({suit: Hearts, rank: Ace}))
        expect(Array.length(GameState.cardsInPile(same, 0)))->toBe(1) // not duplicated
      | Error(_) => expect(true)->toBe(false)
      }
    | Error(_) => expect(true)->toBe(false)
    }
  })

  test("a completed foundation reports via Rules.isCompleteRun", () => {
    // Deal a whole Hearts Ace→King run loose and stack it onto the foundation
    // via the reducer; the finished pile is a complete run.
    let runGame: Game.t = {
      ...game,
      loose: [
        Ace,
        Two,
        Three,
        Four,
        Five,
        Six,
        Seven,
        Eight,
        Nine,
        Ten,
        Jack,
        Queen,
        King,
      ]->Array.map(rank => {suit: Hearts, rank}),
    }
    let state = ref(GameState.initial(runGame))
    runGame.loose->Array.forEach(
      card =>
        switch Reducer.reduce(~game=runGame, state.contents, Move({card, to: ToPile(0)})) {
        | Ok(next) => state := next
        | Error(_) => ()
        },
    )
    expect(GameState.cardsInPile(state.contents, 0)->Array.length)->toBe(13)
    expect(Rules.isCompleteRun(GameState.cardsInPile(state.contents, 0)))->toBe(true)
  })

  test("moving a card that isn't in the state fails with CardNotFound", () => {
    let state = fresh()
    expect(
      Reducer.reduce(~game, state, Move({card: {suit: Diamonds, rank: King}, to: ToPile(0)})),
    )->toEqual(Error(Reducer.CardNotFound))
  })

  test("moving onto an out-of-range pile fails with NoSuchPile", () => {
    let state = fresh()
    expect(
      Reducer.reduce(~game, state, Move({card: {suit: Hearts, rank: Ace}, to: ToPile(99)})),
    )->toEqual(Error(Reducer.NoSuchPile))
  })

  // Pile capacity → free cells (#93): a capped `Free` pile holds exactly one
  // card. A tiny board of one capacity-1 cell (pile 0) beside an uncapped `Free`
  // pile (pile 1), with two cards dealt loose to move around.
  describe("capacity", () => {
    let capGame: Game.t = {
      id: "cap",
      name: "Cap",
      piles: [
        {role: FreeCell, stacking: Squared, rule: Rules.Free, capacity: Some(1), cards: []},
        {role: Cascade, stacking: Squared, rule: Rules.Free, capacity: None, cards: []},
      ],
      free: true,
      loose: [{suit: Spades, rank: Ace}, {suit: Hearts, rank: King}],
      caption: None,
    }
    let fresh = () => GameState.initial(capGame)

    test(
      "a capacity-1 cell accepts its first card",
      () => {
        let state = fresh()
        switch Reducer.reduce(
          ~game=capGame,
          state,
          Move({card: {suit: Spades, rank: Ace}, to: ToPile(0)}),
        ) {
        | Ok(next) =>
          expect(GameState.topOf(next, 0))->toEqual(Some({suit: Spades, rank: Ace}))
          expect(Array.length(GameState.cardsInPile(next, 0)))->toBe(1)
        | Error(_) => expect(true)->toBe(false)
        }
      },
    )

    test(
      "a second card onto a full cell is rejected with PileFull",
      () => {
        // Park the Ace in the cell, then try to drop the King on top: no room.
        let state = fresh()
        let filled = switch Reducer.reduce(
          ~game=capGame,
          state,
          Move({card: {suit: Spades, rank: Ace}, to: ToPile(0)}),
        ) {
        | Ok(s) => s
        | Error(_) => state
        }
        expect(
          Reducer.reduce(
            ~game=capGame,
            filled,
            Move({card: {suit: Hearts, rank: King}, to: ToPile(0)}),
          ),
        )->toEqual(Error(Reducer.PileFull))
        // The failed drop changed nothing: the King is still loose, the cell still
        // holds only the Ace.
        expect(GameState.locationOf(filled, {suit: Hearts, rank: King}))->toEqual(
          Some(GameState.Loose),
        )
        expect(Array.length(GameState.cardsInPile(filled, 0)))->toBe(1)
      },
    )

    test(
      "re-dropping the occupant onto its own full cell stays Ok (identity)",
      () => {
        // A card already topping a capacity-1 cell isn't a new arrival, so the
        // identity re-drop must succeed rather than report PileFull.
        let state = fresh()
        let filled = switch Reducer.reduce(
          ~game=capGame,
          state,
          Move({card: {suit: Spades, rank: Ace}, to: ToPile(0)}),
        ) {
        | Ok(s) => s
        | Error(_) => state
        }
        switch Reducer.reduce(
          ~game=capGame,
          filled,
          Move({card: {suit: Spades, rank: Ace}, to: ToPile(0)}),
        ) {
        | Ok(same) =>
          expect(GameState.topOf(same, 0))->toEqual(Some({suit: Spades, rank: Ace}))
          expect(Array.length(GameState.cardsInPile(same, 0)))->toBe(1) // not duplicated
        | Error(_) => expect(true)->toBe(false)
        }
      },
    )

    test(
      "an unbounded pile (capacity None) keeps accepting past one card",
      () => {
        // Pile 1 is uncapped, so both loose cards stack onto it — no PileFull.
        let state = fresh()
        let afterAce = switch Reducer.reduce(
          ~game=capGame,
          state,
          Move({card: {suit: Spades, rank: Ace}, to: ToPile(1)}),
        ) {
        | Ok(s) => s
        | Error(_) => state
        }
        switch Reducer.reduce(
          ~game=capGame,
          afterAce,
          Move({card: {suit: Hearts, rank: King}, to: ToPile(1)}),
        ) {
        | Ok(next) => expect(Array.length(GameState.cardsInPile(next, 1)))->toBe(2)
        | Error(_) => expect(true)->toBe(false)
        }
      },
    )
  })

  // Auto-move to foundation (#122): `foundationTarget` finds the foundation a card
  // may be sent *home* to — the query the web double-click and the CLI `home` verb
  // both dispatch through. Exercised against the outer `game` (a single foundation
  // at pile 0) and the real sixteen-pile FreeCell board (four foundations).
  describe("foundationTarget", () => {
    test(
      "finds the foundation an Ace may open",
      () => {
        let state = fresh()
        // The empty foundation (pile 0) opens on an Ace; the tableau (pile 1) is no
        // foundation, so it's never a target.
        expect(Reducer.foundationTarget(~game, state, {suit: Hearts, rank: Ace}))->toEqual(Some(0))
      },
    )

    test(
      "finds the foundation for the next rank up once the Ace is home",
      () => {
        let state = fresh()
        let afterAce = switch Reducer.reduce(
          ~game,
          state,
          Move({card: {suit: Hearts, rank: Ace}, to: ToPile(0)}),
        ) {
        | Ok(s) => s
        | Error(_) => state
        }
        // Same suit, one rank up, goes home…
        expect(Reducer.foundationTarget(~game, afterAce, {suit: Hearts, rank: Two}))->toEqual(
          Some(0),
        )
        // …but a card that would skip a rank has nowhere to go.
        expect(Reducer.foundationTarget(~game, afterAce, {suit: Hearts, rank: Three}))->toEqual(
          None,
        )
      },
    )

    test(
      "returns None when no foundation will take the card",
      () => {
        let state = fresh()
        // A non-Ace can't open the empty foundation, whatever its suit — nowhere home.
        expect(Reducer.foundationTarget(~game, state, {suit: Hearts, rank: Two}))->toEqual(None)
        expect(Reducer.foundationTarget(~game, state, {suit: Spades, rank: King}))->toEqual(None)
      },
    )

    test(
      "returns None on a board with no foundations",
      () => {
        // The stacking demo is all cascades — no Foundation pile to send a card to.
        let state = GameState.initial(Game.stacking)
        expect(
          Reducer.foundationTarget(~game=Game.stacking, state, {suit: Spades, rank: Ace}),
        )->toEqual(None)
      },
    )

    test(
      "among several foundations, picks the one matching by suit",
      () => {
        // The real FreeCell board has four foundations (indices 4–7): an Ace homes to
        // the first empty one, its follow-up targets that same pile, and another
        // suit's Ace opens a *different* foundation.
        let board = Game.freecell
        let state = GameState.initial(board)
        let first = Game.pileIndices(board, Game.Foundation)->Array.getUnsafe(0)
        expect(Reducer.foundationTarget(~game=board, state, {suit: Spades, rank: Ace}))->toEqual(
          Some(first),
        )
        let afterAce = switch Reducer.reduce(
          ~game=board,
          state,
          Move({card: {suit: Spades, rank: Ace}, to: ToPile(first)}),
        ) {
        | Ok(s) => s
        | Error(_) => state
        }
        // The Two of Spades follows its Ace home to the very same foundation…
        expect(Reducer.foundationTarget(~game=board, afterAce, {suit: Spades, rank: Two}))->toEqual(
          Some(first),
        )
        // …while another suit's Ace opens a different, still-empty foundation.
        switch Reducer.foundationTarget(~game=board, afterAce, {suit: Hearts, rank: Ace}) {
        | Some(i) => expect(i != first)->toBe(true)
        | None => expect(true)->toBe(false)
        }
      },
    )
  })

  // Safe auto-collect (#125): `isSafeToCollect` (accepted *and* safe) and the
  // `autoCollect` fixpoint that sends every safe card home. Exercised on a little
  // four-foundation board — one foundation per suit, plus a Free cascade and a free
  // cell to hold candidate cards — so the opposite-colour safe rule is testable by
  // hand-setting the foundations.
  describe("autoCollect", () => {
    let acGame: Game.t = {
      id: "ac",
      name: "AC",
      piles: [
        {role: Foundation, stacking: Squared, rule: Rules.foundation, capacity: None, cards: []},
        {role: Foundation, stacking: Squared, rule: Rules.foundation, capacity: None, cards: []},
        {role: Foundation, stacking: Squared, rule: Rules.foundation, capacity: None, cards: []},
        {role: Foundation, stacking: Squared, rule: Rules.foundation, capacity: None, cards: []},
        {role: Cascade, stacking: Fanned, rule: Rules.Free, capacity: None, cards: []},
        {role: Cascade, stacking: Fanned, rule: Rules.Free, capacity: None, cards: []},
      ],
      free: false,
      loose: [],
      caption: None,
    }
    // A hand-built snapshot from the six piles' contents (foundations 0–3, then two
    // Free cascades 4–5), so a test can pose any foundation heights it likes.
    let stateOf = (piles): GameState.t => {GameState.piles, loose: []}

    describe(
      "isSafeToCollect",
      () => {
        test(
          "an Ace is always safe (and homes to an empty foundation)",
          () => {
            let state = stateOf([[], [], [], [], [{suit: Spades, rank: Ace}], []])
            expect(Reducer.isSafeToCollect(~game=acGame, state, {suit: Spades, rank: Ace}))->toBe(
              true,
            )
          },
        )

        test(
          "a Two is always safe, even with the opposite-colour foundations empty",
          () => {
            // Spades foundation at the Ace so the Two is accepted; hearts/diamonds
            // (the opposite colour) untouched — a Two is safe regardless.
            let state = stateOf([
              [{suit: Spades, rank: Ace}],
              [],
              [],
              [],
              [{suit: Spades, rank: Two}],
              [],
            ])
            expect(Reducer.isSafeToCollect(~game=acGame, state, {suit: Spades, rank: Two}))->toBe(
              true,
            )
          },
        )

        test(
          "a higher card is safe only once both opposite-colour foundations reach rank − 1",
          () => {
            // 3♠ (black) is accepted onto a 2♠-topped foundation. It's safe only when
            // both red foundations (hearts, diamonds) are at least the Two.
            let safe = stateOf([
              [{suit: Spades, rank: Ace}, {suit: Spades, rank: Two}],
              [{suit: Hearts, rank: Ace}, {suit: Hearts, rank: Two}],
              [{suit: Diamonds, rank: Ace}, {suit: Diamonds, rank: Two}],
              [],
              [{suit: Spades, rank: Three}],
              [],
            ])
            expect(Reducer.isSafeToCollect(~game=acGame, safe, {suit: Spades, rank: Three}))->toBe(
              true,
            )
            // Drop diamonds back to just the Ace: now a cascade could still want the
            // 3♠, so it's *not* safe — even though a foundation would still accept it.
            let unsafe = stateOf([
              [{suit: Spades, rank: Ace}, {suit: Spades, rank: Two}],
              [{suit: Hearts, rank: Ace}, {suit: Hearts, rank: Two}],
              [{suit: Diamonds, rank: Ace}],
              [],
              [{suit: Spades, rank: Three}],
              [],
            ])
            expect(
              Reducer.isSafeToCollect(~game=acGame, unsafe, {suit: Spades, rank: Three}),
            )->toBe(false)
            // …but the foundation *would* accept it — safe is strictly stronger.
            expect(
              Reducer.foundationTarget(~game=acGame, unsafe, {suit: Spades, rank: Three}),
            )->toEqual(Some(0))
          },
        )

        test(
          "a card no foundation will take is never safe",
          () => {
            // No spades foundation started, so a 3♠ can't be homed at all.
            let state = stateOf([[], [], [], [], [{suit: Spades, rank: Three}], []])
            expect(Reducer.isSafeToCollect(~game=acGame, state, {suit: Spades, rank: Three}))->toBe(
              false,
            )
          },
        )
      },
    )

    test(
      "the fixpoint collects a whole chain, exposing and enabling cards in turn",
      () => {
        // Two Free cascades each hold a suit's Ace atop its Two (bottom-first
        // [Two, Ace]). Collecting the Ace exposes the Two and makes it safe, so a
        // single pass sweeps all four cards home to their foundations.
        let state = stateOf([
          [],
          [],
          [],
          [],
          [{suit: Spades, rank: Two}, {suit: Spades, rank: Ace}],
          [{suit: Hearts, rank: Two}, {suit: Hearts, rank: Ace}],
        ])
        let (settled, moved) = Reducer.autoCollect(~game=acGame, state)
        // All four cards moved home; the cascades are emptied.
        expect(Array.length(moved))->toBe(4)
        expect(GameState.cardsInPile(settled, 4))->toEqual([])
        expect(GameState.cardsInPile(settled, 5))->toEqual([])
        // Each suit's foundation is built to the Two.
        expect(GameState.topOf(settled, 0))->toEqual(Some({suit: Spades, rank: Two}))
        expect(GameState.topOf(settled, 1))->toEqual(Some({suit: Hearts, rank: Two}))
        // The Aces were collected before their Twos (a card can't precede its own
        // base). `findIndex` with structural identity, since `indexOf` on records is
        // reference equality.
        let orderOf = card => moved->Array.findIndex(c => GameState.sameCard(c, card))
        expect(orderOf({suit: Spades, rank: Ace}) < orderOf({suit: Spades, rank: Two}))->toBe(true)
      },
    )

    test(
      "unsafe cards are left where they rest",
      () => {
        // Foundations built high enough to *accept* a 3♠ but not to make it safe
        // (diamonds only at the Ace). Auto-collect changes nothing and moves nothing.
        let state = stateOf([
          [{suit: Spades, rank: Ace}, {suit: Spades, rank: Two}],
          [{suit: Hearts, rank: Ace}, {suit: Hearts, rank: Two}],
          [{suit: Diamonds, rank: Ace}],
          [],
          [{suit: Spades, rank: Three}],
          [],
        ])
        let (settled, moved) = Reducer.autoCollect(~game=acGame, state)
        expect(moved)->toEqual([])
        expect(GameState.topOf(settled, 4))->toEqual(Some({suit: Spades, rank: Three}))
      },
    )

    test(
      "a board with no foundations is left untouched",
      () => {
        // The stacking demo is all cascades — nothing is ever safe to collect.
        let state = GameState.initial(Game.stacking)
        let (settled, moved) = Reducer.autoCollect(~game=Game.stacking, state)
        expect(moved)->toEqual([])
        expect(settled)->toEqual(state)
      },
    )
  })

  // The supermove (#123): a multi-card `MoveRun` and its `(1 + free cells) × 2 ^
  // (empty columns)` limit. A little FreeCell-shaped board — two capacity-1 free
  // cells then four `Rules.cascade` columns, cards confined to piles — lets the
  // tests pose exact free-cell/empty-column combinations by hand.
  describe("supermove", () => {
    let smGame: Game.t = {
      id: "sm",
      name: "SM",
      piles: [
        {role: FreeCell, stacking: Squared, rule: Rules.Free, capacity: Some(1), cards: []},
        {role: FreeCell, stacking: Squared, rule: Rules.Free, capacity: Some(1), cards: []},
        {role: Cascade, stacking: Fanned, rule: Rules.cascade, capacity: None, cards: []},
        {role: Cascade, stacking: Fanned, rule: Rules.cascade, capacity: None, cards: []},
        {role: Cascade, stacking: Fanned, rule: Rules.cascade, capacity: None, cards: []},
        {role: Cascade, stacking: Fanned, rule: Rules.cascade, capacity: None, cards: []},
      ],
      free: false,
      loose: [],
      caption: None,
    }
    // A distinct single-card filler, so "occupied" piles hold real, unique cards.
    let f = i => [Cards.all->Array.getUnsafe(i)]
    // A hand-built snapshot from the six piles' contents (cells 0–1, cascades 2–5).
    let stateOf = (piles): GameState.t => {GameState.piles, loose: []}

    // A legal descending-alternating run, bottom-first — the tail a supermove lifts.
    let run4 = [
      {suit: Hearts, rank: Eight}, // red
      {suit: Spades, rank: Seven}, // black
      {suit: Hearts, rank: Six}, // red
      {suit: Spades, rank: Five}, // black
    ]

    describe(
      "maxSupermove",
      () => {
        test(
          "no empties: only the single card in hand moves — (1 + 0) × 2^0 = 1",
          () => {
            let state = stateOf([f(0), f(1), f(2), f(3), f(4), f(5)])
            expect(Reducer.maxSupermove(~game=smGame, state))->toBe(1)
          },
        )

        test(
          "one empty free cell doubles nothing but adds to the base — (1 + 1) × 2^0 = 2",
          () => {
            let state = stateOf([[], f(1), f(2), f(3), f(4), f(5)])
            expect(Reducer.maxSupermove(~game=smGame, state))->toBe(2)
          },
        )

        test(
          "two empty cells and one empty column — (1 + 2) × 2^1 = 6",
          () => {
            let state = stateOf([[], [], [], f(3), f(4), f(5)])
            expect(Reducer.maxSupermove(~game=smGame, state))->toBe(6)
          },
        )

        test(
          "two empty cells and two empty columns — (1 + 2) × 2^2 = 12",
          () => {
            let state = stateOf([[], [], [], [], f(4), f(5)])
            expect(Reducer.maxSupermove(~game=smGame, state))->toBe(12)
          },
        )

        test(
          "~ignoring drops the destination's own emptiness from the exponent",
          () => {
            // Two empty cells and one empty column → 6, but a run *onto* that empty
            // column can't also use it as a spare: (1 + 2) × 2^0 = 3.
            let state = stateOf([[], [], [], f(3), f(4), f(5)])
            expect(Reducer.maxSupermove(~game=smGame, state))->toBe(6)
            expect(Reducer.maxSupermove(~game=smGame, state, ~ignoring=2))->toBe(3)
          },
        )
      },
    )

    describe(
      "MoveRun",
      () => {
        test(
          "a legal run within the limit moves as one, keeping its order atop the pile",
          () => {
            // Cascade 2 holds the run; cascade 3 is topped by 9♠, which takes the
            // run's red 8♥ bottom; both cells and cascades 4–5 empty → capacity 12.
            let state = stateOf([[], [], run4, [{suit: Spades, rank: Nine}], [], []])
            switch Reducer.reduce(~game=smGame, state, MoveRun({cards: run4, to: ToPile(3)})) {
            | Ok(next) =>
              expect(GameState.cardsInPile(next, 3))->toEqual(
                Array.concat([{suit: Spades, rank: Nine}], run4),
              )
              expect(GameState.cardsInPile(next, 2))->toEqual([]) // lifted off the source
            | Error(_) => expect(true)->toBe(false)
            }
          },
        )

        test(
          "cards that aren't an ordered run are rejected with NotARun",
          () => {
            // 8♥ then 7♥ — right rank step, same colour, so not a run.
            let notRun = [{suit: Hearts, rank: Eight}, {suit: Hearts, rank: Seven}]
            let state = stateOf([[], [], notRun, [{suit: Spades, rank: Nine}], [], []])
            expect(
              Reducer.reduce(~game=smGame, state, MoveRun({cards: notRun, to: ToPile(3)})),
            )->toEqual(Error(Reducer.NotARun))
          },
        )

        test(
          "a run the destination won't take is rejected by the rule",
          () => {
            // The run is legal, but its red 8♥ bottom can't land on a red 9♥ top.
            let state = stateOf([[], [], run4, [{suit: Hearts, rank: Nine}], [], []])
            expect(
              Reducer.reduce(~game=smGame, state, MoveRun({cards: run4, to: ToPile(3)})),
            )->toEqual(Error(Reducer.Rejected))
          },
        )

        test(
          "a run longer than the limit is rejected with RunTooLong",
          () => {
            // Both cells filled and no empty column → capacity 1; a two-card run is
            // one over. The run is legal and the destination accepts it, so the limit
            // is the sole reason it bounces.
            let twoRun = [{suit: Hearts, rank: Eight}, {suit: Spades, rank: Seven}]
            let state = stateOf([f(0), f(1), twoRun, [{suit: Spades, rank: Nine}], f(2), f(3)])
            expect(Reducer.maxSupermove(~game=smGame, state))->toBe(1)
            expect(
              Reducer.reduce(~game=smGame, state, MoveRun({cards: twoRun, to: ToPile(3)})),
            )->toEqual(Error(Reducer.RunTooLong))
          },
        )

        test(
          "moving onto an empty column can't count that column toward its own limit",
          () => {
            // Cells filled, cascades 4–5 empty, cascade 3 topped by 9♠. A three-card
            // run moves onto the non-empty cascade 3 (capacity 4), but the *same* run
            // onto empty cascade 4 is RunTooLong — its own emptiness is excluded, so
            // only cascade 5 remains a spare: (1 + 0) × 2^1 = 2 < 3.
            let run3 = [
              {suit: Hearts, rank: Eight},
              {suit: Spades, rank: Seven},
              {suit: Hearts, rank: Six},
            ]
            let state = stateOf([f(0), f(1), run3, [{suit: Spades, rank: Nine}], [], []])
            switch Reducer.reduce(~game=smGame, state, MoveRun({cards: run3, to: ToPile(3)})) {
            | Ok(next) =>
              expect(GameState.cardsInPile(next, 3))->toEqual(
                Array.concat([{suit: Spades, rank: Nine}], run3),
              )
            | Error(_) => expect(true)->toBe(false)
            }
            expect(
              Reducer.reduce(~game=smGame, state, MoveRun({cards: run3, to: ToPile(4)})),
            )->toEqual(Error(Reducer.RunTooLong))
          },
        )

        test(
          "a multi-card run onto a free cell is refused — a cell holds one card (#133)",
          () => {
            // The run is legal and well within the supermove limit, but a free cell
            // (capacity 1) can't hold two cards. The drop bounces with PileFull — the
            // count-aware refusal (#93), not RunTooLong — for an empty cell and an
            // occupied one alike, and the shared `canMoveRun` query agrees so the
            // view's drop highlight refuses too (the #133 bug: it used to accept).
            let twoRun = [{suit: Hearts, rank: Eight}, {suit: Spades, rank: Seven}]
            // Cell 0 the empty target, cell 1 empty, cascade 2 holds the run, 3–5
            // empty → a generous limit, so capacity is the sole reason it's refused.
            let onEmpty = stateOf([[], [], twoRun, [], [], []])
            expect(Reducer.maxSupermove(~game=smGame, onEmpty, ~ignoring=0) >= 2)->toBe(true)
            expect(
              Reducer.reduce(~game=smGame, onEmpty, MoveRun({cards: twoRun, to: ToPile(0)})),
            )->toEqual(Error(Reducer.PileFull))
            expect(Reducer.canMoveRun(~game=smGame, onEmpty, twoRun, ~onto=0))->toBe(false)
            // An *occupied* cell is refused just the same.
            let onOccupied = stateOf([f(0), [], twoRun, [], [], []])
            expect(
              Reducer.reduce(~game=smGame, onOccupied, MoveRun({cards: twoRun, to: ToPile(0)})),
            )->toEqual(Error(Reducer.PileFull))
            expect(Reducer.canMoveRun(~game=smGame, onOccupied, twoRun, ~onto=0))->toBe(false)
          },
        )

        test(
          "a run whose cards aren't in play fails with CardNotFound",
          () => {
            let ghost = [{suit: Diamonds, rank: King}, {suit: Clubs, rank: Queen}]
            let empty = stateOf([[], [], [], [], [], []])
            expect(
              Reducer.reduce(~game=smGame, empty, MoveRun({cards: ghost, to: ToPile(2)})),
            )->toEqual(Error(Reducer.CardNotFound))
          },
        )

        test(
          "a run onto an out-of-range pile fails with NoSuchPile",
          () => {
            let state = stateOf([[], [], run4, [], [], []])
            expect(
              Reducer.reduce(~game=smGame, state, MoveRun({cards: run4, to: ToPile(99)})),
            )->toEqual(Error(Reducer.NoSuchPile))
          },
        )

        test(
          "a run has nowhere loose to go — MoveRun to the table is refused",
          () => {
            let state = stateOf([[], [], run4, [], [], []])
            expect(
              Reducer.reduce(~game=smGame, state, MoveRun({cards: run4, to: ToTable})),
            )->toEqual(Error(Reducer.LooseNotAllowed))
          },
        )
      },
    )
  })
})

// The deck as data (#96): the 52-card pack, a deterministic seeded shuffle, and
// the round-robin deal — the reproducible basis for numbered deals, all pure and
// tested without any view.
describe("Cards", () => {
  // Two cards are the same card when suit and rank match (deck-scoped identity,
  // the same notion `GameState` keys off).
  let same = (a: card, b: card) => a.suit == b.suit && a.rank == b.rank

  // Is `deck` a permutation of `Cards.all` — every card exactly once, none
  // dropped or duplicated? Same length as the full deck and every one of the 52
  // present is enough, since 52 distinct cards can't fit in 52 slots with a gap.
  let isFullDeck = (deck: array<card>) =>
    Array.length(deck) == 52 && Cards.all->Array.every(card => deck->Array.some(c => same(c, card)))

  test("all is the 52-card deck, every card distinct", () => {
    expect(Array.length(Cards.all))->toBe(52)
    // No card appears twice: each is found exactly once in the deck.
    let noDupes =
      Cards.all->Array.every(card => Cards.all->Array.filter(c => same(c, card))->Array.length == 1)
    expect(noDupes)->toBe(true)
  })

  test("shuffle is a permutation of the deck — nothing dropped or duplicated", () => {
    let shuffled = Cards.shuffle(~seed=42)
    expect(isFullDeck(shuffled))->toBe(true)
  })

  test("shuffle is deterministic: the same seed reproduces the same order", () => {
    expect(Cards.shuffle(~seed=7))->toEqual(Cards.shuffle(~seed=7))
    expect(Cards.shuffle(~seed=12345))->toEqual(Cards.shuffle(~seed=12345))
  })

  test("different seeds give different orders", () => {
    let a = Cards.shuffle(~seed=1)
    let b = Cards.shuffle(~seed=2)
    // Both are full decks…
    expect(isFullDeck(a))->toBe(true)
    expect(isFullDeck(b))->toBe(true)
    // …but not in the same order: at least one position differs.
    let differs =
      a->Array.mapWithIndex((card, i) => !same(card, b->Array.getUnsafe(i)))->Array.some(x => x)
    expect(differs)->toBe(true)
  })

  test("shuffle doesn't disturb the deck order it draws from", () => {
    let before = Cards.all->Array.map(c => c)
    Cards.shuffle(~seed=99)->ignore
    // `Cards.all` is untouched by a shuffle (it works over a copy).
    expect(Cards.all)->toEqual(before)
  })

  describe("deal", () => {
    test(
      "deals round-robin, dropping card i into pile i mod n",
      () => {
        // A tiny hand-made deck so the round-robin is legible: seven cards across
        // three piles → [0,3,6], [1,4], [2,5].
        let seven =
          [Ace, Two, Three, Four, Five, Six, Seven]->Array.map(rank => {suit: Spades, rank})
        let columns = Cards.deal(~piles=3, seven)
        expect(columns->Array.map(col => col->Array.map(c => c.rank)))->toEqual([
          [Ace, Four, Seven],
          [Two, Five],
          [Three, Six],
        ])
      },
    )

    test(
      "dealing the whole deck loses no cards and spreads them evenly",
      () => {
        let columns = Cards.deal(~piles=8, Cards.shuffle(~seed=1))
        expect(columns->Array.length)->toBe(8)
        // 52 across 8 piles: the first four hold seven, the rest six.
        expect(columns->Array.map(Array.length))->toEqual([7, 7, 7, 7, 6, 6, 6, 6])
        // Pooling the piles back together is still a full deck.
        let pooled = columns->Array.flatMap(col => col)
        expect(isFullDeck(pooled))->toBe(true)
      },
    )

    test(
      "no piles yields no columns",
      () => {
        expect(Cards.deal(~piles=0, Cards.all))->toEqual([])
      },
    )
  })
})

// Driver options (#125): the preference record threaded into the post-move step.
// Today it carries a single flag; a settings toggle (#112) will flip it later.
describe("Options", () => {
  test("defaults auto-collect on", () => {
    expect(Options.default.autoCollect)->toBe(true)
  })
})
