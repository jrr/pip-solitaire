// The menu (#109): a slide-over overlay opened from the top bar's Menu button,
// holding everything that isn't day-to-day play. Top to bottom:
//   - the **title** ("Pip"), moved here from the retired Home scene;
//   - a **Game** section (#156): **New Game** (re-deals a fresh seed) and
//     **Restart** (re-deals the *same* seed to replay the current deal). New Game
//     moved here from the top bar; both call the scene's re-deal hooks and close
//     the menu so the board is visible again. On a scene with no game (a demo)
//     the handlers are wired to no-op hooks;
//   - the **scene list** — SceneSwitcher's row controls, spliced in as the
//     `scenes` node. It leads with FreeCell (the game) as a top-level row and
//     buries the debug/demo scenes inside a collapsible "Debug scenes" group (#135),
//     so the menu opens on the game with the demos tucked away but one tap out;
//   - the **debug states** — a sibling collapsible group (`DebugStates`, spliced in
//     as the `debugStates` node) listing the named starting positions a tap drops
//     the board into (`Scenario`), the menu twin of the URL's `?state=`;
//   - a **Settings** section (#139): the driver-preference toggles, starting with
//     **Auto-collect** — a switch the player can flip mid-game, its state passed
//     in as `autoCollect` and a click reported out through `onToggleAutoCollect`;
//   - (a spot is left here for a future rules reference — not built yet);
//   - the **About** footer — the build/version line (`<VersionBadge>`, folded in
//     from the old bottom-right badge) and, when a service-worker update is
//     waiting, a short note plus the green **Update now** button (#165). The
//     update control lived on the top bar before (#109); it moved here so the bar
//     no longer carries an always-present slot for a rare action, and its
//     availability is now flagged by a pip on the bar's Menu button instead.
//
// It's a pure `props => vnode` in the `VersionBadge` mold (see VersionBadge for
// why the record is spelled out by hand). Open/closed is chrome
// model state passed in as `open_`; a click on the backdrop or the close button
// calls `onClose`. The scene rows are an externally-owned real DOM node (the
// switcher owns them), spliced with `Html.node` so the reconciler leaves them be
// across open/close re-renders. Layout lives in index.html.
type props = {
  open_: bool,
  onClose: unit => unit,
  onNewGame: unit => unit,
  onRestart: unit => unit,
  scenes: Html.element,
  debugStates: Html.element,
  autoCollect: bool,
  onToggleAutoCollect: unit => unit,
  version: string,
  buildTime: string,
  offlineReady: bool,
  updateVisible: bool,
  onReload: unit => unit,
}

let make = ({
  open_,
  onClose,
  onNewGame,
  onRestart,
  scenes,
  debugStates,
  autoCollect,
  onToggleAutoCollect,
  version,
  buildTime,
  offlineReady,
  updateVisible,
  onReload,
}) =>
  <div id="menu-overlay" hidden={!open_}>
    <div className="menu-overlay__backdrop" onClick={_ => onClose()} />
    <aside className="menu-panel" attrs={[("aria-label", "Menu")]}>
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
      <div className="menu-section" attrs={[("aria-label", "Game")]}>
        <div className="menu-buttons">
          <button className="menu-button" onClick={_ => onNewGame()} attrs={[("type", "button")]}>
            {Html.string("New Game")}
          </button>
          <button className="menu-button" onClick={_ => onRestart()} attrs={[("type", "button")]}>
            {Html.string("Restart")}
          </button>
        </div>
      </div>
      <nav className="menu-section" attrs={[("aria-label", "Scenes")]}> {Html.node(scenes)} </nav>
      <nav className="menu-section" attrs={[("aria-label", "Debug states")]}>
        {Html.node(debugStates)}
      </nav>
      <div className="menu-section" attrs={[("aria-label", "Settings")]}>
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
      </div>
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
