// Web-app entry point. The app *opens as a game*: on startup it mounts the
// FreeCell board straight away (#109), and all the chrome — a single top bar plus
// a slide-over menu — is expressed as ReScript JSX on the `Html` runtime and
// driven by its Elm-style loop. The bottom of the screen is left
// clear for dragging cards; every control lives up top.
//
// The chrome is two components over the scene:
//   - `<TopBar>` — Menu · Undo. Always visible across the top; the Menu
//     button carries a green pip when a version update is waiting (#165).
//   - `<Menu>` — the slide-over holding the title ("Pip", moved out of the
//     retired Home scene), a **game** section (New · Restart · Share Seed, #156/#98), the
//     debug/demo scene list as tappable rows, and the About footer (build/version
//     info plus the conditional "Update" button beside it, #165).
// The scene area underneath is still the imperative `SceneSwitcher`, and its scene
// container is spliced into the scene band untouched with `Html.node`, which is
// exactly how a JSX chrome wraps a subtree it doesn't own. That container is now the
// *only* node it hands over: the menu's scene rows left as data (#336, #337), so the
// switcher is the mount/teardown engine and nothing else.

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
// `src/components/` (the menu's own under `components/menu/`). Each is a
// `props => vnode` function; capitalized JSX lowers
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
  // Where that console sits when it's up (#275): over the top of the board, docked into
  // the discarded width beside it, along the bottom, or over the whole window
  // (`ConsoleDock`). Unlike `consoleOpen` this *is* persisted — a placement you flip by
  // hand rather than an automatic breakpoint has to stay flipped — and it mirrors the
  // `Preferences` value like `debugLog` does.
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
  // Which scene is mounted (#337). The menu's games rows render their highlight from
  // this, so a scene change moves it through the diff rather than through a class
  // rewritten on a button the switcher kept hold of. Seeded from `switcher.active`
  // (the initial mount happens before this loop exists) and moved by `SceneActivated`
  // after that. `option` because a build with no scenes at all would have nothing
  // mounted; in practice there is always one.
  activeScene: option<string>,
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
  // (`ShareLink.urlForDeal`), so only the number has to be to hand — that, and the game
  // it's a deal of, which the press reads off `liveGame` rather than the model (#353).
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
  // ⇧` — step the console round its four placements (#275): top, side, bottom, full. The
  // flag is the *live board's* verdict on whether it can spare the side dock's width,
  // read at the keypress and carried in (like `RefreshDetected`) so `update` stays a pure
  // function of the model rather than reaching into the layout.
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
  | SceneActivated(string) // the switcher mounted a scene — which one the menu highlights (#337)
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

// The board on screen, and everything it offers this chrome (#300): one
// `TableScene.controls` record, handed over as the scene mounts (see `gameScene`) and
// dropped whole on every scene change (see the switcher's `onActivate`).
//
// It replaced eleven module-level `ref`s — `newGameHook`, `restartHook`,
// `loadStateHook`, `readHistoryHook`, `loadHistoryHook`, `relayoutHook`,
// `dockFitHook`, `shakeControlHook`, `undoHook`, `consoleHook`, `loadGameHook` — and
// the eleven-line reset that had to null each one by name when a scene changed.
// Nothing type-checked that that list was complete, so a twelfth hook nobody
// remembered to add to it was this chrome quietly driving a board that had been torn
// down: a stale-closure bug the compiler couldn't see. A scene swap now replaces the
// whole record, so there's no list left to get wrong.
//
// `None` means there's no board on the scene now showing — one of the debug/demo
// scenes, or the moment between two mounts. That's what lets the menu's New Game be a
// harmless no-op there and the console answer "no board on this scene" rather than
// silently doing nothing.
let liveBoard: ref<option<TableScene.controls>> = ref(None)

// The live board's saved game, or `None` on a scene that has none (a demo) or
// before a board has mounted. What the share button encodes — its undo/redo history
// and its play tally (#289), rebuilt into a board at the far end by
// `controls.loadHistory`.
let currentHistory = () => liveBoard.contents->Option.flatMap(board => board.readHistory())

// The game a `#g=` link brought, once it has actually reached the board — and `None`
// until then, which is most of what this is for. It gates saving on a shared open (see
// `gameScene`): a shared game takes over storage the moment it lands, but not before —
// the placeholder deal the board wears while the blob inflates must never be written
// over the player's own saved game, and a link that turns out to be corrupt must leave
// that game untouched.
//
// It carries the *game* rather than a bare "landed" flag because the blob names one
// (#354), and every scene has to be able to ask whether the link was for it: a link
// shared from Mini takes over Mini's save and leaves FreeCell's alone.
//
// A ref at all only because a shared open builds the board twice (#259) — and now also
// because the name arrives asynchronously, after every scene has been built. Close that
// gap and the placeholder build goes with it, and so does the need for this.
let sharedGame: ref<option<Game.t>> = ref(None)

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

