open Vitest
open Card

test("greeting returns the expected message", () => {
  expect(Core.greeting())->toBe("Hello from ReScript core!")
})

// The modelled games (#62): assert the rules the presentation layer reads back.
describe("Game", () => {
  test("the stacking demo is two piles (squared, then fanned), free, three loose", () => {
    expect(Game.stacking.piles->Array.map(p => p.stacking))->toEqual([Game.Squared, Game.Fanned])
    expect(Game.stacking.free)->toBe(true)
    expect(Game.stacking.loose)->toEqual([
      {suit: Spades, rank: Ace},
      {suit: Hearts, rank: King},
      {suit: Diamonds, rank: Seven},
    ])
  })

  test("four-fans is four fanned piles, all free", () => {
    expect(Game.fourFans.piles->Array.map(p => p.stacking))->toEqual([
      Game.Fanned,
      Game.Fanned,
      Game.Fanned,
      Game.Fanned,
    ])
    expect(Game.fourFans.free)->toBe(true)
  })

  test("every game is listed with a stable id and a non-empty name", () => {
    expect(Game.all->Array.map(g => g.id))->toEqual(["stacking", "four-fans"])
    expect(Game.all->Array.every(g => g.name != ""))->toBe(true)
  })
})
