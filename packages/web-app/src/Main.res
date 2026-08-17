// Web-app entry point. The app *opens as a game*: on startup it mounts the
// FreeCell board straight away (#109), and all the chrome — a single top bar plus
// a slide-over menu — is expressed as ReScript JSX on the hand-rolled `Html`
// runtime and driven by its Elm-style loop. The bottom of the screen is left
// clear for dragging cards; every control lives up top.
//
// The chrome is two components over the scene:
//   - `<TopBar>` — Menu · Undo. Always visible across the top; the Menu
//     button carries a green pip when a version update is waiting (#165).
//   - `<Menu>` — the slide-over holding the title ("Pip", moved out of the
//     retired Home scene), a **game** section (New · Restart · Share Seed, #156/#98), the
//     debug/demo scene list as tappable rows, and the About footer (build/version
//     info plus the conditional "Update" button beside it, #165).
// The scene area underneath is still the imperative `SceneSwitcher`; its scene
// container and its row controls are spliced into the view untouched with
// `Html.node` (the container into the scene band, the rows into the menu), which
// is exactly how a JSX chrome wraps a subtree it doesn't own.

@val @scope("document") external body: Html.element = "body"

// --- Build version ----------------------------------------------------------
// Injected by Vite `define` at build time (see vite.config.js); "unknown" only
// if the build ran without git.
@val external appVersion: string = "__APP_VERSION__"
@val external buildTime: string = "__BUILD_TIME__"

@val external setTimeout: (unit => unit, int) => int = "setTimeout"

// How long the share row's "Link copied…" line stays up before clearing itself.
let shareStatusMs = 2500

// --- Service-worker registration (vite-plugin-pwa virtual module) -----------
// `registerSW` registers the worker (with a relative URL, so its scope follows
// the GitHub Pages subpath) and returns an `updateSW(reloadPage)` function that
// tells the waiting worker to skip waiting and then reloads the page.
type registerSWOptions
@obj
external makeOptions: (
  ~onNeedRefresh: unit => unit=?,
  ~onOfflineReady: unit => unit=?,
) => registerSWOptions = ""

@module("virtual:pwa-register")
external registerSW: registerSWOptions => bool => promise<unit> = "registerSW"

// --- Chrome components -------------------------------------------------------
// The capitalized components used by the view below — `<TopBar/>`, `<Menu/>`,
// and (nested inside the menu) `<VersionBadge/>` — live under
// `src/components/`. Each is a `props => vnode` function; capitalized JSX lowers
// `<TopBar .../>` to `Html.jsx(TopBar.make, props)`, filling the module's `props`
// record from the attributes. See those files for why the record is spelled out
// by hand instead of derived by the `@jsx.component` sugar.

// --- The Elm loop ------------------------------------------------------------
// The chrome is a pure model + update + view. The reactive bits: service-worker
// lifecycle (two booleans flip when their callbacks fire) and whether the menu is
// open.
type model = {
  version: string,
  buildTime: string,
  updateAvailable: bool,
  menuOpen: bool,
  // Which screen the open menu shows (#191): the main menu, the Settings
  // screen, or the Debug screen nested below it. Reset to `Main` whenever the menu
  // opens or closes, so reopening always lands on the main menu.
  menuScreen: Menu.screen,
  // Whether the drop-down debug console is showing (#271). Dev chrome, so it lives
  // here in the chrome model and never reaches `core`'s reducer — and it's session
  // state, deliberately unpersisted: the panel is always closed on load, so a
  // rendered screenshot or OG image can never carry one.
  consoleOpen: bool,
  // Where that console sits when it's up (#275): overlaid across the top of the board,
  // or docked into the discarded width beside it (`ConsoleDock`). Unlike `consoleOpen`
  // this *is* persisted — a mode you flip by hand rather than an automatic breakpoint
  // has to stay flipped — and it mirrors the `Preferences` value like `debugLog` does.
  consoleDock: ConsoleDock.t,
  autoCollect: bool,
  cardTilt: bool,
  // "Wiggle Waggle" (#235): the shake-to-jostle switch, a state machine rather than a
  // bool. `Motion.state` carries whether we're off/listening/blocked/unavailable, which
  // drives both the switch position and its problem-only subtitle. Settings owns the
  // motion grant; the board only listens when this is `On`.
  wiggle: Motion.state,
  // "Display content around screen notch" (#204): on (default) lets the landscape
  // rail ride out into the corner wings beside the notch; off clamps every control
  // inside the safe area. Presentation-only chrome, so it mirrors a `Preferences`
  // flag (like `cardTilt`) rather than a driver `Options` field.
  notchDisplay: bool,
  cutoutDebug: bool,
  // "Console logging" (#213): the Debug screen's switch for narrating every UI↔Core
  // interaction to the JS console. Mirrors the persisted `Preferences` flag (like
  // `cutoutDebug`) so the switch opens in the right position; the logging itself is
  // driven by the shared `DebugLog.enabled` gate the toggle flips.
  debugLog: bool,
  // The hidden settings and the run of taps that reveals them (`HiddenOptions`).
  // `revealed` is persisted; the tap count is session state, cleared on the way out
  // of the Settings screen so a half-finished run can't be resumed later.
  hidden: HiddenOptions.t,
  canUndo: bool,
  // The adaptive Settings refresh control (#112). `refreshMode` is `None` until
  // `Refresh.detect` resolves (and stays effectively hidden on an unsupported
  // browser); it decides the button's "Refresh" vs "Check for updates" shape.
  // `refreshBusy` is whether a check/refresh is in flight — it spins the on-button
  // indicator rather than a status line beneath it (#201).
  refreshMode: option<Refresh.mode>,
  refreshBusy: bool,
  // The Debug screen's "Share game state" row (`ShareLink`). `shareUrl` is the
  // encoded link for the board as it stood when the screen opened — computed *then*,
  // not on the press, because `navigator.share` needs the click's transient
  // activation and would lose it behind the compression's `await` (see
  // `ShareLink.deliver`). The board can't move while the menu covers it, so a link
  // built on open is still current when the button is pressed. `None` means there's
  // nothing to share (a demo scene) or the encode hasn't finished yet, and the row
  // renders disabled. `shareStatus` is the transient line reporting what happened.
  shareUrl: option<string>,
  shareStatus: option<string>,
  // The main menu's Share Seed button (#98): the seed of the board on the table,
  // reported by the scene (`~onDeal` below), and the transient line under the buttons
  // reporting where its link went. `None` greys the button out — a demo scene, or a
  // game resumed from a save with no deal number recorded. Unlike `shareUrl` above
  // there's nothing to prepare: the link is a `?seed=` string built on the press
  // (`ShareLink.urlForDeal`), so only the number has to be to hand.
  dealSeed: option<int>,
  shareDealStatus: option<string>,
}

