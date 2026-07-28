// The menu (#109): a slide-over overlay opened from the top bar's Menu button,
// holding everything that isn't day-to-day play. Its sections carry `menu-section__heading`
// labels (#185) and split into a top group and a bottom group, with the panel's
// flex column growing the empty space between so play controls sit up top and the
// utility sections hug the foot.
//
// The pane has **three screens** (#191): the **main menu**, a dedicated
// **Settings screen**, and a **Debug screen** nested one level below Settings —
// which one shows is chosen by the `screen` variant. The **About** footer (version
// line + update controls) stays put across all three — only the content above it
// swaps. Reopening the menu always lands on the main screen (the chrome resets
// `screen` to `Main` when it closes/opens the menu).
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
// **Settings screen** (#191) — the player-facing preferences, the toggles a
// player can flip mid-game. Its content flows from the *top* now: the panel
// grows the space *below* the sections (a `.menu-screen` wrapper takes the slack)
// so the footer still hugs the foot, but the settings no longer float in the middle
// under an empty header. Top to bottom:
//   - a header with a **back** button (`onBackToMenu`, returns to the main menu)
//     and the ✕ (`onClose`, still closes the whole menu);
//   - the preference toggles (#139), one per row with a one-line description under
//     its label; no section heading — the "Settings" title in the header
//     already names them. **Auto-collect** — state passed as `autoCollect`, toggled
//     through `onToggleAutoCollect`; **Sloppy placement** (#65) — the slight
//     resting-card tilt, `cardTilt` / `onToggleCardTilt`, for players who'd rather
//     see cards stacked dead-square; **Wiggle Waggle** (#235) — shake-to-jostle,
//     the one title-cased, description-less row, whose `Motion.state` drives both the
//     switch and a problem-only subtitle (`wiggle` / `onToggleWiggle`, see
//     `wiggleRow`), and which is **hidden** until the screen's title has been tapped
//     ten times (`revealHidden`, see `HiddenOptions`); and
//     **Display content around notch** (#204) —
//     whether the landscape rail may ride out into the corner wings beside the notch
//     (`notchDisplay` / `onToggleNotchDisplay`); off clamps every control inside the
//     safe area;
//   - a **Debug** nav row (`onOpenDebug`) that opens the Debug screen — the debug
//     tools moved off Settings entirely onto their own screen so the player
//     preferences stand alone.
//
// **Debug screen** — the developer tools that used to sit at the foot of the
// Settings screen, relocated onto their own screen a level below it. Top to bottom:
//   - a header whose **back** button (`onBackToSettings`) returns to Settings — one
//     step back up, not all the way out — beside the ✕;
//     the **Safe-area overlay** toggle (`cutoutDebug` / `onToggleCutoutDebug`) and
//     the **Console logging** toggle (`debugLog` / `onToggleDebugLog`, #213 — narrates
//     the UI↔core traffic to the JS console) up top, then the two collapsible groups
//     that were the old "Debug scenes"/"Debug states": the debug/demo scenes
//     (`debugScenes`, labelled "scenes") and the named
//     starting positions (`debugStates`, "states") a tap drops the board into
//     (`Scenario`), the menu twin of `?state=`.
//
// The **About** footer sits at the foot of every screen — the build/version line
// and, when a service-worker update is waiting, the green **Update** button (#165).
// The adaptive **update-check** button (#112) folds into that footer too now:
// it used to be its own "Updates" section above About; the build info and the
// update check belong together, so `Menu` hands the footer a `refresh` vnode (a
// `<RefreshControl>` when a worker state is known, an empty node otherwise) and the
// footer tucks it under the version row. Both `<AboutFooter>` and `<RefreshControl>`
// are their own pure components, lifted out so their size-across-state can be pinned
// in isolation (#201) — see those files for the "don't wiggle" story.
//
// It's a pure `props => vnode` in the `VersionBadge` mold (see VersionBadge for
// why the record is spelled out by hand). Open/closed and which-screen are chrome
// model state passed in as `open_`/`screen`; a click on the backdrop or the close
// button calls `onClose`. The scene rows are an externally-owned real DOM node (the
// switcher owns them), spliced with `Html.node` so the reconciler leaves them be
// across open/close re-renders. Layout lives in index.html.

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
  onNewGame: unit => unit,
  onRestart: unit => unit,
  games: Html.element,
  debugScenes: Html.element,
  debugStates: Html.element,
  cutoutDebug: bool,
  onToggleCutoutDebug: unit => unit,
  debugLog: bool,
  onToggleDebugLog: unit => unit,
  autoCollect: bool,
  onToggleAutoCollect: unit => unit,
  cardTilt: bool,
  onToggleCardTilt: unit => unit,
  // "Wiggle Waggle" (#235): the shake-to-jostle switch. Not a bool — its
  // `Motion.state` decides both the switch position and the problem-only subtitle
  // (see `wiggleRow`). `onToggleWiggle` asks for motion permission on the flip.
  wiggle: Motion.state,
  onToggleWiggle: unit => unit,
  notchDisplay: bool,
  onToggleNotchDisplay: unit => unit,
  // Whether the not-ready-yet settings are showing (`HiddenOptions`). Today that's
  // just the Wiggle Waggle row; `onTapSettingsTitle` counts a tap on the Settings
  // screen's title, every ten of which flip this. The handler is attached *only* to
  // the Settings screen's title — see the header below. A hidden row says nothing
  // about whether its setting is *on*: hiding leaves it running.
  revealHidden: bool,
  onTapSettingsTitle: unit => unit,
  refreshButton: option<refreshButton>,
  version: string,
  buildTime: string,
  updateVisible: bool,
  onReload: unit => unit,
}

