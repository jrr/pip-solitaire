// Tests for the named starting scenarios (Scenario.res). The scenarios feed the
// screenshot report a fixed mid-game position, so the essential guarantee is
// that the position is *well-formed* — it holds a full deck (no card invented,
// dropped or duplicated) and lays out onto the board's roles the way the report
// expects (part-built foundations, a couple of occupied cells, the rest in the
// cascades). These lock that in so a future tweak to the heights or the deal can't
// silently produce a broken board.

open Vitest
open Card

// A pile is a legal foundation run when it's the ascending Ace-up sequence in a
// single suit — Ace, Two, Three, … with no gaps. Built by comparing against the
// canonical run of the first card's suit, so an empty pile trivially passes.
let isFoundationRun = (cards: array<card>): bool =>
  switch cards[0] {
  | None => true
  | Some(first) =>
    let expected =
      Cards.ranks
      ->Array.slice(~start=0, ~end=Array.length(cards))
      ->Array.map(rank => {suit: first.suit, rank})
    cards
    ->Array.mapWithIndex((c, i) =>
      switch expected[i] {
      | Some(e) => GameState.sameCard(c, e)
      | None => false
      }
    )
    ->Array.every(x => x)
  }

describe("Scenario", () => {
  describe("freecell midgame", () => {
    let game = Game.freecell
    let state: GameState.t = Scenario.forName(game, "midgame")->Option.getOrThrow

    test(
      "holds a full 52-card deck, every card exactly once",
      () => {
        let all = state.piles->Array.flatMap(cards => cards)
        expect(Array.length(all))->toBe(52)
        // Every card of the deck is present…
        expect(
          Cards.all->Array.every(card => all->Array.some(c => GameState.sameCard(c, card))),
        )->toBe(true)
        // …and none appears twice (a permutation, not a multiset).
        expect(
          Cards.all->Array.every(
            card => all->Array.filter(c => GameState.sameCard(c, card))->Array.length == 1,
          ),
        )->toBe(true)
      },
    )

    test(
      "opens mid-game: part-built foundations, two occupied cells, the rest in cascades",
      () => {
        let pilesFor = (role: Game.role) =>
          Game.pileIndices(game, role)->Array.map(i => state.piles->Array.getUnsafe(i))
        let foundations = pilesFor(Game.Foundation)
        let cells = pilesFor(Game.FreeCell)
        let cascades = pilesFor(Game.Cascade)

        // Every foundation is a legal ascending run, and together they're partway
        // built — some cards down, but nowhere near a finished four suits.
        expect(foundations->Array.every(isFoundationRun))->toBe(true)
        let onFoundations = foundations->Array.reduce(0, (n, p) => n + Array.length(p))
        expect(onFoundations > 0 && onFoundations < 52)->toBe(true)

        // Exactly two of the four cells are occupied, each holding a single card.
        let occupied = cells->Array.filter(p => Array.length(p) > 0)
        expect(Array.length(occupied))->toBe(2)
        expect(occupied->Array.every(p => Array.length(p) == 1))->toBe(true)

        // The bulk of the deck sits in the cascades, nothing left loose.
        expect(cascades->Array.reduce(0, (n, p) => n + Array.length(p)) > 26)->toBe(true)
        expect(Array.length(state.loose))->toBe(0)
      },
    )
  })

  describe("freecell almost-won", () => {
    let game = Game.freecell
    let state: GameState.t = Scenario.forName(game, "almost-won")->Option.getOrThrow

    test(
      "holds a full 52-card deck, every card exactly once",
      () => {
        let all = state.piles->Array.flatMap(cards => cards)
        expect(Array.length(all))->toBe(52)
        expect(
          Cards.all->Array.every(card => all->Array.some(c => GameState.sameCard(c, card))),
        )->toBe(true)
        expect(
          Cards.all->Array.every(
            card => all->Array.filter(c => GameState.sameCard(c, card))->Array.length == 1,
          ),
        )->toBe(true)
      },
    )

    test(
      "is one legal move short of a win: three suits done, one Queen-high, its King in a cell",
      () => {
        let foundations =
          Game.pileIndices(game, Game.Foundation)->Array.map(i => state.piles->Array.getUnsafe(i))
        // Three foundations are complete Ace→King runs; the fourth stops at the Queen.
        let complete = foundations->Array.filter(Rules.isCompleteRun)
        expect(Array.length(complete))->toBe(3)
        // Exactly one card sits in the free cells — the pending King — and it's a King.
        let cellCards =
          Game.pileIndices(game, Game.FreeCell)
          ->Array.map(i => state.piles->Array.getUnsafe(i))
          ->Array.flat
        expect(Array.length(cellCards))->toBe(1)
        expect((cellCards->Array.getUnsafe(0)).rank)->toEqual(King)
        // Not yet a win — the last foundation still wants its King.
        expect(GameState.hasWon(game, state))->toBe(false)
      },
    )
  })

  describe("freecell supermove", () => {
    let game = Game.freecell
    let state: GameState.t = Scenario.forName(game, "supermove")->Option.getOrThrow

    test(
      "holds a full 52-card deck, every card exactly once",
      () => {
        let all = state.piles->Array.flatMap(cards => cards)
        expect(Array.length(all))->toBe(52)
        expect(
          Cards.all->Array.every(card => all->Array.some(c => GameState.sameCard(c, card))),
        )->toBe(true)
        expect(
          Cards.all->Array.every(
            card => all->Array.filter(c => GameState.sameCard(c, card))->Array.length == 1,
          ),
        )->toBe(true)
      },
    )

    test(
      "sits a five-card movable run atop the first cascade, cells and foundations empty, one empty column",
      () => {
        let cascades = Game.pileIndices(game, Game.Cascade)
        // Free cells and foundations open empty (the free-cell term at its max), and
        // exactly one cascade is empty: the limit is (1 + 4) × 2^1 = 10.
        expect(
          Game.pileIndices(game, Game.FreeCell)->Array.every(
            i => Array.length(GameState.cardsInPile(state, i)) == 0,
          ),
        )->toBe(true)
        expect(
          Game.pileIndices(game, Game.Foundation)->Array.every(
            i => Array.length(GameState.cardsInPile(state, i)) == 0,
          ),
        )->toBe(true)
        expect(
          cascades
          ->Array.filter(i => Array.length(GameState.cardsInPile(state, i)) == 0)
          ->Array.length,
        )->toBe(1)
        expect(Reducer.maxSupermove(~game, state))->toBe(10)

        // The first cascade holds a legal five-card descending-alternating run.
        let firstCascade = cascades->Array.getUnsafe(0)
        let run = GameState.cardsInPile(state, firstCascade)
        expect(Array.length(run))->toBe(5)
        expect(Rules.isRun(Rules.cascade, run))->toBe(true)
      },
    )

    test(
      "the whole run supermoves onto the empty column — its own emptiness excluded, the cap is exactly 5",
      () => {
        let cascades = Game.pileIndices(game, Game.Cascade)
        let firstCascade = cascades->Array.getUnsafe(0)
        let run = GameState.cardsInPile(state, firstCascade)
        let emptyColumn =
          cascades
          ->Array.find(i => Array.length(GameState.cardsInPile(state, i)) == 0)
          ->Option.getOrThrow
        // Onto the empty column the cap is (1 + 4) × 2^0 = 5 — exactly the run.
        expect(Reducer.maxSupermove(~game, state, ~ignoring=emptyColumn))->toBe(5)
        switch Reducer.reduce(~game, state, MoveRun({cards: run, to: ToPile(emptyColumn)})) {
        | Ok(next) =>
          expect(GameState.cardsInPile(next, emptyColumn))->toEqual(run)
          expect(GameState.cardsInPile(next, firstCascade))->toEqual([]) // lifted off
        | Error(_) => expect(true)->toBe(false)
        }
      },
    )
  })

  test("an unknown scenario, or one that doesn't fit the board, is None", () => {
    expect(Scenario.forName(Game.freecell, "no-such-scenario"))->toEqual(None)
    // "midgame" is a FreeCell position; it doesn't apply to the stacking demo.
    expect(Scenario.forName(Game.stacking, "midgame"))->toEqual(None)
    // "almost-won" is likewise a FreeCell position only.
    expect(Scenario.forName(Game.stacking, "almost-won"))->toEqual(None)
    // "supermove" too — a FreeCell position, not applicable to the stacking demo.
    expect(Scenario.forName(Game.stacking, "supermove"))->toEqual(None)
  })
})