type msg =
  | UpdateAvailable // a new build is waiting in the wings
  | Reload // user asked to activate the waiting worker and reload
  | ToggleMenu // the top bar's Menu button
  | CloseMenu // backdrop / close button / a scene row was tapped
  | ToggleConsole // the ` key — drop the debug console over the board, or put it away (#271)
  | CloseConsole // Escape while the console is showing (#271)
  // ⇧` — dock the console beside the board, or put it back over it (#275). The flag is
  // the *live board's* verdict on whether it can spare the dock's width, read at the
  // keypress and carried in (like `RefreshDetected`) so `update` stays a pure function
  // of the model rather than reaching into the layout.
  | ToggleConsoleDock(bool)
  | OpenSettings // the main menu's Settings button — swap to the Settings screen (#191)
  | BackToMenu // the Settings screen's back button — swap back to the main menu (#191)
  | OpenDebug // the Settings screen's Debug row — swap to the Debug screen
  | BackToSettings // the Debug screen's back button — swap back to Settings
  | ToggleAutoCollect // the menu's Auto-collect switch (#139)
  | ToggleCardTilt // the menu's hand-placed-tilt switch (#65)
  | WiggleOff // the Wiggle Waggle switch turned off (#235) — stop listening, square up
  | WiggleResolved(Motion.state) // a motion-permission request resolved to a new state (#235)
  | ToggleNotchDisplay // the menu's "Display content around screen notch" switch (#204)
  | ToggleCutoutDebug // the menu's safe-area overlay switch (debug)
  | ToggleDebugLog // the Debug screen's console-logging switch (#213)
  | SettingsTitleTapped // a tap on the Settings screen's title — ten reveal the hidden settings
  | HistoryChanged(bool) // whether the board can undo after a move (#85)
  | RefreshDetected(Refresh.mode) // service-worker presence detected — sets the button's shape (#112)
  | RefreshStarted // the refresh button was tapped — start spinning the button (#112/#201)
  | RefreshChecked // an update check finished — stop the spinner (a found update surfaces as the About button)
  | ShareLinkReady(option<string>) // the open Debug screen's board, encoded into a link (`ShareLink`)
  | ShareStatus(option<string>) // the share row's transient status line; `None` clears it
  | DealChanged(option<int>) // the board reported which deal it's showing (#98)
  | ShareDealStatus(option<string>) // the Share button's transient status line; `None` clears it

// `updateSW` only exists once registerSW has run, which needs `dispatch`, which
// needs the loop to be mounted — so the Reload effect reaches it through a ref
// that's filled in just after mount (see below).
let updateSW: ref<option<bool => promise<unit>>> = ref(None)

// The active scene's "New Game" action, if it has one. The mounted scene
// publishes its re-deal here (see `gameScene` / `TableScene`), the switcher's
// `onActivate` clears it before each scene change, and the menu's New Game
// button runs whatever is current. Only FreeCell publishes one today, so on a
// debug scene the button is a harmless no-op.
let newGameHook: ref<option<unit => unit>> = ref(None)

// The active scene's "Restart" action (#156), sibling of `newGameHook`: re-deals
// the *same* seed to replay the current deal. Every card table publishes one (a
// fixed-layout demo restarts to its own deal), the switcher's `onActivate` clears
// it before each scene change, and the menu's Restart button runs whatever is
// current — a no-op on a non-game scene.
let restartHook: ref<option<unit => unit>> = ref(None)

// The active card-table scene's "load state" action: a `GameState.t => unit` that
// rebuilds the board into a forced position. Every `TableScene` publishes one on
// mount (see `gameScene`), the switcher's `onActivate` clears it before each scene
// change, and the debug-states menu (below) calls it after surfacing FreeCell to
// drop the board into a named `Scenario` position.
let loadStateHook: ref<option<GameState.t => unit>> = ref(None)

// The active card-table scene's share-link hooks (`ShareLink`), siblings of
// `loadStateHook`. `readHistoryHook` hands back the live board's undo/redo history
// so the Debug screen can encode it into a link; `loadHistoryHook` is the way back
// in, rebuilding the board onto a history a `#g=` link carried. Both are published
// by every `TableScene` on mount and cleared on each scene change, so on a demo
// scene there's nothing to share and nothing to restore into.
let readHistoryHook: ref<option<unit => option<History.t<GameState.t>>>> = ref(None)
let loadHistoryHook: ref<option<History.t<GameState.t> => unit>> = ref(None)

// The live board's history, or `None` on a scene that has none (a demo) or before
// a board has mounted. What the share button encodes.
let currentHistory = () => readHistoryHook.contents->Option.flatMap(read => read())

// Whether a `#g=` link's game has actually reached the board. It gates saving on a
// shared open (see `gameScene`): a shared game takes over storage the moment it
// lands, but not before — the placeholder deal the board wears while the blob
// inflates must never be written over the player's own saved game, and a link that
// turns out to be corrupt must leave that game untouched.
//
// This flag only exists because a shared open builds the board twice (#259). Close
// that gap and the placeholder build goes with it, and so does the need for this.
let shareLanded = ref(false)

// The active board's Undo action (#85), sibling of `newGameHook`. The mounted
// `TableScene` publishes a thunk here on every build (a re-deal republishes the
// fresh board's), the switcher's `onActivate` clears it before each scene change,
// and the top bar's Undo button runs whatever is current. A debug/demo scene
// publishes none, so the button is a harmless no-op there.
let undoHook: ref<option<unit => unit>> = ref(None)

// The active board's console command runner (#273), sibling of `undoHook` and
// published on every build for the same reason: a `Command.t => string` that plays one
// parsed command against the board actually on the table. `None` on a scene with no
// board, which is what lets the console answer "no board here" instead of silently
// doing nothing.
let consoleHook: ref<option<Command.t => string>> = ref(None)

// …and the addressed re-deal behind the console's `deal <n>` (#273): open *this* game.
// Only the re-dealable scene publishes one (the same gate as `newGameHook`), since a
// fixed-layout demo has no deal number to name.
let loadGameHook: ref<option<Game.t => unit>> = ref(None)

// The undo availability the board reports during its *opening* mount, captured to
// seed the model below (#177). That first report fires while the switcher mounts
// the initial scene (see `switcher` below) — which happens during module init,
// before `dispatch` (and so `reportHistory`'s real dispatcher) exists — so a
// resumed game whose restored stack can already undo would otherwise lose its
// `canUndo = true` and open with the Undo button wrongly disabled. The pre-mount
// default `reportHistory` records the latest value here; the model reads it at init.
let initialCanUndo = ref(false)

// The board's reverse channel (#85): after every state change it reports whether
// there's anything to undo so the top bar can enable/disable the button. Filled
// with a real dispatcher just after mount (like `closeMenu`); until then it stashes
// the value into `initialCanUndo` (above) so the opening report survives to seed the
// model, and it's reset to `false` on each scene change so a non-game scene leaves
// the button disabled.
let reportHistory: ref<bool => unit> = ref(canUndo => initialCanUndo := canUndo)

// The deal number the board reports during its *opening* mount (#98), captured to
// seed the model — the same pre-mount problem `initialCanUndo` solves, and here it's
// the ordinary case rather than a corner: every plain open deals a board and reports
// its number while the switcher mounts the initial scene, which is during module
// init, before `dispatch` exists. Without this the Share button would open dark on
// every load and only light up after a New Game.
let initialDealSeed: ref<option<int>> = ref(None)

// The board's deal-number channel (#98), sibling of `reportHistory`: the deal now on
// the table, for the menu's Share button. Filled with a real dispatcher just after
// mount; until then it stashes the value for the model to read at init, and it's
// reset to `None` on each scene change so a demo scene offers nothing to share.
let reportDeal: ref<option<int> => unit> = ref(seed => initialDealSeed := seed)

// The deal number on the table right now, mirrored out of the reports below. The
// menu's Share Seed button renders from the *model* (through `DealChanged`), but the
// win overlay's Share button (#264) is built by the board itself, outside the loop,
// and asks at the moment the overlay goes up — so it needs the live value rather
// than a dispatched copy of it.
let liveDealSeed: ref<option<int>> = ref(None)

// Report the deal now on the table: record it for the imperative reader above, then
// hand it to whichever dispatcher is installed. Every report goes through here, which
// is what keeps the two from drifting — a board whose number the menu knows and the
// win overlay doesn't (or vice versa) would be a share button lying about which deal
// it's offering.
let publishDeal = (seed: option<int>): unit => {
  liveDealSeed := seed
  reportDeal.contents(seed)
}

// Closing the menu means dispatching into the loop, but a scene row is an
// imperative listener built before `dispatch` exists (like `updateSW`). It
// reaches the loop through this ref, filled in just after mount.
let closeMenu: ref<unit => unit> = ref(() => ())

