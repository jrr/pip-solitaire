// The `localStorage` edge of save-and-resume (#177): `SavedGame` writes a game's
// history under a per-game-type key and reads it back, delegating the actual
// encoding to `core`'s `SaveState` (round-tripped in `SaveState_test`). These
// exercise the storage path end to end — save→load, the no-save-yet case, and
// `clear`.
//
// jsdom on an opaque origin exposes no `localStorage`, so — exactly as
// `TableScene_test` stubs `matchMedia` — a minimal in-memory Storage is installed
// on `globalThis` for these tests to save into. It's just enough of the Web
// Storage surface (`getItem`/`setItem`/`removeItem`, missing key → `null`) for the
// `@scope("localStorage")` bindings the module uses.
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

open Vitest

describe("SavedGame (#177)", () => {
  let game = Game.freecell
  // A history with a move recorded, so a lossy save would show up as an inequality.
  let history = History.make(GameState.initial(game))->History.record({
    ...GameState.initial(game),
    loose: [{suit: Spades, rank: Ace}],
  })

  test("save then load round-trips the whole history", () => {
    SavedGame.save(game.id, history)
    switch SavedGame.load(game.id) {
    | Some(loaded) => expect(loaded)->toEqual(history)
    | None => expect("loaded")->toBe("but got None")
    }
  })

  test("loading a game type with nothing saved is None", () => {
    SavedGame.clear("no-such-game")
    expect(SavedGame.load("no-such-game"))->toEqual(None)
  })

  test("clear removes the saved game", () => {
    SavedGame.save(game.id, history)
    SavedGame.clear(game.id)
    expect(SavedGame.load(game.id))->toEqual(None)
  })

  // The deal number stored beside the history (#98). It's a separate key because the
  // history has no room for it and no need of it — but the Share button does, since a
  // resumed board can't work out which deal it came from on its own.
  test("a deal number saved with a game reads back with it", () => {
    SavedGame.saveSeed(game.id, 24680)
    expect(SavedGame.loadSeed(game.id))->toEqual(Some(24680))
  })

  test("a game saved with no deal number has none to read", () => {
    // What an older save looks like — written before deal numbers were kept. "No
    // number" is the right answer for it, and the Share button greys out rather than
    // offering a board nobody has seen.
    SavedGame.clearSeed("legacy-game")
    SavedGame.save("legacy-game", history)
    expect(SavedGame.loadSeed("legacy-game"))->toEqual(None)
  })

  test("clearSeed drops the deal number and leaves the game", () => {
    // The shared-game case: the save is taken over by a position that was never dealt
    // from a number here, so the previous deal's number must not stay behind to be
    // read as its own.
    SavedGame.save(game.id, history)
    SavedGame.saveSeed(game.id, 13579)
    SavedGame.clearSeed(game.id)
    expect(SavedGame.loadSeed(game.id))->toEqual(None)
    expect(SavedGame.load(game.id)->Option.isSome)->toBe(true)
  })

  test("clear drops the deal number along with the game", () => {
    SavedGame.save(game.id, history)
    SavedGame.saveSeed(game.id, 13579)
    SavedGame.clear(game.id)
    expect(SavedGame.loadSeed(game.id))->toEqual(None)
  })

  test("deal numbers are namespaced per game type, like the saves", () => {
    SavedGame.saveSeed("freecell", 111)
    SavedGame.clearSeed("other")
    expect(SavedGame.loadSeed("other"))->toEqual(None)
    expect(SavedGame.loadSeed("freecell"))->toEqual(Some(111))
  })

  test("saves are namespaced per game type", () => {
    // A save under one game id doesn't leak into another — one saved game per type.
    SavedGame.save("freecell", history)
    SavedGame.clear("other")
    expect(SavedGame.load("other"))->toEqual(None)
    expect(SavedGame.load("freecell")->Option.isSome)->toBe(true)
  })
})
