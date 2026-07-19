// The menu (#109): a slide-over overlay opened from the top bar's Menu button,
// holding everything that isn't day-to-day play. Top to bottom:
//   - the **title** ("Sleight"), moved here from the retired Home scene;
//   - the **scene list** — SceneSwitcher's row controls, spliced in as the
//     `scenes` node. It leads with FreeCell (the game) as a top-level row and
//     buries the debug/demo scenes inside a collapsible "Debug" group (#135), so
//     the menu opens on the game with the demos tucked away but one tap out;
//   - (a spot is left here for a future rules reference — not built yet);
//   - the **version info** (`<VersionBadge>`, folded in from the old bottom-right
//     badge).
//
// It's a pure `props => vnode` in the `VersionBadge` / `UpdateButton` mold (see
// VersionBadge for why the record is spelled out by hand). Open/closed is chrome
// model state passed in as `open_`; a click on the backdrop or the close button
// calls `onClose`. The scene rows are an externally-owned real DOM node (the
// switcher owns them), spliced with `Html.node` so the reconciler leaves them be
// across open/close re-renders. Layout lives in index.html.
type props = {
  open_: bool,
  onClose: unit => unit,
  scenes: Html.element,
  version: string,
  buildTime: string,
  offlineReady: bool,
}

let make = ({open_, onClose, scenes, version, buildTime, offlineReady}) =>
  <div id="menu-overlay" hidden={!open_}>
    <div className="menu-overlay__backdrop" onClick={_ => onClose()} />
    <aside className="menu-panel" attrs={[("aria-label", "Menu")]}>
      <div className="menu-panel__header">
        <h1 className="menu-title"> {Html.string("Sleight")} </h1>
        <button
          className="menu-close"
          onClick={_ => onClose()}
          attrs={[("type", "button"), ("aria-label", "Close menu")]}
        >
          {Html.string("✕")}
        </button>
      </div>
      <nav className="menu-section" attrs={[("aria-label", "Scenes")]}> {Html.node(scenes)} </nav>
      <div className="menu-footer">
        <VersionBadge version={version} buildTime={buildTime} offlineReady={offlineReady} />
      </div>
    </aside>
  </div>