// The live driver preferences (#139), seeded from the persisted settings (#134's
// auto-collect defaults on). This is the same ref the board reads at each
// post-move step (see `gameScene` → `TableScene`), so the menu's Auto-collect
// switch flipping a field here changes the board's behaviour on the very next move
// — no rebuild — while the model's mirror of the flag keeps the switch in sync.
let options: ref<Options.t> = ref(Preferences.load())

// The live hand-placed-tilt preference (#65), seeded from storage (defaults on).
// A presentation-only flag the CLI has no notion of, so it rides beside `options`
// rather than inside the shared `Options.t`. The board reads this ref wherever it
// lays a card out, so the menu's tilt switch flipping it here re-tilts the board on
// its next relayout, and the model's mirror keeps the switch in sync.
let tiltEnabled: ref<bool> = ref(Preferences.loadCardTilt())

// The persisted "Display content around screen notch" preference (#204, defaults
// on). Presentation-only and read entirely by the CSS via the document-root
// attribute (see `NotchDisplay`), so unlike `tiltEnabled` the board never reads it
// — a plain value seeds the model's mirror and the startup attribute apply below.
let notchDisplayEnabled = Preferences.loadNotchDisplay()

// The persisted "Console logging" preference (#213, defaults off). Read once at
// startup to seed both the model's toggle and the shared `DebugLog` gate, and the gate
// is opened straight away — before the first board is built below — so a developer who
// left logging on sees the opening deal's UI↔Core traffic too, not only interactions
// after the first in-app toggle.
let debugLogEnabled = Preferences.loadDebugLog()
DebugLog.setConsoleEnabled(debugLogEnabled)

// The persisted console dock mode (#275, defaults to the overlay). Unlike the flag
// above there's nothing to apply at startup: the console is always closed on load, so
// the dock only reaches the document root once one is opened (see `ConsoleDock.reflect`
// — the attribute means docked *and* showing).
let consoleDockMode = Preferences.loadConsoleDock()

// The active board's "relayout" action (#65), sibling of `undoHook`: the mounted
// `TableScene` publishes a thunk that re-lays every resting card, so a tilt toggle
// can re-tilt the board in place at once. Cleared on each scene change and a no-op
// until the next board republishes.
let relayoutHook: ref<option<unit => unit>> = ref(None)

// The live board's dock-refusal test (#275), sibling of `relayoutHook`: "could you give
// up this many px of stage width and still deal cards above `minScale`?" (see
// `TableScene`'s `~publishDockFit`). `None` on a scene with no board, which refuses —
// there's nothing to dock beside.
let dockFitHook: ref<option<float => bool>> = ref(None)

// Whether the console may dock right now, asked of the stage as it actually stands.
// Read at the keypress rather than inside `update`: the answer comes off live layout,
// and the loop's update stays a pure function of the model.
let dockFits = () =>
  switch dockFitHook.contents {
  | Some(fits) => fits(ConsoleDock.width)
  | None => false
  }

// The persisted Wiggle Waggle *intent* (#235), read once at startup. It's intent, not
// permission — the OS can revoke the grant behind us — so on relaunch the first board
// tap re-asks `Motion.requestAccess` (silent if still granted; see the wiring at the
// foot of the file) and the switch reflects whatever it finds.
let wantsShake = Preferences.loadWantsShake()

// The switch state the app opens in: `Unavailable(reason)` on a device/origin that
// can't do motion, else the saved intent (`On`/`Off`). Never prompts — the real grant
// is deferred to a user gesture. Also seeds `Motion.current`, the shared state the
// debug Motion scene reads (it no longer owns a "Request permission" button).
let wiggleInit = Motion.initialState(~wantsShake)
Motion.current := wiggleInit

// The active board's shake control (#235), sibling of `relayoutHook`: the mounted
// `TableScene` publishes `{start, stop}` here, and Settings calls it as the switch
// flips. Cleared on each scene change; the mounting board republishes.
let shakeControlHook: ref<option<TableScene.shakeControl>> = ref(None)

// Whether the board *should* be listening for shakes right now (#235): true once
// Wiggle Waggle is on and permission is granted. Held outside the Elm model so a
// scene mount — which happens through the imperative switcher — can re-apply it to
// the freshly-published control (see `~publishShake` in `gameScene`).
let shakeActive = ref(Motion.isOn(wiggleInit))

