// Persist a player's menu preferences (#139) across sessions in the browser's
// localStorage, so a toggle they flip in the menu is still set on the next launch.
// Only the web app persists preferences — the CLI takes its `Options` per run — so
// this binding lives here rather than in `core`. The driver preferences speak the
// shared `Options.t` (currently just `autoCollect`) so the stored shape tracks the
// same seam both drivers already read; the *presentation-only* preferences (the
// hand-placed card tilt, #65) are web-app chrome the CLI has no notion of, so they
// live outside `Options` and are persisted under their own keys here.
//
// localStorage access can throw outright (Safari private mode, a sandboxed frame,
// storage disabled), so every touch is guarded: a failure to read falls back to
// the shipped default (auto-collect on, tilt on), and a failure to write is
// swallowed — the preference simply won't persist, which is no worse than having
// no storage at all.

@val @scope("localStorage") external getItem: string => Nullable.t<string> = "getItem"
@val @scope("localStorage") external setItem: (string, string) => unit = "setItem"

// The storage keys, each namespaced so they won't collide with anything else the
// app might persist later.
let autoCollectKey = "pip.autoCollect"
let cardTiltKey = "pip.cardTilt"

// Read a boolean flag from storage, treating only an explicit "false" as off; a
// missing, garbage, or unreadable value keeps the on-by-default `fallback`. This
// is the shared shape both flags below are stored in.
let loadFlag = (key, ~fallback) => {
  let stored = try getItem(key)->Nullable.toOption catch {
  | _ => None
  }
  switch stored {
  | Some("false") => false
  | _ => fallback
  }
}

// Persist a boolean flag. A write failure (storage disabled or full) is swallowed
// — the preference just won't survive the session.
let saveFlag = (key, value) =>
  try setItem(key, value ? "true" : "false") catch {
  | _ => ()
  }

// Load the saved driver preferences, falling back to the shipped defaults for
// anything missing, unparseable, or unreadable.
let load = (): Options.t => {
  let autoCollect = loadFlag(autoCollectKey, ~fallback=Options.default.autoCollect)
  // `allowColumnReorder` (#159) has no UI toggle yet, so it isn't persisted — it
  // always takes the shipped default (our variant's house rule, on). When a
  // settings control is wired later it can start saving its own key here.
  {autoCollect, allowColumnReorder: Options.default.allowColumnReorder}
}

// Persist the current driver preferences.
let save = (options: Options.t) => saveFlag(autoCollectKey, options.autoCollect)

// The hand-placed card tilt (#65) defaults on, matching the shipped look; the
// menu's toggle lets a player who'd rather see cards stacked dead-square turn it
// off, and this remembers that across launches.
let loadCardTilt = (): bool => loadFlag(cardTiltKey, ~fallback=true)
let saveCardTilt = (enabled: bool) => saveFlag(cardTiltKey, enabled)
