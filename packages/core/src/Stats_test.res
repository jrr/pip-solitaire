open Vitest

// The play tally (#289). Three rules, and they only make sense together: a move
// counts, an undo doesn't count as a move (it counts as an undo), and a redo counts
// as a move again. What's pinned here is that `moves` is monotonic — the count of
// moves *made*, which no amount of undoing can walk back — since that's the property
// the whole design turns on, and the one a "just use `History.steps`" implementation
// would quietly fail.
describe("Stats", () => {
  test("a game not yet played has nothing to report", () => {
    expect(Stats.zero)->toEqual({Stats.moves: 0, undos: 0})
  })

  test("a move counts as a move", () => {
    expect(Stats.zero->Stats.move->Stats.move)->toEqual({Stats.moves: 2, undos: 0})
  })

  test("an undo counts as an undo, and never takes a move back", () => {
    let s = Stats.zero->Stats.move->Stats.move->Stats.undo
    expect(s.moves)->toBe(2) // the moves were still made
    expect(s.undos)->toBe(1)
  })

  test("a redo counts as a move again", () => {
    // Otherwise undo-then-redo is a way to play for free.
    let s = Stats.zero->Stats.move->Stats.undo->Stats.redo
    expect(s)->toEqual({Stats.moves: 2, undos: 1})
  })

  test("moves only ever go up, however much undoing happens", () => {
    let s = Stats.zero->Stats.move->Stats.undo->Stats.undo->Stats.undo
    expect(s)->toEqual({Stats.moves: 1, undos: 3})
  })

  test("the labels count in the singular at one", () => {
    expect(Stats.moveLabel(1))->toBe("1 move")
    expect(Stats.moveLabel(0))->toBe("0 moves")
    expect(Stats.moveLabel(94))->toBe("94 moves")
    expect(Stats.undoLabel(1))->toBe("1 undo")
    expect(Stats.undoLabel(3))->toBe("3 undos")
  })

  test("the summary says both numbers, zero included", () => {
    // A clean run saying "0 undos" is the boast; leaving it out would make the
    // absence of a number ambiguous with the absence of the feature.
    expect(Stats.summary({Stats.moves: 94, undos: 0}))->toBe("94 moves · 0 undos")
    expect(Stats.summary({Stats.moves: 1, undos: 1}))->toBe("1 move · 1 undo")
  })
})