let update = (msg, model) =>
  switch msg {
  | UpdateAvailable => ({...model, updateAvailable: true}, Html.noEffect)
  // Opening or closing the menu resets it to the main screen, so a visit to
  // Settings never lingers into the next open (#191).
  // Every screen change also abandons a part-finished run of reveal taps
  // (`HiddenOptions.reset`), here and in the five branches below: the counter only
  // ever spans one uninterrupted visit to the Settings screen.
  // Opening the menu also puts an *overlaid* debug console away (#271): the menu is the
  // modal chrome and takes the screen for itself, and the console's twin rule below
  // closes the menu on the way in. A **docked** console is exempt (#275) — it's beside
  // the board rather than over the Menu button, so nothing is in anything's way, and
  // leaving the log up is the point: flip a debug setting and watch the line it emits.
  | ToggleMenu =>
    let menuOpen = !model.menuOpen
    let putConsoleAway = menuOpen && !ConsoleDock.isDocked(model.consoleDock)
    (
      {
        ...model,
        menuOpen,
        menuScreen: Menu.Main,
        refreshBusy: false,
        hidden: HiddenOptions.reset(model.hidden),
        consoleOpen: putConsoleAway ? false : model.consoleOpen,
      },
      putConsoleAway
        ? () => DebugConsole.apply(~open_=false, ~dock=model.consoleDock)
        : Html.noEffect,
    )
  // The ` key (#271). Opening subscribes the panel to `DebugLog` — a closed console
  // isn't listening, so it costs nothing — and closes the menu if it was showing, unless
  // it's opening docked, in which case the two coexist (see `ToggleMenu` above).
  | ToggleConsole =>
    let consoleOpen = !model.consoleOpen
    let putMenuAway = consoleOpen && !ConsoleDock.isDocked(model.consoleDock)
    (
      {
        ...model,
        consoleOpen,
        menuOpen: putMenuAway ? false : model.menuOpen,
        menuScreen: putMenuAway ? Menu.Main : model.menuScreen,
      },
      () => DebugConsole.apply(~open_=consoleOpen, ~dock=model.consoleDock),
    )
  | CloseConsole =>
    model.consoleOpen
      ? (
          {...model, consoleOpen: false},
          () => DebugConsole.apply(~open_=false, ~dock=model.consoleDock),
        )
      : (model, Html.noEffect)
  // ⇧` flips the dock (#275). `fits` is the live board's verdict on whether it can spare
  // the width: a window too narrow keeps the mode it had and says so in the log rather
  // than silently docking into a board that would then deal cards below `minScale`.
  // Undocking is never refused — the overlay fits any window by construction.
  //
  // The console comes up either way, refusal included: a mode you can't see change isn't
  // a mode, and the refusal is only legible in the panel it's about.
  | ToggleConsoleDock(fits) =>
    let wanted = ConsoleDock.isDocked(model.consoleDock) ? ConsoleDock.Overlay : ConsoleDock.Docked
    let refused = ConsoleDock.isDocked(wanted) && !fits
    let consoleDock = refused ? model.consoleDock : wanted
    // Landing on the overlay while the menu is up is the exclusive case again, so it
    // takes the same exit `ToggleConsole` does.
    let putMenuAway = !ConsoleDock.isDocked(consoleDock)
    (
      {
        ...model,
        consoleDock,
        consoleOpen: true,
        menuOpen: putMenuAway ? false : model.menuOpen,
        menuScreen: putMenuAway ? Menu.Main : model.menuScreen,
      },
      () => {
        // Open first: `DebugLog` only publishes to subscribers, so a refusal announced
        // before the panel subscribes would be announced to nobody.
        DebugConsole.apply(~open_=true, ~dock=consoleDock)
        refused
          ? DebugLog.log("console", "too narrow to dock")
          : Preferences.saveConsoleDock(consoleDock)
      },
    )
  | HistoryChanged(canUndo) =>
    canUndo == model.canUndo ? (model, Html.noEffect) : ({...model, canUndo}, Html.noEffect) // no change — don't re-render
  | CloseMenu =>
    model.menuOpen
      ? (
          {
            ...model,
            menuOpen: false,
            menuScreen: Menu.Main,
            refreshBusy: false,
            hidden: HiddenOptions.reset(model.hidden),
          },
          Html.noEffect,
        )
      : (model, Html.noEffect)
  // Enter Settings clean: clear any stale spinner from a prior visit. The label
  // itself is re-detected on open (see the view's `onOpenSettings`).
  | OpenSettings => (
      {
        ...model,
        menuScreen: Menu.Settings,
        refreshBusy: false,
        hidden: HiddenOptions.reset(model.hidden),
      },
      Html.noEffect,
    )
  | BackToMenu => (
      {...model, menuScreen: Menu.Main, hidden: HiddenOptions.reset(model.hidden)},
      Html.noEffect,
    )
  // Opening the Debug screen clears the previous visit's share link rather than
  // leaving it up: the board may well have moved on since, and a stale link is worse
  // than a briefly disabled button. The view kicks off a fresh encode alongside this
  // message, which arrives back as `ShareLinkReady` and re-enables the row.
  | OpenDebug => (
      {
        ...model,
        menuScreen: Menu.Debug,
        hidden: HiddenOptions.reset(model.hidden),
        shareUrl: None,
        shareStatus: None,
      },
      Html.noEffect,
    )
  | BackToSettings => (
      {...model, menuScreen: Menu.Settings, hidden: HiddenOptions.reset(model.hidden)},
      Html.noEffect,
    )
  | ToggleAutoCollect =>
    let autoCollect = !model.autoCollect
    (
      {...model, autoCollect},
      // Push the flip into the shared preference ref the board reads, and persist
      // it so the choice survives a reload. Both run as the post-update effect.
      () => {
        options := {...options.contents, autoCollect}
        Preferences.save(options.contents)
      },
    )
  | ToggleCardTilt =>
    let cardTilt = !model.cardTilt
    (
      {...model, cardTilt},
      // Flip the shared preference ref the board reads, persist it, and ask the
      // board to relayout so the tilt appears (or clears) immediately, not just on
      // the next move. All three run as the post-update effect.
      () => {
        tiltEnabled := cardTilt
        Preferences.saveCardTilt(cardTilt)
        relayoutHook.contents->Option.forEach(relayout => relayout())
      },
    )
  // Wiggle Waggle turned off (#235): stop listening and square the board back up
  // (the board's `stop` does both), persist the flipped-off intent, and drop the
  // shared state to `Off`. Snapping the mess back is the deliberate way out — a
  // hidden square-up gesture can't be the only one (#236).
  | WiggleOff => (
      {...model, wiggle: Motion.Off},
      () => {
        shakeActive := false
        Motion.current := Motion.Off
        Preferences.saveWantsShake(false)
        shakeControlHook.contents->Option.forEach(control => control.stop())
      },
    )
  // A motion-permission request resolved (#235). `On` — granted or ungated: start
  // listening and persist the intent so the next launch resumes. `Blocked` — the OS
  // refused: the switch snaps back to off (its subtitle explains why) and we stop;
  // crucially we *don't* persist a false intent, so a grant revoked behind us (the
  // saved intent still `true`) keeps re-asking on future launches rather than giving
  // up. `Unavailable`/`Off` just reflect the state.
  | WiggleResolved(state) => (
      {...model, wiggle: state},
      () => {
        Motion.current := state
        switch state {
        | Motion.On =>
          shakeActive := true
          Preferences.saveWantsShake(true)
          shakeControlHook.contents->Option.forEach(control => control.start())
        | Blocked =>
          shakeActive := false
          shakeControlHook.contents->Option.forEach(control => control.stop())
        | Unavailable(_) | Off => ()
        }
      },
    )
  | ToggleNotchDisplay =>
    let notchDisplay = !model.notchDisplay
    (
      {...model, notchDisplay},
      // Reflect the flip onto the document root so the CSS wing-placement rules
      // switch off/on at once, and persist it so the choice survives a reload. Both
      // run as the post-update effect.
      () => {
        NotchDisplay.setEnabled(notchDisplay)
        Preferences.saveNotchDisplay(notchDisplay)
      },
    )
  | ToggleCutoutDebug =>
    let cutoutDebug = !model.cutoutDebug
    (
      {...model, cutoutDebug},
      // Show/hide the overlay at once. Not persisted — it's a debug aid, on only
      // for the session; the model state carries it across rotations regardless.
      () => CutoutDebug.setVisible(cutoutDebug),
    )
  | ToggleDebugLog =>
    let debugLog = !model.debugLog
    (
      {...model, debugLog},
      // Subscribe (or drop) the JS console on the shared log the whole app publishes
      // through (#213) and persist the choice so it survives a reload. Both run as the
      // post-update effect. The drop-down console (#271) is a separate subscriber, so
      // the two are independent: either, both, or neither can be listening.
      () => {
        DebugLog.setConsoleEnabled(debugLog)
        Preferences.saveDebugLog(debugLog)
      },
    )
  // A tap on the Settings screen's title (`HiddenOptions`): every tenth flips the
  // settings that aren't ready to be found yet into or out of view, and persists that
  // so the gesture is performed once per device rather than once per launch. Hiding
  // them again leaves whatever they switched on running — see `HiddenOptions` for why
  // that's deliberate, and what it costs.
  //
  // The screen guard is the other half of "only Settings unlocks": the same green
  // `menu-title` heads all three screens, and while the view only wires the handler
  // onto Settings' copy, this makes the invariant explicit rather than resting on the
  // reconciler clearing a reused node's click handler.
  | SettingsTitleTapped if model.menuScreen != Menu.Settings => (model, Html.noEffect)
  | SettingsTitleTapped =>
    let hidden = HiddenOptions.tap(model.hidden)
    (
      {...model, hidden},
      // Only the tap that actually flipped the reveal is worth persisting; the other
      // nine in a run just move the counter.
      HiddenOptions.revealChanged(~before=model.hidden, ~after=hidden)
        ? () => Preferences.saveRevealHidden(hidden.revealed)
        : Html.noEffect,
    )
  | Reload => (
      model, // no state change — just run the effect
      () =>
        switch updateSW.contents {
        | Some(reload) => reload(true)->ignore
        | None => ()
        },
    )
  | RefreshDetected(mode) => ({...model, refreshMode: Some(mode)}, Html.noEffect)
  | RefreshStarted => ({...model, refreshBusy: true}, Html.noEffect)
  // An update check finished. Stop the spinner; a pending update surfaces itself
  // through the onNeedRefresh → About "Update" flow, so there's nothing more to do.
  | RefreshChecked => ({...model, refreshBusy: false}, Html.noEffect)
  | ShareLinkReady(shareUrl) => ({...model, shareUrl}, Html.noEffect)
  | ShareStatus(shareStatus) => ({...model, shareStatus}, Html.noEffect)
  // A new deal reached the table (#98). Whatever status line the previous deal's
  // share left up goes with it — "Link copied to clipboard." must not sit under a
  // number it no longer refers to.
  | DealChanged(dealSeed) =>
    dealSeed == model.dealSeed
      ? (model, Html.noEffect) // no change — don't re-render
      : ({...model, dealSeed, shareDealStatus: None}, Html.noEffect)
  | ShareDealStatus(shareDealStatus) => ({...model, shareDealStatus}, Html.noEffect)
  }