// Win detection (#121): every foundation complete is a win. Exercised through the
// scenarios above so the states are real positions, not hand-built shapes.
describe("hasWon", () => {
  let game = Game.freecell

  test("the opening deal is not won", () => {
    expect(GameState.hasWon(game, GameState.initial(game)))->toBe(false)
  })

  test("a mid-game position is not won", () => {
    let state = Scenario.forName(game, "midgame")->Option.getOrThrow
    expect(GameState.hasWon(game, state))->toBe(false)
  })

  test("completing the final foundation wins the game", () => {
    // From the near-won position, move the one pending King onto its (same-suit,
    // Queen-topped) foundation: that completes the fourth suit, so `hasWon` flips.
    let state = Scenario.forName(game, "almost-won")->Option.getOrThrow
    let cell =
      Game.pileIndices(game, Game.FreeCell)
      ->Array.find(i => Array.length(GameState.cardsInPile(state, i)) > 0)
      ->Option.getOrThrow
    let king = GameState.cardsInPile(state, cell)->Array.getUnsafe(0)
    let foundation =
      Game.pileIndices(game, Game.Foundation)
      ->Array.find(
        i =>
          switch GameState.topOf(state, i) {
          | Some(top) => top.suit == king.suit
          | None => false
          },
      )
      ->Option.getOrThrow
    let won = switch Reducer.reduce(~game, state, Move({card: king, to: ToPile(foundation)})) {
    | Ok(next) => next
    | Error(_) => state
    }
    expect(GameState.hasWon(game, won))->toBe(true)
  })

  test("a board with no foundations is never won", () => {
    // The stacking demo has no foundation piles, so completing its piles can't win —
    // guarding against a vacuous `every`-over-nothing win.
    expect(GameState.hasWon(Game.stacking, GameState.initial(Game.stacking)))->toBe(false)
  })
})
