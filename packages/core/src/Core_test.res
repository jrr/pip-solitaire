open Vitest
open Card

test("greeting returns the expected message", () => {
  expect(Core.greeting())->toBe("Hello from ReScript core!")
})

// The modelled games: assert the rules the presentation layer reads back.
describe("Game", () => {
  test("every game is listed with a stable id and a non-empty name", () => {
    // FreeCell, its two short-deck siblings and the two Spider boards — the list the
    // scene picker and the CLI's `games`/`deal <id>` enumerate, in picker order.
    expect(Game.all->Array.map(g => g.id))->toEqual([
      "freecell",
      "mini",
      "micro",
      "simplesimon",
      "spiderette",
    ])
    expect(Game.all->Array.every(g => g.name != ""))->toBe(true)
  })

  // The ids are also the localStorage keys `SavedGame` saves under and the `?scene=`
  // values a deal link names, so two boards sharing one would silently share a save.
  test("game ids are unique", () => {
    let ids = Game.all->Array.map(g => g.id)
    expect(
      ids->Array.filter(id => ids->Array.filter(other => other == id)->Array.length > 1),
    )->toEqual([])
  })

  // The assembled FreeCell board: pile capacity, pile roles, the cascade rule and
  // the seeded deck converge into one 16-pile `Game.t`, dealt from a seed and
  // playable through the existing reducer.
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
        // `pileIndices` addresses each group by role.
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
      },
    )

    test(
      "the deal is reproducible: the same seed lays out the same cascades",
      () => {
        // The default board is deal #1, and rebuilding that seed reproduces it
        // exactly (the basis for shareable deal numbers).
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
      "a dealt board carries the seed that reproduces it",
      () => {
        // The board says where it came from, which is what lets the app report a
        // deal number and build a `?seed=` link back to it.
        expect(Game.freecellDeal(~seed=4242).seed)->toEqual(Some(4242))
        expect(Game.freecell.seed)->toEqual(Some(Game.freecellSeed))

        // The promise the field makes, and the one sharing a deal number rests on:
        // dealing a board's *reported* seed lays out that same board again. This is
        // the round trip a recipient makes when they paste the number into `?seed=`.
        let dealt = Game.freecellDeal(~seed=987654)
        let reopened = switch dealt.seed {
        | Some(seed) => Game.freecellDeal(~seed)
        | None => Game.freecell // can't happen; fails the comparison below if it does
        }
        expect(reopened.piles->Array.map(p => p.cards))->toEqual(
          dealt.piles->Array.map(p => p.cards),
        )
      },
    )

    test(
      "a board says how to deal another of its own game",
      () => {
        // The inverse of `seed`: `seed` says which number produced *this* board,
        // `deal` says how to produce the next one. So
        // "deal me another" is a question the board in hand answers — no caller has to
        // name FreeCell's deal function to ask it.
        let cards = (game: Game.t) => game.piles->Array.map(p => p.cards)
        let another = Game.freecell.deal->Option.getOrThrow
        let dealt = another(4242)
        expect(dealt.id)->toBe(Game.freecell.id)
        expect(dealt.seed)->toEqual(Some(4242))
        expect(cards(dealt))->toEqual(cards(Game.freecellDeal(~seed=4242)))
        // …and the board that comes back can deal again, which is what makes re-dealing
        // repeatable rather than a one-shot: New Game after New Game after New Game.
        let again = dealt.deal->Option.getOrThrow
        expect(cards(again(9)))->toEqual(cards(Game.freecellDeal(~seed=9)))

        // `dealt` is that capability applied, and the answer for a board with no deal to
        // vary is the board itself — a caller asking for the next board of a fixed game
        // gets a board rather than an exception.
        expect(cards(Game.dealt(Game.freecell, ~seed=4242)))->toEqual(cards(dealt))
        expect(Game.dealt({...Game.freecell, deal: None}, ~seed=4242).seed)->toEqual(
          Some(Game.freecellSeed),
        )

        // The game a deal *number* belongs to when nothing names a game — what a bare
        // `deal`/`deal 12345` lays out. FreeCell today, and re-dealable by definition.
        expect(Game.default.id)->toBe(Game.freecell.id)
        expect(Game.default.deal->Option.isSome)->toBe(true)
      },
    )

    test(
      "plays a scripted sequence of legal and illegal single-card moves through the reducer",
      () => {
        let board = Game.freecell
        let cell = Game.pileIndices(board, Game.FreeCell)->Array.getUnsafe(0)
        let foundation = Game.pileIndices(board, Game.Foundation)->Array.getUnsafe(0)
        let cascades = Game.pileIndices(board, Game.Cascade)
        // A move lifts only what a hand could lift — the card nothing rests on
        // (`Reducer.isFree`) — so the script poses each card it names on top of a
        // cascade of its own first, wherever the shuffle dealt it. `placeOnPile` is
        // the posing primitive: it brings a card to a pile's top. Every `reduce`
        // below then plays a card that's genuinely showing, which is the whole point
        // of the script — the rules being tested are the *destination's*.
        let showing = (s, card, ~on) => Reducer.placeOnPile(s, card, on)
        let state =
          GameState.initial(board)
          ->showing({suit: Spades, rank: King}, ~on=cascades->Array.getUnsafe(0))
          ->showing({suit: Hearts, rank: King}, ~on=cascades->Array.getUnsafe(1))
          ->showing({suit: Hearts, rank: Two}, ~on=cascades->Array.getUnsafe(2))
          ->showing({suit: Spades, rank: Ace}, ~on=cascades->Array.getUnsafe(3))
          ->showing({suit: Spades, rank: Two}, ~on=cascades->Array.getUnsafe(4))
          ->showing({suit: Hearts, rank: Three}, ~on=cascades->Array.getUnsafe(5))

        // Park a card in an empty free cell — a `Free`, capacity-1 slot takes any
        // single card.
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

        // A second card onto the full cell bounces with `PileFull`.
        expect(
          Reducer.reduce(
            ~game=board,
            afterPark,
            Move({card: {suit: Hearts, rank: King}, to: ToPile(cell)}),
          ),
        )->toEqual(Error(Reducer.PileFull))

        // Only an Ace founds a foundation: a non-Ace is `Rejected`.
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

        // The cascade rule builds *down* in alternating colour: derive a legal
        // follow-up (and an illegal same-colour one) from a cascade's own top
        // card, so the check holds for whatever the shuffle dealt.
        let cascade = cascades->Array.getUnsafe(0)
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

  // The short-deck siblings: FreeCell in every mechanic, differing only in
  // deck and shape. What's asserted here is the shape each declares and the two
  // things a short deck changes downstream — what "complete" means, and which suits
  // auto-collect waits on — the two places a four-suit assumption would hide.
  describe("mini and micro", () => {
    // The board shape as a table, so the two are read side by side rather than as
    // two near-identical blocks.
    let boards = [("mini", Game.mini, 4, 2, 4, 20, 5), ("micro", Game.micro, 4, 2, 2, 16, 4)]

    test(
      "each declares its cascades, cells and foundations",
      () =>
        boards->Array.forEach(
          ((label, board, cascades, cells, foundations, _, _)) => {
            expect((label, Array.length(Game.pilesOf(board, Game.Cascade))))->toEqual((
              label,
              cascades,
            ))
            expect((label, Array.length(Game.pilesOf(board, Game.FreeCell))))->toEqual((
              label,
              cells,
            ))
            expect((label, Array.length(Game.pilesOf(board, Game.Foundation))))->toEqual((
              label,
              foundations,
            ))
            // Cells and foundations first, cascades below — the board order the view
            // groups its two rows by.
            expect((label, Game.pileIndices(board, Game.FreeCell)))->toEqual((
              label,
              Array.fromInitializer(~length=cells, i => i),
            ))
            expect((label, Game.pileIndices(board, Game.Cascade)))->toEqual((
              label,
              Array.fromInitializer(~length=cascades, i => cells + foundations + i),
            ))
            // …and each pile carries the FreeCell rule its role calls for, so the
            // mechanics are the same game rather than a lookalike.
            Game.pilesOf(board, Game.FreeCell)->Array.forEach(
              p => {
                expect(p.rule)->toEqual(Rules.Free)
                expect(p.capacity)->toEqual(Some(1))
                expect(p.stacking)->toEqual(Game.Squared)
              },
            )
            Game.pilesOf(board, Game.Foundation)->Array.forEach(
              p => {
                expect(p.rule)->toEqual(Rules.foundation)
                expect(p.stacking)->toEqual(Game.Squared)
              },
            )
            Game.pilesOf(board, Game.Cascade)->Array.forEach(
              p => {
                expect(p.rule)->toEqual(Rules.cascade)
                expect(p.capacity)->toEqual(None)
                expect(p.stacking)->toEqual(Game.Fanned)
              },
            )
            // …and the board-level laws are FreeCell's: runs move by the supermove,
            // and safe cards go home on their own.
            expect((label, board.runLimit))->toEqual((label, Game.Supermove))
            expect((label, board.collect))->toEqual((label, Game.SafeCards))
          },
        ),
    )

    test(
      "deals its own short deck evenly across the cascades, cells and foundations empty",
      () =>
        boards->Array.forEach(
          ((label, board, _, _, _, deckSize, perColumn)) => {
            let cascades = Game.pilesOf(board, Game.Cascade)
            // Every column the same depth: both decks divide evenly by four.
            expect((label, cascades->Array.map(p => Array.length(p.cards))))->toEqual((
              label,
              Array.fromInitializer(~length=Array.length(cascades), _ => perColumn),
            ))
            // The pooled cascade cards are exactly the board's own deck — every card
            // of it once, and nothing from outside it.
            let dealt = cascades->Array.flatMap(p => p.cards)
            let deck = Cards.cardsOf(board.deck)
            expect((label, Array.length(dealt)))->toEqual((label, deckSize))
            expect((label, Array.length(deck)))->toEqual((label, deckSize))
            expect((
              label,
              deck->Array.every(card => dealt->Array.some(c => GameState.sameCard(c, card))),
            ))->toEqual((label, true))
            // Cells and foundations open empty, as on the full board.
            expect((
              label,
              Game.pilesOf(board, Game.FreeCell)->Array.every(p => Array.length(p.cards) == 0) &&
                Game.pilesOf(board, Game.Foundation)->Array.every(p => Array.length(p.cards) == 0),
            ))->toEqual((label, true))
          },
        ),
    )

    test(
      "is re-dealable under its own id, reproducibly",
      () =>
        boards->Array.forEach(
          ((label, board, _, _, _, _, _)) => {
            let cards = (game: Game.t) => game.piles->Array.map(p => p.cards)
            let another = board.deal->Option.getOrThrow
            let dealt = another(4242)
            // A re-deal is another board of the *same* game — same id, same deck —
            // which is what keeps its saved game and its `?scene=` link its own.
            expect((label, dealt.id))->toEqual((label, board.id))
            expect((label, dealt.deck))->toEqual((label, board.deck))
            expect((label, dealt.seed))->toEqual((label, Some(4242)))
            // …and the deal number round-trips: dealing the seed a board reports
            // lays that board out again (the promise a `?seed=` link rests on).
            let again = dealt.deal->Option.getOrThrow
            expect((label, cards(again(4242))))->toEqual((label, cards(dealt)))
            // A different number is a different board.
            expect(cards(again(9)) == cards(dealt))->toBe(false)
          },
        ),
    )

    test(
      "a foundation is complete at the short deck's own highest rank",
      () => {
        // The whole-pack assumption, seen from the boards that break it: `mini`
        // finishes at the Five and `micro` at the Eight, so a 13-card, King-topped
        // definition of "complete" would leave either board unwinnable.
        let run = (~suit, ~upTo) =>
          Cards.ranks
          ->Array.filter(rank => Rules.rankValue(rank) <= Rules.rankValue(upTo))
          ->Array.map(rank => {suit, rank})
        expect(Rules.isCompleteRun(~deck=Game.mini.deck, run(~suit=Spades, ~upTo=Five)))->toBe(true)
        expect(Rules.isCompleteRun(~deck=Game.micro.deck, run(~suit=Spades, ~upTo=Eight)))->toBe(
          true,
        )
        // One short of the top is not complete on either.
        expect(Rules.isCompleteRun(~deck=Game.mini.deck, run(~suit=Spades, ~upTo=Four)))->toBe(
          false,
        )
        expect(Rules.isCompleteRun(~deck=Game.micro.deck, run(~suit=Spades, ~upTo=Seven)))->toBe(
          false,
        )
        // …and a full-pack board still finishes at the King, unchanged.
        expect(Rules.isCompleteRun(~deck=Game.freecell.deck, run(~suit=Spades, ~upTo=Five)))->toBe(
          false,
        )
      },
    )

    test(
      "auto-collect on micro waits only on the suits its two-colour deck actually has",
      () => {
        // The case a hard-coded four-suit rule would stall (and the reason
        // `micro` needs it): with only ♠ and ♥ in play, a black card waits on Hearts
        // alone. Both foundations up to the Two, the Three of Spades on a cascade —
        // asking `[Hearts, Diamonds]` would find Diamonds stuck at rank 0 forever and
        // refuse every card above a Two for the rest of the game.
        //
        // Board order on `micro` is 2 cells, 2 foundations, 4 cascades.
        let posed = GameState.faceUp([
          [],
          [],
          [{suit: Spades, rank: Ace}, {suit: Spades, rank: Two}],
          [{suit: Hearts, rank: Ace}, {suit: Hearts, rank: Two}],
          [{suit: Spades, rank: Three}],
          [{suit: Spades, rank: Four}],
          [],
          [],
        ])
        expect(Reducer.isSafeToCollect(~game=Game.micro, posed, {suit: Spades, rank: Three}))->toBe(
          true,
        )
        // …and the rule is still a rule: the Four waits, because Hearts hasn't reached
        // the Three a descending cascade could still want it on.
        expect(Reducer.isSafeToCollect(~game=Game.micro, posed, {suit: Spades, rank: Four}))->toBe(
          false,
        )
      },
    )

    test(
      "the deck each plays with is the one it declares",
      () => {
        // `mini` is four suits × five ranks, `micro` two suits × eight — the whole of
        // what makes them different games.
        expect(Game.mini.deck.suits)->toEqual(Cards.suits)
        expect(Game.mini.deck.ranks)->toEqual([Ace, Two, Three, Four, Five])
        expect(Game.micro.deck.suits)->toEqual([Spades, Hearts])
        expect(Game.micro.deck.ranks)->toEqual([Ace, Two, Three, Four, Five, Six, Seven, Eight])
        // A foundation per suit on both, which is what makes them winnable at all.
        expect(Array.length(Game.pilesOf(Game.mini, Game.Foundation)))->toBe(
          Array.length(Game.mini.deck.suits),
        )
        expect(Array.length(Game.pilesOf(Game.micro, Game.Foundation)))->toBe(
          Array.length(Game.micro.deck.suits),
        )
      },
    )

    test(
      "the slot labels fall out of the role counts, with no per-game table",
      () => {
        // `Slot` counts within a role, so a shorter board simply has shorter runs of
        // labels, and a new short board needs no edit here.
        expect(Slot.labels(~game=Game.mini))->toEqual([
          "C1",
          "C2",
          "F1",
          "F2",
          "F3",
          "F4",
          "T1",
          "T2",
          "T3",
          "T4",
        ])
        expect(Slot.labels(~game=Game.micro))->toEqual([
          "C1",
          "C2",
          "F1",
          "F2",
          "T1",
          "T2",
          "T3",
          "T4",
        ])
      },
    )

    test(
      "the solver declines them rather than mis-reading a board it can't model",
      () => {
        // Out of the solver's scope, and deliberately so: `Position` models exactly the
        // 4/4/8 FreeCell shape, so these two get an honest `None` and autoplay answers
        // `NotFreeCell` — rather than a position with pieces missing.
        expect(
          Position.ofGameState(~game=Game.mini, GameState.initial(Game.mini))->Option.isNone,
        )->toBe(true)
        expect(
          Position.ofGameState(~game=Game.micro, GameState.initial(Game.micro))->Option.isNone,
        )->toBe(true)
      },
    )
  })

  // The first board from another family. Where `mini`/`micro` prove a board can vary
  // in deck and counts, this one varies in *law* — Spider's cascades, sealed
  // foundations, runs that move whole, a completed run lifted off the table — and
  // what's asserted is that every one of those is data the reducer already reads,
  // not a branch on the game's id. Board order is 4 foundations, then 10 cascades.
  describe("simple simon", () => {
    let board = Game.simpleSimon
    let foundations = Game.pileIndices(board, Game.Foundation)
    let cascades = Game.pileIndices(board, Game.Cascade)
    let spades = ranks => ranks->Array.map(rank => {suit: Spades, rank})
    // A posed position from its cascades alone (foundations empty, missing cascades
    // empty), so a test states only the columns it's about.
    let posed = (~foundationCards=[], columns: array<array<card>>): GameState.t =>
      GameState.faceUp(
        foundations
        ->Array.map(_ => [])
        ->Array.concat(
          cascades->Array.mapWithIndex((_, i) => columns->Array.get(i)->Option.getOr([])),
        )
        ->Array.mapWithIndex((cards, i) => i == 0 ? foundationCards : cards),
      )
    // The full King→Ace run of a suit, bottom-first as a cascade holds it.
    let kingToAce = suit => Cards.ranks->Array.toReversed->Array.map(rank => {suit, rank})

    test(
      "is fourteen piles: four sealed foundations, then ten cascades under Spider's law, no cells",
      () => {
        expect(Array.length(board.piles))->toBe(14)
        expect(foundations)->toEqual([0, 1, 2, 3])
        expect(cascades)->toEqual([4, 5, 6, 7, 8, 9, 10, 11, 12, 13])
        expect(Game.pileIndices(board, Game.FreeCell))->toEqual([])
        // The hand never plays a card to a foundation: it is filled by collection alone.
        Game.pilesOf(board, Game.Foundation)->Array.forEach(
          p => {
            expect(p.rule)->toEqual(Rules.Sealed)
            expect(p.stacking)->toEqual(Game.Squared)
            expect(p.capacity)->toEqual(None)
          },
        )
        Game.pilesOf(board, Game.Cascade)->Array.forEach(
          p => {
            expect(p.rule)->toEqual(Rules.spiderCascade)
            expect(p.stacking)->toEqual(Game.Fanned)
            expect(p.capacity)->toEqual(None)
          },
        )
        // The two board-level laws that make it Spider rather than FreeCell.
        expect(board.runLimit)->toEqual(Game.Unlimited)
        expect(board.collect)->toEqual(Game.CompleteRuns)
        expect(board.deck)->toEqual(Cards.standard)
      },
    )

    test(
      "deals the whole pack by counts, 8/8/8/7/6/5/4/3/2/1, foundations empty",
      () => {
        expect(Game.pilesOf(board, Game.Cascade)->Array.map(p => Array.length(p.cards)))->toEqual([
          8,
          8,
          8,
          7,
          6,
          5,
          4,
          3,
          2,
          1,
        ])
        let dealt = Game.pilesOf(board, Game.Cascade)->Array.flatMap(p => p.cards)
        expect(Array.length(dealt))->toBe(52)
        expect(
          Cards.all->Array.every(card => dealt->Array.some(c => GameState.sameCard(c, card))),
        )->toBe(true)
        expect(
          Game.pilesOf(board, Game.Foundation)->Array.every(p => Array.length(p.cards) == 0),
        )->toBe(true)
      },
    )

    test(
      "is re-dealable under its own id, reproducibly",
      () => {
        let cards = (game: Game.t) => game.piles->Array.map(p => p.cards)
        let another = board.deal->Option.getOrThrow
        let dealt = another(4242)
        expect(dealt.id)->toBe(board.id)
        expect(dealt.seed)->toEqual(Some(4242))
        expect(dealt.runLimit)->toEqual(Game.Unlimited)
        expect(dealt.collect)->toEqual(Game.CompleteRuns)
        let again = dealt.deal->Option.getOrThrow
        expect(cards(again(4242)))->toEqual(cards(dealt))
        expect(cards(again(9)) == cards(dealt))->toBe(false)
      },
    )

    test(
      "any card one rank lower may land on a cascade, whatever its suit",
      () => {
        // ♠8 tops the first cascade; the candidates each sit alone on their own.
        let state = posed([
          spades([Eight]),
          [{suit: Hearts, rank: Seven}],
          spades([Seven]),
          spades([Nine]),
          spades([Six]),
        ])
        let onto = cascades->Array.getUnsafe(0)
        expect(Reducer.canDrop(~game=board, state, {suit: Hearts, rank: Seven}, ~onto))->toBe(true)
        expect(Reducer.canDrop(~game=board, state, {suit: Spades, rank: Seven}, ~onto))->toBe(true)
        // Still descending by one: neither a higher card nor a gap.
        expect(Reducer.canDrop(~game=board, state, {suit: Spades, rank: Nine}, ~onto))->toBe(false)
        expect(Reducer.canDrop(~game=board, state, {suit: Spades, rank: Six}, ~onto))->toBe(false)
        // …and never onto a foundation, empty or not.
        expect(Reducer.canDrop(~game=board, state, {suit: Spades, rank: Ace}, ~onto=0))->toBe(false)
        expect(Reducer.foundationTarget(~game=board, state, {suit: Spades, rank: Ace}))->toEqual(
          None,
        )
      },
    )

    test(
      "only a same-suit run moves as one: a lawful drop can head no run",
      () => {
        // ♥7 on ♠8 was a lawful drop; ♥6 on ♥7 continues a run. The hand may lift
        // ♥7 ♥6 together, but not ♠8 ♥7 ♥6 — the suit change is where the run ends.
        let column = [
          {suit: Spades, rank: Eight},
          {suit: Hearts, rank: Seven},
          {suit: Hearts, rank: Six},
        ]
        let state = posed([column, [{suit: Clubs, rank: Eight}]])
        let to = Reducer.ToPile(cascades->Array.getUnsafe(1))
        let hearts = column->Array.slice(~start=1, ~end=3)
        expect(Reducer.reduce(~game=board, state, MoveRun({cards: hearts, to}))->Result.isOk)->toBe(
          true,
        )
        expect(Reducer.reduce(~game=board, state, MoveRun({cards: column, to})))->toEqual(
          Error(Reducer.NotARun),
        )
        // The same verdicts from the shared queries the view and `moverun` read.
        expect(
          Reducer.canMoveRun(~game=board, state, hearts, ~onto=cascades->Array.getUnsafe(1)),
        )->toBe(true)
        expect(
          Reducer.canMoveRun(~game=board, state, column, ~onto=cascades->Array.getUnsafe(1)),
        )->toBe(false)
        expect(Command.runShowing(~game=board, state, cascades->Array.getUnsafe(0)))->toEqual(
          hearts,
        )
      },
    )

    test(
      "a same-suit run of any length moves whole, with nothing to relay it through",
      () => {
        // Nine cascades occupied, no cells at all: FreeCell's supermove would allow one
        // card. Simple Simon lifts the six-card run regardless.
        let run = spades([Nine, Eight, Seven, Six, Five, Four])
        let state = posed([
          run,
          [{suit: Hearts, rank: Ten}],
          spades([King]),
          spades([Queen]),
          spades([Jack]),
          spades([Ten]),
          spades([Three]),
          spades([Two]),
          spades([Ace]),
          [{suit: Hearts, rank: King}],
        ])
        let onto = cascades->Array.getUnsafe(1)
        expect(Reducer.maxSupermove(~game=board, state, ~ignoring=onto))->toBe(1)
        expect(Reducer.canMoveRun(~game=board, state, run, ~onto))->toBe(true)
        switch Reducer.reduce(~game=board, state, MoveRun({cards: run, to: ToPile(onto)})) {
        | Ok(next) =>
          expect(GameState.cardsInPile(next, onto))->toEqual(
            [{suit: Hearts, rank: Ten}]->Array.concat(run),
          )
        | Error(e) => expect(Ok(e))->toEqual(Error(Reducer.RunTooLong))
        }
      },
    )

    test(
      "a completed King→Ace run is lifted off its cascade onto an empty foundation",
      () => {
        // The run sits on a ♣3 it was built over; the ♣3 stays, the run goes home,
        // King first as the pile held it. A run one short stays where it is.
        let done = [{suit: Clubs, rank: Three}]->Array.concat(kingToAce(Spades))
        let nearly = kingToAce(Hearts)->Array.slice(~start=0, ~end=12)
        let state = posed([done, nearly])
        let (settled, moved) = Reducer.autoCollect(~game=board, state)
        expect(moved)->toEqual(kingToAce(Spades))
        expect(GameState.cardsInPile(settled, 0))->toEqual(kingToAce(Spades))
        expect(GameState.cardsInPile(settled, cascades->Array.getUnsafe(0)))->toEqual([
          {suit: Clubs, rank: Three},
        ])
        expect(GameState.cardsInPile(settled, cascades->Array.getUnsafe(1)))->toEqual(nearly)
        // Nothing to collect answers with the board unchanged, as the drivers rely on.
        let (again, more) = Reducer.autoCollect(~game=board, settled)
        expect(GameState.equal(again, settled))->toBe(true)
        expect(more)->toEqual([])
      },
    )

    test(
      "two runs completed at once both go home, each to its own foundation",
      () => {
        let state = posed([kingToAce(Spades), kingToAce(Hearts)])
        let (settled, moved) = Reducer.autoCollect(~game=board, state)
        expect(Array.length(moved))->toBe(26)
        expect(GameState.cardsInPile(settled, 0))->toEqual(kingToAce(Spades))
        expect(GameState.cardsInPile(settled, 1))->toEqual(kingToAce(Hearts))
        expect(
          cascades->Array.every(i => Array.length(GameState.cardsInPile(settled, i)) == 0),
        )->toBe(true)
      },
    )

    test(
      "a collected run is home for good: nothing on a foundation is the hand's",
      () => {
        let state = posed(~foundationCards=kingToAce(Spades), [[{suit: Hearts, rank: Two}]])
        let ace = {suit: Spades, rank: Ace}
        let empty = Reducer.ToPile(cascades->Array.getUnsafe(1))
        // The foundation's Ace tops its pile and an empty cascade would take any card —
        // and it still can't move, alone or as the run it heads.
        expect(Reducer.isFree(state, ace))->toBe(true)
        expect(Reducer.isHome(~game=board, state, ace))->toBe(true)
        expect(Reducer.reduce(~game=board, state, Move({card: ace, to: empty})))->toEqual(
          Error(Reducer.CardHome),
        )
        expect(Reducer.reduce(~game=board, state, MoveRun({cards: [ace], to: empty})))->toEqual(
          Error(Reducer.CardHome),
        )
        expect(Reducer.validMoves(~game=board, state, ace))->toEqual([])
        expect(
          Reducer.canMoveRun(~game=board, state, [ace], ~onto=cascades->Array.getUnsafe(1)),
        )->toBe(false)
        // The view reads the same answer off the rule: not even the top card heads a run.
        expect(Rules.isRun(Rules.Sealed, [ace]))->toBe(false)
        // A card on the table is still the hand's, so the rule is about the pile.
        expect(Reducer.isHome(~game=board, state, {suit: Hearts, rank: Two}))->toBe(false)
      },
    )

    test(
      "is won when every foundation holds its run, and not before",
      () => {
        let three = GameState.faceUp(
          board.piles->Array.mapWithIndex(
            (_, i) =>
              switch i {
              | 0 => kingToAce(Spades)
              | 1 => kingToAce(Hearts)
              | 2 => kingToAce(Diamonds)
              | 4 => kingToAce(Clubs)
              | _ => []
              },
          ),
        )
        expect(GameState.hasWon(board, three))->toBe(false)
        // The last run is still on a cascade; collecting it is the win.
        let (settled, moved) = Reducer.autoCollect(~game=board, three)
        expect(Array.length(moved))->toBe(13)
        expect(GameState.hasWon(board, settled))->toBe(true)
        // A Spider board is never finishable by foundation moves — there are none —
        // so the finish sweep has nothing to offer it short of the win itself.
        expect(Reducer.canFinish(~game=board, three))->toBe(false)
        expect(Reducer.canFinish(~game=board, settled))->toBe(true)
      },
    )

    test(
      "the slot labels count ten columns and no cells",
      () => {
        expect(Slot.labels(~game=board))->toEqual([
          "F1",
          "F2",
          "F3",
          "F4",
          "T1",
          "T2",
          "T3",
          "T4",
          "T5",
          "T6",
          "T7",
          "T8",
          "T9",
          "T10",
        ])
        expect(Slot.parse("T10"))->toEqual(Some((Game.Cascade, 10)))
      },
    )

    test(
      "the solver declines it rather than mis-reading a board it can't model",
      () => {
        expect(Position.ofGameState(~game=board, GameState.initial(board))->Option.isNone)->toBe(
          true,
        )
      },
    )

    // A `<card> <slot>` move against the board in play: the run the named card heads,
    // lifted to the slot — `Move` for one card, `MoveRun` for more. The same vocabulary
    // the browser suite drags by, so one recorded line serves both.
    let actionOf = (game: Game.t, state: GameState.t, text: string): Reducer.action => {
      let parts = text->String.trim->String.split(" ")
      let card = parts->Array.get(0)->Option.flatMap(CardText.parse)->Option.getOrThrow
      let (role, ordinal) = parts->Array.get(1)->Option.flatMap(Slot.parse)->Option.getOrThrow
      let to = Reducer.ToPile(Slot.indexOf(~game, ~role, ~ordinal)->Option.getOrThrow)
      switch GameState.locationOf(state, card) {
      | Some(InPile(i, slot)) =>
        let pile = GameState.cardsInPile(state, i)
        Command.moveAction(~cards=pile->Array.slice(~start=slot, ~end=Array.length(pile)), ~to)
      | _ => Reducer.Move({card, to}) // not in play: the reducer will say so
      }
    }

    test(
      "deal #1 plays to the win: a recorded line, every move settled through the session",
      () => {
        // Found by search over this very reducer, then kept as a fixed script: the deal
        // is deterministic, so this proves the canonical board is winnable and that the
        // rules above compose into a game — runs lifted, four collections, the win
        // tripped by the last of them.
        let line = "JH T9, TC T9, 7S T1, 8S T9, AC T8, 3C T3, 6H T9, 4H T10, QH T5, 5C T9, 4H T9, QH T6, KD T10, AC T5, 2H T3, 3D T9, 2H T9, 2C T3, TS T8, AD T9, QS T10, JC T6, TS T6, 4C T2, 4D T8, 9D T1, 9S T6, 6S T4, 7H T3, 8H T5, 9H T7, 8D T1, TD T3, AD T1, JD T10, 5S T4, 4D T4, TH T3, 7C T10, AH T9, AS T5, 2H T7, 3D T4, 2S T4, 4H T5, 4C T9, 4H T2, 2D T5, 6D T10, 5H T10, KH T2, TS T1, TH T6, 5C T3, 6H T6, 8S T1, 5H T6, 5C T10, TH T3, TC T6, TH T9, JC T3, JH T6, JS T9, QH T2, KS T1, JC T6, QC T1, 3S T2, 8C T1, 3S T6, 2S T6, 2D T4, 4D T3, 4S T4, 6S T9, 7D T1, 4D T4, 5D T3, 2H T4, 3H T2, 6C T1, 5C T1, 5D T10, 6C T2, 6D T1, 6C T10, 7D T2, 7C T1, 7D T10, JS T2, JD T9, JS T10, QC T2, QS T1, QD T10, QC T9"
        let start = Session.open_(
          ~clock=() => 0.,
          ~options=Options.default,
          ~seed=board.seed,
          board,
          GameState.initial(board),
        )
        let collected = ref(0)
        let final =
          line
          ->String.split(",")
          ->Array.reduce(
            start,
            (s, text) => {
              let (next, change) = Session.dispatch(
                ~clock=() => 0.,
                s,
                actionOf(board, Session.present(s), text),
              )
              switch change {
              | Session.Settled({collected: home}) =>
                collected := collected.contents + Array.length(home)
              | _ => expect(text)->toBe("a settled move")
              }
              next
            },
          )
        expect(Session.hasWon(final))->toBe(true)
        expect(collected.contents)->toBe(52)
      },
    )
  })

  // Spider's stock and its face-down cards, on the board that needs no second pack.
  // Board order: the stock, four sealed foundations, then seven cascades. What's
  // asserted is that a face-down card is a *count on the snapshot* — turned over by
  // the move that exposes it and put back by undo, never a flag a driver remembers —
  // and that the deal is one more action the reducer takes, refused on the board's own
  // terms rather than a branch on its id.
  describe("spiderette", () => {
    let board = Game.spiderette
    let stock = Reducer.stockOf(board)->Option.getOrThrow
    let foundations = Game.pileIndices(board, Game.Foundation)
    let cascades = Game.pileIndices(board, Game.Cascade)
    let cascade = k => cascades->Array.getUnsafe(k)
    let opening = GameState.initial(board)
    let deal = state =>
      switch Reducer.reduce(~game=board, state, Reducer.Deal) {
      | Ok(next) => next
      | Error(_) => state
      }
    let spades = ranks => ranks->Array.map(rank => {suit: Spades, rank})
    let kingToAce = suit => Cards.ranks->Array.toReversed->Array.map(rank => {suit, rank})
    // A posed position from its columns and stock alone, everything face up unless
    // `~down` says otherwise: a count per column, matched by position.
    let posed = (~stockCards=[], ~down=[], columns: array<array<card>>): GameState.t => {
      let piles = board.piles->Array.mapWithIndex(
        (pile: Game.pile, i) =>
          switch pile.role {
          | Game.Stock => stockCards
          | Game.Foundation => []
          | Game.Cascade | Game.FreeCell =>
            columns->Array.get(cascades->Array.indexOf(i))->Option.getOr([])
          },
      )
      let state = GameState.faceUp(piles)
      {
        ...state,
        faceDown: state.faceDown->Array.mapWithIndex(
          (n, i) =>
            i == stock
              ? Array.length(stockCards)
              : down->Array.get(cascades->Array.indexOf(i))->Option.getOr(n),
        ),
      }
    }

    test(
      "is twelve piles: a sealed stock, four sealed foundations, then seven cascades under Spider's law",
      () => {
        expect(Array.length(board.piles))->toBe(12)
        expect(stock)->toBe(0)
        expect(foundations)->toEqual([1, 2, 3, 4])
        expect(cascades)->toEqual([5, 6, 7, 8, 9, 10, 11])
        expect(Game.pileIndices(board, Game.FreeCell))->toEqual([])
        Game.pilesOf(board, Game.Stock)->Array.forEach(
          p => {
            expect(p.rule)->toEqual(Rules.Sealed)
            expect(p.stacking)->toEqual(Game.Squared)
          },
        )
        Game.pilesOf(board, Game.Foundation)->Array.forEach(
          p => expect(p.rule)->toEqual(Rules.Sealed),
        )
        Game.pilesOf(board, Game.Cascade)->Array.forEach(
          p => {
            expect(p.rule)->toEqual(Rules.spiderCascade)
            expect(p.stacking)->toEqual(Game.Fanned)
          },
        )
        expect(board.runLimit)->toEqual(Game.Unlimited)
        expect(board.collect)->toEqual(Game.CompleteRuns)
        // Two suits, twice over: 52 cards and four runs, one per foundation.
        expect(board.deck)->toEqual({suits: [Spades, Hearts], ranks: Cards.ranks, copies: 2})
        expect(Array.length(Cards.cardsOf(board.deck)))->toBe(52)
      },
    )

    test(
      "deals 1/2/3/4/5/6/7 with only each column's top card face up, and the other 24 into the stock face down",
      () => {
        let columns = Game.pilesOf(board, Game.Cascade)
        expect(columns->Array.map(p => Array.length(p.cards)))->toEqual([1, 2, 3, 4, 5, 6, 7])
        expect(columns->Array.map(p => p.faceDown))->toEqual([0, 1, 2, 3, 4, 5, 6])
        let stockPile = board.piles->Array.getUnsafe(stock)
        expect(Array.length(stockPile.cards))->toBe(24)
        expect(stockPile.faceDown)->toBe(24)
        // Every card of the pack exactly once, between the columns and the stock —
        // both copies of each face, as two cards.
        let dealt = columns->Array.flatMap(p => p.cards)->Array.concat(stockPile.cards)
        expect(Array.length(dealt))->toBe(52)
        expect(
          Cards.cardsOf(board.deck)->Array.every(
            card => dealt->Array.filter(c => GameState.sameCard(c, card))->Array.length == 1,
          ),
        )->toBe(true)
        // The snapshot carries the counts, and reads them per card.
        expect(opening.faceDown)->toEqual([24, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6])
        let second = GameState.cardsInPile(opening, cascade(1))
        expect(GameState.isFaceDown(opening, second->Array.getUnsafe(0)))->toBe(true)
        expect(GameState.isFaceDown(opening, second->Array.getUnsafe(1)))->toBe(false)
        // The stock's top is the card the shuffle would have dealt next.
        let shuffled = Cards.shuffle(~deck=board.deck, ~seed=Game.freecellSeed)
        expect(GameState.topOf(opening, stock))->toEqual(shuffled->Array.get(28))
      },
    )

    test(
      "is re-dealable under its own id, reproducibly",
      () => {
        let cards = (game: Game.t) => game.piles->Array.map(p => p.cards)
        let another = board.deal->Option.getOrThrow
        let dealt = another(4242)
        expect(dealt.id)->toBe(board.id)
        expect(dealt.seed)->toEqual(Some(4242))
        let again = dealt.deal->Option.getOrThrow
        expect(cards(again(4242)))->toEqual(cards(dealt))
        expect(cards(again(9)) == cards(dealt))->toBe(false)
      },
    )

    test(
      "a deal drops the stock's top card face up on every column, left to right, as one step",
      () => {
        let row = Reducer.nextDeal(~game=board, opening)
        let stockCards = GameState.cardsInPile(opening, stock)
        expect(row)->toEqual(stockCards->Array.slice(~start=17, ~end=24)->Array.toReversed)
        let next = deal(opening)
        expect(GameState.equal(next, opening))->toBe(false)
        expect(Array.length(GameState.cardsInPile(next, stock)))->toBe(17)
        cascades->Array.forEachWithIndex(
          (i, k) => {
            expect(GameState.topOf(next, i))->toEqual(row->Array.get(k))
            expect(Array.length(GameState.cardsInPile(next, i)))->toBe(k + 2)
            expect(GameState.isFaceDown(next, row->Array.getUnsafe(k)))->toBe(false)
          },
        )
        // The columns' face-down cards are untouched, and the stock is still all backs.
        expect(next.faceDown)->toEqual([17, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6])
      },
    )

    test(
      "the last deal is three cards onto the first three columns, and then there is nothing to deal",
      () => {
        let three = opening->deal->deal->deal
        expect(Array.length(GameState.cardsInPile(three, stock)))->toBe(3)
        let row = Reducer.nextDeal(~game=board, three)
        expect(Array.length(row))->toBe(3)
        let last = deal(three)
        expect(Array.length(GameState.cardsInPile(last, stock)))->toBe(0)
        expect(cascades->Array.map(i => Array.length(GameState.cardsInPile(last, i))))->toEqual([
          5,
          6,
          7,
          7,
          8,
          9,
          10,
        ])
        expect(Reducer.reduce(~game=board, last, Reducer.Deal))->toEqual(Error(Reducer.StockEmpty))
        expect(Reducer.nextDeal(~game=board, last))->toEqual([])
      },
    )

    test(
      "a deal is refused while a column stands empty, and on a board with no stock",
      () => {
        let gap = posed(~stockCards=spades([Ace, Two]), [spades([King]), [], spades([Queen])])
        expect(Reducer.reduce(~game=board, gap, Reducer.Deal))->toEqual(Error(Reducer.CascadeEmpty))
        expect(Reducer.nextDeal(~game=board, gap))->toEqual([])
        let simon = Game.simpleSimon
        expect(Reducer.reduce(~game=simon, GameState.initial(simon), Reducer.Deal))->toEqual(
          Error(Reducer.NoStock),
        )
        expect(Reducer.nextDeal(~game=simon, GameState.initial(simon)))->toEqual([])
      },
    )

    test(
      "a face-down card is nobody's to lift, alone or under a run it happens to continue",
      () => {
        // ♠8 face down under ♠7: by rank and suit the pair is a run, and it isn't one.
        let state = posed(~down=[1], [spades([Eight, Seven]), [{suit: Hearts, rank: Eight}]])
        let eight = {suit: Spades, rank: Eight}
        let seven = {suit: Spades, rank: Seven}
        let to = Reducer.ToPile(cascade(1))
        expect(Reducer.reduce(~game=board, state, Move({card: eight, to})))->toEqual(
          Error(Reducer.CardFaceDown),
        )
        expect(Reducer.reduce(~game=board, state, MoveRun({cards: [eight, seven], to})))->toEqual(
          Error(Reducer.CardFaceDown),
        )
        expect(Reducer.canMoveRun(~game=board, state, [eight, seven], ~onto=cascade(1)))->toBe(
          false,
        )
        expect(Reducer.validMoves(~game=board, state, eight))->toEqual([])
        // The run showing in the column stops above the face-down card.
        expect(Command.runShowing(~game=board, state, cascade(0)))->toEqual([seven])
        // …and the seven itself is still the hand's.
        expect(Reducer.reduce(~game=board, state, Move({card: seven, to}))->Result.isOk)->toBe(true)
      },
    )

    test(
      "the move that exposes a face-down card turns it over, and undo turns it back",
      () => {
        let state = posed(~down=[1], [spades([Eight, Seven]), [{suit: Hearts, rank: Eight}]])
        let eight = {suit: Spades, rank: Eight}
        let seven = {suit: Spades, rank: Seven}
        let session = Session.open_(
          ~clock=() => 0.,
          ~options=Options.default,
          ~seed=None,
          board,
          state,
        )
        let (moved, change) = Session.dispatch(
          ~clock=() => 0.,
          session,
          Move({card: seven, to: ToPile(cascade(1))}),
        )
        switch change {
        | Session.Settled(_) => ()
        | _ => expect("a settled move")->toBe("something else")
        }
        let after = Session.present(moved)
        expect(GameState.cardsInPile(after, cascade(0)))->toEqual([eight])
        expect(GameState.isFaceDown(after, eight))->toBe(false)
        expect(GameState.faceDownIn(after, cascade(0)))->toBe(0)
        // Now the eight is the hand's.
        expect(Reducer.validMoves(~game=board, after, eight)->Array.length > 0)->toBe(true)
        // One step back restores the position *as it lay*, back included.
        let (undone, _) = Session.undo(~clock=() => 0., moved)
        expect(GameState.equal(Session.present(undone), state))->toBe(true)
        expect(GameState.isFaceDown(Session.present(undone), eight))->toBe(true)
      },
    )

    test(
      "a run lifted whole, or collected, turns over the card it was resting on — and only then",
      () => {
        // ♣K face down under a three-card spade run: lifting the run exposes it.
        let run = spades([Nine, Eight, Seven])
        let state = posed(
          ~down=[1],
          [[{suit: Clubs, rank: King}]->Array.concat(run), [{suit: Hearts, rank: Ten}]],
        )
        switch Reducer.reduce(~game=board, state, MoveRun({cards: run, to: ToPile(cascade(1))})) {
        | Ok(next) =>
          expect(GameState.cardsInPile(next, cascade(0)))->toEqual([{suit: Clubs, rank: King}])
          expect(next.faceDown->Array.getUnsafe(cascade(0)))->toBe(0)
        | Error(e) => expect(Ok(e))->toEqual(Error(Reducer.NotARun))
        }
        // A face-down ♦2 under a complete run: collecting the run turns it over.
        let done = posed(
          ~down=[1],
          [[{suit: Diamonds, rank: Two}]->Array.concat(kingToAce(Spades))],
        )
        let (settled, moved) = Reducer.autoCollect(~game=board, done)
        expect(moved)->toEqual(kingToAce(Spades))
        expect(GameState.cardsInPile(settled, cascade(0)))->toEqual([{suit: Diamonds, rank: Two}])
        expect(GameState.isFaceDown(settled, {suit: Diamonds, rank: Two}))->toBe(false)
        expect(GameState.cardsInPile(settled, foundations->Array.getUnsafe(0)))->toEqual(
          kingToAce(Spades),
        )
      },
    )

    test(
      "a deal that completes a run has it collected, in the same settled step",
      () => {
        // The stock's top is ♠A and the first column is ♠K→2: the deal completes the
        // run, and settling lifts it. The other six dealt cards land where they fall.
        let filler = [Two, Three, Four, Five, Six, Seven]->Array.map(rank => {suit: Hearts, rank})
        let stockCards = filler->Array.concat(spades([Ace]))
        let state = posed(
          ~stockCards,
          [
            kingToAce(Spades)->Array.slice(~start=0, ~end=12),
            spades([Two])->Array.map(_ => {suit: Clubs, rank: Nine}),
            [{suit: Clubs, rank: Eight}],
            [{suit: Clubs, rank: Seven}],
            [{suit: Clubs, rank: Six}],
            [{suit: Clubs, rank: Five}],
            [{suit: Clubs, rank: Four}],
          ],
        )
        let session = Session.open_(
          ~clock=() => 0.,
          ~options=Options.default,
          ~seed=None,
          board,
          state,
        )
        let (next, change) = Session.dispatch(~clock=() => 0., session, Reducer.Deal)
        switch change {
        | Session.Settled({moved, collected}) =>
          expect(moved)->toEqual(spades([Ace])->Array.concat(filler->Array.toReversed))
          expect(collected)->toEqual(kingToAce(Spades))
        | _ => expect("a settled deal")->toBe("something else")
        }
        let after = Session.present(next)
        expect(GameState.cardsInPile(after, foundations->Array.getUnsafe(0)))->toEqual(
          kingToAce(Spades),
        )
        expect(GameState.cardsInPile(after, cascade(0)))->toEqual([])
        expect(GameState.cardsInPile(after, stock))->toEqual([])
        expect(next.stats.moves)->toBe(1)
        expect(Session.canUndo(next))->toBe(true)
      },
    )

    test(
      "a column reorder carries its face-down count with it",
      () => {
        let state = posed(~down=[1, 0], [spades([Eight, Seven]), spades([Six])])
        switch Reducer.reduce(~game=board, state, MoveColumn({from: cascade(0), to: cascade(1)})) {
        | Ok(next) =>
          expect(GameState.cardsInPile(next, cascade(1)))->toEqual(spades([Eight, Seven]))
          expect(GameState.faceDownIn(next, cascade(1)))->toBe(1)
          expect(GameState.faceDownIn(next, cascade(0)))->toBe(0)
        | Error(_) => expect("reordered")->toBe("refused")
        }
      },
    )

    test(
      "two copies of a face are two cards: lifting one leaves the other, and a name resolves to the one a hand could lift",
      () => {
        let seven = {suit: Spades, rank: Seven}
        let other = Card.nth(seven, 1)
        expect(GameState.sameCard(seven, other))->toBe(false)
        expect(GameState.sameFace(seven, other))->toBe(true)
        // One Seven face up atop the first column, the other face down under a Nine.
        let state = posed(
          ~down=[0, 1],
          [[seven], [other, {suit: Hearts, rank: Nine}], [{suit: Hearts, rank: Eight}]],
        )
        let to = Reducer.ToPile(cascade(2))
        switch Reducer.reduce(~game=board, state, Move({card: seven, to})) {
        | Ok(next) =>
          expect(GameState.cardsInPile(next, cascade(0)))->toEqual([])
          expect(GameState.cardsInPile(next, cascade(1)))->toEqual([
            other,
            {suit: Hearts, rank: Nine},
          ])
          expect(GameState.isFaceDown(next, other))->toBe(true)
        | Error(_) => expect("moved")->toBe("refused")
        }
        // A typed `7S` is a face; the board says which copy, and it's the liftable one.
        expect(Command.resolveCard(~game=board, state, seven))->toEqual(Ok(seven))
        // Both liftable is refused by name rather than guessed at.
        let both = posed([[seven], [other], [{suit: Hearts, rank: Eight}]])
        switch Command.resolveCard(~game=board, both, seven) {
        | Error(message) => expect(message->String.includes("T1, T2"))->toBe(true)
        | Ok(_) => expect("refused")->toBe("resolved")
        }
        // …and the typed move goes through the session the same way.
        let session = Session.open_(
          ~clock=() => 0.,
          ~options=Options.default,
          ~seed=None,
          board,
          state,
        )
        let (next, outcome) = Session.step(
          ~clock=() => 0.,
          session,
          Command.Dispatch(Move({card: Card.nth(seven, 1), to})),
        )
        switch outcome.change {
        | Session.Settled({moved}) => expect(moved)->toEqual([seven])
        | _ => expect("a settled move")->toBe("something else")
        }
        expect(GameState.cardsInPile(Session.present(next), cascade(0)))->toEqual([])
      },
    )

    test(
      "the slot labels name the stock too",
      () => {
        expect(Slot.labels(~game=board))->toEqual([
          "S1",
          "F1",
          "F2",
          "F3",
          "F4",
          "T1",
          "T2",
          "T3",
          "T4",
          "T5",
          "T6",
          "T7",
        ])
        expect(Slot.parse("S1"))->toEqual(Some((Game.Stock, 1)))
        expect(Slot.indexOf(~game=board, ~role=Game.Stock, ~ordinal=1))->toEqual(Some(stock))
      },
    )

    test(
      "the solver declines it rather than mis-reading a board it can't model",
      () => {
        expect(Position.ofGameState(~game=board, opening)->Option.isNone)->toBe(true)
        expect(Solver.autoplay(~game=board, opening))->toEqual(Solver.NotFreeCell)
        // Nothing on it is ever finishable by foundation moves: the foundations take
        // only what the game collects.
        expect(Reducer.canFinish(~game=board, opening))->toBe(false)
      },
    )
  })

  // Addressing piles by role: the two helpers every group-targeted query is
  // built on — the deal, auto-to-foundation, win detection, the supermove limit.
  // A little three-role board makes the ordering and the absent-role case legible
  // without leaning on FreeCell's sixteen piles (which the `freecell` describe
  // above already covers).
  describe("roles", () => {
    let rolesGame: Game.t = {
      id: "roles",
      deck: Cards.standard,
      name: "Roles",
      piles: [
        {
          role: Foundation,
          stacking: Squared,
          rule: Rules.foundation,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {
          role: FreeCell,
          stacking: Squared,
          rule: Rules.Free,
          capacity: Some(1),
          cards: [],
          faceDown: 0,
        },
        {
          role: FreeCell,
          stacking: Squared,
          rule: Rules.Free,
          capacity: Some(1),
          cards: [],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Fanned,
          rule: Rules.cascade,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
      ],
      seed: None,
      deal: None,
      runLimit: Game.Supermove,
      collect: Game.SafeCards,
    }
    // A board with only cascades, for the absent-role case.
    let cascadesOnly: Game.t = {
      ...rolesGame,
      piles: [
        {
          role: Cascade,
          stacking: Fanned,
          rule: Rules.cascade,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
      ],
    }

    test(
      "pileIndices returns the positions of every pile with a role, in board order",
      () => {
        expect(Game.pileIndices(rolesGame, Game.Foundation))->toEqual([0])
        expect(Game.pileIndices(rolesGame, Game.FreeCell))->toEqual([1, 2])
        expect(Game.pileIndices(rolesGame, Game.Cascade))->toEqual([3])
        // A role absent from a board yields no indices.
        expect(Game.pileIndices(cascadesOnly, Game.Foundation))->toEqual([])
      },
    )

    test(
      "pilesOf returns the piles with a role, in board order",
      () => {
        let cells = Game.pilesOf(rolesGame, Game.FreeCell)
        expect(cells->Array.length)->toBe(2)
        // Every returned pile is a FreeCell, and they are the capacity-1 cells.
        expect(cells->Array.every(p => p.role == Game.FreeCell))->toBe(true)
        expect(cells->Array.map(p => p.capacity))->toEqual([Some(1), Some(1)])
        // A role absent from a board yields no piles.
        expect(Game.pilesOf(cascadesOnly, Game.Foundation))->toEqual([])
      },
    )
  })
})

// The immutable game-state snapshot: where each card rests, derived from a
// board definition and read back through pure queries — no view, no behaviour.
describe("GameState", () => {
  // A hand-built board whose opening deal is written down here, so the queries are
  // read against a layout the test states outright rather than against whatever a
  // shuffle produced: two empty free cells, then two cascades opening with cards.
  let dealt: Game.t = {
    id: "dealt",
    deck: Cards.standard,
    name: "Dealt",
    piles: [
      {
        role: FreeCell,
        stacking: Squared,
        rule: Rules.Free,
        capacity: Some(1),
        cards: [],
        faceDown: 0,
      },
      {
        role: FreeCell,
        stacking: Squared,
        rule: Rules.Free,
        capacity: Some(1),
        cards: [],
        faceDown: 0,
      },
      {
        role: Cascade,
        stacking: Fanned,
        rule: Rules.cascade,
        capacity: None,
        cards: [{suit: Spades, rank: Six}, {suit: Diamonds, rank: Five}],
        faceDown: 0,
      },
      {
        role: Cascade,
        stacking: Fanned,
        rule: Rules.cascade,
        capacity: None,
        cards: [{suit: Hearts, rank: Nine}, {suit: Spades, rank: Eight}],
        faceDown: 0,
      },
    ],
    seed: None,
    deal: None,
    runLimit: Game.Supermove,
    collect: Game.SafeCards,
  }

  test("initial places each pile's dealt cards, and nothing rests loose", () => {
    let state = GameState.initial(dealt)
    expect(GameState.cardsInPile(state, 2))->toEqual([
      {suit: Spades, rank: Six},
      {suit: Diamonds, rank: Five},
    ])
    // The cells open empty, and no card rests outside a pile.
    expect(GameState.cardsInPile(state, 0))->toEqual([])
    expect(state.loose)->toEqual([])
  })

  test("cardsInPile preserves the dealt order, bottom-first", () => {
    let state = GameState.initial(dealt)
    expect(GameState.cardsInPile(state, 3))->toEqual([
      {suit: Hearts, rank: Nine},
      {suit: Spades, rank: Eight},
    ])
  })

  test("cardsInPile returns a copy, so mutating it can't corrupt the snapshot", () => {
    let state = GameState.initial(dealt)
    let cards = GameState.cardsInPile(state, 2)
    cards->Array.push({suit: Spades, rank: King})
    // the snapshot is unchanged by the caller's mutation.
    expect(Array.length(GameState.cardsInPile(state, 2)))->toBe(2)
  })

  test("topOf is the last card of a pile, None when empty or out of range", () => {
    let state = GameState.initial(dealt)
    expect(GameState.topOf(state, 2))->toEqual(Some({suit: Diamonds, rank: Five}))
    expect(GameState.topOf(state, 0))->toEqual(None) // an empty cell has no top
    expect(GameState.topOf(state, 99))->toEqual(None) // out-of-range index
  })

  test("locationOf round-trips a card to its pile and slot", () => {
    let state = GameState.initial(dealt)
    // pile 3 opens holding Hearts Nine (bottom) then Spades Eight (top).
    expect(GameState.locationOf(state, {suit: Hearts, rank: Nine}))->toEqual(
      Some(GameState.InPile(3, 0)),
    )
    expect(GameState.locationOf(state, {suit: Spades, rank: Eight}))->toEqual(
      Some(GameState.InPile(3, 1)),
    )
  })

  test("locationOf reports a card this board never dealt as None", () => {
    let state = GameState.initial(dealt)
    expect(GameState.locationOf(state, {suit: Diamonds, rank: King}))->toEqual(None)
  })

  test("every dealt card round-trips: locationOf then back through cardsInPile", () => {
    let state = GameState.initial(Game.freecell)
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

// The stackability rules: pure predicates over `rule` data, tested without
// any view.
describe("Rules", () => {
  test("suits map to their two colours", () => {
    expect(Rules.color(Hearts))->toBe(Rules.Red)
    expect(Rules.color(Diamonds))->toBe(Rules.Red)
    expect(Rules.color(Spades))->toBe(Rules.Black)
    expect(Rules.color(Clubs))->toBe(Rules.Black)
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
  // The first exercise of the `Down` direction.
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

  // A legal ordered run: the maximal tail a supermove may lift, decided
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
        expect(Rules.isCompleteRun(~deck=Cards.standard, fullRun))->toBe(true)
      },
    )

    test(
      "an empty pile is not complete",
      () => {
        expect(Rules.isCompleteRun(~deck=Cards.standard, []))->toBe(false)
      },
    )

    test(
      "a pile short of the King is not complete",
      () => {
        // Ace→Queen: twelve cards, not yet done.
        let almost = fullRun->Array.slice(~start=0, ~end=12)
        expect(Rules.isCompleteRun(~deck=Cards.standard, almost))->toBe(false)
      },
    )

    // "Complete" is read off the deck, not the 52: a short deck's run is as
    // long as *its* ranks and topped by *its* highest.
    describe(
      "a short deck",
      () => {
        // Ace→Five in two suits: five ranks, so a finished foundation is five cards
        // ending on the Five.
        let short: Cards.deck = {
          suits: [Spades, Hearts],
          ranks: [Ace, Two, Three, Four, Five],
          copies: 1,
        }
        let shortRun = short.ranks->Array.map(rank => {suit: Hearts, rank})

        test(
          "an Ace→Five run is complete for an Ace→Five deck",
          () => {
            expect(Rules.isCompleteRun(~deck=short, shortRun))->toBe(true)
          },
        )

        test(
          "the same run is not complete for the standard deck",
          () => {
            // What `~deck` is for: the same five cards are a complete run under one
            // deck and not the other, so completeness can't be a hard-coded thirteen
            // and King.
            expect(Rules.isCompleteRun(~deck=Cards.standard, shortRun))->toBe(false)
          },
        )

        test(
          "a full Ace→King run is not complete for an Ace→Five deck",
          () => {
            // Too long, and topped by a rank the deck doesn't have.
            expect(Rules.isCompleteRun(~deck=short, fullRun))->toBe(false)
          },
        )

        test(
          "a run short of the deck's highest is not complete",
          () => {
            expect(Rules.isCompleteRun(~deck=short, shortRun->Array.slice(~start=0, ~end=4)))->toBe(
              false,
            )
          },
        )
      },
    )

    // Either way up: a Spider foundation holds the run a cascade built downward.
    test(
      "a King→Ace run is complete too — a collected Spider run is the same run, upside down",
      () => {
        expect(Rules.isCompleteRun(~deck=Cards.standard, fullRun->Array.toReversed))->toBe(true)
        expect(
          Rules.isCompleteRun(
            ~deck=Cards.standard,
            fullRun->Array.toReversed->Array.slice(~start=0, ~end=12),
          ),
        )->toBe(false)
      },
    )

    test(
      "thirteen cards of two suits are not complete, however they're ordered",
      () => {
        // One suit is part of what "a complete run" means, and the only thing that
        // separates it from "thirteen cards ending on a King".
        let mixed = fullRun->Array.mapWithIndex((c, i) => i == 5 ? {...c, suit: Spades} : c)
        expect(Rules.isCompleteRun(~deck=Cards.standard, mixed))->toBe(false)
      },
    )
  })

  // Spider's two laws in one rule: any suit may land, only one suit holds together.
  describe("spiderCascade (any suit, descending)", () => {
    let eight = {suit: Spades, rank: Eight}

    test(
      "any card founds an empty pile",
      () => {
        expect(Rules.accepts(Rules.spiderCascade, {suit: Hearts, rank: Two}, None))->toBe(true)
      },
    )

    test(
      "one rank lower stacks, whatever the suit or colour",
      () => {
        expect(Rules.accepts(Rules.spiderCascade, {suit: Hearts, rank: Seven}, Some(eight)))->toBe(
          true,
        )
        expect(Rules.accepts(Rules.spiderCascade, {suit: Clubs, rank: Seven}, Some(eight)))->toBe(
          true,
        )
        expect(Rules.accepts(Rules.spiderCascade, {suit: Spades, rank: Seven}, Some(eight)))->toBe(
          true,
        )
      },
    )

    test(
      "a gap, an equal rank or an ascending one is rejected",
      () => {
        expect(Rules.accepts(Rules.spiderCascade, {suit: Hearts, rank: Six}, Some(eight)))->toBe(
          false,
        )
        expect(Rules.accepts(Rules.spiderCascade, {suit: Hearts, rank: Eight}, Some(eight)))->toBe(
          false,
        )
        expect(Rules.accepts(Rules.spiderCascade, {suit: Hearts, rank: Nine}, Some(eight)))->toBe(
          false,
        )
      },
    )

    test(
      "a run is a run only within one suit — a lawful drop of another suit ends it",
      () => {
        let spades = [Eight, Seven, Six]->Array.map(rank => {suit: Spades, rank})
        expect(Rules.isRun(Rules.spiderCascade, spades))->toBe(true)
        // ♥7 may land on ♠8 (`accepts`), and the pair is still not a run (`isRun`): the
        // two questions a rule answers, answered differently.
        let mixed = [eight, {suit: Hearts, rank: Seven}]
        expect(Rules.accepts(Rules.spiderCascade, {suit: Hearts, rank: Seven}, Some(eight)))->toBe(
          true,
        )
        expect(Rules.isRun(Rules.spiderCascade, mixed))->toBe(false)
        // The step still has to be one rank: a same-suit gap is no run either.
        expect(Rules.isRun(Rules.spiderCascade, [eight, {suit: Spades, rank: Six}]))->toBe(false)
      },
    )
  })

  describe("Sealed", () => {
    test(
      "accepts nothing, empty or not",
      () => {
        expect(Rules.accepts(Rules.Sealed, {suit: Spades, rank: King}, None))->toBe(false)
        expect(
          Rules.accepts(
            Rules.Sealed,
            {suit: Spades, rank: Queen},
            Some({suit: Spades, rank: King}),
          ),
        )->toBe(false)
      },
    )

    test(
      "holds no run the hand may lift, not even a single card",
      () => {
        expect(Rules.isRun(Rules.Sealed, [{suit: Spades, rank: Ace}]))->toBe(false)
        expect(Rules.isRun(Rules.Sealed, []))->toBe(false)
      },
    )
  })
})

// The action variant + pure reducer: transitions `GameState` and enforces
// the rules, tested without any view. The load-bearing roadmap principle —
// immutable state + action + pure reducer, illegal actions rejected — as tests.
describe("Reducer", () => {
  // A tiny hand-built board so the tests own their setup: a foundation (Ace-only,
  // same-suit ascending) at pile 0 and a cascade (alternating colour, descending)
  // at pile 1, both opening empty. Everything the moves below reach for is parked
  // alone on a permissive staging column of its own (piles 2 up), so every card is
  // present *and* liftable — a rejection is then the destination's *rule* refusing
  // it, never a missing or buried card.
  let staged = [
    {suit: Hearts, rank: Ace},
    {suit: Hearts, rank: Two},
    {suit: Hearts, rank: Three},
    {suit: Diamonds, rank: Two},
    {suit: Spades, rank: Ace},
    {suit: Spades, rank: Ten},
    {suit: Hearts, rank: Jack},
  ]
  let game: Game.t = {
    id: "test",
    deck: Cards.standard,
    name: "Test",
    piles: [
      (
        {
          role: Foundation,
          stacking: Squared,
          rule: Rules.foundation,
          capacity: None,
          cards: [],
          faceDown: 0,
        }: Game.pile
      ),
      {
        role: Cascade,
        stacking: Fanned,
        rule: Rules.cascade,
        capacity: None,
        cards: [],
        faceDown: 0,
      },
    ]->Array.concat(
      staged->Array.map((card): Game.pile => {
        role: Cascade,
        stacking: Squared,
        rule: Rules.Free,
        capacity: None,
        cards: [card],
        faceDown: 0,
      }),
    ),
    seed: None,
    deal: None,
    runLimit: Game.Supermove,
    collect: Game.SafeCards,
  }
  // The staging column a card opens on, so a test can name where it started.
  let stagedAt = (card: Card.card) => 2 + staged->Array.findIndex(c => GameState.sameCard(c, card))

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
      // the card is lifted off its staging column…
      expect(GameState.cardsInPile(next, stagedAt({suit: Hearts, rank: Ace})))->toEqual([])
      // …and the input snapshot is untouched: a fresh value was returned, with
      // the card still resting where it began and the foundation still empty.
      expect(GameState.topOf(state, 0))->toEqual(None)
      expect(GameState.locationOf(state, {suit: Hearts, rank: Ace}))->toEqual(
        Some(GameState.InPile(stagedAt({suit: Hearts, rank: Ace}), 0)),
      )
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
    // Hearts Two onto the empty foundation is rejected; the cascade (AnyCard)
    // would take it, proving the empty-pile rule is per-pile.
    let state = fresh()
    expect(
      Reducer.reduce(~game, state, Move({card: {suit: Hearts, rank: Two}, to: ToPile(0)})),
    )->toEqual(Error(Reducer.Rejected))
  })

  test("ascending onto a descending pile is rejected (wrong direction)", () => {
    // Cascade founded with Spades Ten; a red Jack is the opposite colour but one
    // rank *higher* — a cascade only descends, so the ascending step is rejected.
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
      Reducer.reduce(~game, afterTen, Move({card: {suit: Hearts, rank: Jack}, to: ToPile(1)})),
    )->toEqual(Error(Reducer.Rejected))
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

  test("GameState.equal tells a no-op re-drop from a real move", () => {
    let state = fresh()
    // The identity re-drop the reducer returns is `equal` to the state it started
    // from — the signal a driver reads to skip the undo record for a no-op.
    switch Reducer.reduce(~game, state, Move({card: {suit: Hearts, rank: Ace}, to: ToPile(0)})) {
    | Ok(afterAce) =>
      expect(GameState.equal(state, afterAce))->toBe(false) // a real move changed the board
      switch Reducer.reduce(
        ~game,
        afterAce,
        Move({card: {suit: Hearts, rank: Ace}, to: ToPile(0)}),
      ) {
      | Ok(noOp) => expect(GameState.equal(afterAce, noOp))->toBe(true) // the no-op didn't
      | Error(_) => expect(true)->toBe(false)
      }
    | Error(_) => expect(true)->toBe(false)
    }
  })

  test("a completed foundation reports via Rules.isCompleteRun", () => {
    // Park a whole Hearts Ace→King run one card per staging column, then stack it
    // onto the foundation via the reducer; the finished pile is a complete run.
    let heartsRun =
      [Ace, Two, Three, Four, Five, Six, Seven, Eight, Nine, Ten, Jack, Queen, King]->Array.map(
        rank => {suit: Hearts, rank},
      )
    let runGame: Game.t = {
      ...game,
      piles: [
        (
          {
            role: Foundation,
            stacking: Squared,
            rule: Rules.foundation,
            capacity: None,
            cards: [],
            faceDown: 0,
          }: Game.pile
        ),
      ]->Array.concat(
        heartsRun->Array.map(
          (card): Game.pile => {
            role: Cascade,
            stacking: Squared,
            rule: Rules.Free,
            capacity: None,
            cards: [card],
            faceDown: 0,
          },
        ),
      ),
    }
    let state = ref(GameState.initial(runGame))
    heartsRun->Array.forEach(
      card =>
        switch Reducer.reduce(~game=runGame, state.contents, Move({card, to: ToPile(0)})) {
        | Ok(next) => state := next
        | Error(_) => ()
        },
    )
    expect(GameState.cardsInPile(state.contents, 0)->Array.length)->toBe(13)
    expect(Rules.isCompleteRun(~deck=runGame.deck, GameState.cardsInPile(state.contents, 0)))->toBe(
      true,
    )
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

  // Pile capacity → free cells: a capped `Free` pile holds exactly one
  // card. A tiny board of one capacity-1 cell (pile 0) beside an uncapped `Free`
  // pile (pile 1), with two cards each parked alone on a column of their own
  // (piles 2 and 3) so both are liftable.
  describe("capacity", () => {
    let capGame: Game.t = {
      id: "cap",
      deck: Cards.standard,
      name: "Cap",
      piles: [
        {
          role: FreeCell,
          stacking: Squared,
          rule: Rules.Free,
          capacity: Some(1),
          cards: [],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Squared,
          rule: Rules.Free,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Squared,
          rule: Rules.Free,
          capacity: None,
          cards: [{suit: Spades, rank: Ace}],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Squared,
          rule: Rules.Free,
          capacity: None,
          cards: [{suit: Hearts, rank: King}],
          faceDown: 0,
        },
      ],
      seed: None,
      deal: None,
      runLimit: Game.Supermove,
      collect: Game.SafeCards,
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
        // The failed drop changed nothing: the King is still on its own column, the
        // cell still holds only the Ace.
        expect(GameState.locationOf(filled, {suit: Hearts, rank: King}))->toEqual(
          Some(GameState.InPile(3, 0)),
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
        // Pile 1 is uncapped, so both staged cards stack onto it — no PileFull.
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

  // Auto-move to foundation: `foundationTarget` finds the foundation a card
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
        // All cascades — no Foundation pile to send a card to.
        let noFoundations: Game.t = {
          ...game,
          piles: [
            {
              role: Cascade,
              stacking: Fanned,
              rule: Rules.cascade,
              capacity: None,
              cards: [{suit: Spades, rank: Ace}],
              faceDown: 0,
            },
          ],
        }
        let state = GameState.initial(noFoundations)
        expect(
          Reducer.foundationTarget(~game=noFoundations, state, {suit: Spades, rank: Ace}),
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
        // The Ace is buried in the deal, and a buried card doesn't move (`isFree`) —
        // so pose it home directly rather than scripting a move no hand could make.
        // What's under test is which foundation *takes* a card, not how it got there.
        let afterAce = Reducer.placeOnPile(state, {suit: Spades, rank: Ace}, first)
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

  // The single-card move query: `validMoves` lists every legal destination
  // for one card, role-tagged, built on the same `canDrop` a hand-drag consults. A
  // little four-pile board covers all three roles at once — a foundation, a free
  // cell, and two cascades — so one movable card can offer a move of each kind.
  describe("validMoves", () => {
    let vmGame: Game.t = {
      id: "vm",
      deck: Cards.standard,
      name: "VM",
      piles: [
        {
          role: Foundation,
          stacking: Squared,
          rule: Rules.foundation,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {
          role: FreeCell,
          stacking: Squared,
          rule: Rules.Free,
          capacity: Some(1),
          cards: [],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Fanned,
          rule: Rules.cascade,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Fanned,
          rule: Rules.cascade,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
      ],
      seed: None,
      deal: None,
      runLimit: Game.Supermove,
      collect: Game.SafeCards,
    }
    // A hand-built snapshot from the four piles' contents, so a test can pose any
    // board it likes.
    let stateOf = (piles): GameState.t => GameState.faceUp(piles)

    test(
      "a buried card has no moves",
      () => {
        // The 2♥ rests atop the A♠ in a cascade (a legal build-down), so the A♠ is
        // buried — not the top of its pile — and can move nowhere.
        let state = stateOf([[], [], [{suit: Spades, rank: Ace}, {suit: Hearts, rank: Two}], []])
        expect(Reducer.validMoves(~game=vmGame, state, {suit: Spades, rank: Ace}))->toEqual([])
      },
    )

    test(
      "a card not in play has no moves",
      () => {
        let state = stateOf([[], [], [], []])
        expect(Reducer.validMoves(~game=vmGame, state, {suit: Spades, rank: Ace}))->toEqual([])
      },
    )

    test(
      "the top of a cascade lists every legal cell, cascade and foundation, role-tagged",
      () => {
        // 2♠ (black) tops its own cascade (pile 3). It can go home onto the A♠
        // foundation, park in the empty free cell, and build down onto the 3♦ (red) in
        // the other cascade — one destination of each role.
        let state = stateOf([
          [{suit: Spades, rank: Ace}], // foundation, ready for the 2♠
          [], // empty free cell
          [{suit: Diamonds, rank: Three}], // cascade: black 2 builds down onto red 3
          [{suit: Spades, rank: Two}], // the card under test, atop its own cascade
        ])
        expect(Reducer.validMoves(~game=vmGame, state, {suit: Spades, rank: Two}))->toEqual([
          {Reducer.to: 0, role: Game.Foundation},
          {Reducer.to: 1, role: Game.FreeCell},
          {Reducer.to: 2, role: Game.Cascade},
        ])
        // The card's *own* pile (3) never appears — an identity re-drop isn't a move.
      },
    )

    test(
      "an already-home card excludes its own pile — and here has nowhere else to go",
      () => {
        // A♠ rests home on the foundation (pile 0). The one pile that would accept it —
        // that same foundation — is its own, so it's excluded (an identity re-drop
        // isn't a move). Every other pile refuses: the free cell is occupied (full),
        // and an Ace can never build *down* onto a non-empty cascade (nothing is a rank
        // lower). So a card already home lists no moves.
        let state = stateOf([
          [{suit: Spades, rank: Ace}], // A♠ home — its own foundation, excluded
          [{suit: Diamonds, rank: Five}], // free cell full — no room
          [{suit: Hearts, rank: King}], // non-empty cascade — no Ace builds down
          [{suit: Clubs, rank: Queen}], // non-empty cascade — no Ace builds down
        ])
        expect(Reducer.validMoves(~game=vmGame, state, {suit: Spades, rank: Ace}))->toEqual([])
      },
    )

    test(
      "the first foundation move is exactly the send-home target",
      () => {
        // The property the double-tap send-home now routes through: taking the first
        // `Foundation` move in `validMoves` lands on the very pile `foundationTarget`
        // picks. On a two-foundation board (both empty, so both accept an Ace) with a
        // lone A♠ topping a column of its own — `validMoves` lists both foundations in
        // board order, and its first is what `foundationTarget` returns.
        let twoFoundations: Game.t = {
          id: "2f",
          deck: Cards.standard,
          name: "2F",
          piles: [
            {
              role: Foundation,
              stacking: Squared,
              rule: Rules.foundation,
              capacity: None,
              cards: [],
              faceDown: 0,
            },
            {
              role: Foundation,
              stacking: Squared,
              rule: Rules.foundation,
              capacity: None,
              cards: [],
              faceDown: 0,
            },
            {
              role: Cascade,
              stacking: Fanned,
              rule: Rules.cascade,
              capacity: None,
              cards: [{suit: Spades, rank: Ace}],
              faceDown: 0,
            },
          ],
          seed: None,
          deal: None,
          runLimit: Game.Supermove,
          collect: Game.SafeCards,
        }
        let state = GameState.initial(twoFoundations)
        // Both empty foundations accept the Ace, so there are two foundation moves…
        let foundationMoves =
          Reducer.validMoves(~game=twoFoundations, state, {suit: Spades, rank: Ace})->Array.filter(
            m => m.role == Game.Foundation,
          )
        expect(foundationMoves)->toEqual([
          {Reducer.to: 0, role: Game.Foundation},
          {Reducer.to: 1, role: Game.Foundation},
        ])
        // …and taking the first matches the send-home target exactly.
        let firstFoundation = foundationMoves->Array.get(0)->Option.map(m => m.to)
        expect(firstFoundation)->toEqual(
          Reducer.foundationTarget(~game=twoFoundations, state, {suit: Spades, rank: Ace}),
        )
      },
    )
  })

  // Safe auto-collect: `isSafeToCollect` (accepted *and* safe) and the
  // `autoCollect` fixpoint that sends every safe card home. Exercised on a little
  // four-foundation board — one foundation per suit, plus a Free cascade and a free
  // cell to hold candidate cards — so the opposite-colour safe rule is testable by
  // hand-setting the foundations.
  describe("autoCollect", () => {
    let acGame: Game.t = {
      id: "ac",
      deck: Cards.standard,
      name: "AC",
      piles: [
        {
          role: Foundation,
          stacking: Squared,
          rule: Rules.foundation,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {
          role: Foundation,
          stacking: Squared,
          rule: Rules.foundation,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {
          role: Foundation,
          stacking: Squared,
          rule: Rules.foundation,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {
          role: Foundation,
          stacking: Squared,
          rule: Rules.foundation,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {role: Cascade, stacking: Fanned, rule: Rules.Free, capacity: None, cards: [], faceDown: 0},
        {role: Cascade, stacking: Fanned, rule: Rules.Free, capacity: None, cards: [], faceDown: 0},
      ],
      seed: None,
      deal: None,
      runLimit: Game.Supermove,
      collect: Game.SafeCards,
    }
    // A hand-built snapshot from the six piles' contents (foundations 0–3, then two
    // Free cascades 4–5), so a test can pose any foundation heights it likes.
    let stateOf = (piles): GameState.t => GameState.faceUp(piles)

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
        // All cascades and no foundation — nothing is ever safe to collect.
        let noFoundations: Game.t = {
          ...acGame,
          piles: acGame.piles->Array.filter(p => p.role != Game.Foundation),
        }
        let state = stateOf([[{suit: Spades, rank: Ace}], []])
        let (settled, moved) = Reducer.autoCollect(~game=noFoundations, state)
        expect(moved)->toEqual([])
        expect(settled)->toEqual(state)
      },
    )
  })

  // The end-game finish sweep: `canFinish` (drainable to a win by
  // foundation moves alone?) and `finishSequence` (the ordered drain that
  // completes it). Exercised on a little FreeCell-shaped board — four same-suit
  // foundations then eight `Rules.cascade` columns, cards confined to piles — so a
  // test can pose exact endgame tails by hand.
  describe("canFinish / finishSequence", () => {
    let finGame: Game.t = {
      id: "fin",
      deck: Cards.standard,
      name: "FIN",
      piles: [0, 1, 2, 3]
      ->Array.map(
        (_): Game.pile => {
          role: Foundation,
          stacking: Squared,
          rule: Rules.foundation,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
      )
      ->Array.concat(
        [0, 1, 2, 3, 4, 5, 6, 7]->Array.map(
          (_): Game.pile => {
            role: Cascade,
            stacking: Fanned,
            rule: Rules.cascade,
            capacity: None,
            cards: [],
            faceDown: 0,
          },
        ),
      ),
      seed: None,
      deal: None,
      runLimit: Game.Supermove,
      collect: Game.SafeCards,
    }
    // A snapshot from four foundation runs then the cascade contents, padded to the
    // board's eight cascades so the pile count always lines up.
    let stateOf = (foundations, cascades): GameState.t => {
      let cs = cascades->Array.copy
      while Array.length(cs) < 8 {
        cs->Array.push([])
      }
      GameState.faceUp(foundations->Array.concat(cs))
    }
    // A whole suit as a descending cascade King→Ace (bottom-first), so its top is
    // the Ace — a column that drains completely by foundation moves alone.
    let fullSuit = suit => Cards.ranks->Array.toReversed->Array.map(rank => {suit, rank})

    test(
      "true on a trivially drainable board; finishSequence sweeps every card home",
      () => {
        // Four empty foundations and one full descending suit per cascade — every
        // top is the next card its foundation wants, so the whole board drains.
        let state = stateOf([[], [], [], []], Cards.suits->Array.map(fullSuit))
        expect(Reducer.canFinish(~game=finGame, state))->toBe(true)
        let (settled, moved) = Reducer.finishSequence(~game=finGame, state)
        expect(GameState.hasWon(finGame, settled))->toBe(true)
        expect(Array.length(moved))->toBe(52)
      },
    )

    test(
      "true on the trapped ♠6-over-♥3 tail that safe auto-collect stalls on",
      () => {
        // The scenario the issue calls out: foundations ♠5/♣5/♥2/♦2 with ♠6 sitting
        // on ♥3. Built over the real FreeCell board, so it's a genuine 52-card tail.
        let state = Scenario.freecellFinish(Game.freecell)
        // The finish rule sees it's home free and drains it to a win…
        expect(Reducer.canFinish(~game=Game.freecell, state))->toBe(true)
        let (settled, _moved) = Reducer.finishSequence(~game=Game.freecell, state)
        expect(GameState.hasWon(Game.freecell, settled))->toBe(true)
        // …but the conservative safe rule jams: ♠6 is accepted yet not safe (reds
        // at the Two), trapping ♥3, so auto-collect alone can never complete it.
        let (acSettled, _acMoved) = Reducer.autoCollect(~game=Game.freecell, state)
        expect(GameState.hasWon(Game.freecell, acSettled))->toBe(false)
      },
    )

    test(
      "false when a card genuinely needs a tableau move first",
      () => {
        // Three suits drain, but spades buries its Ace under its Two (…,3,A,2 — the
        // Two on top), so no foundation move can reach the Ace: the board can't be
        // finished by foundation moves alone until a tableau move frees it.
        let spadesStuck =
          [King, Queen, Jack, Ten, Nine, Eight, Seven, Six, Five, Four, Three, Ace, Two]->Array.map(
            rank => {suit: Spades, rank},
          )
        let state = stateOf(
          [[], [], [], []],
          [spadesStuck, fullSuit(Hearts), fullSuit(Diamonds), fullSuit(Clubs)],
        )
        expect(Reducer.canFinish(~game=finGame, state))->toBe(false)
        // The drain still plays what it can (the three free suits) but stops short of
        // the win rather than looping forever.
        let (settled, _moved) = Reducer.finishSequence(~game=finGame, state)
        expect(GameState.hasWon(finGame, settled))->toBe(false)
      },
    )

    test(
      "a board with no foundations is never finishable",
      () => {
        // The same board with its four foundations dropped: the drain wins nothing,
        // so `hasWon`'s non-empty guard keeps it un-finishable.
        let noFoundations: Game.t = {
          ...finGame,
          piles: finGame.piles->Array.filter(p => p.role != Game.Foundation),
        }
        let state = GameState.faceUp(Cards.suits->Array.map(fullSuit))
        expect(Reducer.canFinish(~game=noFoundations, state))->toBe(false)
      },
    )
  })

  // The supermove: a multi-card `MoveRun` and its `(1 + free cells) × 2 ^
  // (empty columns)` limit. A little FreeCell-shaped board — two capacity-1 free
  // cells then four `Rules.cascade` columns, cards confined to piles — lets the
  // tests pose exact free-cell/empty-column combinations by hand.
  describe("supermove", () => {
    let smGame: Game.t = {
      id: "sm",
      deck: Cards.standard,
      name: "SM",
      piles: [
        {
          role: FreeCell,
          stacking: Squared,
          rule: Rules.Free,
          capacity: Some(1),
          cards: [],
          faceDown: 0,
        },
        {
          role: FreeCell,
          stacking: Squared,
          rule: Rules.Free,
          capacity: Some(1),
          cards: [],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Fanned,
          rule: Rules.cascade,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Fanned,
          rule: Rules.cascade,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Fanned,
          rule: Rules.cascade,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Fanned,
          rule: Rules.cascade,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
      ],
      seed: None,
      deal: None,
      runLimit: Game.Supermove,
      collect: Game.SafeCards,
    }
    // A distinct single-card filler, so "occupied" piles hold real, unique cards.
    let f = i => [Cards.all->Array.getUnsafe(i)]
    // A hand-built snapshot from the six piles' contents (cells 0–1, cascades 2–5).
    let stateOf = (piles): GameState.t => GameState.faceUp(piles)

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
          "a multi-card run onto a free cell is refused — a cell holds one card",
          () => {
            // The run is legal and well within the supermove limit, but a free cell
            // (capacity 1) can't hold two cards. The drop bounces with PileFull — the
            // count-aware refusal, not RunTooLong — for an empty cell and an
            // occupied one alike, and the shared `canMoveRun` query agrees so the
            // view's drop highlight refuses too.
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
      },
    )
  })

  // What a move may *lift*. Every other check in the reducer is about where a card is
  // going; these are about whether it was the player's to pick up in the first place.
  // A pile is a stack, so the cards resting on a card hold it down — naming a buried
  // card names a move no hand could make, and a run has to be lying on the board the
  // way the move claims to lift it. The view enforces this by only making liftable
  // cards draggable; a typed command (`move QH KC`) has no gesture behind it, so the
  // reducer is where the rule has to hold for both front ends.
  describe("lifting", () => {
    let qs = {suit: Spades, rank: Queen}
    let jh = {suit: Hearts, rank: Jack}
    let ts = {suit: Spades, rank: Ten}
    let kh = {suit: Hearts, rank: King}
    let qc = {suit: Clubs, rank: Queen}
    let fc = {suit: Clubs, rank: Four}
    // Two free cells then four cascades — enough empties that the supermove limit is
    // never the reason a run bounces.
    let liftGame: Game.t = {
      id: "lift",
      deck: Cards.standard,
      name: "Lift",
      piles: [
        {
          role: FreeCell,
          stacking: Squared,
          rule: Rules.Free,
          capacity: Some(1),
          cards: [],
          faceDown: 0,
        },
        {
          role: FreeCell,
          stacking: Squared,
          rule: Rules.Free,
          capacity: Some(1),
          cards: [],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Fanned,
          rule: Rules.cascade,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Fanned,
          rule: Rules.cascade,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Fanned,
          rule: Rules.cascade,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
        {
          role: Cascade,
          stacking: Fanned,
          rule: Rules.cascade,
          capacity: None,
          cards: [],
          faceDown: 0,
        },
      ],
      seed: None,
      deal: None,
      runLimit: Game.Supermove,
      collect: Game.SafeCards,
    }
    let stateOf = (piles): GameState.t => GameState.faceUp(piles)

    test(
      "a buried card is refused — the cards on it hold it down",
      () => {
        // Q♠ lies under the J♥ built onto it; K♥ tops another cascade and would take
        // the Q♠ gladly. The *destination* is willing, so buriedness is the only
        // thing refusing the move — and `canDrop` agreeing proves it.
        let buried = stateOf([[], [], [qs, jh], [kh], [], []])
        expect(Reducer.canDrop(~game=liftGame, buried, qs, ~onto=3))->toBe(true)
        expect(Reducer.reduce(~game=liftGame, buried, Move({card: qs, to: ToPile(3)})))->toEqual(
          Error(Reducer.CardBuried),
        )
        // …and nothing was pulled out from under the J♥.
        expect(GameState.cardsInPile(buried, 2))->toEqual([qs, jh])

        // Uncover the Q♠ and the very same move plays.
        let free = stateOf([[], [], [qs], [kh], [], []])
        switch Reducer.reduce(~game=liftGame, free, Move({card: qs, to: ToPile(3)})) {
        | Ok(next) =>
          expect(GameState.cardsInPile(next, 3))->toEqual([kh, qs])
          expect(GameState.cardsInPile(next, 2))->toEqual([])
        | Error(_) => expect(true)->toBe(false)
        }
      },
    )

    test(
      "buriedness is judged before the destination, wherever the card was headed",
      () => {
        // An empty free cell takes any single card, so the cell is willing — and the
        // Q♠ still can't be pulled out from under the J♥.
        let buried = stateOf([[], [], [qs, jh], [], [], []])
        expect(Reducer.reduce(~game=liftGame, buried, Move({card: qs, to: ToPile(0)})))->toEqual(
          Error(Reducer.CardBuried),
        )
        // The card on top of it is free, and goes.
        switch Reducer.reduce(~game=liftGame, buried, Move({card: jh, to: ToPile(0)})) {
        | Ok(next) =>
          expect(GameState.cardsInPile(next, 0))->toEqual([jh])
          expect(GameState.cardsInPile(next, 2))->toEqual([qs])
        | Error(_) => expect(true)->toBe(false)
        }
      },
    )

    test(
      "a run gathered from two piles isn't a supermove",
      () => {
        // J♥ tops one cascade and 10♠ another. Read as a sequence they're a perfect
        // run, and the Q♣ would take them — but they aren't lying together, so
        // moving them would be a teleport rather than a supermove.
        let scattered = stateOf([[], [], [jh], [ts], [qc], []])
        expect(Rules.isRun(Rules.cascade, [jh, ts]))->toBe(true)
        expect(Reducer.maxSupermove(~game=liftGame, scattered, ~ignoring=4) >= 2)->toBe(true)
        expect(
          Reducer.reduce(~game=liftGame, scattered, MoveRun({cards: [jh, ts], to: ToPile(4)})),
        )->toEqual(Error(Reducer.NotASpan))
        // The view's hover highlight reads the same query, so it refuses too.
        expect(Reducer.canMoveRun(~game=liftGame, scattered, [jh, ts], ~onto=4))->toBe(false)
      },
    )

    test(
      "a run taken from under the cards covering it isn't a supermove",
      () => {
        // The J♥-10♠ run sits in the middle of its pile, with a 4♣ parked on top of
        // it. Lifting the run would leave the 4♣ hanging in mid-air.
        let covered = stateOf([[], [], [jh, ts, fc], [], [qc], []])
        expect(
          Reducer.reduce(~game=liftGame, covered, MoveRun({cards: [jh, ts], to: ToPile(4)})),
        )->toEqual(Error(Reducer.NotASpan))
        expect(Reducer.canMoveRun(~game=liftGame, covered, [jh, ts], ~onto=4))->toBe(false)
      },
    )

    test(
      "the run showing at the top of a pile still moves as one",
      () => {
        // The same two cards, now the tail of their pile with nothing on them: the
        // ordinary supermove, unaffected by the span check.
        let span = stateOf([[], [], [fc, jh, ts], [], [qc], []])
        expect(Reducer.canMoveRun(~game=liftGame, span, [jh, ts], ~onto=4))->toBe(true)
        switch Reducer.reduce(~game=liftGame, span, MoveRun({cards: [jh, ts], to: ToPile(4)})) {
        | Ok(next) =>
          expect(GameState.cardsInPile(next, 4))->toEqual([qc, jh, ts])
          expect(GameState.cardsInPile(next, 2))->toEqual([fc])
        | Error(_) => expect(true)->toBe(false)
        }
      },
    )
  })

  // Column reorder: `MoveColumn` pulls the cascade at `from` out and
  // reinserts it at `to`, the rest sliding over (insert-and-shift, not a swap). A
  // little board — two free cells then two foundations then four cascades, each
  // cascade opening with one distinct marker card so a permutation is legible —
  // lets the reorder be checked column by column.
  describe("MoveColumn", () => {
    let ks = {suit: Spades, rank: King}
    let qh = {suit: Hearts, rank: Queen}
    let js = {suit: Spades, rank: Jack}
    let th = {suit: Hearts, rank: Ten}
    let mcGame: Game.t = {
      id: "mc",
      deck: Cards.standard,
      name: "MC",
      piles: [0, 1]
      ->Array.map(
        (_): Game.pile => {
          role: FreeCell,
          stacking: Squared,
          rule: Rules.Free,
          capacity: Some(1),
          cards: [],
          faceDown: 0,
        },
      )
      ->Array.concat(
        [0, 1]->Array.map(
          (_): Game.pile => {
            role: Foundation,
            stacking: Squared,
            rule: Rules.foundation,
            capacity: None,
            cards: [],
            faceDown: 0,
          },
        ),
      )
      // Cascades 4–7, each holding one distinct card so a reorder is legible.
      ->Array.concat(
        [[ks], [qh], [js], [th]]->Array.map(
          (cards): Game.pile => {
            role: Cascade,
            stacking: Fanned,
            rule: Rules.cascade,
            capacity: None,
            cards,
            faceDown: 0,
          },
        ),
      ),
      seed: None,
      deal: None,
      runLimit: Game.Supermove,
      collect: Game.SafeCards,
    }
    let fresh = () => GameState.initial(mcGame)

    test(
      "pulls a column out and reinserts it, the rest sliding over",
      () => {
        // movecol 4 7: K♠ (cascade 4) drops on the far end; the columns after it slide
        // down one — so cascade 4 becomes Q♥, 5 becomes J♠, 6 becomes T♥, 7 becomes K♠.
        switch Reducer.reduce(~game=mcGame, fresh(), MoveColumn({from: 4, to: 7})) {
        | Ok(next) =>
          expect(GameState.cardsInPile(next, 4))->toEqual([qh])
          expect(GameState.cardsInPile(next, 5))->toEqual([js])
          expect(GameState.cardsInPile(next, 6))->toEqual([th])
          expect(GameState.cardsInPile(next, 7))->toEqual([ks])
          // The free cells and foundations (0–3) are untouched — a reorder only
          // permutes the cascades.
          [0, 1, 2, 3]->Array.forEach(i => expect(GameState.cardsInPile(next, i))->toEqual([]))
        | Error(_) => expect(true)->toBe(false)
        }
      },
    )

    test(
      "reordering back the other way shifts the columns up",
      () => {
        // movecol 7 4: T♠… the reverse — T♥ (cascade 7) slots in at 4, pushing the rest
        // up one, so cascade 4 becomes T♥, 5 becomes K♠, 6 becomes Q♥, 7 becomes J♠.
        switch Reducer.reduce(~game=mcGame, fresh(), MoveColumn({from: 7, to: 4})) {
        | Ok(next) =>
          expect(GameState.cardsInPile(next, 4))->toEqual([th])
          expect(GameState.cardsInPile(next, 5))->toEqual([ks])
          expect(GameState.cardsInPile(next, 6))->toEqual([qh])
          expect(GameState.cardsInPile(next, 7))->toEqual([js])
        | Error(_) => expect(true)->toBe(false)
        }
      },
    )

    test(
      "from == to is an exact no-op",
      () => {
        let state = fresh()
        expect(Reducer.reduce(~game=mcGame, state, MoveColumn({from: 5, to: 5})))->toEqual(
          Ok(state),
        )
      },
    )

    test(
      "rejects a non-cascade target with NotAColumn",
      () => {
        // The `to` addresses a foundation (pile 2) — not reorderable.
        expect(Reducer.reduce(~game=mcGame, fresh(), MoveColumn({from: 4, to: 2})))->toEqual(
          Error(Reducer.NotAColumn),
        )
        // …and the `from` addressing a free cell (pile 0) is refused just the same.
        expect(Reducer.reduce(~game=mcGame, fresh(), MoveColumn({from: 0, to: 5})))->toEqual(
          Error(Reducer.NotAColumn),
        )
      },
    )

    test(
      "rejects an out-of-range index with NoSuchPile",
      () => {
        expect(Reducer.reduce(~game=mcGame, fresh(), MoveColumn({from: 4, to: 99})))->toEqual(
          Error(Reducer.NoSuchPile),
        )
        expect(Reducer.reduce(~game=mcGame, fresh(), MoveColumn({from: 99, to: 4})))->toEqual(
          Error(Reducer.NoSuchPile),
        )
      },
    )

    test(
      "the reducer never mutates its input snapshot",
      () => {
        let state = fresh()
        let _ = Reducer.reduce(~game=mcGame, state, MoveColumn({from: 4, to: 7}))
        // The source is untouched: cascade 4 still holds K♠ where it was dealt.
        expect(GameState.cardsInPile(state, 4))->toEqual([ks])
        expect(GameState.cardsInPile(state, 7))->toEqual([th])
      },
    )

    // The invariant the issue calls out: a reorder is purely organizational, so
    // win-state and `canFinish` are unchanged under it. Checked over the real
    // FreeCell board on the drainable ♠6-over-♥3 tail (`canFinish` true, not yet
    // won): reordering two of its eight cascades preserves both.
    test(
      "preserves win-state and canFinish (purely organizational)",
      () => {
        let state = Scenario.freecellFinish(Game.freecell)
        expect(GameState.hasWon(Game.freecell, state))->toBe(false)
        expect(Reducer.canFinish(~game=Game.freecell, state))->toBe(true)
        switch Reducer.reduce(~game=Game.freecell, state, MoveColumn({from: 8, to: 15})) {
        | Ok(reordered) =>
          expect(GameState.hasWon(Game.freecell, reordered))->toBe(false)
          expect(Reducer.canFinish(~game=Game.freecell, reordered))->toBe(true)
        | Error(_) => expect(true)->toBe(false)
        }
      },
    )
  })
})

// The deck as data: the 52-card pack, a deterministic seeded shuffle, and
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

  // What a shared deal number is a promise of. Every other test here compares the
  // shuffle with itself, which any pure function passes — rewrite the PRNG and they
  // all stay green. These compare it with the boards already out in the world, so a
  // rewrite goes red here and nowhere else. That is the signal the frozen banner in
  // `Cards.res` describes: read it before touching an expected value.
  describe("the deal-number contract", () => {
    let codes = (cards: array<card>) => cards->Array.map(CardText.format)->Array.join(" ")

    test(
      "deal 1 shuffles to the order it always has",
      () => {
        expect(codes(Cards.shuffle(~seed=1)))->toBe(
          "JS KH 6D 2D TD 8S TC 9C 5H JC QS AD TS 6H 3C AC 5S JD 8H 6S 9S 9D 4D 4C 6C 3H " ++ "5D 7D 5C QH 4H 2S 8D 9H 7H 2C KD 4S 8C 3S QC KS AS AH 7C TH 3D 2H 7S KC QD JH",
        )
      },
    )

    test(
      "deal 1 lays out the board it always has",
      () => {
        // Pinned at the board rather than the shuffle, because the board is what a
        // `?seed=` link names: this one assertion also covers the eight cascades and
        // the cells–foundations–cascades pile order. When both goldens fail the
        // permutation changed; when only this one does, the deal's shape did.
        expect(Game.freecellDeal(~seed=1).piles->Array.map(p => codes(p.cards)))->toEqual([
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "JS 5H 5S 6C 8D QC 7S",
          "KH JC JD 3H 9H KS KC",
          "6D QS 8H 5D 7H AS QD",
          "2D AD 6S 7D 2C AH JH",
          "TD TS 9S 5C KD 7C",
          "8S 6H 9D QH 4S TH",
          "TC 3C 4D 4H 8C 3D",
          "9C AC 4C 2S 3S 2H",
        ])
      },
    )
  })

  // The deck as a *parameter*: a subset of one pack, taken `copies` times, with `standard` the
  // four × thirteen everything plays with today. The same two properties the full
  // pack is pinned by — a shuffle is a permutation, and a seed reproduces it —
  // hold for a short deck too.
  describe("deck", () => {
    // Ace→Five in two suits: ten cards, half the ranks, half the suits.
    let short: Cards.deck = {
      suits: [Spades, Hearts],
      ranks: [Ace, Two, Three, Four, Five],
      copies: 1,
    }

    test(
      "standard is the full pack, and cardsOf(standard) is `all`",
      () => {
        expect(Cards.standard.suits)->toEqual(Cards.suits)
        expect(Cards.standard.ranks)->toEqual(Cards.ranks)
        expect(Cards.cardsOf(Cards.standard))->toEqual(Cards.all)
      },
    )

    test(
      "cardsOf a short deck is its suits × its ranks, each card once",
      () => {
        let cards = Cards.cardsOf(short)
        expect(Array.length(cards))->toBe(10)
        let noDupes =
          cards->Array.every(card => cards->Array.filter(c => same(c, card))->Array.length == 1)
        expect(noDupes)->toBe(true)
        // Nothing outside the deck sneaks in.
        expect(
          cards->Array.every(
            c =>
              short.suits->Array.some(s => s == c.suit) &&
                short.ranks->Array.some(r => r == c.rank),
          ),
        )->toBe(true)
      },
    )

    test(
      "cardsOf hands back a fresh array each time",
      () => {
        // `shuffle` mutates what `cardsOf` gives it, so this is what keeps a shuffle
        // from disturbing anyone else's deck.
        let a = Cards.cardsOf(short)
        a->Array.setUnsafe(0, {suit: Hearts, rank: Five})
        expect(Cards.cardsOf(short))->toEqual(Cards.cardsOf(short))
        expect((Cards.cardsOf(short)->Array.getUnsafe(0)).rank)->toEqual(Ace)
      },
    )

    test(
      "shuffling a short deck is a permutation of that deck — nothing dropped or duplicated",
      () => {
        let shuffled = Cards.shuffle(~deck=short, ~seed=42)
        let cards = Cards.cardsOf(short)
        expect(Array.length(shuffled))->toBe(Array.length(cards))
        expect(cards->Array.every(card => shuffled->Array.some(c => same(c, card))))->toBe(true)
      },
    )

    test(
      "shuffling a short deck is deterministic: the same seed reproduces the same order",
      () => {
        expect(Cards.shuffle(~deck=short, ~seed=7))->toEqual(Cards.shuffle(~deck=short, ~seed=7))
      },
    )

    test(
      "shuffle defaults to the standard deck",
      () => {
        expect(Cards.shuffle(~seed=3))->toEqual(Cards.shuffle(~deck=Cards.standard, ~seed=3))
      },
    )
  })

  // FreeCell carries the standard deck, so nothing about today's board changed.
  test("a board carries its deck", () => {
    expect(Game.freecell.deck)->toEqual(Cards.standard)
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

  describe("dealByCounts", () => {
    test(
      "deals each column its count of cards, in order, bottom-first",
      () => {
        // Seven cards by [3, 2, 2] → the first three, the next two, the last two.
        let seven =
          [Ace, Two, Three, Four, Five, Six, Seven]->Array.map(rank => {suit: Spades, rank})
        let columns = Cards.dealByCounts(~counts=[3, 2, 2], seven)
        expect(columns->Array.map(col => col->Array.map(c => c.rank)))->toEqual([
          [Ace, Two, Three],
          [Four, Five],
          [Six, Seven],
        ])
      },
    )

    test(
      "counts that don't reach the pack leave the rest undealt",
      () => {
        let seven =
          [Ace, Two, Three, Four, Five, Six, Seven]->Array.map(rank => {suit: Spades, rank})
        let columns = Cards.dealByCounts(~counts=[2, 2], seven)
        expect(columns->Array.map(col => col->Array.map(c => c.rank)))->toEqual([
          [Ace, Two],
          [Three, Four],
        ])
      },
    )

    test(
      "a deck taken twice is every card twice, each copy a card of its own",
      () => {
        let twice: Cards.deck = {suits: [Spades, Hearts], ranks: Cards.ranks, copies: 2}
        let cards = Cards.cardsOf(twice)
        expect(Array.length(cards))->toBe(52)
        // The first copy of every card comes first, spelled as the plain card, and the
        // second after it, spelled as the copy — so a single-pack deck's order is
        // unchanged, and `==` tells the two apart while `sameFace` doesn't.
        expect(cards->Array.slice(~start=0, ~end=26))->toEqual(Cards.cardsOf({...twice, copies: 1}))
        expect(cards->Array.getUnsafe(26))->toEqual(Card.nth({suit: Spades, rank: Ace}, 1))
        expect(Card.copyOf(cards->Array.getUnsafe(0)))->toBe(0)
        expect(Card.copyOf(cards->Array.getUnsafe(26)))->toBe(1)
        expect(cards->Array.getUnsafe(0) == cards->Array.getUnsafe(26))->toBe(false)
        expect(GameState.sameFace(cards->Array.getUnsafe(0), cards->Array.getUnsafe(26)))->toBe(
          true,
        )
        // A shuffle of it is still a permutation: every card once.
        let shuffled = Cards.shuffle(~deck=twice, ~seed=7)
        expect(
          cards->Array.every(
            card => shuffled->Array.filter(c => GameState.sameCard(c, card))->Array.length == 1,
          ),
        )->toBe(true)
      },
    )

    test(
      "Simple Simon's counts cover the pack exactly",
      () => {
        expect(Game.simpleSimonCounts->Array.reduce(0, (a, b) => a + b))->toBe(52)
        let columns = Cards.dealByCounts(~counts=Game.simpleSimonCounts, Cards.shuffle(~seed=1))
        expect(columns->Array.map(Array.length))->toEqual(Game.simpleSimonCounts)
      },
    )
  })
})

// Driver options: the preference record threaded into the post-move step.
// Today it carries a single flag; a settings toggle will flip it later.
describe("Options", () => {
  test("defaults auto-collect on", () => {
    expect(Options.default.autoCollect)->toBe(true)
  })

  test("defaults column reorder on (our variant's house rule)", () => {
    expect(Options.default.allowColumnReorder)->toBe(true)
  })
})