// The scene area (switcher + demos) is built imperatively and owns its own
// subtree. `render` hands back the row controls (placed in the menu) and the
// scene container (wrapped by the scene band) as two separate real DOM nodes; the
// view splices each in with `Html.node` and never re-renders them.
//
// The app always opens on the FreeCell board: `~default="freecell"` is the launch
// scene, replacing the old "resume the last scene" behaviour — the game is always
// home. An explicit `?scene=` still wins (`~forced`), and `?state=` still forces a
// scenario, so the screenshot report's `?scene=freecell&state=midgame` lands
// exactly where it says. `Game.all` is the source of truth for the game scenes;
// only FreeCell (a seeded shuffle) is re-dealable.
let url = AppUrl.parse()

// A fresh seed for each New Game (#108). The seed is the future "deal number"
// (#98): random for now, so every re-deal lays out a different FreeCell board;
// a deal-number entry point can later supply a chosen seed to this same
// `freecellDeal`. `Math.random` is fine here — this is the impure view layer,
// not `core`'s deterministic deal path.
let randomSeed = () => (Math.random() *. 1_000_000.)->Float.toInt

// Only FreeCell is re-dealable: it's built from a seeded shuffle, so a new seed
// gives a genuinely new board. The fixed-layout demos have no seed to vary, so
// they publish no New Game action. `~publishNewGame` hands the scene's re-deal to
// the top bar (see `newGameHook`).
let gameScene = (game: Game.t) => {
  let isFreecell = game.id == Game.freecell.id
  // A *plain* FreeCell open is the only place save-and-resume applies (#177): the
  // app's primary game, opened without a URL asking for a specific position. A
  // `?state=` scenario or a `?seed=` deal link addresses an exact board, so it opens
  // that board and leaves any saved game strictly alone — neither resumed nor
  // overwritten (the issue's "a `?state=` link doesn't disturb a saved game", and the
  // same for the screenshot report's `?seed=`/`?state=` shots, which must stay
  // side-effect-free).
  // A `#g=` share link is the one addressed open that *does* touch storage, and it
  // splits the two halves apart: it doesn't resume (the link says which board to
  // open, so reading the save would be pointless), but once the shared game lands it
  // **takes over** — becoming the saved game, with play from there saving as usual,
  // exactly as if it had been dealt here. Opening someone's link adopts their game
  // rather than borrowing it, so the two halves are gated separately below.
  let sharedOpen = isFreecell && url.shared->Option.isSome
  let plainOpen =
    isFreecell && url.state->Option.isNone && url.seed->Option.isNone && url.shared->Option.isNone
  // Resume a saved game when there is one and this is a plain open; otherwise `None`
  // (nothing saved, corrupt/old data, or a URL-addressed board) means deal fresh.
  // Storage is read when the scene *mounts*, not here where it's built: a scene can
  // mount more than once (the switcher re-mounts on a scene change), and a value read
  // at build time is a snapshot of the save as it stood at page load, which a later
  // mount would restore over the game actually being played.
  let loadHistory = () => plainOpen ? SavedGame.load(game.id) : None

  // Open FreeCell from a fresh random seed on each load too (#108/#98), so a plain
  // reload with nothing saved lays out a new board instead of always deal #1 —
  // matching what New Game does. A `?seed=` pins that deal number instead (#98), so a
  // link — and the screenshot report's dealt-board shot — lands on the same board
  // every time. The fixed module-level `Game.freecell` (seed 1) stays the
  // deterministic fallback for a forced `?state=` scenario, which screenshots depend
  // on: when a state is forced we mount the fixed deal so `Scenario.forName` derives
  // from the exact same board the report expects. The fixed-layout demos have no seed
  // to vary, so they mount as-is. When a saved game is resumed the opening deal only
  // supplies the 52 card nodes; every resting position comes from the restored history.
  //
  // A `#g=` share link joins `?state=` in taking the fixed deal rather than a random
  // one. Decompressing the blob is asynchronous, so the board is necessarily built
  // *before* the shared history can land on it (see the restore below) — and dealing
  // a random board for that frame would make the swap read as a glitch. The fixed
  // deal keeps it stable and identical every time; the fly-in is skipped for the
  // same reason. Both are mitigations, not a fix — see #259, which measures the gap
  // (sub-millisecond, so one render frame) and weighs the ways to close it.
  let addressed = url.state->Option.isSome || url.shared->Option.isSome
  let opening =
    isFreecell && !addressed ? Game.freecellDeal(~seed=url.seed->Option.getOr(randomSeed())) : game
  let newDeal = isFreecell ? Some(() => Game.freecellDeal(~seed=randomSeed())) : None
  TableScene.make(
    ~initial=?url.state->Option.flatMap(name => Scenario.forName(game, name)),
    // Restore the saved undo/redo stack (#177) and, when saving applies, hand the
    // board a sink that writes each change back to storage. New Game/Restart/every
    // move flow through this same sink, so the saved game always tracks the live one.
    ~loadHistory,
    // A plain open saves from the first build. A shared open saves too, but only
    // from the moment the shared game actually lands (`shareLanded`) — the fixed
    // deal the board is built from while the blob inflates is scaffolding, and
    // writing *that* to storage would clobber the player's own game with a board
    // nobody asked for. It also means a link that fails to decode leaves the saved
    // game exactly as it was: nothing landed, so nothing is written.
    ~persist=?plainOpen || sharedOpen
      ? Some(
          history =>
            if plainOpen || shareLanded.contents {
              SavedGame.save(game.id, history)
            },
        )
      : None,
    ~newDeal?,
    ~publishNewGame=hook => newGameHook := Some(hook),
    ~publishRestart=hook => restartHook := Some(hook),
    ~publishLoadState=hook => loadStateHook := Some(hook),
    ~publishLoadHistory=hook => loadHistoryHook := Some(hook),
    ~publishReadHistory=hook => readHistoryHook := Some(hook),
    ~publishUndo=hook => undoHook := Some(hook),
    ~publishConsole=hook => consoleHook := Some(hook),
    // `deal <n>` only means something where a number names a board, so this rides the
    // same gate as New Game: the re-dealable (seeded) game publishes it, the
    // fixed-layout demos don't.
    ~publishLoadGame=?isFreecell ? Some(hook => loadGameHook := Some(hook)) : None,
    ~publishRelayout=hook => relayoutHook := Some(hook),
    ~publishDockFit=hook => dockFitHook := Some(hook),
    // Adopt the board's shake control (#235) and, if Wiggle Waggle is already on,
    // start it listening straight away — this is what re-applies an active shake to a
    // board that mounts (or re-deals) after the switch was flipped.
    ~publishShake=control => {
      shakeControlHook := Some(control)
      if shakeActive.contents {
        control.start()
      }
    },
    ~onHistory=canUndo => reportHistory.contents(canUndo),
    // The deal number behind the board, resolved from what the scene can see to what
    // is actually true of the game on screen (#98).
    //
    // `Some(n)` is a board freshly dealt from `n` — the opening deal, a New Game, a
    // Restart. When this open is one that saves, the number is saved with it: it's
    // the one fact the history doesn't carry (see `SavedGame.saveSeed`), and without
    // it the *next* session's resumed game couldn't be shared at all.
    //
    // `None` from the scene means the board is showing something other than a deal's
    // opening position — a restored history or a forced state — and where the number
    // comes from then depends on which:
    //
    //   - a plain open is the resume path, and the deal number is exactly what was
    //     stored last time, so it's read back here;
    //   - a `?state=` scenario asks `core` which deal that position descends from
    //     (`Scenario.seedForName`). Only a scenario that has *proved* a line to itself
    //     answers — `almost-won` from deal 264 (#264) — so a posed board either offers
    //     the deal it genuinely came from or offers nothing;
    //   - a `#g=` shared game has a real position with no deal number attached to it,
    //     so there's nothing to name and the Share buttons stay dark rather than
    //     pointing at a board nobody is looking at.
    ~onDeal=seed =>
      publishDeal(
        switch seed {
        | Some(n) =>
          if plainOpen || (sharedOpen && shareLanded.contents) {
            SavedGame.saveSeed(game.id, n)
          }
          Some(n)
        | None =>
          plainOpen
            ? SavedGame.loadSeed(game.id)
            : url.state->Option.flatMap(name => Scenario.seedForName(game, name))
        },
      ),
    // The win overlay's Share button (#264): the same deal number the menu's Share
    // Seed offers, wrapped in a message and handed over when the player wins. It's
    // resolved here rather than in the board for the reason spelled out on `~onDeal`
    // above — a resumed game's number lives in this driver's storage, not in the
    // board — so `liveDealSeed` is the one place that knows, and both buttons read it.
    //
    // No deal number, no button: a posed `?state=` board or a game landed from a `#g=`
    // link has nothing truthful to offer, so the overlay is New Game alone rather than
    // a button that shares someone else's deal. (Those are the cases worth revisiting
    // — a shared game *does* descend from a deal, it just doesn't carry the number.)
    //
    // `deliver` is called with the click's transient activation intact: `urlForDeal`
    // is a string built from an int, so nothing is awaited between the tap and the
    // share sheet.
    ~winShare={
      available: () => liveDealSeed.contents->Option.isSome,
      share: (~moves) =>
        switch liveDealSeed.contents {
        | Some(seed) =>
          ShareLink.deliver(
            ~text=ShareLink.victoryMessage(~seed, ~moves),
            ShareLink.urlForDeal(seed),
          )->Promise.thenResolve(ShareLink.message)
        // Unreachable: the button is only built when `available` says yes, and nothing
        // can re-deal the board while the overlay covers it. Reporting the failure
        // line rather than throwing keeps that an honest dead end instead of a crash.
        | None => Promise.resolve(ShareLink.message(ShareLink.Failed))
        },
    },
    ~options,
    ~tiltEnabled,
    // Skip the opening-deal fly-in when the URL asks for `?animate=off`, so the
    // board is shown already dealt (the same instant placement reduced-motion gives).
    // A shared board skips the fly-in too: the cards it deals are about to be
    // replaced by the shared position, so animating them in only draws the eye to a
    // board that isn't the one being opened.
    ~skipDealAnimation=!url.animate || url.shared->Option.isSome,
    opening,
  )
}
let switcher = SceneSwitcher.render(
  ~default="freecell",
  ~forced=?url.scene,
  // Reset the per-scene hooks before each scene mounts (the mounting scene
  // republishes whichever apply) and close the menu after a row tap.
  ~onActivate=_scene => {
    newGameHook := None
    restartHook := None
    loadStateHook := None
    // Drop the outgoing board's share-link hooks; a demo scene publishes none, so
    // the Debug screen's share row correctly reports nothing to share there.
    readHistoryHook := None
    loadHistoryHook := None
    relayoutHook := None
    // …and its dock-refusal test (#275), so the console refuses to dock on a scene with
    // no board to dock beside until the mounting one publishes its own.
    dockFitHook := None
    // Drop the outgoing board's shake control (#235); its teardown already detached
    // the `devicemotion` listener. The mounting scene republishes its own, and the
    // `~publishShake` handler re-applies `shakeActive` to it.
    shakeControlHook := None
    // Drop the outgoing board's undo and reset the top bar's button to disabled;
    // the mounting scene republishes and reports its own history (#85).
    undoHook := None
    // …and its console hooks (#273), so a command typed on a scene with no board is
    // told so rather than reaching the board that scene replaced.
    consoleHook := None
    loadGameHook := None
    reportHistory.contents(false)
    // …and clear the deal number with it (#98), so the Share buttons are dark for the
    // moment between scenes; the mounting scene reports its own (a demo reports none).
    publishDeal(None)
    closeMenu.contents()
  },
  // A tap on the row for the game already showing: nothing mounts, so none of the
  // per-scene hooks above may be reset — they still belong to the live board — and
  // closing the menu is the whole response. The board carries on untouched.
  ~onReselect=() => closeMenu.contents(),
  Array.concat(
    [
      SpinnerScene.make(),
      SvgScene.make(),
      GalleryScene.make(),
      // The card-sprite fidelity check (#225). `?raster=` picks which of the
      // three renderings it opens on; without it the scene's own default wins.
      RasterScene.make(~rendering=?url.raster),
      MotionScene.make(),
    ],
    Game.all->Array.map(gameScene),
  ),
)

