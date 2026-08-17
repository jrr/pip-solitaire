// Where the debug console sits (#275), on the two halves of it that are answerable
// without a browser: the mode's trip through `localStorage`, and the arithmetic that
// decides whether a window is wide enough to dock into at all.
//
// The rest of docking is layout — the board reflowing into the remaining width, the two
// rects not intersecting, the menu coexisting — and lives in `debug-console.spec.mjs`,
// where there's a real engine to measure.
//
// jsdom on an opaque origin exposes no `localStorage`, so — exactly as `SavedGame_test`
// does — a minimal in-memory Storage is installed for `Preferences`' bindings to write
// into.
%%raw(`
  globalThis.localStorage = (() => {
    const store = new Map()
    return {
      getItem: (k) => (store.has(k) ? store.get(k) : null),
      setItem: (k, v) => { store.set(k, String(v)) },
      removeItem: (k) => { store.delete(k) },
      clear: () => { store.clear() },
    }
  })()
`)

// Not on `Preferences`, which only ever writes: these reach past it to set up the
// "nothing saved" and "garbage saved" cases it has to survive.
@val @scope("localStorage") external setItem: (string, string) => unit = "setItem"
@val @scope("localStorage") external removeItem: string => unit = "removeItem"

open Vitest

describe("ConsoleDock (#275)", () => {
  test("the dock mode round-trips through storage", () => {
    // Both directions: `docked` is the one that has to survive a reload for the mode to
    // mean anything, and `overlay` has to be written back rather than merely left
    // unwritten, or undocking would silently persist as docked.
    Preferences.saveConsoleDock(ConsoleDock.Docked)
    expect(Preferences.loadConsoleDock())->toEqual(ConsoleDock.Docked)
    Preferences.saveConsoleDock(ConsoleDock.Overlay)
    expect(Preferences.loadConsoleDock())->toEqual(ConsoleDock.Overlay)
  })

  test("a device that has never docked opens as the overlay", () => {
    removeItem(Preferences.consoleDockKey)
    expect(Preferences.loadConsoleDock())->toEqual(ConsoleDock.Overlay)
  })

  test("an unreadable stored value falls back to the overlay", () => {
    // What a value written by a future (or corrupted) build looks like. The shipped
    // default is the shape that fits every window, so falling back to it is always safe.
    setItem(Preferences.consoleDockKey, "sideways")
    expect(Preferences.loadConsoleDock())->toEqual(ConsoleDock.Overlay)
  })

  test("the mode's stored spelling is its own name", () => {
    // The stored shape is a named value rather than a boolean precisely so a third mode
    // could join without a migration; pinning the spelling is what makes that promise
    // checkable.
    expect(ConsoleDock.toString(ConsoleDock.Docked))->toBe("docked")
    expect(ConsoleDock.toString(ConsoleDock.Overlay))->toBe("overlay")
    expect(ConsoleDock.fromString("docked"))->toEqual(Some(ConsoleDock.Docked))
    expect(ConsoleDock.fromString(""))->toEqual(None)
  })

  test("a desktop window has room for the dock; a phone has not", () => {
    // The refusal test, in the terms the chrome asks it in: the stage gives up the
    // dock's width, and what's left has to keep an eight-column FreeCell board above
    // `minScale` (`TableScene.minStageWidth`). No pixel breakpoint is named on either
    // side — both numbers come from the layout's own constants.
    let roomFor = stage => stage -. ConsoleDock.width >= TableScene.minStageWidth(~columns=8)
    expect(roomFor(1440.))->toBe(true)
    expect(roomFor(390.))->toBe(false)
  })
})
