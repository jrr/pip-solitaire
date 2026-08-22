// The menu's **Debug screen**, lifted out of `Menu` into its own pure component
// (#307): the developer tools that used to sit at the foot of the Settings screen,
// relocated onto their own screen a level below it (#191). `Menu` puts the About
// footer under it.
//
// Top to bottom:
//   - a header whose **back** button (`onBackToSettings`) returns to Settings — one
//     step back up, not all the way out — beside the ✕;
//   - the **Safe-area overlay** toggle (`cutoutDebug`) and the **Console logging**
//     toggle (`debugLog`, #213 — narrates the UI↔core traffic to the JS console);
//   - **Share game state** (`ShareLink`), the action row;
//   - the two collapsible groups that were the old "Debug scenes"/"Debug states": the
//     debug/demo scenes (`debugScenes`, labelled "scenes") and the named starting
//     positions (`debugStates`, "states") a tap drops the board into (`Scenario`),
//     the menu twin of `?state=`.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).
type props = {
  onClose: unit => unit,
  onBackToSettings: unit => unit,
  cutoutDebug: bool,
  onToggleCutoutDebug: unit => unit,
  debugLog: bool,
  onToggleDebugLog: unit => unit,
  // "Share game state" (`ShareLink`): whether a link has been encoded for the board
  // behind this screen — false on a scene with no game, and for the moment between
  // opening the screen and the encode resolving, which is what the disabled state
  // covers.
  shareEnabled: bool,
  // The transient line reporting where the link went; it replaces the row's
  // description while it's up, so the row doesn't change height as it comes and goes.
  shareStatus: option<string>,
  onShareGame: unit => unit,
  // Externally-owned real DOM nodes (SceneSwitcher owns them), spliced with
  // `Html.node` so the reconciler leaves them be across open/close re-renders.
  debugScenes: Html.element,
  debugStates: Html.element,
}

// The "Share game state" row's description. The status line takes over the
// description while it's up, so reporting where the link went doesn't reflow the
// rows around it.
let shareDesc = (~enabled, ~status) =>
  switch status {
  | Some(status) => status
  | None =>
    enabled
      ? "Copy a link that reopens this exact game, undo history and all."
      : "No game on screen to share."
  }

let make = ({
  onClose,
  onBackToSettings,
  cutoutDebug,
  onToggleCutoutDebug,
  debugLog,
  onToggleDebugLog,
  shareEnabled,
  shareStatus,
  onShareGame,
  debugScenes,
  debugStates,
}) => <>
  <MenuHeader
    title="Debug"
    back={Some({label: "Back to settings", onClick: onBackToSettings})}
    onTitleTap=None
    onClose
  />
  <div className="menu-screen">
    <nav className="menu-section" attrs={[("aria-label", "Debug")]}>
      <MenuToggleRow
        label="Safe-area overlay"
        desc="Outline the device safe area to check cutout handling."
        on=cutoutDebug
        onToggle=onToggleCutoutDebug
      />
      <MenuToggleRow
        label="Console logging"
        desc="Log every UI↔core interaction to the browser console."
        on=debugLog
        onToggle=onToggleDebugLog
      />
      // "Share game state" (`ShareLink`): encode the board behind this screen into a
      // link and hand it to the OS share sheet, or failing that the clipboard.
      <MenuActionRow
        label="Share game state"
        desc={shareDesc(~enabled=shareEnabled, ~status=shareStatus)}
        enabled=shareEnabled
        onClick=onShareGame
      />
      {Html.node(debugScenes)}
      {Html.node(debugStates)}
    </nav>
  </div>
</>