// Land a shared game on the board (`ShareLink`). The blob came off the `#g=`
// fragment synchronously, but inflating it is asynchronous — `DecompressionStream`
// has no synchronous form — so the board is already mounted from `gameScene`'s
// fixed opening deal by the time the history arrives, and this drops the real
// position onto it. That's one frame of a stable, un-animated FreeCell deal before
// the swap; both are arranged above precisely so this reads as the board settling
// rather than as a board changing its mind. The frame itself is #259.
//
// Landing is also the point the shared game takes over storage: `shareLanded` is
// set first, so the rebuild this triggers writes itself through `gameScene`'s
// persist sink and every later move follows it. From here on it's simply the saved
// game, indistinguishable from one dealt on this device.
//
// A blob that doesn't decode (truncated in the paste, or written by an incompatible
// `SaveState` version) leaves the dealt board exactly where it is: a bad link opens
// a playable game rather than an error. `shareLanded` stays false in that case, so
// the placeholder board is never saved and whatever game this device already had is
// still there on the next plain load.
switch url.shared {
| Some(blob) =>
  (
    async () =>
      switch await ShareLink.historyFrom(blob) {
      | Some(restored) =>
        shareLanded := true
        // The shared game takes over storage, so the previous game's deal number must
        // not stay behind to be read as its own (#98): a shared position was never
        // dealt from a number here, and a later resume asking "which deal is this?"
        // has to be told there isn't one rather than handed the last one this device
        // dealt for itself.
        SavedGame.clearSeed(Game.freecell.id)
        loadHistoryHook.contents->Option.forEach(load => load(restored))
      | None => DebugLog.message("share link: could not decode the shared game")
      }
  )()->ignore
| None => ()
}

// The debug "states" menu (sibling to the switcher's "Debug scenes"): one row per
// named FreeCell position (`Scenario.scenariosFor`). Tapping a row surfaces FreeCell
// — mounting it if a demo scene is showing — then forces that position onto the
// board through the mounted scene's `loadStateHook`, the live in-app twin of the
// URL's `?state=`. `ensureActive` runs first so the hook is FreeCell's, and closing
// the menu is explicit (a no-op if `ensureActive` already closed it on a scene
// change).
let debugStates = DebugStates.render(
  Scenario.scenariosFor(Game.freecell)->Array.map((scenario: Scenario.named): DebugStates.entry => {
    label: scenario.label,
    onSelect: () => {
      switcher.ensureActive("freecell")
      loadStateHook.contents->Option.forEach(load => load(scenario.build(Game.freecell)))
      // Say which deal the board is now showing, the menu twin of the `?state=` rule
      // above (#264): a posed position offers the deal it's been shown to descend from,
      // and nothing otherwise. This runs *after* the load because the rebuild it
      // triggers reports `None` through `~onDeal` on its way past — on a plain open
      // that resolves to the saved game's seed, which is the board this load has just
      // replaced. Correcting it here is what stops a debug jump from leaving the Share
      // buttons pointing at the deal the player was on a moment ago.
      publishDeal(scenario.seed)
      closeMenu.contents()
    },
  }),
)

