open Vitest

// The undo/redo history (#85): a pure past/present/future zipper. Exercised here
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
