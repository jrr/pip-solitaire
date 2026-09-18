// The sweep behind the Debug screen's "Clear saved data". What's worth pinning is the
// part that has no list to check it against: it finds keys by prefix, so the test that
// matters is what it leaves *behind* — the origin may be shared with something that
// isn't this app, and a sweep that took everything would be a bug nothing in the app
// would ever show.
//
// jsdom on an opaque origin exposes no `localStorage`, so — as `SavedGame_test` does —
// a minimal in-memory Storage goes on `globalThis`. This one carries `length` and
// `key(i)` as well, since enumerating is the whole subject: insertion order, and an
// index past the end reading `null`, are the two things the real API promises here.
%%raw(`
  globalThis.localStorage = (() => {
    const store = new Map()
    return {
      getItem: (k) => (store.has(k) ? store.get(k) : null),
      setItem: (k, v) => { store.set(k, String(v)) },
      removeItem: (k) => { store.delete(k) },
      clear: () => { store.clear() },
      key: (i) => [...store.keys()][i] ?? null,
      get length() { return store.size },
    }
  })()
`)

open Vitest

@val @scope("localStorage") external setItem: (string, string) => unit = "setItem"
@val @scope("localStorage") external getItem: string => Nullable.t<string> = "getItem"
@val @scope("localStorage") external empty: unit => unit = "clear"

// One of each kind the app writes, spelled out rather than produced through
// `SavedGame`/`Preferences`: the point is that the sweep finds keys those modules
// invent at runtime — a game id, a family id — without being told what they are.
let seedStorage = () => {
  empty()
  setItem("pip.savedGame.freecell", "{}")
  setItem("pip.savedDeal.freecell", "24680")
  setItem("pip.lastGame", "freecell")
  setItem("pip.autoCollect", "false")
  setItem("pip.variant.freecell", "mini")
}

describe("StoredState", () => {
  test("finds every key the app wrote, whatever its tail", () => {
    seedStorage()
    expect(StoredState.keys()->Array.toSorted(String.compare))->toEqual([
      "pip.autoCollect",
      "pip.lastGame",
      "pip.savedDeal.freecell",
      "pip.savedGame.freecell",
      "pip.variant.freecell",
    ])
  })

  test("clears all of them in one pass, not every other one", () => {
    // Removing a key renumbers the ones after it, so a sweep that enumerated and
    // deleted together would step over half of what it found — and leave a saved game
    // behind on a screen that says it cleared.
    seedStorage()
    StoredState.clear()
    expect(StoredState.keys())->toEqual([])
    expect(getItem("pip.savedGame.freecell")->Nullable.toOption)->toEqual(None)
  })

  test("leaves what it didn't write alone", () => {
    seedStorage()
    setItem("someone-elses-key", "keep me")
    StoredState.clear()
    expect(getItem("someone-elses-key")->Nullable.toOption)->toEqual(Some("keep me"))
  })

  test("finds nothing to clear in empty storage, rather than failing at it", () => {
    empty()
    StoredState.clear()
    expect(StoredState.keys())->toEqual([])
  })
})