let view = (model, dispatch) => <>
  <main id="app">
    <TopBar
      onMenu={() => dispatch(ToggleMenu)}
      onUndo={() =>
        switch undoHook.contents {
        | Some(undo) => undo()
        | None => ()
        }}
      canUndo={model.canUndo}
      updateVisible={model.updateAvailable}
    />
    <section id="scene-area">
      <div id="scene-box"> {Html.node(switcher.scene)} </div>
    </section>
  </main>
  // The drop-down debug console (#271). Only its shell is JSX; the scrollback itself
  // is a real `<ol>` the module appends to, spliced in with `Html.node` — the same
  // arrangement as the scene container above, and for the same reason (the reconciler
  // leaves a spliced node alone, so a growing log never re-patches its lines).
  <DebugConsole open_={model.consoleOpen} body={DebugConsole.lines} />
  <Menu
    open_={model.menuOpen}
    screen={model.menuScreen}
    onClose={() => dispatch(CloseMenu)}
    onOpenSettings={() => {
      // Re-detect the service-worker state each time Settings opens, so the button
      // reflects a worker that registered (or self-destructed) since page load.
      Refresh.detect(mode => dispatch(RefreshDetected(mode)))
      dispatch(OpenSettings)
    }}
    onBackToMenu={() => dispatch(BackToMenu)}
    onOpenDebug={() => {
      dispatch(OpenDebug)
      // Encode the board *now*, while the menu is going up, so the share button has a
      // link ready to hand straight to `navigator.share` without an `await` in front
      // of it (see `ShareLink.deliver`). Nothing can move the board until this screen
      // is dismissed, so the link stays current for as long as the row is on screen.
      // A scene with no history to read (a demo) resolves to `None` and the row
      // stays disabled.

      (
        async () =>
          switch currentHistory() {
          | Some(history) => dispatch(ShareLinkReady(await ShareLink.urlFor(history)))
          | None => dispatch(ShareLinkReady(None))
          }
      )()->ignore
    }}
    onBackToSettings={() => dispatch(BackToSettings)}
    onNewGame={() => {
      newGameHook.contents->Option.forEach(newGame => newGame())
      dispatch(CloseMenu)
    }}
    onRestart={() => {
      restartHook.contents->Option.forEach(restart => restart())
      dispatch(CloseMenu)
    }}
    shareDealSeed={model.dealSeed}
    shareDealStatus={model.shareDealStatus}
    onShareDeal={() =>
      // Share the *deal* (#98). The link is a `?seed=` string, so it's built right
      // here and handed straight to `deliver` — no `await` between the click and
      // `navigator.share`, which is what keeps the gesture's transient activation
      // intact for the OS share sheet (the Debug screen's whole-game share has to
      // encode ahead of time for exactly this reason; this one doesn't).
      //
      // The menu deliberately stays open, unlike New Game and Restart: the status
      // line under the buttons is the only confirmation the player gets, and on a
      // desktop browser — where the link goes quietly onto the clipboard with no OS
      // sheet to acknowledge it — closing over it would leave nothing to see. It
      // clears itself a few seconds later so it can't go stale.
      model.dealSeed->Option.forEach(seed =>
        ShareLink.deliver(ShareLink.urlForDeal(seed))
        ->Promise.thenResolve(outcome => {
          dispatch(ShareDealStatus(Some(ShareLink.message(outcome))))
          setTimeout(() => dispatch(ShareDealStatus(None)), shareStatusMs)->ignore
        })
        ->ignore
      )}
    games={switcher.controls}
    debugScenes={switcher.debugScenes}
    debugStates={debugStates}
    cutoutDebug={model.cutoutDebug}
    onToggleCutoutDebug={() => dispatch(ToggleCutoutDebug)}
    debugLog={model.debugLog}
    onToggleDebugLog={() => dispatch(ToggleDebugLog)}
    shareEnabled={model.shareUrl->Option.isSome}
    shareStatus={model.shareStatus}
    onShareGame={() =>
      // Straight into `deliver` with the link encoded on screen-open: no `await`
      // between the click and `navigator.share`, which is what keeps the gesture's
      // transient activation intact for the OS share sheet. The status line clears
      // itself a few seconds later so it doesn't sit there stale.
      model.shareUrl->Option.forEach(url =>
        ShareLink.deliver(url)
        ->Promise.thenResolve(outcome => {
          dispatch(ShareStatus(Some(ShareLink.message(outcome))))
          setTimeout(() => dispatch(ShareStatus(None)), shareStatusMs)->ignore
        })
        ->ignore
      )}
    autoCollect={model.autoCollect}
    onToggleAutoCollect={() => dispatch(ToggleAutoCollect)}
    cardTilt={model.cardTilt}
    onToggleCardTilt={() => dispatch(ToggleCardTilt)}
    wiggle={model.wiggle}
    onToggleWiggle={() =>
      // The single chance to ask (#235): flip *on* asks for the motion grant under
      // this real click's transient activation — iOS won't prompt without it and
      // remembers a denial per origin. Flip *off* just stops. An `Unavailable` switch
      // has nothing to grant, so a tap is inert.
      switch model.wiggle {
      | Motion.Unavailable(_) => ()
      | On => dispatch(WiggleOff)
      | Off | Blocked =>
        Motion.requestAccess()
        ->Promise.thenResolve(state => dispatch(WiggleResolved(state)))
        ->ignore
      }}
    notchDisplay={model.notchDisplay}
    onToggleNotchDisplay={() => dispatch(ToggleNotchDisplay)}
    revealHidden={model.hidden.revealed}
    onTapSettingsTitle={() => dispatch(SettingsTitleTapped)}
    refreshButton={switch model.refreshMode {
    | None | Some(Refresh.Unsupported) => None // still detecting, or unsupported — no button
    | Some(Refresh.NoWorker) =>
      Some({
        label: "Refresh",
        busy: model.refreshBusy,
        onClick: () => {
          dispatch(RefreshStarted)
          Refresh.forceReload()
        },
      })
    | Some(Refresh.HasWorker) =>
      Some({
        label: "Check for updates",
        busy: model.refreshBusy,
        onClick: () => {
          dispatch(RefreshStarted)
          Refresh.checkForUpdates(_pending => dispatch(RefreshChecked))
        },
      })
    }}
    version={model.version}
    buildTime={model.buildTime}
    updateVisible={model.updateAvailable}
    onReload={() => dispatch(Reload)}
  />
</>

// --- Wire it up --------------------------------------------------------------
Console.log(Core.greeting())

// A single wrapper is the loop's root so the reconciler owns a clean child list
// (mounting straight onto <body> would fight the module <script> already there).
// It's `display: contents` (see index.html) so it vanishes from layout and #app
// stays a direct flex child of <body>, exactly as before.
let root = WebDom.createElement("div")
root->WebDom.setAttribute("id", "app-root")
body->WebDom.appendChild(root)->ignore

// Publish which side any display cutout sits on (`data-cutout` on <html>) so the
// landscape chrome can put its control rail on the safe side (see CutoutSide and
// the `[data-cutout="left"]` landscape rules in index.html).
CutoutSide.install()

// Reflect the persisted "Display content around screen notch" preference (#204)
// onto the document root up front, so a player who turned wing placement off sees
// the clamped layout from the first paint rather than after a toggle.
NotchDisplay.setEnabled(notchDisplayEnabled)

// The safe-area debug overlay (a menu Debug-section toggle): built once here,
// hidden, and flipped live by ToggleCutoutDebug. A developer aid for spot-checking
// cutout detection on a device; session-only, not persisted.
CutoutDebug.install(~visible=false)

