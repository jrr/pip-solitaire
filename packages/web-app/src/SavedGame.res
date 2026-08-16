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

// --- The deal number behind a saved game (#98) --------------------------------
//
// Stored beside the history rather than inside it, as its own tiny key. The
// history is `core`'s versioned `SaveState` format and knows nothing about deal
// numbers — it carries positions, which is all replaying a game needs — so folding
// a seed in would mean a format change for a fact that isn't part of the game
// state.
//
// It's here at all because a resumed board can't work its own deal number out. The
// history restores the *positions*; the deal that produced them is long gone by
// then (the board a resume mounts on is dealt from a fresh random seed, and only
// its card nodes are used). Without this, the Share button would go dark for the
// most ordinary case there is — open the app, carry on with the game you had — or,
// worse, offer the number of a deal nobody has seen. So the seed is written
// whenever a deal becomes the saved game and read back when that game resumes.
//
// A missing, unreadable, or non-numeric value reads as `None`: no deal number, so
// nothing to share. That's also what an older save — written before this key
// existed — looks like, which is the right answer for it.
let seedKey = (gameId: string): string => "pip.savedDeal." ++ gameId

let loadSeed = (gameId: string): option<int> => {
  let stored = try getItem(seedKey(gameId))->Nullable.toOption catch {
  | _ => None
  }
  stored->Option.flatMap(value => Int.fromString(value))
}

let saveSeed = (gameId: string, seed: int): unit =>
  try setItem(seedKey(gameId), Int.toString(seed)) catch {
  | _ => ()
  }

// Drop just the deal number, leaving the saved game itself alone. What a shared
// game's arrival needs (`Main`): it takes over as the saved game but was never
// dealt from a number here, so the previous game's seed must not stay behind and
// be read as its own.
let clearSeed = (gameId: string): unit =>
  try removeItem(seedKey(gameId)) catch {
  | _ => ()
  }

// Drop `gameId`'s saved game, deal number and all. Not used by the resume flow
// (New Game overwrites via `save` rather than clearing), but kept for completeness
// and testing.
let clear = (gameId: string): unit => {
  try removeItem(key(gameId)) catch {
  | _ => ()
  }
  clearSeed(gameId)
}
