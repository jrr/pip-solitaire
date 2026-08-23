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
let wantsShakeKey = "pip.wantsShake"
let notchDisplayKey = "pip.notchDisplay"
let debugLogKey = "pip.debugLog"
let revealHiddenKey = "pip.revealHidden"
let consoleDockKey = "pip.consoleDock"

// Read a boolean flag from storage: an explicit "true"/"false" wins, and anything
// else — missing, garbage, or unreadable — keeps `fallback`. This is the shared
// shape every flag below is stored in.
//
// Honouring "true" matters for the flags that default *off* (`wantsShake`,
// `debugLog`, `revealHidden`): reading only "false" and falling back otherwise
// meant a stored `true` fell through to the off default, so those three could be
// written but never read back — they silently failed to survive a reload. The
// default-on flags were unaffected either way (their stored "true" and their
// fallback agree), which is why it went unnoticed.
let loadFlag = (key, ~fallback) => {
  let stored = try getItem(key)->Nullable.toOption catch {
  | _ => None
  }
  switch stored {
  | Some("true") => true
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

// Persist auto-collect. One flag at a time rather than a `save(options)` taking the
// whole `Options.t`: the switch that writes it owns nothing but the flag (see
// `MenuSettingsScreen`, which holds its own state since #308), and every other
// preference on that screen already persisted itself through a setter this shape.
// `load` above still answers with a whole `Options.t`, because the driver wants one.
let saveAutoCollect = (enabled: bool) => saveFlag(autoCollectKey, enabled)

// The hand-placed card tilt (#65) defaults on, matching the shipped look; the
// menu's toggle lets a player who'd rather see cards stacked dead-square turn it
// off, and this remembers that across launches.
let loadCardTilt = (): bool => loadFlag(cardTiltKey, ~fallback=true)
let saveCardTilt = (enabled: bool) => saveFlag(cardTiltKey, enabled)

// "Wiggle Waggle" (#235): whether the player wants shake-to-jostle on, defaulting
// off. What's persisted is *intent*, not the OS permission — the grant can be
// revoked behind us, so on relaunch the first board tap re-asks `Motion.requestAccess`
// (which resolves silently if still granted) and the switch reflects whatever it
// finds. Off by default: finding out what it does is the point, so it starts quiet.
let loadWantsShake = (): bool => loadFlag(wantsShakeKey, ~fallback=false)
let saveWantsShake = (enabled: bool) => saveFlag(wantsShakeKey, enabled)

// "Display content around screen notch" (#204) defaults on, matching today's
// shipped landscape layout: the Menu/Undo rail rides out into the corner "wings"
// beside the notch, sharing the strip that's unsafe anyway (see CutoutSide and the
// wing-placement rules in styles/landscape-rail.css). A player on untested phone geometry, where
// that placement could land a control awkwardly or unreachably, can turn it off to
// fall back to a layout clamped entirely inside the browser-reported safe area —
// worse-looking, but always playable. Presentation-only chrome the CLI has no
// notion of, so it rides beside `options` like the tilt flag rather than inside
// the shared `Options.t`.
let loadNotchDisplay = (): bool => loadFlag(notchDisplayKey, ~fallback=true)
let saveNotchDisplay = (enabled: bool) => saveFlag(notchDisplayKey, enabled)

// "Console logging" (#213) defaults off — a developer aid that narrates the app's
// UI↔Core traffic to the JS console, not something a player wants running. Unlike
// the session-only safe-area overlay it *is* persisted, so a developer who turns it
// on still sees logs after a reload (see DebugLog / the menu's Debug screen).
let loadDebugLog = (): bool => loadFlag(debugLogKey, ~fallback=false)
let saveDebugLog = (enabled: bool) => saveFlag(debugLogKey, enabled)

// Whether the hidden settings are showing on this device (`HiddenOptions`): off
// until someone taps the Settings title ten times, and persisted either way so the
// gesture is performed once, not once per launch. Written in both directions — ten
// more taps hides the rows again, without turning off whatever they switched on.
let loadRevealHidden = (): bool => loadFlag(revealHiddenKey, ~fallback=false)
let saveRevealHidden = (revealed: bool) => saveFlag(revealHiddenKey, revealed)

// Where the debug console sits (#275): over the top of the board, docked into the width
// beside it, along the bottom, or over the whole window (`ConsoleDock`). Persisted like
// `debugLog` rather than left as session state, because the whole point of a placement
// you flip by hand — rather than an automatic breakpoint — is that it stays flipped. It
// defaults to the top overlay, which is the shape every window can show, including the
// ones too narrow to dock.
//
// Not a flag, so it doesn't go through `loadFlag`/`saveFlag`: the value is the
// placement's own name, which is what let the bottom band and the full window join the
// original two without a stored-shape migration (`ConsoleDock.fromString` still reads
// the two older spellings). Everything unreadable — missing key, garbage, storage that
// throws — resolves to the shipped default, exactly as the flags do.
let loadConsoleDock = (): ConsoleDock.t => {
  let stored = try getItem(consoleDockKey)->Nullable.toOption catch {
  | _ => None
  }
  stored->Option.flatMap(ConsoleDock.fromString)->Option.getOr(ConsoleDock.Top)
}

let saveConsoleDock = (placement: ConsoleDock.t) =>
  try setItem(consoleDockKey, ConsoleDock.toString(placement)) catch {
  | _ => ()
  }
