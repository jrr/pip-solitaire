// The variant mark, read off the real families rather than off fixtures: these are
// claims about what a player sees on the segment, which is the whole point of the
// module.
open Vitest

let markFor = (game: Game.t) => Game.variantOf(game)->Option.getOrThrow->GameVariant.forVariant

describe("GameVariant.forVariant", () => {
  test("draws a pack as the suits in play, in the deck's own order", () => {
    // The suits alone, however many times over the deck holds each of them: all three
    // Spiderette packs are 52 cards, so the multiplier only counts back up to a total
    // every pack shares.
    expect(markFor(Game.spiderette).mark)->toEqual(GameVariant.Pips("♠♥"))
    expect(markFor(Game.spiderette1).mark)->toEqual(GameVariant.Pips("♠"))
    expect(markFor(Game.spiderette4).mark)->toEqual(GameVariant.Pips("♠♥♦♣"))
  })

  test("draws a size as the word the family gives it", () => {
    expect(markFor(Game.freecell).mark)->toEqual(GameVariant.Word("Standard"))
    expect(markFor(Game.mini).mark)->toEqual(GameVariant.Word("Mini"))
    expect(markFor(Game.micro).mark)->toEqual(GameVariant.Word("Micro"))
  })

  test("carries the same fact in words, for a control that has to be named", () => {
    expect((markFor(Game.spiderette1).noun, markFor(Game.spiderette1).name))->toEqual((
      "pack",
      "1 suit",
    ))
    expect((markFor(Game.spiderette).noun, markFor(Game.spiderette).name))->toEqual((
      "pack",
      "2 suits",
    ))
    expect((markFor(Game.micro).noun, markFor(Game.micro).name))->toEqual(("size", "Micro"))
  })

  test("reads a pack off any deck, not off a table of the packs there happen to be", () => {
    // Micro FreeCell is ♠♥ Ace-to-Eight, one pack — a deck the pips were never written
    // for, and they still describe it. It is marked by its *size* on the row, which is
    // the other half of the same point: a deck that can't tell two games apart mustn't
    // be what tells them apart.
    expect(GameVariant.pips(Game.micro.deck).mark)->toEqual(GameVariant.Pips("♠♥"))
  })
})
