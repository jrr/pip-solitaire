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
//   - the collapsible groups: the demo scenes (`debugScenes`, labelled "scenes"), the
//     named starting positions (`debugStates`, "states") a tap drops the board into
//     (`Scenario`, the menu twin of `?state=`), and the victory cascade's dimming
//     (`cascadeChoices` and `cascadeKnobs`, "cascade" — chips and sliders rather than
//     rows, and the one group here that governs the real game's animation rather than
//     a demo of it).
//
// The groups arrive the same way and are drawn by the same component: a list of
// `<MenuDisclosure>` entries each, one from `SceneSwitcher` and one from `Main`.
// Both calls differ only in their data — a group that needs its own markup wants a prop
// on `<MenuDisclosure>`, not a third way of drawing a disclosure here.
//
// **A game the main menu withholds is listed on no screen, this one included** (`Main`'s
// `menuGames` — Spider, until the Beta features switch or its release lists it). It is
// reached by `?game=` and nothing else, which is the whole of what withholding a game
// means; a board already on the table when the switch goes off stays up, with no row
// anywhere to bring it back.
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
  // covers. The press raises `ShareDialog`, which is where the link is handed over.
  shareEnabled: bool,
  onShareGame: unit => unit,
  // "Clear saved data": throw away everything the app has stored on this device and
  // reopen it, which is the only way to see a first launch without devtools or a new
  // browser profile. Always live — there is nothing it depends on being on screen,
  // and storage with nothing in it is a clear that finds nothing rather than a row
  // that has to go dark.
  onClearStored: unit => unit,
  // The victory cascade's dimming, as sliders — the one group here that governs the
  // *game's* animation rather than a demo of it, which is why it is on this screen and
  // not in a scene: the board behind this panel is the one it is about, and its next win
  // is the one being tuned. Nothing here stores them (`Main`'s `cascadeFade`).
  //
  // A list rather than a prop apiece, because the group is expected to grow: another
  // knob is an entry in the driver and no change on this screen at all.
  cascadeKnobs: array<MenuSlider.spec>,
  // …and the same group's controls that pick rather than measure (`MenuChoiceRow`),
  // above the sliders: which unit the length is said in, and what the fade waits for.
  // A list for the same reason the knobs are one.
  cascadeChoices: array<MenuChoiceRow.spec>,
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
// — which is what makes a word here worth painting at all, and the freeze that follows
// a thing being waited out rather than a hang.
let thinking = "Thinking…"

// The "Autoplay" row's description — the solver's own words once it has any, standing
// in for the description so the row doesn't change height as they come and go.
let autoplayDesc = (~enabled, ~status) =>
  switch status {
  | Some(status) => status
  | None => enabled ? "Solve the current game for me." : "No game on screen to solve."
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
  autoplayEnabled,
  autoplayStatus,
  onAutoplay,
  shareEnabled,
  onShareGame,
  onClearStored,
  cascadeKnobs,
  cascadeChoices,
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
      // No rows in this one: its contents are sliders, which are not `<MenuRow>`s (see
      // `MenuSlider`). Same `<details>` tree as the two above it regardless — a group
      // that needs its own markup takes the `content` prop rather than a second way of
      // drawing a disclosure here. Last of the three because it is the one nothing
      // navigates with: the lists above it are how a developer gets somewhere.
      <MenuDisclosure
        summary="cascade"
        entries=[]
        content={<>
          {cascadeChoices
          ->Array.map(row =>
            <MenuChoiceRow
              label={row.label} readout=?{row.readout} choices={row.choices} key={row.label}
            />
          )
          ->Html.array}
          {cascadeKnobs
          ->Array.map(knob =>
            <MenuSlider
              label={knob.label}
              min={knob.min}
              max={knob.max}
              step={knob.step}
              value={knob.value}
              readout={knob.readout}
              onInput={knob.onInput}
              key={knob.label}
            />
          )
          ->Html.array}
        </>}
      />
    </MenuSection>
  </div>
</>
