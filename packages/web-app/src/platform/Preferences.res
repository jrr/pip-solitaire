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
let betaFeaturesKey = "pip.betaFeatures"
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

// Auto-collect is one field of the driver's `Options.t` and the only one stored, so
// there are two ways in: the whole record, for a caller that holds one, and the flag
// alone, for the settings switch that holds only its own mirror.
let saveAutoCollect = (enabled: bool) => saveFlag(autoCollectKey, enabled)

let save = (options: Options.t) => saveAutoCollect(options.autoCollect)

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

// `HiddenOptions`: persisted so the ten-tap gesture is performed once per device, not
// once per launch. Written in both directions — ten more taps hides the rows again,
// without turning off whatever they switched on.
let loadRevealHidden = (): bool => loadFlag(revealHiddenKey, ~fallback=false)
let saveRevealHidden = (revealed: bool) => saveFlag(revealHiddenKey, revealed)

// "Beta features": the one switch in front of everything built but not finished. Spider
// stands behind it today (`Main`'s `betaGames`). Off by default and reachable only from
// the hidden settings, which is a second gesture in front of this one; persisted like
// the rest, so a device left with it on keeps it across launches.
//
// One key for all of it rather than one per feature, so a feature graduating drops its
// gate and leaves nothing stored behind — the switch outlives whatever is currently
// behind it.
let loadBetaFeatures = (): bool => loadFlag(betaFeaturesKey, ~fallback=false)
let saveBetaFeatures = (enabled: bool) => saveFlag(betaFeaturesKey, enabled)

// Which variant of a family the Games list is offering (`Game.familyOf`), as the chosen
// board's **game id** — the same string `?game=` and the save keys use, so a choice is
// remembered as the game it actually is rather than as a suit count or a size word that
// something else would have to turn back into one.
//
// A key per family rather than one key holding several, so a family joining or leaving
// costs no stored-shape migration; `family` is the family's own id, which is why it is
// stable across a rename of what a player sees.
//
// Handed back raw, because what counts as a variant is `Game`'s to say and not
// storage's: the reader resolves the id against the family and falls back to its
// default, so a stale id, a garbage value and a variant this build has dropped are all
// one answer — exactly how a remembered last game is read (`Main`'s `menuGameById`).
let variantKey = (~family: string) => "pip.variant." ++ family

let loadVariant = (~family: string): option<string> =>
  try getItem(variantKey(~family))->Nullable.toOption catch {
  | _ => None
  }

let saveVariant = (~family: string, id: string) =>
  try setItem(variantKey(~family), id) catch {
  | _ => ()
  }

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
