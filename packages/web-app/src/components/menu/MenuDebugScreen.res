// The menu's **Debug screen**: the developer tools, on their own screen a level
// below Settings. `Menu` puts the About footer under it.
//
// Top to bottom:
//   - a header whose **back** button (`onBackToSettings`) returns to Settings — one
//     step back up, not all the way out — beside the ✕;
//   - the **Safe-area overlay** toggle (`cutoutDebug`) and the **Console logging**
//     toggle (`debugLog` — narrates the UI↔core traffic to the JS console);
//   - the three action rows: **Autoplay** (the console's verb of the same name, as a
//     button), **Share game state** (`ShareLink`) and **Clear saved data**
//     (`StoredState`);
//   - the collapsible groups: the
//     games without a row in the main menu (`gameScenes`, labelled "games"),
//     the demo scenes (`debugScenes`, "scenes") and the named starting positions
//     (`debugStates`, "states") a tap drops the board into (`Scenario`), the menu
//     twin of `?state=`.
//
// The groups arrive the same way and are drawn by the same component: a list of
// `<MenuDisclosure>` entries each, two from `SceneSwitcher` and one from `Main`.
// All three calls differ only in their data — a group that needs its own markup wants
// a prop on `<MenuDisclosure>`, not a fourth way of drawing a disclosure here.
//
// The "games" group is the odd one: it is placed only when it has entries, and today it
// has none — every game has a row in the main menu (`Main`'s `menuGames`) — so the
// screen shows two groups, scenes then states. It stays so that a game withheld from
// that menu lands among the games rather than under "scenes", between Gallery and
// Motion, filed as a render demo.
type props = {
  onClose: unit => unit,
  onBackToSettings: unit => unit,
  cutoutDebug: bool,
  onToggleCutoutDebug: unit => unit,
  debugLog: bool,
  onToggleDebugLog: unit => unit,
  // "Autoplay": whether there is a board behind this screen to hand to the solver.
  // False on a scene with no game, where the row goes dark rather than answering a tap
  // with a refusal.
  autoplayEnabled: bool,
  // What the solver said. It takes over the row's description the way a share's status
  // does, and for the same reason — a row that grew a line of its own would shove the
  // scene lists below it down the panel.
  autoplayStatus: option<string>,
  onAutoplay: unit => unit,
  // "Share game state" (`ShareLink`): whether a link has been encoded for the board
  // behind this screen — false on a scene with no game, and for the moment between
  // opening the screen and the encode resolving, which is what the disabled state
  // covers.
  shareEnabled: bool,
  // The transient line reporting where the link went; it replaces the row's
  // description while it's up, so the row doesn't change height as it comes and goes.
  shareStatus: option<string>,
  onShareGame: unit => unit,
  // "Clear saved data": throw away everything the app has stored on this device and
  // reopen it, which is the only way to see a first launch without devtools or a new
  // browser profile. Always live — there is nothing it depends on being on screen,
  // and storage with nothing in it is a clear that finds nothing rather than a row
  // that has to go dark.
  onClearStored: unit => unit,
  // The games that don't have a row in the main menu, one entry each, with the
  // mounted one `selected`. Empty when every game has one, and an empty group isn't
  // placed at all.
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

// What the row says while the solver is searching. The search holds the thread for as
// long as it runs, so this is the last thing the panel paints before it stops answering
// — and the only warning anyone gets that the freeze is the point rather than a hang.
let thinking = "Thinking — nothing responds until the solver is done."

// The "Autoplay" row's description — the solver's own words once it has any, on the
// same substitution as the share row below.
let autoplayDesc = (~enabled, ~status) =>
  switch status {
  | Some(status) => status
  | None => enabled ? "Solve the current game for me." : "No game on screen to solve."
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
  autoplayEnabled,
  autoplayStatus,
  onAutoplay,
  shareEnabled,
  shareStatus,
  onShareGame,
  onClearStored,
  gameScenes,
  gameScenesOpen,
  debugScenes,
  debugScenesOpen,
  debugStates,
}) => <>
  <MenuHeader
    title="Debug"
    back={Some({label: "Back to settings", onClick: onBackToSettings})}
    action=Html.empty
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
      // The console's `autoplay` without the console: the solver takes the board and
      // plays its line out a move at a time. A line found takes this menu down with it —
      // the run is the answer, and it is behind the panel — so the status line only ever
      // carries a refusal, or the word that the thinking has started.
      <MenuActionRow
        label="Autoplay"
        desc={autoplayDesc(~enabled=autoplayEnabled, ~status=autoplayStatus)}
        enabled=autoplayEnabled
        onClick=onAutoplay
      />
      // "Share game state" (`ShareLink`): encode the board behind this screen into a
      // link and hand it to the OS share sheet, or failing that the clipboard.
      <MenuActionRow
        label="Share game state"
        desc={shareDesc(~enabled=shareEnabled, ~status=shareStatus)}
        enabled=shareEnabled
        onClick=onShareGame
      />
      // Under Share deliberately: it is the one row here that destroys something, and
      // the description is the only warning it gets — a tap clears and reloads, with
      // nothing in between to take it back.
      <MenuActionRow
        label="Clear saved data"
        desc="Forget every saved game and setting on this device, then reopen the app."
        enabled=true
        onClick=onClearStored
      />
      // Placed only when there is something in it: an empty `<details>` is a summary
      // that opens onto nothing, and today — every game already in the main menu —
      // that is what it would be.
      {Array.length(gameScenes) == 0
        ? Html.empty
        : <MenuDisclosure summary="games" entries=gameScenes open_=gameScenesOpen />}
      <MenuDisclosure summary="scenes" entries=debugScenes open_=debugScenesOpen />
      <MenuDisclosure summary="states" entries=debugStates />
    </MenuSection>
  </div>
</>
