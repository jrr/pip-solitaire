// The pack mark, read off the real decks rather than off fixtures: these are claims
// about what the three Spiderette packs look like on a control, which is the whole
// point of the module.
open Vitest

describe("GamePack.forDeck", () => {
  test("draws the suits in play, in the deck's own order", () => {
    expect(GamePack.forDeck(Game.spiderette.deck).suits)->toBe("♠♥")
    expect(GamePack.forDeck(Game.spiderette1.deck).suits)->toBe("♠")
    expect(GamePack.forDeck(Game.spiderette4.deck).suits)->toBe("♠♥♦♣")
  })

  test("says how many times over, and stays silent on a single pack", () => {
    // "♠♥ ×2" and "♠ ×4" are two suits and one; "♠♥♦♣ ×1" would be the standard deck
    // with a number after it that a reader has to discard.
    expect(GamePack.forDeck(Game.spiderette.deck).copies)->toEqual(Some("×2"))
    expect(GamePack.forDeck(Game.spiderette1.deck).copies)->toEqual(Some("×4"))
    expect(GamePack.forDeck(Game.spiderette4.deck).copies)->toEqual(None)
  })

  test("carries the same fact in words, for a control that has to be named", () => {
    expect(GamePack.forDeck(Game.spiderette1.deck).name)->toBe("1 suit")
    expect(GamePack.forDeck(Game.spiderette.deck).name)->toBe("2 suits")
    expect(GamePack.forDeck(Game.spiderette4.deck).name)->toBe("4 suits")
  })

  test("is a reading of any deck, not a table of the packs there happen to be", () => {
    // Micro FreeCell is ♠♥ Ace-to-Eight, one pack: a deck this was never written for,
    // and the mark still describes it.
    let mark = GamePack.forDeck(Game.micro.deck)
    expect((mark.suits, mark.copies, mark.name))->toEqual(("♠♥", None, "2 suits"))
  })
})