let dispatch = Html.mount(
  ~root,
  ~init={
    version: appVersion,
    buildTime,
    updateAvailable: false,
    menuOpen: false,
    // The menu opens on its main screen; Settings and Debug are swap-ins (#191).
    menuScreen: Menu.Main,
    // The debug console is closed on every load (#271) — it's opened by a keypress and
    // never remembered, so a rendered screenshot or link-preview image can't show one.
    consoleOpen: false,
    // …but *where* it opens is remembered (#275): the mode is a deliberate choice, so
    // it survives a reload. Nothing shows until a keypress opens the panel, so a
    // screenshot taken on a load with `docked` saved still sees an untouched board.
    consoleDock: consoleDockMode,
    // Mirror the persisted preferences so the menu's switches open in the right
    // position (the board reads the `options` and `tiltEnabled` refs directly).
    autoCollect: options.contents.autoCollect,
    cardTilt: tiltEnabled.contents,
    // The Wiggle Waggle switch opens in its computed startup state (#235): its saved
    // intent, or an `Unavailable` reason on a device/origin that can't do motion. The
    // real grant is deferred to the first board tap (wired at the foot of the file).
    wiggle: wiggleInit,
    // Mirror the persisted notch-display preference so the switch opens in the
    // right position; the layout itself is driven by the root attribute applied
    // above (see `NotchDisplay`).
    notchDisplay: notchDisplayEnabled,
    // Debug overlay starts off each session (not persisted); the model keeps it
    // across rotations.
    cutoutDebug: false,
    // Mirror the persisted console-logging preference (#213) so the switch opens in
    // the right position; the `DebugLog` gate itself was seeded above.
    debugLog: debugLogEnabled,
    // The hidden settings open showing or not according to whether this device has
    // ever completed the ten-tap unlock; the tap run always starts fresh.
    hidden: HiddenOptions.initial(~revealed=Preferences.loadRevealHidden()),
    // Seeded from the board's opening history report (#177): a fresh deal reports
    // `false` (nothing to undo yet), but a resumed game with a restored undo stack
    // reports `true`, and that report already fired during the switcher's initial
    // mount above — before `dispatch` existed — so it's read back from
    // `initialCanUndo` here rather than hardcoded off (#85).
    canUndo: initialCanUndo.contents,
    // The refresh button starts hidden until `Refresh.detect` reports the
    // service-worker state (#112); not busy until an action runs.
    refreshMode: None,
    refreshBusy: false,
    // The share row is filled in when the Debug screen opens (`ShareLink`), not at
    // startup — there's no point encoding a board nobody has asked to share.
    shareUrl: None,
    shareStatus: None,
    // Seeded from the board's opening deal report (#98), for the same reason
    // `canUndo` is: it fired during the switcher's initial mount above, before
    // `dispatch` existed. On a plain open that report *is* the deal number the Share
    // button offers, so reading it back here is what lets the button work on the
    // first menu open rather than only after a re-deal.
    dealSeed: initialDealSeed.contents,
    shareDealStatus: None,
  },
  ~update,
  ~view,
)

// Now that `dispatch` exists, let a scene row close the menu through it.
closeMenu := (() => dispatch(CloseMenu))

// …and arm the debug console's keys (#271): ` drops it over the board, ` or Escape puts
// it away. A window listener, so it works wherever the focus happens to be — the board
// is plain DOM with nothing focusable in the way.
DebugConsole.installKeys(
  ~onToggle=() => dispatch(ToggleConsole),
  ~onClose=() => dispatch(CloseConsole),
  // ⇧` docks it beside the board instead (#275). The board is asked *here*, at the
  // keypress, whether it can spare the width — the answer is live layout, so it can't
  // come from inside the loop's pure update.
  ~onDock=() => dispatch(ToggleConsoleDock(dockFits())),
)

// …and wire what the console's input line *does* with a typed line (#273). The grammar
// is shared with the CLI (`Command.parse`), and the split of who answers what follows
// the app's own shape: the chrome owns the verbs about the session and the panel (help,
// clear, dealing a new board — the things that live out here in `Main`), and everything
// board-shaped is forwarded to the live board's runner, which plays it through the very
// `dispatch` a pointer drop uses. So a typed `move 8H 5` and a dragged one are the same
// move, down to auto-collect, the undo step and the save.
//
// A reply of `""` means "the log already said it": `DebugLog` narrates the dispatch and
// core's answer either way, so an accepted move adds no line of its own and only the
// things the instrumentation can't say get one.
DebugConsole.setRunner(line => {
  let reply = switch Command.parse(line) {
  | Command.Blank => ""
  | Command.Help => DebugConsole.helpText()
  | Command.Clear =>
    DebugConsole.clear()
    ""
  | Command.Games => Command.gamesList()
  | Command.Unknown({verb}) => Command.describeUnknown(verb)
  | Command.Usage({message}) => message
  // Bare `deal`/`new` is the menu's New Game, reached the same way the button reaches
  // it, so a typed one is saved and reported like any other fresh deal.
  | Command.Deal({game: None}) =>
    switch newGameHook.contents {
    | Some(newGame) =>
      newGame()
      ""
    | None => "Nothing to deal on this scene."
    }
  // `deal <n>` opens a *chosen* deal number. Turning the number into a board is the
  // driver's job — only out here is it known that a deal is a seeded FreeCell shuffle
  // — so the number is resolved here and the resulting game handed to the board.
  | Command.Deal({game: Some(token)}) =>
    switch (Int.fromString(token), loadGameHook.contents) {
    | (Some(seed), Some(load)) =>
      load(Game.freecellDeal(~seed))
      ""
    | (Some(_), None) => "This scene doesn't play a numbered deal."
    | (None, _) => `Not a deal number: "${token}" (try a number, e.g. deal 12345).`
    }
  | board =>
    switch consoleHook.contents {
    | Some(run) => run(board)
    | None => "No board on this scene."
    }
  }
  if reply != "" {
    DebugConsole.say(reply)
  }
})

// Resume the shake grant on the first tap (#235). With `wantsShake` set, the switch
// opened optimistically `On`, but iOS may require transient activation to (re)confirm
// the grant, and it can have been revoked behind us — so we defer to the first user
// gesture rather than prompting at startup. This one-shot `pointerdown` listener asks
// `Motion.requestAccess` (which resolves silently if the grant survived the reload)
// and routes the outcome back through the loop: `On` starts listening, `Blocked` snaps
// the switch to off with its explanation. This is the spike's first-click listener,
// promoted from a hack to the resume path. Only armed when the switch actually opened
// listening — an off, blocked, or unavailable start has nothing to resume.
if Motion.isOn(wiggleInit) {
  let rec onFirstTap = _event => {
    WebDom.removeWindowListener("pointerdown", onFirstTap)
    Motion.requestAccess()
    ->Promise.thenResolve(state => dispatch(WiggleResolved(state)))
    ->ignore
  }
  WebDom.addWindowListener("pointerdown", onFirstTap)
}

// …and let the board's history reports reach the loop, so Undo enables and
// disables as moves are played and undone (#85).
reportHistory := (canUndo => dispatch(HistoryChanged(canUndo)))

// …and the same for the deal number (#98), so the Share button follows the board: a
// New Game's fresh deal, a Restart's same one, a scene switch to a board with none.
reportDeal := (seed => dispatch(DealChanged(seed)))

// Detect the service-worker state up front so the Settings refresh button opens
// with the right label (#112). It's re-detected each time Settings opens too (see
// the view), which also covers the first-load race where the worker registers
// just after this runs.
Refresh.detect(mode => dispatch(RefreshDetected(mode)))

// Now that `dispatch` exists, register the worker and let its callbacks drive
// the loop. Stash the returned updater so the Reload message can reach it.
updateSW := Some(registerSW(makeOptions(~onNeedRefresh=() => dispatch(UpdateAvailable))))
