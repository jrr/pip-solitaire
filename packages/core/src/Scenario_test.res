// Tests for the named starting scenarios (Scenario.res). The scenarios feed the
// screenshot report a fixed mid-game position, so the load-bearing guarantee is
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

  // The enumerable registry (`scenariosFor`) is what a picker lists — the web-app's
  // debug "states" menu — and `forName` resolves. These lock that the two agree, so
  // the menu can never offer a name the resolver rejects, or a label with no build.
  describe("scenariosFor registry", () => {
    test(
      "lists FreeCell's named states, each with a non-empty name and label",
      () => {
        let named = Scenario.scenariosFor(Game.freecell)
        expect(Array.length(named) > 0)->toBe(true)
        expect(named->Array.every(s => s.name != "" && s.label != ""))->toBe(true)
      },
    )

    test(
      "every listed name resolves through forName to the same well-formed position",
      () => {
        Scenario.scenariosFor(Game.freecell)->Array.forEach(
          s => {
            // The registry's `build` and the string-addressed `forName` are one source.
            let viaName = Scenario.forName(Game.freecell, s.name)->Option.getOrThrow
            expect(viaName)->toEqual(s.build(Game.freecell))
            // …and every position it yields is a full 52-card deck.
            expect(Array.length(viaName.piles->Array.flat))->toBe(52)
          },
        )
      },
    )

    test(
      "a board with no scenarios lists none",
      () => {
        expect(Scenario.scenariosFor(Game.stacking))->toEqual([])
      },
    )
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

// The `almost-won` scenario claims to descend from deal **264** (`named.seed`), and
// the web app leans on that claim: it's what lets a victory won from `?state=almost-won`
// hand someone a `?seed=` link that's actually true (#264). A claim like that is worth
// nothing unasserted, so this replays the line and checks where it lands.
//
// The line was found by a solver and is fixture data, not something to read: 130 moves
// as `<rank><suit>:<pile>`, using the same two-character card codes `SaveState` writes.
// What makes it a *proof* rather than a second assertion is that every move goes through
// the real `Reducer` — an illegal one fails the test rather than being skipped — and the
// end state is compared against `freecellAlmostWon` itself. Change the shuffle, the deal,
// the rules or the scenario, and this goes red instead of the app quietly sharing a link
// to a board nobody played.
let almostWonLine264 =
  "7S:0 AC:7 AH:5 QH:8 TH:1 2H:5 6C:2 3H:3 6H:10 8D:13 7S:13 3H:5 KD:0 2C:7 4H:3 5D:15 " ++
  "5S:10 6C:9 5S:2 6H:13 5S:13 4H:13 KS:2 QS:3 AD:6 6C:12 7C:11 7H:10 2D:6 6C:10 KD:9 " ++
  "QS:9 7C:0 7D:3 8H:12 7C:12 9H:0 JC:8 3C:7 KS:11 JC:2 QH:11 JC:11 TH:11 7C:1 8H:2 " ++
  "9C:11 8H:11 7C:11 4H:1 5S:2 6H:11 5S:11 4H:11 KC:1 7S:2 4S:15 4C:7 4H:5 5H:5 QS:8 " ++
  "3D:15 7S:13 KD:2 7D:9 5S:3 6C:9 6H:5 7H:5 8C:12 2S:15 JD:8 5S:10 TD:3 AS:4 2S:4 3S:4 " ++
  "3D:6 4S:4 5S:4 5D:9 6S:4 JH:15 9H:14 7C:0 8H:5 9H:5 TS:15 9C:14 TH:5 TD:11 7S:3 " ++
  "8D:14 9S:11 5C:7 7S:4 8S:4 JD:13 9S:4 TS:4 7C:14 6D:14 JS:4 QS:10 KH:0 QD:3 4D:6 " ++
  "5D:6 6C:7 6D:6 7D:6 7C:7 8C:7 8D:6 9D:6 TD:6 QS:4 9C:7 JD:6 JH:5 QC:8 TC:7 QD:6 JC:7 " ++ "KD:6 QC:7 QH:5 KH:5 KS:4 KC:0"

describe("Scenario almost-won provenance (#264)", () => {
  test("deal 264 really does play to the almost-won position", () => {
    let seed =
      Scenario.freecellScenarios
      ->Array.find(s => s.name == "almost-won")
      ->Option.flatMap(s => s.seed)
      ->Option.getOrThrow
    expect(seed)->toBe(264)

    let game = Game.freecellDeal(~seed)
    let played =
      almostWonLine264
      ->String.split(" ")
      ->Array.reduce(
        Ok(GameState.initial(game)),
        (acc, token) =>
          switch acc {
          | Error(_) => acc
          | Ok(state) =>
            switch String.split(token, ":") {
            | [code, pile] =>
              switch (SaveState.decodeCard(code), Int.fromString(pile)) {
              | (Some(card), Some(to)) =>
                switch Reducer.reduce(~game, state, Move({card, to: ToPile(to)})) {
                | Ok(next) => Ok(next)
                | Error(_) => Error("the rules rejected " ++ token)
                }
              | _ => Error("unreadable move " ++ token)
              }
            | _ => Error("unreadable move " ++ token)
            }
          },
      )

    switch played {
    | Error(why) => expect(why)->toBe("") // fail, naming the move that broke
    | Ok(state) =>
      // Every move was legal, and the board it left is the scenario, card for card.
      expect(GameState.equal(state, Scenario.freecellAlmostWon(game)))->toBe(true)
      // …and it really is one move from a win, which is the whole point of it.
      expect(GameState.hasWon(game, state))->toBe(false)
      let (finished, _moved) = Reducer.finishSequence(~game, state)
      expect(GameState.hasWon(game, finished))->toBe(true)
    }
  })

  test("the scenarios with no established deal say so", () => {
    // The claim is per-scenario and deliberately narrow: a posed layout nobody has
    // shown a line to keeps `None`, so a share button stays dark rather than guessing.
    let seedOf = name =>
      Scenario.freecellScenarios->Array.find(s => s.name == name)->Option.flatMap(s => s.seed)
    expect(seedOf("midgame"))->toBe(None)
    expect(seedOf("finish"))->toBe(None)
    expect(Scenario.seedForName(Game.freecell, "almost-won"))->toBe(Some(264))
    expect(Scenario.seedForName(Game.freecell, "no-such-scenario"))->toBe(None)
  })
})