// A settings toggle row (#139): the label with a one-line description under
// it on the left, a switch track on the right. It's a `<button role="switch">` —
// the Html runtime only wires clicks, so the switch is a plain button, not a
// checkbox — and toggling `--on` slides the knob and greens the track.
let toggleRow = (~label, ~desc, ~on, ~onToggle) =>
  <button
    className={on ? "menu-toggle menu-toggle--on" : "menu-toggle"}
    onClick={_ => onToggle()}
    attrs={[("type", "button"), ("role", "switch"), ("aria-checked", on ? "true" : "false")]}
  >
    <span className="menu-toggle__text">
      <span className="menu-toggle__label"> {Html.string(label)} </span>
      <span className="menu-toggle__desc"> {Html.string(desc)} </span>
    </span>
    <span className="menu-toggle__switch" />
  </button>

// The "Wiggle Waggle" row (#235): the shake-to-jostle switch. Unlike the plain
// `toggleRow`, its label is title-cased and it deliberately carries *no* description
// — the other settings explain themselves; finding out what this one does is the
// point. The subtitle line under the title appears *only* to report a problem
// (`Motion.subtitle`): blocked, no sensor, or an insecure origin. A healthy switch
// — off or listening — shows just the title and the switch, so the row renders no
// `menu-toggle__desc` at all in those states. The switch reads on only while
// actually listening; a `Blocked` state snaps it back to off but keeps its subtitle.
let wiggleRow = (~state: Motion.state, ~onToggle) => {
  let on = Motion.isOn(state)
  <button
    className={on ? "menu-toggle menu-toggle--on" : "menu-toggle"}
    onClick={_ => onToggle()}
    attrs={[("type", "button"), ("role", "switch"), ("aria-checked", on ? "true" : "false")]}
  >
    <span className="menu-toggle__text">
      <span className="menu-toggle__label"> {Html.string("Wiggle Waggle")} </span>
      {switch Motion.subtitle(state) {
      | Some(line) => <span className="menu-toggle__desc"> {Html.string(line)} </span>
      | None => Html.array([])
      }}
    </span>
    <span className="menu-toggle__switch" />
  </button>
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
  games,
  debugScenes,
  debugStates,
  cutoutDebug,
  onToggleCutoutDebug,
  debugLog,
  onToggleDebugLog,
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
  // A ✕ that closes the whole menu — the same control in every screen's header.
  let closeButton =
    <button
      className="menu-close"
      onClick={_ => onClose()}
      attrs={[("type", "button"), ("aria-label", "Close menu")]}
    >
      {Html.string("✕")}
    </button>

  // A header back button: `label` names where it returns to, `onClick` goes there.
  let backButton = (~label, ~onClick) =>
    <button
      className="menu-back"
      onClick={_ => onClick()}
      attrs={[("type", "button"), ("aria-label", label)]}
    >
      {Html.string("‹ Back")}
    </button>

  // The About footer, shown at the foot of every screen. `refresh` is the folded-in
  // update-check button: present on the Settings/Debug screens where a
  // service-worker state has been detected, empty on the main menu.
  let aboutFooter = (~refresh) => <AboutFooter version buildTime updateVisible onReload refresh />

  let refreshNode = switch refreshButton {
  | None => Html.array([])
  | Some({label, busy, onClick}) => <RefreshControl label busy onClick />
  }

  <div id="menu-overlay" hidden={!open_}>
    <div className="menu-overlay__backdrop" onClick={_ => onClose()} />
    <aside className="menu-panel" attrs={[("aria-label", "Menu")]}>
      {switch screen {
      | Settings =>
        <>
          <div className="menu-panel__header">
            {backButton(~label="Back to menu", ~onClick=onBackToMenu)}
            {<h1
              // The hidden-options tap target (`HiddenOptions`): every ten taps here
              // flip the settings that aren't ready to be found yet into or out of
              // view — hiding them is the same gesture again. It's *this* screen's
              // title only — the identical `menu-title` renders "Pip" and "Debug" on the
              // other two screens and must stay inert. Two things keep it that way: the
              // handler is attached in this branch alone (the reconciler re-applies
              // `onClick` on every patch, so switching screens clears it from the reused
              // <h1> — see `Html.applyProps`), and `Main` drops any tap that arrives while
              // `menuScreen` isn't `Settings`. Belt and braces, because a leak here would
              // be invisible until someone found it.
              className="menu-title"
              onClick={_ => onTapSettingsTitle()}
            >
              {Html.string("Settings")}
            </h1>}
            {closeButton}
          </div>
          <div className="menu-screen">
            <div className="menu-section" attrs={[("aria-label", "Settings")]}>
              {toggleRow(
                ~label="Auto-collect",
                ~desc="Send cards to the foundations for you as soon as they're ready.",
                ~on=autoCollect,
                ~onToggle=onToggleAutoCollect,
              )}
              {toggleRow(
                ~label="Sloppy placement",
                ~desc="Cards don't line up perfectly.",
                ~on=cardTilt,
                ~onToggle=onToggleCardTilt,
              )}
              {
                // "Wiggle Waggle" (#235) sits below "Sloppy placement" but is *not*
                // nested under it — the two are independent settings. It's hidden until
                // the Settings title has been tapped ten times (`HiddenOptions`) — not
                // ready to be found by a player yet, but reachable on a test device.
                // Ten more taps hide the row again *without* stopping the shake, so an
                // absent row here doesn't mean the board is sitting still.
                revealHidden ? wiggleRow(~state=wiggle, ~onToggle=onToggleWiggle) : Html.array([])
              }
              {toggleRow(
                ~label="Display content around notch",
                ~desc="Let the controls reach into the corners beside the camera notch.",
                ~on=notchDisplay,
                ~onToggle=onToggleNotchDisplay,
              )}
            </div>
            <nav className="menu-section" attrs={[("aria-label", "More")]}>
              <button
                className="menu-nav-row" onClick={_ => onOpenDebug()} attrs={[("type", "button")]}
              >
                <span className="menu-nav-row__label"> {Html.string("Debug")} </span>
                <span className="menu-nav-row__chevron" attrs={[("aria-hidden", "true")]}>
                  {Html.string("›")}
                </span>
              </button>
            </nav>
          </div>
          {aboutFooter(~refresh=refreshNode)}
        </>
      | Debug =>
        <>
          <div className="menu-panel__header">
            {backButton(~label="Back to settings", ~onClick=onBackToSettings)}
            <h1 className="menu-title"> {Html.string("Debug")} </h1>
            {closeButton}
          </div>
          <div className="menu-screen">
            <nav className="menu-section" attrs={[("aria-label", "Debug")]}>
              {toggleRow(
                ~label="Safe-area overlay",
                ~desc="Outline the device safe area to check cutout handling.",
                ~on=cutoutDebug,
                ~onToggle=onToggleCutoutDebug,
              )}
              {toggleRow(
                ~label="Console logging",
                ~desc="Log every UI↔core interaction to the browser console.",
                ~on=debugLog,
                ~onToggle=onToggleDebugLog,
              )}
              {Html.node(debugScenes)}
              {Html.node(debugStates)}
            </nav>
          </div>
          {aboutFooter(~refresh=refreshNode)}
        </>
      | Main =>
        <>
          <div className="menu-panel__header">
            <h1 className="menu-title"> {Html.string("Pip")} </h1>
            {closeButton}
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
          {aboutFooter(~refresh=Html.array([]))}
        </>
      }}
    </aside>
  </div>
}
