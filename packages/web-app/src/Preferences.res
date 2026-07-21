// Persist a player's driver preferences (#139) across sessions in the browser's
// localStorage, so a toggle they flip in the menu is still set on the next launch.
// Only the web app persists preferences — the CLI takes its `Options` per run — so
// this binding lives here rather than in `core`, and it speaks the shared
// `Options.t` (currently just `autoCollect`) so the stored shape tracks the same
// seam both drivers already read.
//
// localStorage access can throw outright (Safari private mode, a sandboxed frame,
// storage disabled), so every touch is guarded: a failure to read falls back to
// the shipped `Options.default` (auto-collect on), and a failure to write is
// swallowed — the preference simply won't persist, which is no worse than having
// no storage at all.

@val @scope("localStorage") external getItem: string => Nullable.t<string> = "getItem"
@val @scope("localStorage") external setItem: (string, string) => unit = "setItem"

// The storage key for the auto-collect flag, namespaced so it won't collide with
// anything else the app might persist later.
let autoCollectKey = "sleight.autoCollect"

// Load the saved preferences, falling back to the shipped defaults for anything
// missing, unparseable, or unreadable. Only an explicit "false" turns auto-collect
// off; a missing or garbage value keeps the on-by-default behaviour.
let load = (): Options.t => {
  let stored = try getItem(autoCollectKey)->Nullable.toOption catch {
  | _ => None
  }
  let autoCollect = switch stored {
  | Some("false") => false
  | _ => Options.default.autoCollect
  }
  // `allowColumnReorder` (#159) has no UI toggle yet, so it isn't persisted — it
  // always takes the shipped default (our variant's house rule, on). When a
  // settings control is wired later it can start saving its own key here.
  {autoCollect, allowColumnReorder: Options.default.allowColumnReorder}
}

// Persist the current preferences. A write failure (storage disabled or full) is
// swallowed — the preference just won't survive the session.
let save = (options: Options.t) =>
  try setItem(autoCollectKey, options.autoCollect ? "true" : "false") catch {
  | _ => ()
  }
