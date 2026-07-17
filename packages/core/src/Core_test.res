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
// the rules, tested without any view. The load-bearing roadmap principle —
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
})
