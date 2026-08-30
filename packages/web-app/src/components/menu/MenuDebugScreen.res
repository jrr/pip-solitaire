// The menu's **Debug screen**: the developer tools, on their own screen a level
// below Settings. `Menu` puts the About footer under it.
//
// Top to bottom:
//   - a header whose **back** button (`onBackToSettings`) returns to Settings — one
//     step back up, not all the way out — beside the ✕;
//   - the **Safe-area overlay** toggle (`cutoutDebug`) and the **Console logging**
//     toggle (`debugLog` — narrates the UI↔core traffic to the JS console);
//   - **Share game state** (`ShareLink`), the action row;
//   - the collapsible groups: the
//     games that aren't the one in the main menu (`gameScenes`, labelled "games"),
//     the demo scenes (`debugScenes`, "scenes") and the named starting positions
//     (`debugStates`, "states") a tap drops the board into (`Scenario`), the menu
//     twin of `?state=`.
//
// The groups arrive the same way and are drawn by the same component: a list of
// `<MenuDisclosure>` entries each, two from `SceneSwitcher` and one from `Main`.
// All three calls differ only in their data — a group that needs its own markup wants
// a prop on `<MenuDisclosure>`, not a fourth way of drawing a disclosure here.
//
// The "games" group is the odd one: it is placed only when it has entries, so
// with FreeCell the only game this screen shows two groups, scenes then states. It
// exists so that a *second* game lands among the games rather than under "scenes",
// between Gallery and Motion, filed as a render demo.
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
  // The games that don't have a row in the main menu, one entry each, with the
  // mounted one `selected`. Empty while FreeCell is the only game, and an empty group
  // isn't placed at all.
  gameScenes: array<MenuDisclosure.entry>,
  // Whether that group opens expanded, on the same rule as `debugScenesOpen`.
  gameScenesOpen: bool,
  // The demo scenes, one entry per scene, with the mounted one `selected`.
  debugScenes: array<MenuDisclosure.entry>,
  // Whether that group opens expanded — `SceneSwitcher`'s call, made when the app
  // opened on a scene that lives inside it (`?scene=gallery`).
  debugScenesOpen: bool,
  // The named positions. No `selected`: a state row is a jump, and leaves nothing
  // behind for the menu to point at.
  debugStates: array<MenuDisclosure.entry>,
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
  gameScenes,
  gameScenesOpen,
  debugScenes,
  debugScenesOpen,
  debugStates,
}) => <>
  <MenuHeader
    title="Debug"
    back={Some({label: "Back to settings", onClick: onBackToSettings})}
    onTitleTap=None
    onClose
  />
  <div className="menu-screen">
    <MenuSection label="Debug" tag=Nav>
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
      // Placed only when there is something in it: an empty `<details>` is a summary
      // that opens onto nothing, and today — one game, the one already in the main
      // menu — that is what it would be.
      {Array.length(gameScenes) == 0
        ? Html.empty
        : <MenuDisclosure summary="games" entries=gameScenes open_=gameScenesOpen />}
      <MenuDisclosure summary="scenes" entries=debugScenes open_=debugScenesOpen />
      <MenuDisclosure summary="states" entries=debugStates />
    </MenuSection>
  </div>
</>
