// The menu (#109): a slide-over overlay opened from the top bar's Menu button,
// holding everything that isn't day-to-day play.
//
// **This file is the pane, not its contents (#307).** It owns the overlay, the
// backdrop, the panel, which of the three screens is showing, and the About footer
// that sits under all of them. Everything inside a screen is a component of its own
// under `components/` — `<MenuMainScreen>`, `<MenuSettingsScreen>`,
// `<MenuDebugScreen>`, and the rows they're built from (`<MenuHeader>`,
// `<MenuToggleRow>`, `<MenuActionRow>`, `<MenuNavRow>`, `<MenuGameButton>`,
// `<MenuWiggleRow>`) — each with its own props record and its own test, the shape
// `<AboutFooter>` established when it was lifted out of here for the same reason
// (#201). What each screen holds, and why, is documented in its own file.
//
// The pane has **three screens** (#191): the **main menu**, a dedicated **Settings**
// screen, and a **Debug** screen nested one level below Settings — which one shows
// is chosen by the `screen` variant. The **About** footer (version line + update
// controls) stays put across all three — only the content above it swaps. Reopening
// the menu always lands on the main screen (the chrome resets `screen` to `Main` when
// it closes/opens the menu).
//
// The **About** footer is the build/version line and, when a service-worker update is
// waiting, the green **Update** button (#165). The adaptive **update-check** button
// (#112) folds into that footer too: it used to be its own "Updates" section above
// About; the build info and the update check belong together, so `Menu` hands the
// footer a `refresh` vnode (a `<RefreshControl>` when a worker state is known, an
// empty node otherwise) and the footer tucks it under the version row. Both
// `<AboutFooter>` and `<RefreshControl>` are their own pure components, lifted out so
// their size-across-state can be pinned in isolation (#201) — see those files for the
// "don't wiggle" story.
//
// It's a pure `props => vnode` in the `VersionBadge` mold (see VersionBadge for why
// the record is spelled out by hand). Open/closed and which-screen are chrome model
// state passed in as `open_`/`screen`; a click on the backdrop or the close button
// calls `onClose`. The props record stays *flat* — it's the single boundary between
// `Main`'s chrome model and the menu, and this file's job is to fan those fields out
// to the screen that wants them. Layout lives in Menu.css.

// Which of the pane's three screens is showing (#191). Reopening the menu
// resets this to `Main` (see the chrome model), so a visit to Settings/Debug never
// lingers into the next open.
type screen =
  | Main
  | Settings
  | Debug

// The adaptive refresh control folded into the About footer (#112): one button whose
// `label` and click behaviour adapt to whether a service worker is registered
// ("Refresh" force-reloads a cache-only install; "Check for updates" checks a
// real install without applying — see Refresh/Main). `busy` spins the on-button
// indicator while a check/refresh is in flight (#201). The whole control is a
// `props` option: `None` (still detecting, or `serviceWorker` unsupported) hides it.
type refreshButton = {
  label: string,
  busy: bool,
  onClick: unit => unit,
}

type props = {
  open_: bool,
  screen: screen,
  onClose: unit => unit,
  onOpenSettings: unit => unit,
  onBackToMenu: unit => unit,
  onOpenDebug: unit => unit,
  onBackToSettings: unit => unit,
  // --- main screen (see MenuMainScreen) ---
  onNewGame: unit => unit,
  onRestart: unit => unit,
  shareDealSeed: option<int>,
  shareDealStatus: option<string>,
  onShareDeal: unit => unit,
  games: Html.element,
  // --- settings screen (see MenuSettingsScreen) ---
  autoCollect: bool,
  onToggleAutoCollect: unit => unit,
  cardTilt: bool,
  onToggleCardTilt: unit => unit,
  wiggle: Motion.state,
  onToggleWiggle: unit => unit,
  notchDisplay: bool,
  onToggleNotchDisplay: unit => unit,
  revealHidden: bool,
  onTapSettingsTitle: unit => unit,
  // --- debug screen (see MenuDebugScreen) ---
  debugScenes: Html.element,
  debugStates: Html.element,
  cutoutDebug: bool,
  onToggleCutoutDebug: unit => unit,
  debugLog: bool,
  onToggleDebugLog: unit => unit,
  shareEnabled: bool,
  shareStatus: option<string>,
  onShareGame: unit => unit,
  // --- the About footer, under every screen (see AboutFooter) ---
  refreshButton: option<refreshButton>,
  version: string,
  buildTime: string,
  updateVisible: bool,
  onReload: unit => unit,
}

let make = ({
  open_,
  screen,
  onClose,
  onOpenSettings,
  onBackToMenu,
  onOpenDebug,
  onBackToSettings,
  onNewGame,
  onRestart,
  shareDealSeed,
  shareDealStatus,
  onShareDeal,
  games,
  debugScenes,
  debugStates,
  cutoutDebug,
  onToggleCutoutDebug,
  debugLog,
  onToggleDebugLog,
  shareEnabled,
  shareStatus,
  onShareGame,
  autoCollect,
  onToggleAutoCollect,
  cardTilt,
  onToggleCardTilt,
  wiggle,
  onToggleWiggle,
  notchDisplay,
  onToggleNotchDisplay,
  revealHidden,
  onTapSettingsTitle,
  refreshButton,
  version,
  buildTime,
  updateVisible,
  onReload,
}) => {
  // The update-check button folded into the About footer: shown on the Settings and
  // Debug screens once a service-worker state has been detected, and never on the
  // main menu — which is where the detection is kicked off (see `Main`).
  let refresh = switch (screen, refreshButton) {
  | (Main, _) | (_, None) => Html.array([])
  | (_, Some({label, busy, onClick})) => <RefreshControl label busy onClick />
  }

  <div id="menu-overlay" hidden={!open_}>
    <div className="menu-overlay__backdrop" onClick={_ => onClose()} />
    <aside className="menu-panel" ariaLabel="Menu">
      {switch screen {
      | Main =>
        <MenuMainScreen
          onClose onNewGame onRestart shareDealSeed shareDealStatus onShareDeal games onOpenSettings
        />
      | Settings =>
        <MenuSettingsScreen
          onClose
          onBackToMenu
          onOpenDebug
          onTapSettingsTitle
          autoCollect
          onToggleAutoCollect
          cardTilt
          onToggleCardTilt
          wiggle
          onToggleWiggle
          revealHidden
          notchDisplay
          onToggleNotchDisplay
        />
      | Debug =>
        <MenuDebugScreen
          onClose
          onBackToSettings
          cutoutDebug
          onToggleCutoutDebug
          debugLog
          onToggleDebugLog
          shareEnabled
          shareStatus
          onShareGame
          debugScenes
          debugStates
        />
      }}
      <AboutFooter version buildTime updateVisible onReload refresh />
    </aside>
  </div>
}
