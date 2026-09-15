// The facts the info screen shows, read off the real games rather than off a fixture:
// these are claims about FreeCell and Simple Simon, and a fixture would only pin that
// the arithmetic in `GameInfo` is self-consistent.
open Vitest

describe("GameInfo.forGame", () => {
  test("counts FreeCell's board the way a player would describe it", () => {
    let info = GameInfo.forGame(Game.freecell)
    expect((info.name, info.cascades, info.cells, info.cards))->toEqual(("FreeCell", 8, 4, 52))
  })

  test("heads a board of a family with the family, the board's own name saying too much", () => {
    // "Spiderette · 2 suits" over a picker offering the packs is the pack said twice, and
    // it is not what the row a player tapped called the game either.
    expect(GameInfo.forGame(Game.spiderette).name)->toBe("Spiderette")
    expect(GameInfo.forGame(Game.mini).name)->toBe("FreeCell")
    // A game that is a game on its own has only its own name to go by.
    expect(GameInfo.forGame(Game.simpleSimon).name)->toBe("Simple Simon")
  })

  test("counts a short-deck sibling by its own deck, not by the standard pack", () => {
    // Micro FreeCell is ♠♥ Ace-to-Eight: sixteen cards, and a screen that said 52 would
    // be describing a game the player isn't playing.
    let info = GameInfo.forGame(Game.micro)
    expect((info.cascades, info.cells, info.cards))->toEqual((4, 2, 16))
  })

  test("counts the whole pack on a board that holds some of it back", () => {
    // Spiderette deals 28 cards across its cascades and leaves 24 in the stock. "52
    // cards" is what the game is played with, which is the number worth reporting;
    // counting the tableau would report the deal instead.
    expect(GameInfo.forGame(Game.spiderette).cards)->toBe(52)
  })

  test("reports no cells on a game that has none", () => {
    let info = GameInfo.forGame(Game.simpleSimon)
    expect((info.cascades, info.cells, info.cards))->toEqual((10, 0, 52))
  })

  test("sends each game to the article for the game it is a variant of", () => {
    expect(GameInfo.forGame(Game.mini).reference)->toBe("https://en.wikipedia.org/wiki/FreeCell")
    expect(GameInfo.forGame(Game.simpleSimon).reference)->toBe(
      "https://en.wikipedia.org/wiki/Simple_Simon_(solitaire)",
    )
  })

  test("still hands back a link for a game the table has never heard of", () => {
    // A game added to `Game.all` and not to the table: the info screen's link must go
    // somewhere about patience rather than nowhere at all, since a missing `href` is a
    // control that looks live and does nothing.
    expect(GameInfo.referenceFor("klondike"))->toBe("https://en.wikipedia.org/wiki/Patience_(game)")
  })
})

describe("GameInfo.numbers", () => {
  test("sets the board's numbers out as one line", () => {
    expect(GameInfo.numbers(GameInfo.forGame(Game.freecell)))->toBe(
      "8 cascades · 4 cells · 52 cards",
    )
  })

  test("drops a term whose count is zero rather than printing it", () => {
    // "0 cells" is a number the reader has to discard; Simple Simon simply has no cells
    // to report.
    expect(GameInfo.numbers(GameInfo.forGame(Game.simpleSimon)))->toBe("10 cascades · 52 cards")
  })

  test("says one cell rather than 1 cells", () => {
    let one: GameInfo.t = {
      id: "solo",
      name: "Solo",
      cascades: 1,
      cells: 1,
      cards: 1,
      reference: "",
      opening: [],
      previewBox: 0.5,
    }
    expect(GameInfo.numbers(one))->toBe("1 cascade · 1 cell · 1 card")
  })

  test("carries the board it was read off, as dealt", () => {
    // The picture on the screen is drawn from these piles, so they are the facts
    // rather than a lookup the screen makes: 28 of a Spiderette's cards across its
    // seven columns and 24 in the stock, face down.
    let info = GameInfo.forGame(Game.spiderette)
    let dealt =
      info.opening->Array.map(p => Array.length(p.cards))->Array.reduce(0, (a, b) => a + b)
    expect(dealt)->toBe(52)
    expect(
      info.opening->Array.find(p => p.role == Game.Stock)->Option.map(p => p.faceDown),
    )->toEqual(Some(24))
  })

  test("gives a whole family one box to draw its boards in", () => {
    // The reason the field exists: the info screen's picker redraws the still, and a
    // still that came out whatever height its board ran to would move the numbers, the
    // picker and the link down the panel every time one was tapped.
    let box = game => GameInfo.forGame(game).previewBox
    expect((box(Game.mini), box(Game.micro)))->toEqual((box(Game.freecell), box(Game.freecell)))
    expect(box(Game.spiderette1))->toBe(box(Game.spiderette4))
  })

  test("cuts that box for the flattest board of the family, and fits the rest into it", () => {
    // Standard FreeCell is the flattest of the three sizes, so it is the board that
    // fills the box on both axes; Micro is taller-shaped and is drawn smaller inside it,
    // which is also the honest picture of a sixteen-card game.
    expect(GameInfo.forGame(Game.micro).previewBox)->toBe(GameInfo.aspectOf(Game.freecell))
    expect(GameInfo.aspectOf(Game.micro) > GameInfo.aspectOf(Game.freecell))->toBe(true)
  })

  test("gives a game that is a game on its own its own shape", () => {
    // Nothing to keep still for: Simple Simon has no family, so its still is cut to fit
    // exactly.
    expect(GameInfo.forGame(Game.simpleSimon).previewBox)->toBe(GameInfo.aspectOf(Game.simpleSimon))
  })
})
