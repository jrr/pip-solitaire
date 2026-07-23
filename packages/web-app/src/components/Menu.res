// The menu (#109): a slide-over overlay opened from the top bar's Menu button,
// holding everything that isn't day-to-day play. Its sections carry `menu-section__heading`
// labels (#185) and split into a top group and a bottom group, with the panel's
// flex column growing the empty space between so play controls sit up top and the
// utility sections hug the foot.
//
// The pane has **two screens** (#191): the **main menu** and a dedicated
// **Settings screen** it swaps to in place, chosen by `settingsOpen`. The
// **About** footer (version line + Update button) stays put across both — only
// the content above it swaps. Reopening the menu always lands on the main
// screen (the chrome resets `settingsOpen` when it closes/opens the menu).
//
// **Main screen** — top to bottom:
//   - the **title** ("Pip"), moved here from the retired Home scene, beside the ✕;
//   - a **"This game"** section (#156): **New Game** (re-deals a fresh seed) and
//     **Restart** (re-deals the *same* seed to replay the current deal). New Game
//     moved here from the top bar; both call the scene's re-deal hooks and close
//     the menu so the board is visible again. On a scene with no game (a demo)
//     the handlers are wired to no-op hooks;
//   - a **"Games"** section — SceneSwitcher's primary game row(s), spliced in as the
//     `games` node: FreeCell (the game) as a top-level row (#135);
//   - --- the space between top and bottom grows here (`menu-section--bottom`) ---
//   - a single **Settings** button (`onOpenSettings`) low in the menu, just above
//     the About footer — it takes over the pane with the Settings screen (#191).
//
// **Settings screen** (#191) — the toggles and Debug group, relocated here off
// the main menu to declutter it. Top to bottom:
//   - a header with a **back** button (`onBackToMenu`, returns to the main menu)
//     and the ✕ (`onClose`, still closes the whole menu);
//   - a **Settings** section (#139): the preference toggles a player can flip
//     mid-game. **Auto-collect** — its state passed in as `autoCollect`, a click
//     reported out through `onToggleAutoCollect`; and **Hand-placed tilt** (#65) —
//     the slight resting-card tilt, passed as `cardTilt` and toggled through
//     `onToggleCardTilt`, for players who'd rather see cards stacked dead-square;
//   - a **"Debug"** section (#185) gathering the two collapsible groups that were the
//     old "Debug scenes"/"Debug states": the debug/demo scenes (`debugScenes`, now
//     labelled just "scenes") and the named starting positions (`debugStates`,
//     "states") a tap drops the board into (`Scenario`), the menu twin of `?state=`,
//     plus the **Safe-area overlay** toggle.
//
// The **About** footer sits at the foot of both screens — the build/version line
// (`<VersionBadge>`, folded in from the old bottom-right badge) and, when a
// service-worker update is waiting, a short note plus the green **Update now**
// button (#165). The update control lived on the top bar before (#109); it moved
// here so the bar no longer carries an always-present slot for a rare action, and
// its availability is now flagged by a pip on the bar's Menu button instead.
//
// It's a pure `props => vnode` in the `VersionBadge` mold (see VersionBadge for
// why the record is spelled out by hand). Open/closed and which-screen are chrome
// model state passed in as `open_`/`settingsOpen`; a click on the backdrop or the
// close button calls `onClose`. The scene rows are an externally-owned real DOM node (the
// switcher owns them), spliced with `Html.node` so the reconciler leaves them be
// across open/close re-renders. Layout lives in index.html.

// The adaptive refresh control on the Settings screen (#112): one button whose
// `label` and click behaviour adapt to whether a service worker is registered
// ("Refresh" force-reloads a cache-only install; "Check for updates" checks a
// real install without applying — see Refresh/Main). `status` is a transient
// line under it ("Checking…", "Up to date"). The whole control is a `props`
// option: `None` (still detecting, or `serviceWorker` unsupported) hides it.
type refreshButton = {
  label: string,
  status: option<string>,
  onClick: unit => unit,
}

type props = {
  open_: bool,
  settingsOpen: bool,
  onClose: unit => unit,
  onOpenSettings: unit => unit,
  onBackToMenu: unit => unit,
  onNewGame: unit => unit,
  onRestart: unit => unit,
  games: Html.element,
  debugScenes: Html.element,
  debugStates: Html.element,
  cutoutDebug: bool,
  onToggleCutoutDebug: unit => unit,
  autoCollect: bool,
  onToggleAutoCollect: unit => unit,
  cardTilt: bool,
  onToggleCardTilt: unit => unit,
  refreshButton: option<refreshButton>,
  version: string,
  buildTime: string,
  offlineReady: bool,
  updateVisible: bool,
  onReload: unit => unit,
}

