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
    // counting the tableau would report the deal instead. The 24 is reported beside it
    // rather than instead of it.
    let info = GameInfo.forGame(Game.spiderette)
    expect((info.cards, info.stock))->toEqual((52, 24))
  })

  test("reports no stock on a board that deals its whole pack out", () => {
    expect(GameInfo.forGame(Game.freecell).stock)->toBe(0)
    expect(GameInfo.forGame(Game.simpleSimon).stock)->toBe(0)
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

// The spaces inside a term are non-breaking (see `GameInfo.count`), which is why these
// expectations are written with `\u{a0}` where a term holds a space and a plain space
// where the line may be broken: that difference is the claim.
describe("GameInfo.numbers", () => {
  test("sets the board's numbers out as one line", () => {
    expect(GameInfo.numbers(GameInfo.forGame(Game.freecell)))->toBe(
      "52\u{a0}cards · 8\u{a0}cascades · 4\u{a0}cells",
    )
  })

  test("drops a term whose count is zero rather than printing it", () => {
    // "0 cells" is a number the reader has to discard; Simple Simon simply has no cells
    // to report, and no stock either.
    expect(GameInfo.numbers(GameInfo.forGame(Game.simpleSimon)))->toBe(
      "52\u{a0}cards · 10\u{a0}cascades",
    )
  })

  test("says what part of the pack a board with a stock starts with held back", () => {
    // The pack leads, so a reader has the 52 in hand well before being told that 24 of
    // them are out of play.
    expect(GameInfo.numbers(GameInfo.forGame(Game.spiderette)))->toBe(
      "52\u{a0}cards · 7\u{a0}cascades · 24\u{a0}in\u{a0}stock",
    )
  })

  test("says one cell rather than 1 cells", () => {
    let one: GameInfo.t = {
      id: "solo",
      name: "Solo",
      cascades: 1,
      cells: 1,
      cards: 1,
      stock: 0,
      reference: "",
      opening: [],
      previewBox: 0.5,
      description: None,
    }
    expect(GameInfo.numbers(one))->toBe("1\u{a0}card · 1\u{a0}cascade · 1\u{a0}cell")
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

  test("describes a family once, so the paragraph is steady under the picker", () => {
    // Prose keyed by family rather than by board: the three sizes are one game to
    // describe, and words that changed as the picker was tapped would send a reader
    // back to look for a difference that isn't there.
    let about = game => GameInfo.forGame(game).description
    expect(about(Game.mini))->toEqual(about(Game.freecell))
    expect(about(Game.micro))->toEqual(about(Game.freecell))
    expect(about(Game.spiderette1))->toEqual(about(Game.spiderette4))
    expect(about(Game.freecell))->toEqual(GameInfo.descriptionFor("freecell"))
  })

  test("names nothing in the copy that the picker moves", () => {
    // The rule that keeps the paragraph honest as well as steady: it may say "the free
    // cells" but not "four free cells", since Mini has two. A rank named in words — King
    // through Ace — is the same rank on every board, so the copy carries no digit at all.
    let digits = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
    Game.all->Array.forEach(
      game =>
        GameInfo.forGame(game).description->Option.forEach(
          text =>
            digits->Array.forEach(
              d => expect((game.name, text->String.includes(d)))->toEqual((game.name, false)),
            ),
        ),
    )
  })

  test("has nothing to say about a game the copy has never heard of", () => {
    // No paragraph beats a paragraph about patience in general, which is the shape the
    // reference link takes for an unknown game and the wrong shape for this.
    expect(GameInfo.descriptionFor("klondike"))->toEqual(None)
  })

  test("gives a game that is a game on its own its own shape", () => {
    // Nothing to keep still for: Simple Simon has no family, so its still is cut to fit
    // exactly.
    expect(GameInfo.forGame(Game.simpleSimon).previewBox)->toBe(GameInfo.aspectOf(Game.simpleSimon))
  })
})