// The *game* the board on the table is a board of (#353), the companion to
// `liveDealSeed`: a deal link now says which game its number belongs to, so a share
// needs both halves. Set beside `liveBoard` as a card table mounts (`gameScene` closes
// over its own game) and cleared with it on a scene change, so the two can't disagree
// about which board is on screen.
//
// A `ref` rather than a field on the model, deliberately. The win overlay's share is
// built by the board outside the loop and asks at the press, exactly as it does for the
// number — and a `Game.t` carries functions (`deal`), so putting one in the model would
// invite a whole-record `==` that `Game` says nothing does.
let liveGame: ref<option<Game.t>> = ref(None)

// Closing the menu means dispatching into the loop, but the switcher's activation
// callback runs before `dispatch` exists (like `updateSW`) — the initial scene mounts
// during module init. It reaches the loop through this ref, filled in just after mount.
let closeMenu: ref<unit => unit> = ref(() => ())

// The scene the switcher just mounted, on its way to the model's `activeScene` (#337).
// Same ref-until-mounted arrangement as `closeMenu`, and it can afford to *drop* the
// opening report the way `reportHistory` can't: the initial scene is `switcher.active`,
// which `init` reads directly, so the pre-dispatch default has nothing to remember.
let reportScene: ref<string => unit> = ref(_ => ())

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

// The persisted console placement (#275, defaults to the top overlay). Unlike the flag
// above there's nothing to apply at startup: the console is always closed on load, so
// the placement only reaches the document root once one is opened (see
// `ConsoleDock.reflect` — the attribute is published only while the panel shows).
let consoleDockMode = Preferences.loadConsoleDock()

// Whether the console may dock right now (#275), asked of the stage as it actually
// stands: "could you give up this many px of stage width and still deal cards above
// `minScale`?" (see `TableScene.controls.dockFit`). No board on the scene means no,
// since there's nothing to dock beside. Read at the keypress rather than inside
// `update`: the answer comes off live layout, and the loop's update stays a pure
// function of the model. Only the side dock ever asks; the other three placements cover
// the board rather than displacing it.
let dockFits = () =>
  switch liveBoard.contents {
  | Some(board) => board.dockFit(ConsoleDock.width)
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

// Whether the board *should* be listening for shakes right now (#235): true once
// Wiggle Waggle is on and permission is granted. Held outside the Elm model so a
// scene mount — which happens through the imperative switcher — can re-apply it to
// the board that just published its controls (see `~publish` in `gameScene`).
let shakeActive = ref(Motion.isOn(wiggleInit))

let update = (msg, model) =>
  switch msg {
  | UpdateAvailable => ({...model, updateAvailable: true}, Html.noEffect)
  // Opening or closing the menu resets it to the main screen, so a visit to
  // Settings never lingers into the next open (#191).
  // Every screen change also abandons a part-finished run of reveal taps
  // (`HiddenOptions.reset`), here and in the five branches below: the counter only
  // ever spans one uninterrupted visit to the Settings screen.
  // Opening the menu also puts an *overlapping* debug console away (#271): the menu is
  // the modal chrome and takes the screen for itself, and the console's twin rule below
  // closes the menu on the way in. A **side-docked** console is exempt (#275) — it's
  // beside the board rather than over the Menu button or under the menu's own panel, so
  // nothing is in anything's way, and leaving the log up is the point: flip a debug
  // setting and watch the line it emits.
  | ToggleMenu =>
    let menuOpen = !model.menuOpen
    let putConsoleAway = menuOpen && !ConsoleDock.isSide(model.consoleDock)
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
    let putMenuAway = consoleOpen && !ConsoleDock.isSide(model.consoleDock)
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
  // ⇧` steps to the next placement (#275). `fits` is the live board's verdict on whether
  // it can spare the side dock's width: a window too narrow *steps over* that placement
  // rather than landing on it — and says so in the log — instead of silently docking into
  // a board that would then deal cards below `minScale`. The three placements that cover
  // the board rather than displacing it are never refused; they fit any window by
  // construction, which is what keeps the key useful on a phone.
  //
  // The console comes up either way, skipped dock included: a placement you can't see
  // change isn't a placement, and the refusal is only legible in the panel it's about.
  | ToggleConsoleDock(fits) =>
    let consoleDock = ConsoleDock.nextFitting(model.consoleDock, ~roomToDock=fits)
    let refused = consoleDock != ConsoleDock.next(model.consoleDock)
    // Landing anywhere but the side dock while the menu is up is the exclusive case
    // again, so it takes the same exit `ToggleConsole` does.
    let putMenuAway = !ConsoleDock.isSide(consoleDock)
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

        // Both lines, when the dock was stepped over: why the placement you expected
        // didn't come up, and which one did instead.
        if refused {
          DebugLog.log("console", "too narrow to dock")
        }
        DebugLog.log("console", ConsoleDock.toString(consoleDock))
        Preferences.saveConsoleDock(consoleDock)
      },
    )
  // A scene mounted (#337). Only ever a scene *change* — the switcher answers a tap on
  // the row of the scene already showing with `~onReselect` instead, precisely so the
  // live board isn't torn down — so there's no no-change guard here to write.
  | SceneActivated(id) => ({...model, activeScene: Some(id)}, Html.noEffect)
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
        liveBoard.contents->Option.forEach(board => board.relayout())
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
        liveBoard.contents->Option.forEach(board => board.shake.stop())
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
          liveBoard.contents->Option.forEach(board => board.shake.start())
        | Blocked =>
          shakeActive := false
          liveBoard.contents->Option.forEach(board => board.shake.stop())
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
  // diff clearing a reused node's click handler.
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
// subtree. `render` hands back one real DOM node — the scene container, wrapped by
// the scene band and spliced in with `Html.node`, never re-rendered — plus the menu's
// scene lists as plain data for the chrome to draw (#336, #337).
//
// The app always opens on the FreeCell board: `~default="freecell"` is the launch
// scene, replacing the old "resume the last scene" behaviour — the game is always
// home. An explicit `?game=` or `?scene=` still wins (`~forced`), and `?state=` still
// forces a scenario, so the screenshot report's `?game=freecell&state=midgame` lands
// exactly where it says. `Game.all` is the source of truth for the game scenes; which
// of them is re-dealable is the game's own answer (`Game.t.deal`) — FreeCell's seeded
// shuffle today.
let url = AppUrl.parse()