let make = ({
  open_,
  settingsOpen,
  onClose,
  onOpenSettings,
  onBackToMenu,
  onNewGame,
  onRestart,
  games,
  debugScenes,
  debugStates,
  cutoutDebug,
  onToggleCutoutDebug,
  autoCollect,
  onToggleAutoCollect,
  cardTilt,
  onToggleCardTilt,
  refreshButton,
  version,
  buildTime,
  offlineReady,
  updateVisible,
  onReload,
}) =>
  <div id="menu-overlay" hidden={!open_}>
    <div className="menu-overlay__backdrop" onClick={_ => onClose()} />
    <aside className="menu-panel" attrs={[("aria-label", "Menu")]}>
      {settingsOpen
        ? <>
            <div className="menu-panel__header">
              <button
                className="menu-back"
                onClick={_ => onBackToMenu()}
                attrs={[("type", "button"), ("aria-label", "Back to menu")]}
              >
                {Html.string("‹ Back")}
              </button>
              <h1 className="menu-title"> {Html.string("Settings")} </h1>
              <button
                className="menu-close"
                onClick={_ => onClose()}
                attrs={[("type", "button"), ("aria-label", "Close menu")]}
              >
                {Html.string("✕")}
              </button>
            </div>
            <div className="menu-section menu-section--bottom" attrs={[("aria-label", "Settings")]}>
              <h2 className="menu-section__heading"> {Html.string("Settings")} </h2>
              <button
                className={autoCollect ? "menu-toggle menu-toggle--on" : "menu-toggle"}
                onClick={_ => onToggleAutoCollect()}
                attrs={[
                  ("type", "button"),
                  ("role", "switch"),
                  ("aria-checked", autoCollect ? "true" : "false"),
                ]}
              >
                <span className="menu-toggle__label"> {Html.string("Auto-collect")} </span>
                <span className="menu-toggle__switch" />
              </button>
              <button
                className={cardTilt ? "menu-toggle menu-toggle--on" : "menu-toggle"}
                onClick={_ => onToggleCardTilt()}
                attrs={[
                  ("type", "button"),
                  ("role", "switch"),
                  ("aria-checked", cardTilt ? "true" : "false"),
                ]}
              >
                <span className="menu-toggle__label"> {Html.string("Hand-placed tilt")} </span>
                <span className="menu-toggle__switch" />
              </button>
            </div>
            <nav className="menu-section" attrs={[("aria-label", "Debug")]}>
              <h2 className="menu-section__heading"> {Html.string("Debug")} </h2>
              {Html.node(debugScenes)}
              {Html.node(debugStates)}
              <button
                className={cutoutDebug ? "menu-toggle menu-toggle--on" : "menu-toggle"}
                onClick={_ => onToggleCutoutDebug()}
                attrs={[
                  ("type", "button"),
                  ("role", "switch"),
                  ("aria-checked", cutoutDebug ? "true" : "false"),
                ]}
              >
                <span className="menu-toggle__label"> {Html.string("Safe-area overlay")} </span>
                <span className="menu-toggle__switch" />
              </button>
            </nav>
            {switch refreshButton {
            | None => Html.array([])
            | Some({label, status, onClick}) =>
              <div className="menu-section" attrs={[("aria-label", "Updates")]}>
                <h2 className="menu-section__heading"> {Html.string("Updates")} </h2>
                <button
                  className="menu-button" onClick={_ => onClick()} attrs={[("type", "button")]}
                >
                  {Html.string(label)}
                </button>
                {switch status {
                | None => Html.array([])
                | Some(text) => <p className="menu-refresh__status"> {Html.string(text)} </p>
                }}
              </div>
            }}
          </>
        : <>
            <div className="menu-panel__header">
              <h1 className="menu-title"> {Html.string("Pip")} </h1>
              <button
                className="menu-close"
                onClick={_ => onClose()}
                attrs={[("type", "button"), ("aria-label", "Close menu")]}
              >
                {Html.string("✕")}
              </button>
            </div>
            <div className="menu-section" attrs={[("aria-label", "This game")]}>
              <h2 className="menu-section__heading"> {Html.string("This game")} </h2>
              <div className="menu-buttons">
                <button
                  className="menu-button" onClick={_ => onNewGame()} attrs={[("type", "button")]}
                >
                  {Html.string("New Game")}
                </button>
                <button
                  className="menu-button" onClick={_ => onRestart()} attrs={[("type", "button")]}
                >
                  {Html.string("Restart")}
                </button>
              </div>
            </div>
            <nav className="menu-section" attrs={[("aria-label", "Games")]}>
              <h2 className="menu-section__heading"> {Html.string("Games")} </h2>
              {Html.node(games)}
            </nav>
            <div className="menu-section menu-section--bottom">
              <button
                className="menu-button" onClick={_ => onOpenSettings()} attrs={[("type", "button")]}
              >
                {Html.string("Settings")}
              </button>
            </div>
          </>}
      <div className="menu-footer" attrs={[("aria-label", "About")]}>
        <h2 className="menu-section__heading"> {Html.string("About")} </h2>
        <VersionBadge version={version} buildTime={buildTime} offlineReady={offlineReady} />
        <div className="menu-update" hidden={!updateVisible}>
          <p className="menu-update__note"> {Html.string("A new version is available")} </p>
          <button
            className="menu-update__button"
            onClick={_ => onReload()}
            attrs={[
              ("type", "button"),
              ("title", "Update available — reload"),
              ("aria-label", "Update now — reload to the new version"),
            ]}
          >
            {Html.string("↻ Update now")}
          </button>
        </div>
      </div>
    </aside>
  </div>
