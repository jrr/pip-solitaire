// Everything this app has put in the browser, as one thing you can throw away — the
// Debug screen's "Clear saved data", which is the way back to a first launch: the deal
// that arrives with nothing remembered, otherwise reachable only through devtools or a
// fresh browser profile.
//
// It sits beside the two writers rather than inside either, because neither can speak
// for the other: `SavedGame` owns the boards and `Preferences` the toggles, and
// "forget this device" is both at once.
//
// Why the keys are swept rather than listed, why the reopen below is half of the
// operation rather than the caller's business, and which parts of the address survive
// it: `docs/save-and-share.md` § Throwing it all away.
//
// Guarded like every other touch of storage (see `SavedGame`): access can throw
// outright in Safari private mode or a sandboxed frame, and a device that can't read
// its storage has nothing stored to forget.
@val @scope("localStorage") external count: int = "length"
@val @scope("localStorage") external keyAt: int => Nullable.t<string> = "key"
@val @scope("localStorage") external removeItem: string => unit = "removeItem"

// The namespace both writers share. One spelling of it here rather than a third copy:
// a key written under any other prefix is a key this sweep will not find.
let prefix = "pip."

// The app's own keys, as storage holds them now. Collected in full *before* anything
// is removed, because removing a key renumbers every key after it — reading and
// deleting in one pass would step over half of them.
let keys = (): array<string> =>
  try Array.fromInitializer(~length=count, i => keyAt(i)->Nullable.toOption)
  ->Array.filterMap(key => key)
  ->Array.filter(key => key->String.startsWith(prefix)) catch {
  | _ => []
  }

// Forget the device: every saved game, every deal number, every preference, and the
// game a bare launch would have opened on. Nothing else in storage is touched — the
// origin may be shared with something that isn't this app.
let clear = (): unit =>
  keys()->Array.forEach(key =>
    try removeItem(key) catch {
    | _ => ()
    }
  )

// --- Starting over ------------------------------------------------------------
@val @scope(("window", "location")) external pathname: string = "pathname"
@val @scope(("window", "location")) external search: string = "search"
@val @scope(("window", "location")) external replace: string => unit = "replace"

// Reopen the app at this address with the fragment dropped (the doc above says what
// each half of that is for).
//
// `replace` rather than `assign`, so Back doesn't lead to the address just left —
// which, on a `#g=` link, is the one that would put the shared game back.
let relaunch = (): unit => replace(pathname ++ search)
