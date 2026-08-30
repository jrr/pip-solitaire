open Vitest

// The play tally. `moves` is the count of moves *made*, which no amount of undoing can
// walk back — the property the whole design turns on, and the one a "just use
// `History.steps`" implementation would quietly fail. `autoplays` is monotonic for a
// different reason: the victory screen withholds its Share button from a game the
// solver played, so "was this autoplayed" has to survive undoing back past every move
// the solver made.
describe("Stats", () => {
  test("a game not yet played has nothing to report", () => {
    expect(Stats.zero)->toEqual({Stats.moves: 0, undos: 0, autoplays: 0})
  })

  test("a move counts as a move", () => {
    expect(Stats.zero->Stats.move->Stats.move)->toEqual({Stats.moves: 2, undos: 0, autoplays: 0})
  })

  test("an undo counts as an undo, and never takes a move back", () => {
    let s = Stats.zero->Stats.move->Stats.move->Stats.undo
    expect(s.moves)->toBe(2) // the moves were still made
    expect(s.undos)->toBe(1)
  })

  test("a redo counts as a move again", () => {
    // Otherwise undo-then-redo is a way to play for free.
    let s = Stats.zero->Stats.move->Stats.undo->Stats.redo
    expect(s)->toEqual({Stats.moves: 2, undos: 1, autoplays: 0})
  })

  test("moves only ever go up, however much undoing happens", () => {
    let s = Stats.zero->Stats.move->Stats.undo->Stats.undo->Stats.undo
    expect(s)->toEqual({Stats.moves: 1, undos: 3, autoplays: 0})
  })

  test("an autoplay counts as an autoplay, and as nothing else", () => {
    // The moves it goes on to play are counted where every other move is — by the
    // thing that records them — so reaching for the solver is one number and the
    // moves that follow are another.
    expect(Stats.zero->Stats.autoplay)->toEqual({Stats.moves: 0, undos: 0, autoplays: 1})
  })

  test("a game stays autoplayed however far you undo back out of it", () => {
    // The property the victory screen's withheld Share button rests on.
    let s = Stats.zero->Stats.autoplay->Stats.move->Stats.move->Stats.undo->Stats.undo
    expect(Stats.usedAutoplay(s))->toBe(true)
    expect(Stats.usedAutoplay(Stats.zero->Stats.move->Stats.undo))->toBe(false)
  })

  test("the labels count in the singular at one", () => {
    expect(Stats.moveLabel(1))->toBe("1 move")
    expect(Stats.moveLabel(0))->toBe("0 moves")
    expect(Stats.moveLabel(94))->toBe("94 moves")
    expect(Stats.undoLabel(1))->toBe("1 undo")
    expect(Stats.undoLabel(3))->toBe("3 undos")
    expect(Stats.autoplayLabel(1))->toBe("1 autoplay")
    expect(Stats.autoplayLabel(2))->toBe("2 autoplays")
  })

  test("the summary says both numbers, zero included", () => {
    // A clean run saying "0 undos" is the boast; leaving it out would make the
    // absence of a number ambiguous with the absence of the feature.
    expect(Stats.summary({Stats.moves: 94, undos: 0, autoplays: 0}))->toBe("94 moves · 0 undos")
    expect(Stats.summary({Stats.moves: 1, undos: 1, autoplays: 0}))->toBe("1 move · 1 undo")
  })

  test("the summary mentions autoplay only once it's been used", () => {
    // Inverted from the other two on purpose: zero autoplays is every game's
    // starting state, so the line is earned rather than reported.
    expect(Stats.summary({Stats.moves: 47, undos: 2, autoplays: 1}))->toBe(
      "47 moves · 2 undos · 1 autoplay",
    )
  })
})