// A fresh seed for each New Game (#108). The seed is the future "deal number"
// (#98): random for now, so every re-deal lays out a different board; a deal-number
// entry point can later supply a chosen seed to the game's own `deal`. `Math.random`
// is fine here — this is the impure view layer, not `core`'s deterministic deal path.
let randomSeed = () => (Math.random() *. 1_000_000.)->Float.toInt

// Only a *re-dealable* game gets a new board out of a new seed: one built from a seeded
// shuffle, which is FreeCell today. The fixed-layout demos have no deal to vary, so the
// board they publish offers no `newGame` and no `loadDeal` — the scene's `~newDeal`
// is what decides both (see `TableScene.controls`).
let gameScene = (game: Game.t) => {
  // The question every decision below turns on, asked of the game in hand rather than of
  // its id (#349): can this board deal another of itself? A second seeded game answers
  // yes on the day it's added, with no edit here.
  let canDeal = game.deal->Option.isSome
  // A *plain* open of a re-dealable game is the only place save-and-resume applies
  // (#177): the app's primary kind of game — one you can be handed a fresh board of —
  // opened without a URL asking for a specific position. A `?state=` scenario or a
  // `?seed=` deal link addresses an exact board, so it opens
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
  //
  // Which asks *whose* save it takes over, and the link now says (#354). Two questions,
  // asked at two different times, because the answer to the second isn't available when
  // this scene is built: inflating the blob is asynchronous, so at build time all any
  // scene knows is that some link is coming (`sharePending`), and only later does one of
  // them turn out to be the game it named (`sharedOpen`).
  let sharePending = canDeal && url.shared->Option.isSome
  let sharedOpen = () =>
    sharePending && sharedGame.contents->Option.mapOr(false, shared => shared.id == game.id)
  let plainOpen =
    canDeal && url.state->Option.isNone && url.seed->Option.isNone && url.shared->Option.isNone
  // Resume a saved game when there is one and this is a plain open; otherwise `None`
  // (nothing saved, corrupt/old data, or a URL-addressed board) means deal fresh.
  // Storage is read when the scene *mounts*, not here where it's built: a scene can
  // mount more than once (the switcher re-mounts on a scene change), and a value read
  // at build time is a snapshot of the save as it stood at page load, which a later
  // mount would restore over the game actually being played.
  let loadHistory = () => plainOpen ? SavedGame.load(game.id) : None

  // Open a re-dealable game from a fresh random seed on each load too (#108/#98), so a
  // plain reload with nothing saved lays out a new board instead of always deal #1 —
  // matching what New Game does. A `?seed=` pins that deal number instead (#98), so a
  // link — and the screenshot report's dealt-board shot — lands on the same board
  // every time. The game value as `Game.all` holds it (FreeCell's is deal #1) stays the
  // deterministic fallback for a forced `?state=` scenario, which screenshots depend
  // on: when a state is forced we mount that fixed deal so `Scenario.forName` derives
  // from the exact same board the report expects. The fixed-layout demos have no deal
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
  let opening = switch game.deal {
  | Some(deal) if !addressed => deal(url.seed->Option.getOr(randomSeed()))
  | _ => game
  }
  let newDeal = game.deal->Option.map(deal => () => deal(randomSeed()))
  TableScene.make(
    ~initial=?url.state->Option.flatMap(name => Scenario.forName(game, name)),
    // Restore the saved undo/redo stack (#177) and, when saving applies, hand the
    // board a sink that writes each change back to storage. New Game/Restart/every
    // move flow through this same sink, so the saved game always tracks the live one.
    ~loadHistory,
    // A plain open saves from the first build. A shared open saves too, but only
    // from the moment the shared game actually lands on *this* board (`sharedOpen`) —
    // the fixed deal the board is built from while the blob inflates is scaffolding,
    // and writing *that* to storage would clobber the player's own game with a board
    // nobody asked for. It also means a link that fails to decode — or one that names
    // another game (#354) — leaves this game's save exactly as it was: nothing landed
    // here, so nothing is written.
    //
    // The sink is wired for any scene a pending link *might* name, and the gate inside
    // it settles which one it actually did: the sink is called long after the blob has
    // inflated, so it can ask the question this scene couldn't answer when it was built.
    ~persist=?plainOpen || sharePending
      ? Some(
          saved =>
            if plainOpen || sharedOpen() {
              SavedGame.save(game.id, saved)
            },
        )
      : None,
    ~newDeal?,
    // Adopt the mounting board whole (#300) — its re-deals, Undo, console runner,
    // relayout, share-link hooks and shake control, in one record that replaces
    // whatever the outgoing scene left here. Then, if Wiggle Waggle is already on,
    // start the new board listening straight away: this is what re-applies an active
    // shake to a board that mounts after the switch was flipped.
    ~publish=board => {
      liveBoard := Some(board)
      // …and which game it's a board of (#353), for the two share links that now name
      // it. This is the one place that knows: the scene publishes controls, not the
      // `Game.t` they were built from, and `gameScene` has it in hand right here.
      liveGame := Some(game)
      if shakeActive.contents {
        board.shake.start()
      }
    },
    ~onHistory=canUndo => reportHistory.contents(canUndo),
    // The read side of `~onDeal`: what the console's printed board titles itself with.
    // `liveDealSeed` is the resolved number — the same one both Share buttons offer — so
    // a printed board names the deal the app would share, rather than re-deriving it from
    // a `game.seed` that a posed or resumed board would make a liar of.
    ~currentDeal=() => liveDealSeed.contents,
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
          if plainOpen || sharedOpen() {
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
      share: (~moves, ~undos) =>
        switch liveDealSeed.contents {
        | Some(seed) =>
          // The game is this scene's own, not `liveGame`'s: the overlay is over *this*
          // board, and the two say the same thing anyway (#353).
          ShareLink.deliver(
            ~text=ShareLink.victoryMessage(~game, ~seed, ~moves, ~undos),
            ShareLink.urlForDeal(~game, ~seed),
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
  // The launch scene, spelled as the game `core` says a nameless deal number belongs to
  // rather than as the literal `"freecell"` (#353). That's the same fact twice
  // otherwise, and the two halves of one property: `urlForDeal` omits `?scene=` for
  // `Game.default`, so a bare `?seed=7` has to land on `Game.default`'s scene for the
  // link to mean what it says. Written this way the round trip can't drift.
  ~default=Game.default.id,
  // What the URL asked to open, as a scene id. `?game=` is checked first because it is
  // the more specific claim — it names a board, and a board's scene is its id, so it
  // answers "which scene" as a side effect of answering "which game". `?scene=` is what
  // remains: the demos, and the scenes no game is behind.
  ~forced=?url.game->Option.map(game => game.id)->Option.orElse(url.scene),
  // Drop the outgoing board before each scene mounts (a mounting card table publishes
  // its own; a demo scene publishes none, which is how the chrome knows there's nothing
  // to drive), reset the two things the board *reports* rather than offers, and close
  // the menu after a row tap.
  ~onActivate=scene => {
    // One line, and it can't be incomplete (#300): where this used to null eleven hooks
    // by name — and a twelfth that nobody added to the list would have gone on driving
    // the torn-down board — the whole published surface goes at once. The outgoing
    // board's shake subscription is already detached by its own teardown, and
    // `~publish` re-applies `shakeActive` to whichever board mounts next.
    liveBoard := None
    // …and the game that board was a board of (#353), which goes with it: a demo scene
    // publishes neither, and the two must never be one scene apart.
    liveGame := None
    // Reset the top bar's Undo to disabled; the mounting scene reports its own
    // history (#85).
    reportHistory.contents(false)
    // …and clear the deal number with it (#98), so the Share buttons are dark for the
    // moment between scenes; the mounting scene reports its own (a demo reports none).
    publishDeal(None)
    // Move the menu's highlight to the scene coming up (#337). The switcher no longer
    // owns a row to mark, so this report *is* the highlight.
    reportScene.contents(scene.id)
    closeMenu.contents()
  },
  // A tap on the row for the game already showing: nothing mounts, so nothing above
  // may be reset — `liveBoard` still holds the board on screen — and closing the menu
  // is the whole response. The board carries on untouched.
  ~onReselect=() => closeMenu.contents(),
  Array.concat(
    [
      GalleryScene.make(),
      // The card-sprite fidelity check (#225). `?raster=` picks which of the
      // three renderings it opens on; without it the scene's own default wins.
      RasterScene.make(~rendering=?url.raster),
      // Step two of the same animation (#226): the overlay mechanics — a
      // transparent canvas over real cards, and the DOM→canvas hand-off.
      TrailScene.make(),
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
// **The blob says which game it is a game of** (#354), so the first thing that happens
// here is bringing that game's scene forward. `ensureActive` is exactly that job — mount
// the scene, or do nothing when it's already the one showing, which is the common case
// of a FreeCell link landing on the FreeCell the app launches into — and it's the same
// call the debug states menu makes for the same reason. Before this, the position was
// dropped onto whatever board happened to be mounted, which was safe only while there
// was one game to mount.
//
// Landing is also the point the shared game takes over storage: `sharedGame` is set
// before the history lands, so the rebuild that triggers writes itself through
// `gameScene`'s persist sink and every later move follows it. From here on it's simply
// the saved game of *that* game, indistinguishable from one dealt on this device.
//
// The order of those two is load-bearing. `ensureActive` may mount a board, and a
// mounting board persists its opening deal — so the scene has to come up while
// `sharedGame` is still `None`, or the scaffolding deal would be written over the
// player's own saved game of the game they were sent a link to.
//
// A blob that doesn't decode (truncated in the paste, written by an incompatible
// `SaveState` version, naming a game this build doesn't have, or carrying a board that
// doesn't fit the game it names) leaves the dealt board exactly where it is: a bad link
// opens a playable game rather than an error. `sharedGame` stays `None` in that case, so
// no board is mounted, the placeholder is never saved, and whatever game this device
// already had is still there on the next plain load.
switch url.shared {
| Some(blob) =>
  (
    async () =>
      switch await ShareLink.savedFrom(blob) {
      | Some({game, saved}) =>
        // Scene ids *are* game ids (`TableScene`'s `id: game.id`), so the game the blob
        // names is the scene to bring forward.
        switcher.ensureActive(game.id)
        sharedGame := Some(game)
        // The shared game takes over storage, so the previous game's deal number must
        // not stay behind to be read as its own (#98): a shared position was never
        // dealt from a number here, and a later resume asking "which deal is this?"
        // has to be told there isn't one rather than handed the last one this device
        // dealt for itself.
        //
        // The key is the *board being played*, not a hardcoded game (#349) — and since
        // #354 that board is named by the link rather than inferred from whichever
        // scene it opened onto, which is the same fact one step earlier.
        SavedGame.clearSeed(game.id)
        // Read *after* `ensureActive`, so this is the board of the game the link named
        // rather than the one that happened to be showing when the blob arrived.
        liveBoard.contents->Option.forEach(board => board.loadHistory(saved))
      | None => DebugLog.message("share link: could not decode the shared game")
      }
  )()->ignore
| None => ()
}

// The debug "states" menu (sibling to the switcher's "Debug scenes"): one row per
// named FreeCell position (`Scenario.scenariosFor`). Tapping a row surfaces FreeCell
// — mounting it if a demo scene is showing — then forces that position onto the
// board through the mounted board's `loadState` (#300), the live in-app twin of the
// URL's `?state=`. `ensureActive` runs first so the board is FreeCell's, and closing
// the menu is explicit (a no-op if `ensureActive` already closed it on a scene
// change).
//
// A list of entries rather than a built node: `<MenuDisclosure>` renders them — the
// same component the switcher's "scenes" group is drawn with (#336). Module-level,
// because nothing about a row depends on the chrome model — the same array is handed
// down on every render.
let debugStates = Scenario.scenariosFor(
  Game.freecell,
)->Array.map((scenario: Scenario.named): MenuDisclosure.entry => {
  label: scenario.label,
  onSelect: () => {
    switcher.ensureActive("freecell")
    liveBoard.contents->Option.forEach(board => board.loadState(scenario.build(Game.freecell)))
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
})

// Open a named game — and optionally one of its named positions — on the board: what the
// console's `deal <game> [position]` does now that a game id means the same thing here as
// it does in the CLI. These are the debug-states row's own two steps (surface the game's
// scene, then force the position onto it), reused rather than reimplemented, so a typed
// `deal freecell midgame` and a tapped "Mid-game" land on the very same board.
let openNamedDeal = (~game: Game.t, ~position: option<Scenario.named>): string => {
  // Scene ids *are* game ids (`TableScene`'s `id: game.id`), so this is how a demo game
  // gets on screen — and it's a no-op when that game is already showing.
  switcher.ensureActive(game.id)
  switch position {
  | Some(p) =>
    switch liveBoard.contents {
    | Some(board) =>
      board.loadState(p.build(game))
      // Say which deal the posed board descends from, for the same reason the menu row
      // does it (#264): the rebuild reports `None` on its way past, and leaving it there
      // would point the Share buttons at the deal the player was on a moment ago.
      publishDeal(p.seed)
      ""
    | None => `Can't pose a position on ${game.id} here.`
    }
  | None =>
    // No position named, so the scene now showing *is* the answer. For a seeded game
    // that still leaves which deal: pin its canonical one — the number the `Game.all`
    // value reports — so `deal freecell` means `deal 1` here exactly as it does in the
    // CLI, rather than whatever random board the mount happened to invent. A
    // fixed-layout demo has no seed and needs nothing more — mounting its scene dealt it.
    switch (game.seed, liveBoard.contents->Option.flatMap(board => board.loadDeal)) {
    | (Some(seed), Some(load)) =>
      load(seed)
      ""
    | _ => ""
    }
  }
}

// The menu's four prop records (#308). Each is the screen's own contract with this
// chrome, built here and handed to `<Menu>` whole — the pane places whichever screen
// `menuScreen` names and never looks inside. Grouping them this way is what lets a
// new setting be declared once in `Main` and once on the screen that shows it,
// rather than a third and fourth time on the way through the pane.

// The main screen (#109/#191): re-deal the board, share its deal number, pick a
// game, go on to Settings.
let mainScreen = (model, dispatch): MenuMainScreen.props => {
  onClose: () => dispatch(CloseMenu),
  onNewGame: () => {
    liveBoard.contents->Option.forEach(board => board.newGame->Option.forEach(deal => deal()))
    dispatch(CloseMenu)
  },
  onRestart: () => {
    liveBoard.contents->Option.forEach(board => board.restart())
    dispatch(CloseMenu)
  },
  shareDealSeed: model.dealSeed,
  shareDealStatus: model.shareDealStatus,
  onShareDeal: () =>
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
    //
    // Both halves of the link have to be to hand at once (#353): the number the model
    // carries, and the game the live board is a board of. A seed with no game behind it
    // is the moment between two scenes, and there's nothing to share then anyway — the
    // button is dark, so this is a guard rather than a case.
    switch (liveGame.contents, model.dealSeed) {
    | (Some(game), Some(seed)) =>
      ShareLink.deliver(ShareLink.urlForDeal(~game, ~seed))
      ->Promise.thenResolve(outcome => {
        dispatch(ShareDealStatus(Some(ShareLink.message(outcome))))
        setTimeout(() => dispatch(ShareDealStatus(None)), shareStatusMs)->ignore
      })
      ->ignore
    | _ => ()
    },
  // The games list (#337): the switcher's primary scenes, paired with the one the model
  // says is mounted. The switcher hands over scenes, not rows — which of them is
  // current is the chrome's to know, being what a re-render has to reflect — so the
  // `selected` flag and the tap are joined up here.
  games: switcher.primaryScenes->Array.map((scene): MenuRow.entry => {
    label: scene.label,
    selected: model.activeScene == Some(scene.id),
    onSelect: () => switcher.select(scene.id),
  }),
  onOpenSettings: () => {
    // Re-detect the service-worker state each time Settings opens, so the button
    // reflects a worker that registered (or self-destructed) since page load.
    Refresh.detect(mode => dispatch(RefreshDetected(mode)))
    dispatch(OpenSettings)
  },
}

// The Settings screen (#191): the player-facing preferences.
let settingsScreen = (model, dispatch): MenuSettingsScreen.props => {
  onClose: () => dispatch(CloseMenu),
  onBackToMenu: () => dispatch(BackToMenu),
  onOpenDebug: () => {
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
        | Some(saved) => dispatch(ShareLinkReady(await ShareLink.urlFor(saved)))
        | None => dispatch(ShareLinkReady(None))
        }
    )()->ignore
  },
  onTapSettingsTitle: () => dispatch(SettingsTitleTapped),
  autoCollect: model.autoCollect,
  onToggleAutoCollect: () => dispatch(ToggleAutoCollect),
  cardTilt: model.cardTilt,
  onToggleCardTilt: () => dispatch(ToggleCardTilt),
  wiggle: model.wiggle,
  onToggleWiggle: () =>
    // The single chance to ask (#235): flip *on* asks for the motion grant under
    // this real click's transient activation — iOS won't prompt without it and
    // remembers a denial per origin. Flip *off* just stops. An `Unavailable` switch
    // has nothing to grant, so a tap is inert.
    switch model.wiggle {
    | Motion.Unavailable(_) => ()
    | On => dispatch(WiggleOff)
    | Off | Blocked =>
      Motion.requestAccess()->Promise.thenResolve(state => dispatch(WiggleResolved(state)))->ignore
    },
  revealHidden: model.hidden.revealed,
  notchDisplay: model.notchDisplay,
  onToggleNotchDisplay: () => dispatch(ToggleNotchDisplay),
}

// The Debug screen: developer tools, a level below Settings.
let debugScreen = (model, dispatch): MenuDebugScreen.props => {
  onClose: () => dispatch(CloseMenu),
  onBackToSettings: () => dispatch(BackToSettings),
  cutoutDebug: model.cutoutDebug,
  onToggleCutoutDebug: () => dispatch(ToggleCutoutDebug),
  debugLog: model.debugLog,
  onToggleDebugLog: () => dispatch(ToggleDebugLog),
  shareEnabled: model.shareUrl->Option.isSome,
  shareStatus: model.shareStatus,
  onShareGame: () =>
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
    ),
  // Asked afresh on every render: the entry for the scene that's mounted now is the
  // `selected` one, and that's what puts the highlight in the menu.
  gameScenes: switcher.gameScenes(),
  gameScenesOpen: switcher.gameScenesOpen,
  debugScenes: switcher.debugScenes(),
  debugScenesOpen: switcher.debugScenesOpen,
  debugStates,
}

// The adaptive update-check control (#112), or `None` while the service-worker state
// is still being detected — and on a browser that has no `serviceWorker` at all,
// where there is nothing a button could do. `Refresh.mode` is what decides its shape:
// "Refresh" force-reloads a cache-only install, "Check for updates" checks a real one
// without applying it.
let refreshControl = (model, dispatch): option<RefreshControl.props> =>
  switch model.refreshMode {
  | None | Some(Refresh.Unsupported) => None
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
  }

// The About footer, under all three screens: the build/version line, the Update
// button when a new build is waiting (#165), and the update-check control tucked
// under them.
let aboutFooter = (model, dispatch): AboutFooter.props => {
  version: model.version,
  buildTime: model.buildTime,
  updateVisible: model.updateAvailable,
  onReload: () => dispatch(Reload),
  // Shown on the Settings and Debug screens once a worker state has been detected,
  // and never on the main menu — which is where the detection is kicked off (see
  // `mainScreen`'s `onOpenSettings` above). Both halves of that rule are known here,
  // so the footer takes a ready-made node and stays a dumb layout.
  refresh: switch (model.menuScreen, refreshControl(model, dispatch)) {
  | (Menu.Main, _) | (_, None) => Html.empty
  | (_, Some(control)) => RefreshControl.make(control)
  },
}

let view = (model, dispatch) => <>
  <main id="app">
    <TopBar
      onMenu={() => dispatch(ToggleMenu)}
      onUndo={() => liveBoard.contents->Option.forEach(board => board.undo())}
      canUndo={model.canUndo}
      updateVisible={model.updateAvailable}
    />
    <section id="scene-area">
      <div id="scene-box"> {Html.node(switcher.scene)} </div>
    </section>
  </main>
  // The drop-down debug console (#271). Only its shell is JSX; the scrollback itself
  // is a real `<ol>` the module appends to, spliced in with `Html.node` — the same
  // arrangement as the scene container above, and for the same reason (a spliced
  // node's subtree is outside the diff, so a growing log never re-patches its lines).
  <DebugConsole open_={model.consoleOpen} body={DebugConsole.lines} />
  <Menu
    open_={model.menuOpen}
    screen={model.menuScreen}
    onClose={() => dispatch(CloseMenu)}
    main={mainScreen(model, dispatch)}
    settings={settingsScreen(model, dispatch)}
    debug={debugScreen(model, dispatch)}
    about={aboutFooter(model, dispatch)}
  />
</>

// --- Wire it up --------------------------------------------------------------
Console.log(Core.greeting())

// A single wrapper is the loop's root so the diff owns a clean child list
// (mounting straight onto <body> would fight the module <script> already there).
// It's `display: contents` (see styles/app-shell.css) so it vanishes from layout and #app
// stays a direct flex child of <body>, exactly as before.
let root = WebDom.createElement("div")
root->WebDom.setAttribute("id", "app-root")
body->WebDom.appendChild(root)->ignore

// Publish which side any display cutout sits on (`data-cutout` on <html>) so the
// landscape chrome can put its control rail on the safe side (see CutoutSide and
// the `[data-cutout="left"]` rules in styles/landscape-rail.css).
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
    // The scene the switcher mounted on its way up (#337) — read straight off it,
    // since the mount above happened before this loop existed and so before any
    // message could carry the news. Every later change arrives as `SceneActivated`.
    // Unlike `canUndo` and `dealSeed` below this needs no capturing ref: the value is
    // the switcher's own, not something a board reported into a callback.
    activeScene: switcher.active,
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

// Now that `dispatch` exists, let a scene row close the menu through it — and let a
// scene change move the menu's highlight (#337) the same way.
closeMenu := (() => dispatch(CloseMenu))
reportScene := (id => dispatch(SceneActivated(id)))

// …and arm the debug console's keys (#271): ` drops it over the board, ` or Escape puts
// it away. A window listener, so it works wherever the focus happens to be — the board
// is plain DOM with nothing focusable in the way.
DebugConsole.installKeys(
  ~onToggle=() => dispatch(ToggleConsole),
  ~onClose=() => dispatch(CloseConsole),
  // ⇧` steps it round its four placements instead (#275). The board is asked *here*, at the
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
  | Command.Blank => []
  | Command.Help => Render.text(DebugConsole.helpText())
  | Command.Clear =>
    DebugConsole.clear()
    []
  | Command.Games => Render.text(Command.gamesList())
  | Command.Settings => Render.text(Command.describeSettings(options.contents))
  // The driver's flags, typed rather than switched. Auto-collect goes through the menu's
  // own action rather than straight to the ref, so the switch and the saved preference
  // stay in step with a typed change — it *toggles*, hence the guard. The column-reorder
  // house rule (#159) has no switch anywhere, so the console is the only way to reach it:
  // the board reads the ref live at each move, so it takes hold on the very next one.
  | Command.Set({setting, on}) =>
    switch setting {
    | Options.AutoCollect =>
      if options.contents.autoCollect != on {
        dispatch(ToggleAutoCollect)
      }
    | Options.ColumnReorder => options := Options.apply(options.contents, ~setting, ~on)
    }
    Render.text(Command.describeSet(~setting, ~on))
  // The CLI's session verb, answered here rather than forwarded: a panel isn't a
  // session you leave, it's chrome you close, and the keys that close it are on the
  // status line. This is the mirror image of the CLI accepting `clear` as a no-op —
  // both front ends know every verb, even the ones only one of them can act on.
  | Command.Quit => Render.text("Nothing to quit — press ` or esc to close the console.")
  | Command.Unknown({verb}) => Render.text(Command.describeUnknown(verb))
  // A shorthand that fit more than one verb — refused by name rather than guessed at
  // (see `Command.resolveVerb`), and refused out here for the same reason an unknown
  // verb is: nothing about it is a question for the board.
  | Command.Ambiguous({verb, matches}) => Render.text(Command.describeAmbiguous(~verb, ~matches))
  | Command.Usage({message}) => Render.text(message)
  // Every shape of `deal` reads the same here as in the terminal, because the *reading*
  // is `core`'s (`Command.resolveDeal`) and only the acting is ours. What the panel used
  // to do was refuse anything that wasn't a number — including the games its own `games`
  // command listed — so this is where that stops.
  | Command.Deal({game, scenario}) =>
    switch Command.resolveDeal(~game, ~scenario) {
    // Bare `deal`/`new` is the menu's New Game, reached the same way the button reaches
    // it, so a typed one is saved and reported like any other fresh deal.
    | Command.Fresh =>
      switch liveBoard.contents->Option.flatMap(board => board.newGame) {
      | Some(newGame) =>
        newGame()
        []
      | None => Render.text("Nothing to deal on this scene.")
      }
    // `deal <n>` opens a *chosen* deal number, on the board it's typed at: the number
    // goes straight to the live board, which lays it out with its own game's deal
    // (#349). This used to build the board out here from `Game.freecellDeal`, which
    // meant a console command deciding for itself which game a number belonged to.
    | Command.Numbered({seed}) =>
      switch liveBoard.contents->Option.flatMap(board => board.loadDeal) {
      | Some(load) =>
        load(seed)
        []
      | None => Render.text("This scene doesn't play a numbered deal.")
      }
    | Command.Named({game, position}) => Render.text(openNamedDeal(~game, ~position))
    | Command.NoSuchGame({id}) => Render.text(Command.describeNoSuchGame(id))
    | Command.NoSuchScenario({game, name}) =>
      Render.text(Command.describeNoSuchScenario(~game, ~name))
    }
  // `redeal`/`restart` is the menu's Restart button as a verb — the same action on the
  // same record, so it replays the deal on the table with a clean history exactly as the
  // button does.
  | Command.Redeal =>
    switch liveBoard.contents {
    | Some(table) =>
      table.restart()
      []
    | None => Render.text("Nothing to restart on this scene.")
    }
  | board =>
    switch liveBoard.contents {
    | Some(table) => table.runCommand(board)
    | None => Render.text("No board on this scene.")
    }
  }
  // An empty document says nothing, which is how a command whose result `DebugLog`
  // already narrates stays quiet — no guard needed out here any more.
  DebugConsole.say(reply)
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

// Refuse the browser's double-tap-to-zoom gesture app-wide. `styles/base.css`
// already asks for this with `touch-action: manipulation`, which iOS ignores in the
// home-screen web app; `TapZoom` enforces the same policy in the touch layer. Armed
// once here rather than per-scene, since the listener is on `document`.
TapZoom.arm()

// Detect the service-worker state up front so the Settings refresh button opens
// with the right label (#112). It's re-detected each time Settings opens too (see
// the view), which also covers the first-load race where the worker registers
// just after this runs.
Refresh.detect(mode => dispatch(RefreshDetected(mode)))

// Now that `dispatch` exists, register the worker and let its callbacks drive
// the loop. Stash the returned updater so the Reload message can reach it.
updateSW := Some(registerSW(makeOptions(~onNeedRefresh=() => dispatch(UpdateAvailable))))
