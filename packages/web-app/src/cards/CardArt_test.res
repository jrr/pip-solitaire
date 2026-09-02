// The one thing about the card a unit test can hold that a browser can't see: the
// design box and the real card have to be the same shape. `browser-tests/geometry.spec.mjs`
// pins what the board traces off `aspect`; this pins what `aspect` is the shape *of*,
// which is what lets the cascade turn a card-width into a length.

open Vitest

describe("the card's shape", () => {
  test("is a poker card's, which is what makes its width in metres a fact about it", () => {
    // 2.5 × 3.5 inches. As a ratio rather than as two lengths, because the box is 120×168
    // design units and only its proportion is claimed to be the card's.
    expect(CardArt.aspect)->toBeCloseToWithin(3.5 /. 2.5, 10)
    expect(CardArt.widthMetres)->toBeCloseToWithin(2.5 *. 0.0254, 10)
  })
})
