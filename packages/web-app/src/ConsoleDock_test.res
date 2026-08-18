// Where the debug console sits (#275), on the parts of it that are answerable without a
// browser: the placement's trip through `localStorage`, the order ⇧` walks them in (and
// what it does with a placement the window can't show), and the arithmetic that decides
// whether a window is wide enough to dock into at all.
//
// The rest of placement is layout — the board reflowing into the remaining width, the
// two rects not intersecting, the menu coexisting, the bottom band and the full window
// covering what they claim to — and lives in `debug-console.spec.mjs`, where there's a
// real engine to measure.
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
  test("a placement round-trips through storage", () => {
    // Every one of them, in both directions: the placement has to survive a reload for
    // the choice to mean anything, and `Top` has to be *written back* rather than merely
    // left unwritten, or stepping home to it would silently persist as wherever you were
    // before.
    ConsoleDock.cycle->Array.forEach(
      placement => {
        Preferences.saveConsoleDock(placement)
        expect(Preferences.loadConsoleDock())->toEqual(placement)
      },
    )
  })

  test("a device that has never moved the console opens at the top", () => {
    removeItem(Preferences.consoleDockKey)
    expect(Preferences.loadConsoleDock())->toEqual(ConsoleDock.Top)
  })

  test("an unreadable stored value falls back to the top", () => {
    // What a value written by a future (or corrupted) build looks like. The shipped
    // default is the shape that fits every window, so falling back to it is always safe.
    setItem(Preferences.consoleDockKey, "sideways")
    expect(Preferences.loadConsoleDock())->toEqual(ConsoleDock.Top)
  })

  test("the placement's stored spelling is its own name", () => {
    // The stored shape is a named value rather than a boolean precisely so placements
    // could join without a migration; pinning the spelling is what makes that promise
    // checkable.
    expect(ConsoleDock.toString(ConsoleDock.Top))->toBe("top")
    expect(ConsoleDock.toString(ConsoleDock.Side))->toBe("side")
    expect(ConsoleDock.toString(ConsoleDock.Bottom))->toBe("bottom")
    expect(ConsoleDock.toString(ConsoleDock.Full))->toBe("full")
    expect(ConsoleDock.fromString("bottom"))->toEqual(Some(ConsoleDock.Bottom))
    expect(ConsoleDock.fromString(""))->toEqual(None)
  })

  test("the two placements' older spellings still read", () => {
    // `overlay`/`docked` are what the first two were called when they were the only two.
    // A developer with one of them saved is where they left the panel, not somewhere an
    // update moved them to.
    setItem(Preferences.consoleDockKey, "overlay")
    expect(Preferences.loadConsoleDock())->toEqual(ConsoleDock.Top)
    setItem(Preferences.consoleDockKey, "docked")
    expect(Preferences.loadConsoleDock())->toEqual(ConsoleDock.Side)
  })

  test("⇧` walks the four placements and comes back round", () => {
    // The cycle in the order the panel presents it, and that it *is* a cycle: pressing
    // the key four times from anywhere lands you back where you started, so there's no
    // placement you can get stuck in.
    let step = placement => ConsoleDock.nextFitting(placement, ~roomToDock=true)
    expect(step(ConsoleDock.Top))->toEqual(ConsoleDock.Side)
    expect(step(ConsoleDock.Side))->toEqual(ConsoleDock.Bottom)
    expect(step(ConsoleDock.Bottom))->toEqual(ConsoleDock.Full)
    expect(step(ConsoleDock.Full))->toEqual(ConsoleDock.Top)
  })

  test("a window with no room to dock steps over the dock", () => {
    // The refusal, in the shape the cycle gives it: the side dock is the one placement
    // that displaces the board, so a window that can't spare the width skips *past* it to
    // the bottom band rather than sticking on the top overlay. A key that went inert on a
    // narrow window would be indistinguishable from a broken one — and would put the two
    // placements beyond the dock out of reach entirely.
    let step = placement => ConsoleDock.nextFitting(placement, ~roomToDock=false)
    expect(step(ConsoleDock.Top))->toEqual(ConsoleDock.Bottom)
    expect(step(ConsoleDock.Bottom))->toEqual(ConsoleDock.Full)
    expect(step(ConsoleDock.Full))->toEqual(ConsoleDock.Top)
    // Nothing else is ever refused: three of the four cover the board rather than
    // displacing it, so they fit any window by construction.
    ConsoleDock.cycle->Array.forEach(
      placement => expect(ConsoleDock.needsRoom(placement))->toBe(placement == ConsoleDock.Side),
    )
  })

  test("the placements that cover a playable board refuse pointer events", () => {
    // The overlays sit over the free cells, the foundations and the Menu button, so they
    // have to let a drag through to the game they're narrating — which is also why
    // `DebugConsole` scrolls them by hand. The side dock covers nothing and the full
    // window covers everything, and neither has a playable board underneath to protect.
    expect(ConsoleDock.takesPointerEvents(ConsoleDock.Top))->toBe(false)
    expect(ConsoleDock.takesPointerEvents(ConsoleDock.Bottom))->toBe(false)
    expect(ConsoleDock.takesPointerEvents(ConsoleDock.Side))->toBe(true)
    expect(ConsoleDock.takesPointerEvents(ConsoleDock.Full))->toBe(true)
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
