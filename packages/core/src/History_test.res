open Vitest

// The undo/redo history: a pure past/present/future zipper. Exercised here
// over plain `int`s — the zipper is generic, so integers stand in for the
// `GameState.t` snapshots the drivers wrap it around, and equality is trivial to
// assert. The `GameState`-level "apply → undo returns the prior state exactly"
// property is covered end-to-end by the CLI loop tests (`Cli_test`).
describe("History", () => {
  test("a fresh history has nothing to undo or redo", () => {
    let h = History.make(0)
    expect(History.present(h))->toBe(0)
    expect(History.canUndo(h))->toBe(false)
    expect(History.canRedo(h))->toBe(false)
  })

  test("record advances the present and remembers the prior state", () => {
    let h = History.make(1)->History.record(_, 2)->History.record(_, 3)
    expect(History.present(h))->toBe(3)
    expect(History.canUndo(h))->toBe(true)
    expect(History.canRedo(h))->toBe(false)
  })

  test("undo returns to the exact prior state", () => {
    let h = History.make(1)->History.record(2)
    let undone = History.undo(h)
    expect(History.present(undone))->toBe(1)
    // The undone-away state is now available to redo.
    expect(History.canRedo(undone))->toBe(true)
  })

  test("undo past the start is a no-op", () => {
    let h = History.make(1)
    let undone = History.undo(h)
    expect(History.present(undone))->toBe(1)
    expect(History.canUndo(undone))->toBe(false)
    // Undoing a no-op history leaves it entirely unchanged.
    expect(undone)->toEqual(h)
  })

  test("redo replays the undone state; redo past the end is a no-op", () => {
    let h = History.make(1)->History.record(_, 2)->History.record(_, 3)
    let back = h->History.undo->History.undo // present 1, future [2, 3]
    expect(History.present(back))->toBe(1)
    let forward = back->History.redo->History.redo // present 3 again
    expect(History.present(forward))->toBe(3)
    expect(History.canRedo(forward))->toBe(false)
    // A further redo changes nothing.
    expect(History.redo(forward))->toEqual(forward)
  })

  test("a new action after an undo clears the redo future", () => {
    let h = History.make(1)->History.record(_, 2)->History.record(_, 3)
    let undone = History.undo(h) // present 2, future [3]
    expect(History.canRedo(undone))->toBe(true)
    let branched = History.record(undone, 9) // a fresh action from 2
    expect(History.present(branched))->toBe(9)
    // The old 3 is gone — you can't redo onto an abandoned branch.
    expect(History.canRedo(branched))->toBe(false)
    // Undo from the new branch still returns to where it forked (2), not 3.
    expect(History.present(History.undo(branched)))->toBe(2)
  })
})

// `steps` counts the line of play behind the present — deliberately *not* the count
// of moves the player made, which only ever goes up and so lives outside the zipper
// (`Stats`). It's what a save written before that counter existed falls back
// to (`SaveState.ofHistory`). The interesting cases are the ones where undo has been
// at it, since undo pops `past` and so *shortens* the count.
describe("History.steps", () => {
  test("a fresh history has no steps behind it", () => {
    expect(History.steps(History.make(1)))->toBe(0)
  })

  test("counts one step per recorded state", () => {
    let h = History.make(1)->History.record(_, 2)->History.record(_, 3)
    expect(History.steps(h))->toBe(2)
  })

  test("undo shortens the count; redo restores it", () => {
    let h = History.make(1)->History.record(_, 2)->History.record(_, 3)
    expect(History.steps(History.undo(h)))->toBe(1)
    expect(History.steps(h->History.undo->History.redo))->toBe(2)
  })

  test("an abandoned branch doesn't count toward the line that replaced it", () => {
    // Two moves, both undone, then one different move played instead: the line that
    // reached the present is one step long, not three.
    let h = History.make(1)->History.record(_, 2)->History.record(_, 3)
    let branched = h->History.undo->History.undo->History.record(_, 9)
    expect(History.steps(branched))->toBe(1)
  })
})

// `oldest` is where a line *began*, which is the one position a restored save can still
// offer a Restart: the deal it descends from was laid out in some other session, or (a
// share link) by some other player. The cases that matter are the ones that move `past`
// around, since the claim is that its first element never does.
describe("History.oldest", () => {
  test("a fresh history opened on the present is its own opening", () => {
    expect(History.oldest(History.make(1)))->toBe(1)
  })

  test("a line of play still names the state it started from", () => {
    let h = History.make(1)->History.record(_, 2)->History.record(_, 3)
    expect(History.oldest(h))->toBe(1)
  })

  test("stepping back and forth over the line doesn't move it", () => {
    let h = History.make(1)->History.record(_, 2)->History.record(_, 3)
    // All the way back — `past` empties out onto the opening itself…
    let back = h->History.undo->History.undo
    expect(History.present(back))->toBe(1)
    expect(History.oldest(back))->toBe(1)
    // …then forward again, and onto a branch that abandons the original line.
    expect(History.oldest(History.redo(back)))->toBe(1)
    expect(History.oldest(History.record(back, 9)))->toBe(1)
  })
})

// `within` is how a history is cut down to fit somewhere small. The present is what's
// being handed over, so it always survives; the order the rest goes in is the claim.
describe("History.within", () => {
  // Past 1, 2, 3 behind a present of 4, with 5 and 6 undone away ahead of it.
  let h =
    History.make(1)
    ->History.record(_, 2)
    ->History.record(_, 3)
    ->History.record(_, 4)
    ->History.record(_, 5)
    ->History.record(_, 6)
    ->History.undo
    ->History.undo

  test("keeps everything when there's room for it", () => {
    expect(History.length(h))->toBe(5)
    expect(History.within(h, ~steps=5))->toEqual(h)
    expect(History.within(h, ~steps=99))->toEqual(h)
  })

  test("drops the redo branch first, farthest state first", () => {
    expect(History.within(h, ~steps=4))->toEqual({past: [1, 2, 3], present: 4, future: [5]})
    expect(History.within(h, ~steps=3))->toEqual({past: [1, 2, 3], present: 4, future: []})
  })

  test("then drops the past from its oldest end", () => {
    expect(History.within(h, ~steps=1))->toEqual({past: [3], present: 4, future: []})
  })

  test("never drops the present", () => {
    expect(History.within(h, ~steps=0))->toEqual(History.make(4))
    expect(History.within(h, ~steps=-1))->toEqual(History.make(4))
  })
})
