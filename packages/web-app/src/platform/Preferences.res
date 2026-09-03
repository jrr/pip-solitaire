// The menu's toggles, persisted in `localStorage` so a flip survives a launch. Only
// the web app persists preferences — the CLI takes its `Options` per run — which is
// why this lives here rather than in `core`.
//
// Two kinds live side by side. The **driver** preferences speak the shared
// `Options.t`, so the stored shape tracks the seam both front ends read; the
// **presentation-only** ones (tilt, notch display, the console placement) are web-app
// chrome the CLI has no notion of, so they sit outside `Options` under their own keys.
//
// Every touch of storage is guarded, because access can throw outright (Safari private
// mode, a sandboxed frame, storage disabled). A failed read takes the shipped default
// and a failed write is swallowed: the preference just doesn't persist.

@val @scope("localStorage") external getItem: string => Nullable.t<string> = "getItem"
@val @scope("localStorage") external setItem: (string, string) => unit = "setItem"

// Namespaced, so they can't collide with anything else the app persists later.
let autoCollectKey = "pip.autoCollect"
let cardTiltKey = "pip.cardTilt"
let wantsShakeKey = "pip.wantsShake"
let notchDisplayKey = "pip.notchDisplay"
let debugLogKey = "pip.debugLog"
let revealHiddenKey = "pip.revealHidden"
let victoryAnimationKey = "pip.victoryAnimation"
let consoleDockKey = "pip.consoleDock"

// An explicit "true"/"false" wins; anything else — missing, garbage, unreadable —
// keeps `fallback`.
//
// **Both spellings have to be honoured, not just the one that disagrees with the
// default.** A flag that defaults off (`wantsShake`, `debugLog`, `revealHidden`) and
// only reads "false" can be written but never read back: its stored "true" falls
// through to the off default and the preference silently doesn't survive a reload.
// The default-on flags hide this, since their stored value and their fallback agree.
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

let saveFlag = (key, value) =>
  try setItem(key, value ? "true" : "false") catch {
  | _ => ()
  }

let load = (): Options.t => {
  let autoCollect = loadFlag(autoCollectKey, ~fallback=Options.default.autoCollect)
  // `allowColumnReorder` has no UI toggle yet, so it isn't persisted and always takes
  // the shipped default. A settings control would start saving its own key here.
  {autoCollect, allowColumnReorder: Options.default.allowColumnReorder}
}

let save = (options: Options.t) => saveFlag(autoCollectKey, options.autoCollect)

let loadCardTilt = (): bool => loadFlag(cardTiltKey, ~fallback=true)
let saveCardTilt = (enabled: bool) => saveFlag(cardTiltKey, enabled)

// What's persisted is *intent*, not the OS motion permission — that grant can be
// revoked behind us, so on relaunch the first board tap re-asks
// `Motion.requestAccess` and the switch reflects whatever it finds.
let loadWantsShake = (): bool => loadFlag(wantsShakeKey, ~fallback=false)
let saveWantsShake = (enabled: bool) => saveFlag(wantsShakeKey, enabled)

// On by default: the landscape rail rides out into the corner wings beside the notch
// (`CutoutSide`, `styles/landscape-rail.css`). Turning it off clamps the layout
// entirely inside the browser-reported safe area — worse-looking, but the way out on
// untested phone geometry where a control could land unreachably.
let loadNotchDisplay = (): bool => loadFlag(notchDisplayKey, ~fallback=true)
let saveNotchDisplay = (enabled: bool) => saveFlag(notchDisplayKey, enabled)

// Persisted, unlike the session-only safe-area overlay, so a developer who turns
// logging on still sees it after a reload.
let loadDebugLog = (): bool => loadFlag(debugLogKey, ~fallback=false)
let saveDebugLog = (enabled: bool) => saveFlag(debugLogKey, enabled)

// "Victory animation": one of the hidden settings, so it is only reachable once the
// ten-tap gesture has been performed — but the flip itself is persisted like any other
// preference, so a device left with it on comes back with it on. Off by default, which
// is what keeps the cascade off every player's screen while it is still being tried out.
let loadVictoryAnimation = (): bool => loadFlag(victoryAnimationKey, ~fallback=false)
let saveVictoryAnimation = (enabled: bool) => saveFlag(victoryAnimationKey, enabled)

// `HiddenOptions`: persisted so the ten-tap gesture is performed once per device, not
// once per launch. Written in both directions — ten more taps hides the rows again,
// without turning off whatever they switched on.
let loadRevealHidden = (): bool => loadFlag(revealHiddenKey, ~fallback=false)
let saveRevealHidden = (revealed: bool) => saveFlag(revealHiddenKey, revealed)

// Persisted rather than session state, because the point of a placement you flip by
// hand — rather than an automatic breakpoint — is that it stays flipped. `Top` is the
// default because it's the shape every window can show, including one too narrow to dock.
//
// Stored as the placement's own *name* rather than through `loadFlag`/`saveFlag`, which
// is what lets a new placement join without a stored-shape migration; unreadable
// resolves to the default exactly as the flags do.
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
