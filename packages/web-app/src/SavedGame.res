// Persist an in-progress game across sessions (#177): the browser-storage half of
// save-and-resume, sibling to `Preferences`. The pure wire format — encoding a
// board's undo/redo history to a string and back — lives in `core`'s `SaveState`;
// this module only owns the impure edges: which `localStorage` key holds a game,
// and reading/writing it safely.
//
// One saved game per game *type* (the issue's "no named saves or multiple slots"),
// so the key is namespaced by the game id. Only FreeCell saves today — it's the
// only re-dealable game — but keying by id lets a second re-dealable game persist
// alongside it later without collision.
//
// Every touch of `localStorage` can throw outright (Safari private mode, a
// sandboxed frame, storage disabled or full), so — exactly as `Preferences` does —
// a failed read falls back to "no saved game" and a failed write is swallowed. A
// device that can't persist simply always deals fresh, which is no worse than
// having no save feature at all.

@val @scope("localStorage") external getItem: string => Nullable.t<string> = "getItem"
@val @scope("localStorage") external setItem: (string, string) => unit = "setItem"
@val @scope("localStorage") external removeItem: string => unit = "removeItem"

// The storage key for a game type's saved progress, namespaced like the
// `Preferences` keys so it won't collide with anything else the app persists.
let key = (gameId: string): string => "pip.savedGame." ++ gameId

// The saved history for `gameId`, or `None` when there's nothing saved, storage
// is unreadable, or the stored blob can't be trusted (corrupt or an older format —
// `SaveState.decode` rejects it). Any of these means "deal fresh" to the caller.
let load = (gameId: string): option<History.t<GameState.t>> => {
  let stored = try getItem(key(gameId))->Nullable.toOption catch {
  | _ => None
  }
  stored->Option.flatMap(SaveState.decode)
}

// Persist `history` as `gameId`'s saved game, replacing any previous one. A write
// failure (storage disabled or full) is swallowed — the game just won't survive
// the session, no worse than before.
let save = (gameId: string, history: History.t<GameState.t>): unit =>
  try setItem(key(gameId), SaveState.encode(history)) catch {
  | _ => ()
  }

// Drop `gameId`'s saved game. Not used by the resume flow (New Game overwrites via
// `save` rather than clearing), but kept for completeness and testing.
let clear = (gameId: string): unit =>
  try removeItem(key(gameId)) catch {
  | _ => ()
  }
