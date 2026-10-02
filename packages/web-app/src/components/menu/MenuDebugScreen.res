// The menu's **Debug screen**: the developer tools, on their own screen a level
// below Settings. `Menu` puts the About footer under it.
//
// Top to bottom:
//   - a header whose **back** button (`onBackToSettings`) returns to Settings — one
//     step back up, not all the way out — beside the ✕;
//   - the **Safe-area overlay** toggle (`cutoutDebug`) and the **Console logging**
//     toggle (`debugLog` — narrates the UI↔core traffic to the JS console), and the
//     **Thinking indicator** (`thinkingDot` — the corner dot `ThinkingDot` draws);
//   - the three action rows: **Solve** (the console's `autoplay`, split into asking and
//     playing — `SolveDialog` holds the answer), **Share game state** (`ShareLink`) and **Clear saved data**
//     (`StoredState`);
//   - the collapsible groups: the demo scenes (`debugScenes`, labelled "scenes") and
//     the named starting positions (`debugStates`, "states") a tap drops the board
//     into (`Scenario`), the menu twin of `?state=`.
//
// The groups arrive the same way and are drawn by the same component: a list of
// `<MenuDisclosure>` entries each, one from `SceneSwitcher` and one from `Main`.
// Both calls differ only in their data — a group that needs its own markup wants a prop
// on `<MenuDisclosure>`, not a third way of drawing a disclosure here.
//
// **A game the main menu withholds is listed on no screen, this one included** (`Main`'s
// `menuGames` — a game in beta, until the Beta features switch or its release lists
// it). It is reached by `?game=` and nothing else, which is the whole of what withholding a game
// means; a board already on the table when the switch goes off stays up, with no row
// anywhere to bring it back.
type props = {
  onClose: unit => unit,
  onBackToSettings: unit => unit,
  cutoutDebug: bool,
  onToggleCutoutDebug: unit => unit,
  debugLog: bool,
  onToggleDebugLog: unit => unit,
  thinkingDot: bool,
  onToggleThinkingDot: unit => unit,
  // "Solve": whether there is a board behind this screen to hand to the solver.
  // False on a scene with no game, where the row goes dark rather than answering a tap
  // with a refusal.
  solveEnabled: bool,
  // Whether a search is running. The answer itself goes up in `SolveDialog`; what the
  // row carries meanwhile takes over its description, so it doesn't change height.
  solving: bool,
  onSolve: unit => unit,
  // "Share game state" (`ShareLink`): whether a link has been encoded for the board
  // behind this screen — false on a scene with no game, and for the moment between
  // opening the screen and the encode resolving, which is what the disabled state
  // covers. The press raises `ShareDialog`, which is where the link is handed over.
  shareEnabled: bool,
  onShareGame: unit => unit,
  // "Clear saved data": throw away everything the app has stored on this device and
  // reopen it, which is the only way to see a first launch without devtools or a new
  // browser profile. Always live — there is nothing it depends on being on screen,
  // and storage with nothing in it is a clear that finds nothing rather than a row
  // that has to go dark.
  onClearStored: unit => unit,
  // The demo scenes, one entry per scene, with the mounted one `selected`.
  debugScenes: array<MenuDisclosure.entry>,
  // Whether that group opens expanded — `SceneSwitcher`'s call, made when the app
  // opened on a scene that lives inside it (`?scene=gallery`).
  debugScenesOpen: bool,
  // The named positions. No `selected`: a state row is a jump, and leaves nothing
  // behind for the menu to point at.
  debugStates: array<MenuDisclosure.entry>,
}

// What the row says while the solver is searching, on a worker thread, for up to ten
// seconds — long enough that a row that said nothing would read as a tap that missed.
let thinking = "Thinking…"

let solveDesc = (~enabled, ~solving) =>
  if solving {
    thinking
  } else if enabled {
    "Look for a way to win the current game, then offer to play it."
  } else {
    "No game on screen to solve."
  }

let shareDesc = (~enabled) =>
  enabled
    ? "Show a link and QR code that reopen this exact game, undo history and all."
    : "No game on screen to share."

let make = ({
  onClose,
  onBackToSettings,
  cutoutDebug,
  onToggleCutoutDebug,
  debugLog,
  onToggleDebugLog,
  thinkingDot,
  onToggleThinkingDot,
  solveEnabled,
  solving,
  onSolve,
  shareEnabled,
  onShareGame,
  onClearStored,
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
      <MenuToggleRow
        label="Thinking indicator"
        desc="A dot in the corner while the solver thinks ahead: amber thinking, green settled."
        on=thinkingDot
        onToggle=onToggleThinkingDot
      />
      <MenuActionRow
        label="Solve"
        desc={solveDesc(~enabled=solveEnabled, ~solving)}
        enabled=solveEnabled
        onClick=onSolve
      />
      // "Share game state" (`ShareLink`): the board behind this screen as a link, shown
      // in `ShareDialog` as a QR code and a Copy button.
      <MenuActionRow
        label="Share game state"
        desc={shareDesc(~enabled=shareEnabled)}
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
      <MenuDisclosure summary="scenes" entries=debugScenes open_=debugScenesOpen />
      <MenuDisclosure summary="states" entries=debugStates />
    </MenuSection>
  </div>
</>
