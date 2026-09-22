// Web-app entry point. The app *opens as a game*: on startup it mounts the
// FreeCell board straight away, and all the chrome — a single top bar plus
// a slide-over menu — is expressed as ReScript JSX on the `Html` runtime and
// driven by its Elm-style loop. The bottom of the screen is left
// clear for dragging cards; every control lives up top.
//
// The chrome is two components over the scene:
//   - `<TopBar>` — Menu · Undo. Always visible across the top; the Menu
//     button carries a green pip when a version update is waiting.
//   - `<Menu>` — the slide-over holding the title ("Pip", moved out of the
//     retired Home scene), a **this game** section (Restart · Share) and a **new
//     game** one (New Deal · Enter Seed), the debug/demo scene list as tappable rows,
//     and the About footer (build/version info plus the conditional "Update" button
//     beside it).
//   - `<SeedDialog>` — the modal Enter Seed raises, over the menu and over
//     everything else; it is in the tree only while it's showing.
// The scene area underneath is still the imperative `SceneSwitcher`, and its scene
// container is spliced into the scene band untouched with `Html.node`, which is
// exactly how a JSX chrome wraps a subtree it doesn't own. That container is now the
// *only* node it hands over: the menu's scene rows left as data, so the
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
// `<DebugConsole/>` and `<SeedDialog/>` — live under
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
  // Which screen the open menu shows: the main menu, the Settings
  // screen, or the Debug screen nested below it. Reset to `Main` whenever the menu
  // opens or closes, so reopening always lands on the main menu.
  menuScreen: Menu.screen,
  // Whether the drop-down debug console is showing. Dev chrome, so it lives
  // here in the chrome model and never reaches `core`'s reducer — and it's session
  // state, deliberately unpersisted: the panel is always closed on load, so a
  // rendered screenshot or OG image can never carry one.
  consoleOpen: bool,
  // Where that console sits when it's up: over the top of the board, docked into
  // the discarded width beside it, along the bottom, or over the whole window
  // (`ConsoleDock`). Unlike `consoleOpen` this *is* persisted — a placement you flip by
  // hand rather than an automatic breakpoint has to stay flipped — and it mirrors the
  // `Preferences` value like `debugLog` does.
  consoleDock: ConsoleDock.t,
  // The Settings screen's own state, embedded whole. Every player-facing preference is
  // declared, flipped and written through in `MenuSettingsScreen` — this loop carries
  // the model, maps the screen's messages up through `SettingsMsg`, and never reads
  // inside it. The two switches below are the Debug screen's, which is still driven the
  // flat way.
  settings: MenuSettingsScreen.model,
  cutoutDebug: bool,
  // "Console logging": the Debug screen's switch for narrating every UI↔Core
  // interaction to the JS console. Mirrors the persisted `Preferences` flag (like
  // `cutoutDebug`) so the switch opens in the right position; the logging itself is
  // driven by the shared `DebugLog.enabled` gate the toggle flips.
  debugLog: bool,
  // The mirror the Debug screen's cascade sliders render from; `cascadeFade` (above) is
  // the copy the board reads, written through on every drag. Two copies for the reason
  // the settings switches have two — a control renders from the model, and the board
  // reads a ref — and `SetCascadeFade` is what keeps them one value.
  cascade: CascadePlayer.fade,
  // Which scene is mounted. The menu's games rows render their highlight from
  // this, so a scene change moves it through the diff rather than through a class
  // rewritten on a button the switcher kept hold of. Seeded from `switcher.active`
  // (the initial mount happens before this loop exists) and moved by `SceneActivated`
  // after that. `option` because a build with no scenes at all would have nothing
  // mounted; in practice there is always one.
  activeScene: option<string>,
  // Which variant of each family the Games list is offering — a board's game id under
  // its family's id (`Game.families`). In the model because tapping the segment has to
  // re-render that row, and because a variant chosen while another game is on the table
  // changes nothing else: it is remembered, not played. A board of a family mounting
  // sets its family's entry too, so a row shows the board you are actually playing
  // however you arrived at it.
  //
  // A family with no entry falls back to its default, so this starts out holding only
  // what storage remembered (`openingVariants`) and never has to be complete.
  variants: Dict.t<string>,
  canUndo: bool,
  // The adaptive Settings refresh control. `refreshMode` is `None` until
  // `Refresh.detect` resolves (and stays effectively hidden on an unsupported
  // browser); it decides the button's "Refresh" vs "Check for updates" shape.
  // `refreshBusy` is whether a check/refresh is in flight — it spins the on-button
  // indicator rather than a status line beneath it.
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
  // The Debug screen's "Autoplay" row: what the solver had to say, standing in for the
  // row's description until the screen is left. Only ever a refusal or the word that
  // the search has started — a line the solver *found* takes the menu down with it, so
  // there is nothing left here to read it on.
  autoplayStatus: option<string>,
  // The main menu's "this game" section: the seed of the board on the table, which the
  // heading names and Share hands over a link to, reported by the scene (`~onDeal`
  // below) — and the transient line under the buttons
  // reporting where its link went. `None` greys the button out — a demo scene, or a
  // game resumed from a save with no deal number recorded. Unlike `shareUrl` above
  // there's nothing to prepare: the link is a `?seed=` string built on the press
  // (`ShareLink.urlForDeal`), so only the number has to be to hand — that, and the game
  // it's a deal of, which the press reads off `liveGame` rather than the model.
  dealSeed: option<int>,
  shareDealStatus: option<string>,
  // The "Enter seed" modal: whether it's up, and what's been typed into it. The text
  // is a string rather than a number because it is the *text* in the field, which is
  // only sometimes a deal number, and the field can't hold it itself (see
  // `SeedDialog`).
  //
  // Both belong to the open menu rather than to the session — the menu closing takes
  // the dialog with it and clears the field, the way the screen resets to Main and the
  // ten-tap counter goes back to zero. A menu reopened is a menu as it first opens.
  seedDialogOpen: bool,
  seedInput: string,
}

type msg =
  | UpdateAvailable // a new build is waiting in the wings
  | Reload // user asked to activate the waiting worker and reload
  | ToggleMenu // the top bar's Menu button
  | CloseMenu // backdrop / close button / a scene row was tapped
  | ToggleConsole // the ` key — drop the debug console over the board, or put it away
  | CloseConsole // Escape while the console is showing
  // ⇧` — step the console round its four placements: top, side, bottom, full. The
  // flag is the *live board's* verdict on whether it can spare the side dock's width,
  // read at the keypress and carried in (like `RefreshDetected`) so `update` stays a pure
  // function of the model rather than reaching into the layout.
  | ToggleConsoleDock(bool)
  | OpenSettings // the main menu's Settings button — swap to the Settings screen
  | BackToMenu // the Settings screen's back button — swap back to the main menu
  | OpenDebug // the Settings screen's Debug row — swap to the Debug screen
  | OpenAbout // the main menu's About button — swap to the About screen
  | BackToSettings // the Debug screen's back button — swap back to Settings
  // The "i" beside a game's row, and the info screen's own picker — show that game's
  // info screen. The *facts* travel rather than a bare id: `GameInfo.forGame` is what
  // turns a game into them, and the view has already had to resolve the game to know
  // there is one.
  | OpenGameInfo(GameInfo.t)
  // Everything the Settings screen does, in one constructor. The screen's own messages
  // travel up inside it and go straight back down to its `update`; what each of them
  // means is that file's business, not this one's.
  | SettingsMsg(MenuSettingsScreen.msg)
  | ClearStoredState // the Debug screen's "Clear saved data" — forget the device, reopen
  | ToggleCutoutDebug // the menu's safe-area overlay switch (debug)
  | ToggleDebugLog // the Debug screen's console-logging switch
  | SetCascadeFade(CascadePlayer.fade) // a Debug-screen cascade slider, dragged
  | SceneActivated(string) // the switcher mounted a scene — which one the menu highlights
  | VariantChosen(string) // a family's segment tapped, with no board of it up
  | HistoryChanged(bool) // whether the board can undo after a move
  | RefreshDetected(Refresh.mode) // service-worker presence detected — sets the button's shape
  | RefreshStarted // the refresh button was tapped — start spinning the button
  | RefreshChecked // an update check finished — stop the spinner (a found update surfaces as the About button)
  | ShareLinkReady(option<string>) // the open Debug screen's board, encoded into a link (`ShareLink`)
  | ShareStatus(option<string>) // the share row's transient status line; `None` clears it
  | AutoplayStatus(option<string>) // what the solver said, in the Autoplay row's description
  | DealChanged(option<int>) // the board reported which deal it's showing
  | ShareDealStatus(option<string>) // the Share button's transient status line; `None` clears it
  | OpenSeedDialog // the main menu's Enter Seed button — raise the modal over the menu
  | CloseSeedDialog // its Cancel, or a tap on the dim behind it
  | SeedTyped(string) // a keystroke in the seed dialog's field

// `updateSW` only exists once registerSW has run, which needs `dispatch`, which
// needs the loop to be mounted — so the Reload effect reaches it through a ref
// that's filled in just after mount (see below).
let updateSW: ref<option<bool => promise<unit>>> = ref(None)

// The board on screen, and everything it offers this chrome: one
// `TableScene.controls` record, handed over as the scene mounts (see `gameScene`) and
// dropped whole on every scene change (see the switcher's `onActivate`).
//
// `None` means there's no board on the scene now showing — one of the debug/demo
// scenes, or the moment between two mounts. That's what lets the menu's New Game be a
// harmless no-op there and the console answer "no board on this scene" rather than
// silently doing nothing.
let liveBoard: ref<option<TableScene.controls>> = ref(None)

// The live board's saved game, or `None` on a scene that has none (a demo) or
// before a board has mounted. What the share button encodes — its undo/redo history
// and its play tally, rebuilt into a board at the far end by
// `controls.loadHistory`.
let currentHistory = () => liveBoard.contents->Option.flatMap(board => board.readHistory())

// The game a `#g=` link brought, once it has actually reached the board — and `None`
// until then, which is most of what this is for. It gates saving on a shared open (see
// `gameScene`): a shared game takes over storage the moment it lands, but not before —
// the placeholder deal the board wears while the blob inflates must never be written
// over the player's own saved game, and a link that turns out to be corrupt must leave
// that game untouched.
//
// It carries the *game* rather than a bare "landed" flag because the blob names
// one, and every scene has to be able to ask whether the link was for it: a link
// shared from Mini takes over Mini's save and leaves FreeCell's alone.
//
// A ref at all only because a shared open builds the board twice — and now also
// because the name arrives asynchronously, after every scene has been built. Close that
// gap and the placeholder build goes with it, and so does the need for this.
let sharedGame: ref<option<Game.t>> = ref(None)

// --- The seam with the board --------------------------------------------------
// The refs below all exist for one ordering fact: **the first board mounts during
// module init, before `Html.mount` has returned a `dispatch`.** Each channel gets a
// pre-mount stand-in, filled with a real dispatcher just after mount, and two of them
// have to *remember* what they were told rather than dropping it.
//
// `docs/board-driver.md` § Why the reverse channels are refs *in the driver* has the
// table of which is which, and what breaks without each.

// Stashed by the pre-mount `reportHistory` and read by `init`. Without it a resumed
// game whose restored stack can already undo opens with Undo wrongly disabled.
let initialCanUndo = ref(false)

// Reset to `false` on each scene change, so a non-game scene leaves the button off.
let reportHistory: ref<bool => unit> = ref(canUndo => initialCanUndo := canUndo)

// The same, for the deal number — and here it's the ordinary case rather than a
// corner, since every plain open deals a board and reports its number during init.
// Without it the Share button opens dark on every load.
let initialDealSeed: ref<option<int>> = ref(None)

let reportDeal: ref<option<int> => unit> = ref(seed => initialDealSeed := seed)

// The menu's Share renders from the *model*, but the win overlay's Share button
// is built by the board itself, outside the loop, and asks at the moment the overlay
// goes up — so it needs the live value rather than a dispatched copy.
let liveDealSeed: ref<option<int>> = ref(None)

// Every report goes through here, which is what keeps the two from drifting: a board
// whose number the menu knows and the win overlay doesn't would be a Share button
// lying about which deal it offers.
let publishDeal = (seed: option<int>): unit => {
  liveDealSeed := seed
  reportDeal.contents(seed)
}

// The companion to `liveDealSeed`, since a deal link now names its game too. Set
// beside `liveBoard` as a card table mounts and cleared with it, so the two can't
// disagree about which board is on screen.
//
// A `ref` rather than a model field for the same reason as the number — and because a
// `Game.t` carries functions, so putting one in the model would invite a whole-record
// `==` that `Game` says nothing does.
let liveGame: ref<option<Game.t>> = ref(None)

let closeMenu: ref<unit => unit> = ref(() => ())

// **A scene change the menu asked for as a change of state rather than of place.**
// Cycling a family's pack while that family's board is up swaps the board for the next
// pack's — a scene change like any other, except that the control doing it is one you
// watch as you tap it, so the menu has to stay put. Every other activation is a
// departure (a row tap, a link landing), which is why closing the menu is what
// `~onActivate` does by default and this is the one thing that asks it not to.
//
// A ref rather than an argument because it is read inside the switcher's own callback,
// one call away from the tap that sets it, and it is lowered again the moment
// `select` returns — `onActivate` runs synchronously inside it.
let keepMenuOpen = ref(false)

// **A board mounted under the open menu, waiting to be seen.** The board hands its
// opening over as a thunk rather than playing it (`~onceUncovered`), and the one mount
// that happens with the menu up — the segment's swap, under `keepMenuOpen` — is the one
// whose thunk is held here instead of run. Whatever closes the menu runs it
// (`releaseHeldDeal`), so the cards a player couldn't see dealt fly in as the pane
// goes, the way a row tap's do, and a fresh deal becomes theirs at that moment rather
// than as it was built (`gameScene`'s `reveal`). Cleared as any scene activates: a
// board torn down with its deal still waiting has nothing left to play, and a fresh
// one never written was never there.
let heldDeal: ref<option<unit => unit>> = ref(None)
let releaseHeldDeal = () =>
  switch heldDeal.contents {
  | Some(release) =>
    heldDeal := None
    release()
  | None => ()
  }

// This one can afford to *drop* its opening report the way `reportHistory` can't: the
// initial scene is `switcher.active`, which `init` reads directly.
let reportScene: ref<string => unit> = ref(_ => ())

// --- The live preferences -----------------------------------------------------
// Refs, not values, because the board reads them at the moment of use: flipping a
// switch lands on the very next move — or the next relayout, for the tilt — without
// rebuilding the board and throwing the game away. The Settings screen holds the
// mirror the switches render from and writes these on every flip; the driver's job is
// to own them, since they belong to the board rather than to any one screen.

let options: ref<Options.t> = ref(Preferences.load())
let tiltEnabled: ref<bool> = ref(Preferences.loadCardTilt())

// How the victory cascade dims its trail, read by the board the moment a game is won.
// A ref for the reason the two above are — the board is not rebuilt when a slider moves,
// and a run started from a stale value would be the wrong animation for the length of a
// celebration.
//
// **Nothing loads or saves it.** It is a debug knob, not a preference: the Debug screen
// is where it is dragged and a reload is how it is reset, which is the whole of what
// "in memory" buys — no storage key to migrate, and no way to leave the app permanently
// tuned to something nobody meant to keep.
let cascadeFade: ref<CascadePlayer.fade> = ref(CascadePlayer.defaultFade)

// The "Beta features" flag, a ref for a reason of its own — nothing on the board reads
// it. It is read where the Elm model can't reach: the switcher's `~primary` (`menuGames`
// below), which files scenes into menu groups afresh on every render, and first during
// module init, before the chrome exists at all. Seeded from storage here and rewritten
// by the switch through `settingsEnv.publish`, which is what lands a flip on the next
// menu render rather than the next launch.
let betaFeatures: ref<bool> = ref(Preferences.loadBetaFeatures())

// The persisted "Console logging" preference (defaults off). Read once at
// startup to seed both the model's toggle and the shared `DebugLog` gate, and the gate
// is opened straight away — before the first board is built below — so a developer who
// left logging on sees the opening deal's UI↔Core traffic too, not only interactions
// after the first in-app toggle.
let debugLogEnabled = Preferences.loadDebugLog()
DebugLog.setConsoleEnabled(debugLogEnabled)

// The persisted console placement (defaults to the top overlay). Unlike the flag
// above there's nothing to apply at startup: the console is always closed on load, so
// the placement only reaches the document root once one is opened (see
// `ConsoleDock.reflect` — the attribute is published only while the panel shows).
let consoleDockMode = Preferences.loadConsoleDock()

// Whether the console may dock right now, asked of the stage as it actually
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

// --- The Settings screen's state ----------------------------------------------
// The screen reads its own opening state from where each setting lives
// (`MenuSettingsScreen.init`), and the driver supplies only the reach a component can't
// have: the refs above, and a way through to the board on the table.

let settingsInit = MenuSettingsScreen.init()

// Whether the board *should* be listening for shakes right now: true once
// Wiggle Waggle is on and permission is granted. Held outside the Elm model so a
// scene mount — which happens through the imperative switcher — can re-apply it to
// the board that just published its controls (see `~publish` in `gameScene`).
let shakeActive = ref(MenuSettingsScreen.listening(settingsInit))

// A settings flip's reach into the board, resolved against whichever board is on the
// table. A demo scene has none, and the request is dropped — the same "no board here"
// answer New Game gives.
let settingsBoard = (request: MenuSettingsScreen.request) =>
  liveBoard.contents->Option.forEach(board =>
    switch request {
    | MenuSettingsScreen.Relayout => board.relayout()
    | ShakeStart => board.shake.start()
    | ShakeStop => board.shake.stop()
    }
  )

let settingsEnv = MenuSettingsScreen.liveEnv(
  ~options,
  ~tiltEnabled,
  ~shakeActive,
  ~betaFeatures,
  ~board=settingsBoard,
)

// Put the opening settings where the rest of the app reads them, before the first board
// is built below and before the first paint: the refs the board consults, the shared
// motion state the debug scene shows, and the document-root attribute the CSS
// wing-placement rules key off — a player who turned wing placement off must see the
// clamped layout from the first frame rather than after a toggle.
settingsEnv.publish(settingsInit)
settingsEnv.root(settingsInit)

// **A board is now its family's chosen one**, which is the one fact two messages
// below have to write. A scene mounting says it however the board got there — a row
// tap, a `?game=` link, a resume — and so does a family's segment cycled with no board
// of it up. The family is read off the board rather than passed in: a board belongs to
// at most one (`Game.familyOf`), so naming it again at each call site would be the same
// fact written a second time.
//
// A board of no family, or one its family has already chosen, hands the model straight
// back — and the physical-equality check in `Html.mount` is what turns that into no
// re-render at all.
let rememberVariant = (model, id: string) =>
  switch Game.byId(id)->Option.flatMap(Game.familyOf) {
  | Some(family) if model.variants->Dict.get(family.id) != Some(id) =>
    let variants = model.variants->Dict.copy
    variants->Dict.set(family.id, id)
    ({...model, variants}, () => Preferences.saveVariant(~family=family.id, id))
  | _ => (model, Html.noEffect)
  }

let update = (msg, model) =>
  switch msg {
  | UpdateAvailable => ({...model, updateAvailable: true}, Html.noEffect)
  // Opening or closing the menu resets it to the main screen, so a visit to
  // Settings never lingers into the next open.
  // Every screen change also starts the Settings screen's visit afresh
  // (`MenuSettingsScreen.freshVisit`), here and in the five branches below — which is
  // all this loop ever says about what's on that screen. A half-typed seed goes the
  // same way when the menu closes — see `seedInput`.
  // Opening the menu also puts an *overlapping* debug console away: the menu is
  // the modal chrome and takes the screen for itself, and the console's twin rule below
  // closes the menu on the way in. A **side-docked** console is exempt — it's
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
        settings: MenuSettingsScreen.freshVisit(model.settings),
        seedDialogOpen: false,
        seedInput: "",
        consoleOpen: putConsoleAway ? false : model.consoleOpen,
      },
      putConsoleAway
        ? () => DebugConsole.apply(~open_=false, ~dock=model.consoleDock)
        : Html.noEffect,
    )
  // The ` key. Opening subscribes the panel to `DebugLog` — a closed console
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
  // ⇧` steps to the next placement. `fits` is the live board's verdict on whether
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
  // A scene mounted. Only ever a scene *change* — the switcher answers a tap on
  // the row of the scene already showing with `~onReselect` instead, precisely so the
  // live board isn't torn down — so there's no no-change guard here to write.
  | SceneActivated(id) =>
    // A board of a family mounted — from its row's segment, from a `?game=` link, or
    // from a resume — so that family's row is now showing that board: the row shows the
    // game you are playing, however you got to it. Written through for the same reason
    // the segment's own choice is; arriving by link is a choice of variant too.
    let (model, effect) = rememberVariant(model, id)
    ({...model, activeScene: Some(id)}, effect)
  // A family's segment tapped while its board *isn't* up: nothing mounts, the row simply
  // shows the next variant, and the tap on the name beside it is what opens that board.
  | VariantChosen(id) => rememberVariant(model, id)
  | HistoryChanged(canUndo) =>
    canUndo == model.canUndo ? (model, Html.noEffect) : ({...model, canUndo}, Html.noEffect) // no change — don't re-render
  // Closing the menu takes the seed dialog down with it, which is what lets Deal say
  // `CloseMenu` alone and get the whole chrome out of the board's way. The guard asks
  // about both for that reason: a dialog up over a menu already gone would otherwise
  // survive the very message meant to clear the screen.
  | CloseMenu =>
    model.menuOpen || model.seedDialogOpen
      ? (
          {
            ...model,
            menuOpen: false,
            menuScreen: Menu.Main,
            refreshBusy: false,
            settings: MenuSettingsScreen.freshVisit(model.settings),
            seedDialogOpen: false,
            seedInput: "",
          },
          Html.noEffect,
        )
      : (model, Html.noEffect)
  // The dialog opens empty and closes empty: a number is dealt or abandoned, never
  // left half-typed for the next open to offer back.
  | OpenSeedDialog => ({...model, seedDialogOpen: true, seedInput: ""}, Html.noEffect)
  | CloseSeedDialog => ({...model, seedDialogOpen: false, seedInput: ""}, Html.noEffect)
  // Enter Settings clean: clear any stale spinner from a prior visit. The label
  // itself is re-detected on open (see the view's `onOpenSettings`).
  | OpenSettings => (
      {
        ...model,
        menuScreen: Menu.Settings,
        refreshBusy: false,
        settings: MenuSettingsScreen.freshVisit(model.settings),
      },
      Html.noEffect,
    )
  | BackToMenu => (
      {...model, menuScreen: Menu.Main, settings: MenuSettingsScreen.freshVisit(model.settings)},
      Html.noEffect,
    )
  // A game's info screen. Its way back is `BackToMenu` above — the main menu is where
  // the "i" was tapped, and the game it is about need not be the one on the table, so
  // there is nothing here that Settings' own return doesn't already do.
  //
  // **Reading about a board is not choosing it.** The screen is *about* a variant, and
  // its picker moves it from one to another, but neither touches the family's chosen
  // board (`rememberVariant`): the Games list's segment shows what it did before the
  // "i" was tapped, whatever the picker was walked through, and nothing mounts. The
  // segment is the one control that chooses.
  | OpenGameInfo(info) => ({...model, menuScreen: Menu.GameInfo(info)}, Html.noEffect)
  // Opening the Debug screen clears the previous visit's share link rather than
  // leaving it up: the board may well have moved on since, and a stale link is worse
  // than a briefly disabled button. The view kicks off a fresh encode alongside this
  // message, which arrives back as `ShareLinkReady` and re-enables the row.
  | OpenDebug => (
      {
        ...model,
        menuScreen: Menu.Debug,
        settings: MenuSettingsScreen.freshVisit(model.settings),
        shareUrl: None,
        shareStatus: None,
        autoplayStatus: None,
      },
      Html.noEffect,
    )
  // The About screen, which is where the update check lives: enter it clean, the way
  // Settings is entered above, so a spinner left behind by a check that was in flight
  // when the screen was last left doesn't greet the next visit.
  | OpenAbout => (
      {
        ...model,
        menuScreen: Menu.About,
        refreshBusy: false,
        settings: MenuSettingsScreen.freshVisit(model.settings),
      },
      Html.noEffect,
    )
  | BackToSettings => (
      {
        ...model,
        menuScreen: Menu.Settings,
        settings: MenuSettingsScreen.freshVisit(model.settings),
      },
      Html.noEffect,
    )
  // Only the Settings screen's own title unlocks the hidden settings: the same green
  // `menu-title` heads all three screens, and while the view only wires the handler onto
  // Settings' copy, this makes the invariant explicit rather than resting on the diff
  // clearing a reused node's click handler.
  | SettingsMsg(MenuSettingsScreen.TitleTapped) if model.menuScreen != Menu.Settings => (
      model,
      Html.noEffect,
    )
  // The whole of the Settings screen, in four lines: hand the message to the screen's
  // own `update`, put its model back, and pass its effect straight out — which is the
  // one thing that makes this composition free, `Html.mount` already running an effect
  // the update returns. The physical-equality check is the child's half of the loop's
  // no-change rule: a message that moves nothing must leave *this* model alone too, or
  // the re-render it skips happens anyway.
  | SettingsMsg(msg) =>
    let (settings, effect) = MenuSettingsScreen.update(settingsEnv, msg, model.settings)
    (settings === model.settings ? model : {...model, settings}, effect)
  // No model change, and none is wanted: the effect takes the page with it, so the
  // next thing on screen is a launch rather than a render of this one. Which is also
  // why the clear and the relaunch are a pair — see `StoredState`.
  | ClearStoredState => (
      model,
      () => {
        StoredState.clear()
        StoredState.relaunch()
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
  | SetCascadeFade(fade) => (
      {...model, cascade: fade},
      // Through to the board's copy at once — the next victory is the one this is for,
      // and it could be the next move — and then to the celebration on screen, if there
      // is one, so a slider dragged over a falling cascade moves *that* cascade. The
      // same pair the tilt switch makes with `relayout`. Nothing is written to storage;
      // see the ref.
      () => {
        cascadeFade := fade
        liveBoard.contents->Option.forEach(board => board.retuneCascade())
      },
    )
  | ToggleDebugLog =>
    let debugLog = !model.debugLog
    (
      {...model, debugLog},
      // Subscribe (or drop) the JS console on the shared log the whole app publishes
      // through and persist the choice so it survives a reload. Both run as the
      // post-update effect. The drop-down console is a separate subscriber, so
      // the two are independent: either, both, or neither can be listening.
      () => {
        DebugLog.setConsoleEnabled(debugLog)
        Preferences.saveDebugLog(debugLog)
      },
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
  | AutoplayStatus(autoplayStatus) => ({...model, autoplayStatus}, Html.noEffect)
  // A new deal reached the table. Whatever status line the previous deal's
  // share left up goes with it — "Link copied to clipboard." must not sit under a
  // number it no longer refers to.
  | DealChanged(dealSeed) =>
    dealSeed == model.dealSeed
      ? (model, Html.noEffect) // no change — don't re-render
      : ({...model, dealSeed, shareDealStatus: None}, Html.noEffect)
  | ShareDealStatus(shareDealStatus) => ({...model, shareDealStatus}, Html.noEffect)
  | SeedTyped(seedInput) => ({...model, seedInput}, Html.noEffect)
  }

// **Whatever closes the menu uncovers the board.** Four messages lower `menuOpen` — the
// ✕ and the backdrop, the top bar's button, the console and its dock — and a deal
// waiting under the menu (`heldDeal`) is played on the *transition*, not in any one of
// them, or a fifth way of closing the menu would leave a board with its cards parked
// off-stage. Wrapped around the step above rather than written into it because it is
// about the change in the model, which no single branch sees; and an effect rather than
// a call here, so it runs after the render that hides the pane.
let update = (msg, model) => {
  let (next, effect) = update(msg, model)
  if model.menuOpen && !next.menuOpen {
    (
      next,
      () => {
        effect()
        releaseHeldDeal()
      },
    )
  } else {
    (next, effect)
  }
}

// The scene area (switcher + demos) is built imperatively and owns its own
// subtree. `render` hands back one real DOM node — the scene container, wrapped by
// the scene band and spliced in with `Html.node`, never re-rendered — plus the menu's
// scene lists as plain data for the chrome to draw.
//
// A bare launch opens on the game last played, falling back to FreeCell (see
// `launchGame`). An explicit `?game=` or `?scene=` still wins (`~forced`), and
// `?state=` still forces a scenario, so the screenshot report's
// `?game=freecell&state=midgame` lands exactly where it says. `Game.all` is the source
// of truth for the game scenes; which of them is re-dealable is the game's own answer
// (`Game.t.deal`).
let url = AppUrl.parse()

// Whether the URL asks for no particular board — the *plain open* of
// `docs/board-driver.md` § Which opens touch storage, minus the "re-dealable game"
// half each scene adds for itself. One spelling, because the same condition decides
// two things that must not drift apart: which opens touch a game's saved board, and
// which opens are free to resume the game the player was last on.
let plainUrl = url.state->Option.isNone && url.seed->Option.isNone && url.shared->Option.isNone

// The seed a *New Deal* gets: six digits, so every re-deal lays out a
// different board and the number stays short enough to read off the menu's "this game"
// heading and type back into the seed dialog. A board the player names goes to `deal` directly
// and never comes through here. `Math.random` is fine — this is the impure view
// layer, not `core`'s deterministic deal path.
let randomSeed = () => (Math.random() *. 1_000_000.)->Float.toInt

// The driver's half of the board contract — every argument below is settled here.
// **`docs/board-driver.md` is the seam whole**; what follows is this side's decisions.
let gameScene = (game: Game.t) => {
  // The question every decision below turns on, asked of the game in hand rather than
  // of its id: can this board deal another of itself? A second seeded game answers yes
  // on the day it's added, with no edit here.
  let canDeal = game.deal->Option.isSome
  // Which of the four opens this is, which is what decides whether storage is touched
  // at all (§ Which opens touch storage). `sharedOpen` is a *thunk* because its answer
  // isn't available when the scene is built: inflating the blob is asynchronous, so at
  // build time a scene knows only that some link is coming.
  let sharePending = canDeal && url.shared->Option.isSome
  let sharedOpen = () =>
    sharePending && sharedGame.contents->Option.mapOr(false, shared => shared.id == game.id)
  let plainOpen = canDeal && plainUrl

  // **Has this board become the player's own?** A plain open is theirs from the moment
  // it deals; an addressed one becomes theirs when they change what the link opened —
  // a move played, or a board dealt from it. The ref lives for the scene's whole life
  // rather than one mount, which is what makes a swap away to another board and back
  // come home to the game they left instead of re-dealing the link over it.
  let adopted = ref(plainOpen)
  // **Was this mount's opening dealt where nobody could see it?** The segment's swap
  // mounts a board under the open menu, and a fresh deal there is a board the player
  // hasn't met: it writes nothing until the menu goes (`reveal`), and if they cycle on
  // before then it was never there — the next mount of this scene deals afresh, rather
  // than resuming a board they only ever saw at rest. A mount's fact, not the scene's
  // (unlike `adopted`), so every mount starts it false and its opening report settles it.
  let unseen = ref(false)
  // The one question all three storage decisions below ask (§ Which opens touch
  // storage). A thunk for the same reason `sharedOpen` is: both answers can arrive
  // after the scene was built.
  let saving = () => canDeal && !unseen.contents && (adopted.contents || sharedOpen())

  // The moment an addressed board takes over storage, which is a shared game's arrival
  // in miniature. The history needs nothing here — the change that adopted the board
  // persists straight after this — but the deal number never rides in a history, so it
  // is written now: whatever number the app would currently share for this board, or
  // *cleared* when there is none, since a posed board must not be handed the last
  // game's seed to answer with.
  let adopt = (dealSeed: option<int>) =>
    if canDeal && !saving() {
      adopted := true
      switch dealSeed {
      | Some(seed) => SavedGame.saveSeed(game.id, seed)
      | None => SavedGame.clearSeed(game.id)
      }
    }

  // Is the build about to report the one this mount opened with? Raised as the scene
  // mounts (`~publish`, which runs just before that build) and lowered by the report
  // itself, so every deal after it is one the player asked for.
  let openingBuild = ref(true)

  // The menu has gone from over a board dealt behind it: the player has now seen it,
  // and it is theirs the way any plain deal is. What its opening build would have
  // written had anyone been looking — the number (`~onDeal` skipped it) and the history
  // (the sink did) — is written now. Nothing on a board that was seen all along, and
  // nothing on an addressed board, which a look doesn't adopt any more than it did.
  let reveal = () =>
    if unseen.contents {
      unseen := false
      if saving() {
        liveDealSeed.contents->Option.forEach(n => SavedGame.saveSeed(game.id, n))
        currentHistory()->Option.forEach(saved => SavedGame.save(game.id, saved))
      }
    }

  // Read when the scene *mounts*, not here where it's built — § Why the read-backs are
  // thunks.
  let loadHistory = () => saving() ? SavedGame.load(game.id) : None

  // A plain open takes a fresh random seed each load, so a reload with nothing saved
  // lays out a new board rather than always deal #1, matching New Game. A `?seed=`
  // pins one instead.
  //
  // An *addressed* board takes the fixed deal `Game.all` holds. For `?state=` that's
  // what makes the screenshots deterministic — `Scenario.forName` derives from the
  // exact board the report expects. For `#g=` it's a steadiness measure: decompressing
  // is asynchronous, so the board is necessarily built before the shared history can
  // land on it, and dealing a random board for that frame would make the swap read as
  // a glitch (the fly-in is skipped for the same reason). Both are mitigations rather
  // than a fix — #259 measures the gap and weighs the ways to close it.
  let addressed = url.state->Option.isSome || url.shared->Option.isSome
  let opening = switch game.deal {
  | Some(deal) if !addressed => deal(url.seed->Option.getOr(randomSeed()))
  | _ => game
  }
  let newDeal = game.deal->Option.map(deal => () => deal(randomSeed()))
  TableScene.make(
    ~initial=?url.state->Option.flatMap(name => Scenario.forName(game, name)),
    ~loadHistory,
    // The sink is wired for every re-dealable board, and the gate inside it settles
    // which of them may actually write — it runs long after the scene was built, so it
    // can ask what this scene couldn't answer then: whether a pending link turned out
    // to name this game, and whether the player has since made an addressed board
    // theirs.
    //
    // **An addressed open saves nothing until it is adopted.** The deal a `?seed=`
    // names, the pose a `?state=` forces and the scaffolding a `#g=` wears while its
    // blob inflates are all boards the player was *sent*, and writing one on sight
    // would clobber their own game with a board they haven't touched.
    ~persist=?canDeal
      ? Some(
          saved =>
            if saving() {
              SavedGame.save(game.id, saved)
            },
        )
      : None,
    ~newDeal?,
    // Adopt the mounting board whole, replacing whatever the outgoing scene left here.
    // Then, if Wiggle Waggle is already on, start it listening straight away: this is
    // what re-applies an active shake to a board that mounts after the switch flipped.
    ~publish=board => {
      liveBoard := Some(board)
      // …and which game it's a board of. This is the one place that knows: the scene
      // publishes controls, not the `Game.t` they were built from.
      liveGame := Some(game)
      // The board this mount opens with is still to come, whichever it turns out to be
      // (`openingBuild`). Published before it, so this is the moment to say so — and to
      // start the mount as one whose board is in view, until that build says otherwise.
      openingBuild := true
      unseen := false
      if shakeActive.contents {
        board.shake.start()
      }
    },
    // A move is one of the two ways an addressed board becomes the player's own — the
    // report that says a board has something to undo is the report that says it has been
    // played. (The other is dealing from it, below.)
    ~onHistory=canUndo => {
      if canUndo {
        adopt(liveDealSeed.contents)
      }
      reportHistory.contents(canUndo)
    },
    // What the console's printed board titles itself with. `liveDealSeed` is the
    // *resolved* number both Share buttons offer, so a printed board names the deal the
    // app would share rather than re-deriving it from a `game.seed` that a posed or
    // resumed board would make a liar of.
    ~currentDeal=() => liveDealSeed.contents,
    // Resolving the board's `None` into what's actually true of the game on screen —
    // the driver's half of the deal number, and the table of the four cases is
    // `docs/board-driver.md` § Who resolves the deal number.
    //
    // The one local fact: a `Some(n)` on an open that saves is saved *here*, because
    // the number is the one thing the history doesn't carry — without it the next
    // session's resumed game couldn't be shared at all.
    //
    // It is also where the second half of adoption lands. Every deal after the one this
    // mount opened with is a board the player put on the table — a New Deal, an Enter
    // seed, a Restart — so an addressed board becomes theirs at that point exactly as a
    // move makes it theirs, and the number it is adopted with is the one being reported.
    ~onDeal=seed => {
      let playerDealt = !openingBuild.contents
      openingBuild := false

      // A board the player dealt for themselves is one they are looking at, whatever the
      // opening was: a New Deal under the menu closes it in the same breath.
      if playerDealt {
        unseen := false
      }
      publishDeal(
        switch seed {
        | Some(n) =>
          if playerDealt {
            adopt(Some(n))
          } else if keepMenuOpen.contents {
            // A fresh deal, and it is the segment's swap that dealt it: behind the
            // menu, to nobody. Settled before the write below asks `saving()`.
            unseen := true
          }
          if saving() {
            SavedGame.saveSeed(game.id, n)
          }
          Some(n)
        | None =>
          saving()
            ? SavedGame.loadSeed(game.id)
            : url.state->Option.flatMap(name => Scenario.seedForName(game, name))
        },
      )
    },
    // **No deal number, no button.** A posed `?state=` board, or a game landed from a
    // `#g=` link, has nothing truthful to offer, so the overlay is New Game alone
    // rather than a button sharing someone else's deal. (Worth revisiting for the
    // shared case — it *does* descend from a deal, it just doesn't carry the number.)
    //
    // `deliver` is reached with the click's transient activation intact: `urlForDeal`
    // is a string built from an int, so nothing is awaited between tap and sheet.
    ~winShare={
      available: () => liveDealSeed.contents->Option.isSome,
      share: (~moves, ~undos) =>
        switch liveDealSeed.contents {
        | Some(seed) =>
          // The game is this scene's own, not `liveGame`'s: the overlay is over *this*
          // board, and the two say the same thing anyway.
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
    ~cascadeFade,
    // `?animate=off` stills the whole board — every flight, not just the opening
    // one — so a shot or a scripted run reads a settled position at every step.
    ~skipFlights=!url.animate,
    // A shared board skips its opening fly-in alone: the cards it deals are about to be
    // replaced by the shared position, so animating them in only draws the eye to a
    // board that isn't the one being opened. Once that position lands, play is ordinary
    // play and its moves fly like anyone else's.
    ~skipDealFlyIn=url.shared->Option.isSome,
    // Whether the board can be seen is this side's to say: only the segment's swap
    // mounts one under the open menu, and that board waits there for the menu to go —
    // its deal unplayed and, if it was fresh, unwritten (`reveal`).
    ~onceUncovered=release =>
      if keepMenuOpen.contents {
        heldDeal :=
          Some(
            () => {
              reveal()
              release()
            },
          )
      } else {
        release()
      },
    opening,
  )
}
// The games still in development: dealt by `Game.all`, reached by `?game=`, saved and
// resumed like any other, and withheld from the main menu until **Beta features** is
// on. Spider is there while its finer points are polished — a whole family, so that
// the row it will get is the row it is judged on. A game graduates by leaving this list.
let betaGames: array<string> = Game.spiderFamily.variants->Array.map(v => v.game.id)

// The games the menu offers, as its top-level Games rows: every game `Game.all` deals,
// in `Game.all`'s order, less `betaGames` while the flag is off. A game joins the menu by
// being added there and nowhere else — the switcher files it, the menu draws it, and
// `?game=` already reached it.
//
// **A game this list leaves out is offered on no screen at all**, the Debug one included
// (`SceneSwitcher`'s `#withheld`): `?game=` is the way to it and the only way. So a board
// on the table when the switch goes off stays up and playable, with no row anywhere to
// come back to it — worth knowing before withholding a game a player might be mid-way
// through, and the reason this list holds a whole family rather than a board.
//
// A function rather than a value because the switch can flip between two menu renders,
// and a flip has to land on the next one: the rows are asked afresh each render, so the
// game appears among them without a relaunch.
let menuGames = (): array<Game.t> =>
  betaFeatures.contents
    ? Game.all
    : Game.all->Array.filter(game => !(betaGames->Array.includes(game.id)))

// The game a bare launch opens on: the one last on the table, else the default. The
// board waiting on it comes back with it — each game keeps its own save — so this
// resumes the *game*, and `gameScene`'s `loadHistory` resumes the board. The stored id
// is looked up rather than trusted (`Game.byId`): a stale id, a garbage value and a game
// this build has since withdrawn are all the same answer, and all fall back to the
// default rather than to whatever scene happens to lead the list.
//
// **Only on a plain open.** A URL that names a board at all has to be answered by that
// URL: `ShareLink.urlForDeal` omits `?game=` for `Game.default`, so a bare `?seed=7` is
// a link to *FreeCell's* deal 7, and a remembered Simple Simon answering it would open
// a different board under the same link. The `~forced` ids are safe either way, being
// resolved ahead of this, but a deal number is not — hence the whole predicate rather
// than a check for `?game=`.
let launchGame = plainUrl
  ? SavedGame.loadLastGame()->Option.flatMap(Game.byId)->Option.getOr(Game.default)
  : Game.default

let switcher = SceneSwitcher.render(
  // The launch scene: the remembered game, or the game `core` says a nameless deal
  // number belongs to. Never the literal `"freecell"` — that's the same fact twice
  // otherwise, and the two halves of one property: `urlForDeal` omits `?scene=` for
  // `Game.default`, so a bare `?seed=7` has to land on `Game.default`'s scene for the
  // link to mean what it says. `launchGame` is what keeps that true, by declining to
  // remember on exactly the opens that carry such a link.
  ~default=launchGame.id,
  ~primary=() => menuGames()->Array.map(game => game.id),
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
    // One line, and it can't be incomplete: the whole published surface goes at
    // once. The outgoing board's shake subscription is already detached by its own
    // teardown, and `~publish` re-applies `shakeActive` to whichever board mounts next.
    liveBoard := None
    // …and the game that board was a board of, which goes with it: a demo scene
    // publishes neither, and the two must never be one scene apart.
    liveGame := None
    // Reset the top bar's Undo to disabled; the mounting scene reports its own
    // history.
    reportHistory.contents(false)
    // …and clear the deal number with it, so the Share buttons are dark for the
    // moment between scenes; the mounting scene reports its own (a demo reports none).
    publishDeal(None)
    // Move the menu's highlight to the scene coming up. The switcher owns no row to
    // mark, so this report *is* the highlight.
    reportScene.contents(scene.id)
    // …and remember it, so the next bare launch opens here. Every activation counts, a
    // link's as much as a menu tap: what is stored is the game that was played. A demo
    // writes nothing, so the id read back always names a game — the Gallery can never be
    // what the app opens on.
    Game.byId(scene.id)->Option.forEach(game => SavedGame.saveLastGame(game.id))
    // …and drop a deal the outgoing board never got to play, before the close below
    // could run it over a board that is being torn down.
    heldDeal := None
    if !keepMenuOpen.contents {
      closeMenu.contents()
    }
  },
  // A tap on the row for the game already showing: nothing mounts, so nothing above
  // may be reset — `liveBoard` still holds the board on screen — and closing the menu
  // is the whole response. The board carries on untouched.
  ~onReselect=() => closeMenu.contents(),
  Array.concat(
    [
      GalleryScene.make(),
      // The card-sprite fidelity check. `?raster=` picks which of the
      // renderings it opens on; without it the scene's own default wins.
      RasterScene.make(~rendering=?url.raster),
      // Step two of the same animation: the overlay mechanics — a
      // transparent canvas over real cards, and the DOM→canvas hand-off.
      TrailScene.make(),
      // Step three: the motion itself, with the feel on sliders. `?cascade=pose`
      // freezes it at a fixed frame, and `?seed=` — the same deal number a board
      // reads — is what the cascade replays.
      CascadeScene.make(~mode=?url.cascade, ~seed=?url.seed),
      MotionScene.make(),
    ],
    Game.all->Array.map(gameScene),
  ),
)

// **Swapping the board under an open menu**: the Games list's segment has chosen a
// different board of the family whose board is on the table, so the new one mounts and
// the menu stays put (`keepMenuOpen`) — the control a player is looking at as they tap
// it is still there to tap again. The info screen's picker offers the same boards and
// does no such thing: it moves the screen, never the table (`OpenGameInfo`).
//
// Nothing is dispatched here. The activation carries the new board into the model on its
// own (`SceneActivated`), remembered choice and all.
let swapBoard = (id: string) => {
  keepMenuOpen := true
  switcher.select(id)
  keepMenuOpen := false
}

// The boards of a family the menu is offering — its variants narrowed to the scenes in
// front of a player (`switcher.primaryScenes`). Fewer than two of them is no choice to
// offer at all, and both controls that offer one ask the question this way.
let offeredVariants = (scenes: array<SceneSwitcher.choice>, family: Game.family) =>
  family.variants->Array.filter(v => scenes->Array.some(scene => scene.id == v.game.id))

// What each family's row opens showing, keyed by family id: the variant last chosen, if
// it still names one of that family's boards, and nothing at all otherwise — an absent
// entry is the family's own default, decided where the row is drawn.
//
// The board on the table overrides it if that board is one of a family's — a resumed
// game, or a `?game=` link — because a row showing a variant other than the one being
// played would be the row lying about the highlight beside it. The same order
// `SceneActivated` keeps to from here.
let openingVariants = {
  let chosen = Dict.make()
  Game.families->Array.forEach(family =>
    Preferences.loadVariant(~family=family.id)
    ->Option.flatMap(id => family.variants->Array.find(v => v.game.id == id))
    ->Option.forEach(v => chosen->Dict.set(family.id, v.game.id))
  )
  switcher.active
  ->Option.flatMap(Game.byId)
  ->Option.forEach(game =>
    Game.familyOf(game)->Option.forEach(family => chosen->Dict.set(family.id, game.id))
  )
  chosen
}

// Land a shared game on the board (`ShareLink`). The blob came off the `#g=`
// fragment synchronously, but inflating it is asynchronous — `DecompressionStream`
// has no synchronous form — so the board is already mounted from `gameScene`'s
// fixed opening deal by the time the history arrives, and this drops the real
// position onto it. That's one frame of a stable, un-animated FreeCell deal before
// the swap; both are arranged above precisely so this reads as the board settling
// rather than as a board changing its mind. Closing that frame is #259.
//
// **The blob says which game it is a game of**, so the first thing that happens
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
        // not stay behind to be read as its own: a shared position was never
        // dealt from a number here, and a later resume asking "which deal is this?"
        // has to be told there isn't one rather than handed the last one this device
        // dealt for itself.
        //
        // The key is the *board being played*, not a hardcoded game — and that board
        // is named by the link rather than inferred from whichever scene it opened
        // onto, which is the same fact one step earlier.
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
// board through the mounted board's `loadState`, the live in-app twin of the
// URL's `?state=`. `ensureActive` runs first so the board is FreeCell's, and closing
// the menu is explicit (a no-op if `ensureActive` already closed it on a scene
// change).
//
// A list of entries rather than a built node: `<MenuDisclosure>` renders them — the
// same component the switcher's "scenes" group is drawn with. Module-level,
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
    // above: a posed position offers the deal it's been shown to descend from,
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
// console's `deal <game> [position]` does. A game id means the same thing here as it does
// in the CLI, which is what lets one verb serve both. These are the debug-states row's
// own two steps (surface the game's
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
      // does it: the rebuild reports `None` on its way past, and leaving it there
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

// The menu's prop records, one per screen — and one *builder*, for the info screen,
// whose subject arrives with the screen rather than from the model's other fields. Each
// is the screen's own contract with this chrome, built here and handed to `<Menu>`
// whole — the pane places whichever screen `menuScreen` names and never looks inside.
// Grouping them this way is what lets a new setting be declared once in `Main` and once
// on the screen that shows it, rather than a third and fourth time on the way through
// the pane.

// The main screen: re-deal the board — at random or at a number typed in — share its
// deal number, pick a game, go on to Settings.
// **The Games list's rows**, from the switcher's primary scenes. The switcher hands over
// scenes, not rows — which of them is current is the chrome's to know, being what a
// re-render has to reflect — so the `selected` flag and the tap are joined up here. So is
// the "i" beside each: a scene id is a game id, so the facts its screen shows are a
// lookup away.
//
// **A family arrives as several scenes and leaves as one row** (`Game.familyOf`): the
// FreeCells are one game in three sizes, the Spiderettes one game with three packs, so
// the row is the family's name with the choice a segment beside it. It stands where the
// first of that family's boards stands in the list — not where the chosen one does, so
// the row keeps its place as the segment cycles — and the family's other scenes are drawn
// not at all. They keep their scenes regardless, which is what leaves `?game=` reaching
// them, the Debug screen filing them, and a saved game kept per board.
//
// **Offered, not merely existing.** The scenes handed in are the games the menu is
// listing (`menuGames`), and a family is collapsed only over those: a board the list
// isn't offering goes on no segment, rather than into a row of its own.
let gameRows = (model, dispatch, scenes: array<SceneSwitcher.choice>): array<MenuGameRow.props> => {
  let after = (siblings: array<Game.variant>, here: Game.variant) => {
    let i = siblings->Array.findIndex(v => v.game.id == here.game.id)
    siblings->Array.get(mod(i + 1, Array.length(siblings)))->Option.getOr(here)
  }

  let onInfo = (game: Game.t) => () => dispatch(OpenGameInfo(GameInfo.forGame(game)))

  // A primary scene that names no game (there is none today) gets no row, rather than
  // a row whose "i" opens an info screen about nothing.
  scenes->Array.filterMap(scene =>
    Game.byId(scene.id)->Option.flatMap((game): option<MenuGameRow.props> =>
      switch Game.familyOf(game) {
      | Some(family) if Array.length(offeredVariants(scenes, family)) > 1 =>
        let siblings = offeredVariants(scenes, family)
        let leader = siblings->Array.get(0)
        if leader->Option.mapOr(true, first => first.game.id != scene.id) {
          None
        } else {
          // The variant in hand, and the board behind it: everything on this row is that
          // board's, so the name opens what the segment is showing and the highlight marks
          // it only when that same board is the one on the table. A remembered choice the
          // list isn't offering falls through to the family's default, and that to whatever
          // leads — a row can only offer what is in front of it.
          let chosen =
            siblings
            ->Array.find(v => model.variants->Dict.get(family.id) == Some(v.game.id))
            ->Option.orElse(siblings->Array.find(v => v.game.id == family.default.game.id))
            ->Option.orElse(leader)
            ->Option.getOr(family.default)
          let playing = model.activeScene == Some(chosen.game.id)
          Some({
            label: family.name,
            selected: playing,
            onSelect: () => switcher.select(chosen.game.id),
            variant: {
              mark: GameVariant.forVariant(chosen),
              onCycle: () => {
                let next = after(siblings, chosen)
                // This family's board *is* the one on the table, so the choice is a board
                // change; where it isn't, nothing mounts and the choice is only remembered
                // — the tap on the name beside the segment is what opens that board.
                playing ? swapBoard(next.game.id) : dispatch(VariantChosen(next.game.id))
              },
            },
            onInfo: onInfo(chosen.game),
          })
        }
      // A game on its own — or the only board of its family this list is offering: the row
      // it has always been, under its own name.
      | _ =>
        Some({
          label: scene.label,
          selected: model.activeScene == Some(scene.id),
          onSelect: () => switcher.select(scene.id),
          onInfo: onInfo(game),
        })
      }
    )
  )
}

let mainScreen = (model, dispatch): MenuMainScreen.props => {
  onClose: () => dispatch(CloseMenu),
  onNewGame: () => {
    liveBoard.contents->Option.forEach(board => board.newGame->Option.forEach(deal => deal()))
    dispatch(CloseMenu)
  },
  onEnterSeed: () => dispatch(OpenSeedDialog),
  onRestart: () => {
    liveBoard.contents->Option.forEach(board => board.restart())
    dispatch(CloseMenu)
  },
  // The name the "this game" heading wears. A scene id is a game id (`gameScene` files
  // each of `Game.all` under its own), so the mounted scene answers which game is on the
  // table — and a demo, which no game is behind, answers `None` here rather than lending
  // the heading its own label. Read off the model, not `liveGame`: the heading is drawn
  // by the render, so it has to move with one.
  gameName: model.activeScene->Option.flatMap(Game.byId)->Option.map(game => game.name),
  shareDealSeed: model.dealSeed,
  shareDealStatus: model.shareDealStatus,
  onShareDeal: () =>
    // Share the *deal*. The link is a `?seed=` string, so it's built right
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
    // Both halves of the link have to be to hand at once: the number the model
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
  // The games list: the switcher's primary scenes, turned into rows (`gameRows` above).
  games: gameRows(model, dispatch, switcher.primaryScenes()),
  onOpenSettings: () => {
    // Re-detect the service-worker state each time Settings opens, so the button
    // reflects a worker that registered (or self-destructed) since page load.
    Refresh.detect(mode => dispatch(RefreshDetected(mode)))
    dispatch(OpenSettings)
  },
  // About is the screen the update check is *on*, so its own tap is what has to kick
  // the detection off: the check is absent until a service-worker state has been
  // reported, and this button is a player's only way in. The same detect as Settings'
  // above, which is cheap and idempotent — `Refresh.detect` reads the browser and
  // dispatches, and the two screens are never opened at once.
  onOpenAbout: () => {
    Refresh.detect(mode => dispatch(RefreshDetected(mode)))
    dispatch(OpenAbout)
  },
  // The ↻ Update band: this is the screen the top bar's pip opens, so the notification
  // and the thing it notifies about are one tap apart. The About screen offers the same
  // button (`<UpdateButton>`) for a player who went looking, one tap further on.
  updateVisible: model.updateAvailable,
  onReload: () => dispatch(Reload),
}

// The "Enter seed" modal, raised over the menu by its Enter Seed button. It is built
// only while it's showing, so the field's focus-on-mount is a mount rather than a
// render (see `SeedDialog`).
let seedDialog = (model, dispatch): SeedDialog.props => {
  seed: model.seedInput,
  onSeed: text => dispatch(SeedTyped(text)),
  // A deal number the player named. `loadDeal` is the board's own — the same hook the
  // console's `deal <n>` reaches, so a typed number and a tapped one open the very same
  // board — and it's absent on a scene with no game to deal, where this is a no-op
  // exactly as New Deal and Restart are. `CloseMenu` clears the whole chrome, dialog
  // included, so the board it opened is what you're looking at.
  onDeal: seed => {
    liveBoard.contents->Option.flatMap(board => board.loadDeal)->Option.forEach(load => load(seed))
    dispatch(CloseMenu)
  },
  // Cancel leaves the menu up, since that's where the dialog was raised from.
  onCancel: () => dispatch(CloseSeedDialog),
}

// The Settings screen: its own state and its own messages, plus the three ways out of
// it that are the *pane's* business rather than a setting's. There is no per-switch
// field here by construction — a new preference is declared on the screen and reaches
// this file inside `model.settings`.
let settingsScreen = (model, dispatch): MenuSettingsScreen.props => {
  model: model.settings,
  dispatch: msg => dispatch(SettingsMsg(msg)),
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
}

// The cascade sliders' readouts. Two numbers a developer might copy into
// `CascadePlayer.defaultFade`, each with what it *means* beside it: a rate is a length of
// memory, and a coin is how often the surface is filled, which is the whole of what the
// fade costs to run (`docs/cascade.md`). The arithmetic behind both is the player's; the
// words are this screen's.
let hundredth = value => (Math.round(value *. 100.) /. 100.)->Float.toString

let fadeRateReadout = (rate: float) =>
  rate <= 0.
    ? "off · nothing fades"
    : `${hundredth(rate)} /s · half gone in ${hundredth(CascadePlayer.fadeHalfLife(rate))}s`

let fadeCoinReadout = (fade: CascadePlayer.fade) => {
  let every = CascadePlayer.fadePayment(fade, ~stampMs=CascadePlayer.defaults.stampMs)
  every == infinity
    ? `${hundredth(fade.coin)} · nothing to pay`
    : `${hundredth(fade.coin)} · a fill every ${Math.round(every *. 1000.)->Float.toString} ms`
}

// The Debug screen: developer tools, a level below Settings.
let debugScreen = (model, dispatch): MenuDebugScreen.props => {
  onClose: () => dispatch(CloseMenu),
  onBackToSettings: () => dispatch(BackToSettings),
  cutoutDebug: model.cutoutDebug,
  onToggleCutoutDebug: () => dispatch(ToggleCutoutDebug),
  debugLog: model.debugLog,
  onToggleDebugLog: () => dispatch(ToggleDebugLog),
  // The victory cascade's dimming, dragged on a live board. The menu sits above the
  // cascade's canvas, so these can be dragged over a celebration as it falls and land on
  // it — and on the next one, which reads them as it starts. A list, so the next knob is
  // an entry here and no new prop anywhere.
  cascadeKnobs: [
    {
      label: "fade",
      min: 0.,
      max: 0.95,
      step: 0.01,
      value: model.cascade.rate,
      readout: fadeRateReadout(model.cascade.rate),
      onInput: rate => dispatch(SetCascadeFade({...model.cascade, rate})),
    },
    {
      label: "coin",
      min: 0.01,
      max: 0.4,
      step: 0.01,
      value: model.cascade.coin,
      readout: fadeCoinReadout(model.cascade),
      onInput: coin => dispatch(SetCascadeFade({...model.cascade, coin})),
    },
  ],
  // Asked of the live board rather than the model: the row is live wherever a command
  // has somewhere to land, which is the same question the console answers with "no board
  // on this scene".
  autoplayEnabled: liveBoard.contents->Option.isSome,
  autoplayStatus: model.autoplayStatus,
  // The console's `autoplay`, pressed instead of typed — and the two things a button
  // has to do that a typed line doesn't.
  //
  // **It says it is thinking first.** `Solver.interactive` is ten seconds, and the
  // search runs on this thread: a menu that freezes with nothing written on it reads
  // as a crash. The status goes up, and the search waits a tick so the render carrying
  // it is painted before the thread is taken.
  //
  // **Then it gets out of the way, or explains itself.** A line found is played on the
  // board a move at a time, and the board is behind this panel — so the menu closes on
  // it, the way New Game and Restart do. A refusal moves nothing, which is a board that
  // says nothing by itself, so the menu stays up and the solver's words take over the
  // row. Either way the reply also goes to the log, where the typed verb's does and
  // where the play-by-play is about to appear under it.
  onAutoplay: () => {
    dispatch(AutoplayStatus(Some(MenuDebugScreen.thinking)))
    setTimeout(() =>
      liveBoard.contents->Option.forEach(board => {
        let {playing, reply} = board.autoplay()
        DebugConsole.say(reply)
        if playing {
          dispatch(CloseMenu)
        } else {
          dispatch(AutoplayStatus(Some(Render.toPlain(reply))))
        }
      })
    , 0)->ignore
  },
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
  onClearStored: () => dispatch(ClearStoredState),
  // Asked afresh on every render: the entry for the scene that's mounted now is the
  // `selected` one, and that's what puts the highlight in the menu.
  debugScenes: switcher.debugScenes(),
  debugScenesOpen: switcher.debugScenesOpen,
  debugStates,
}

// A game's info screen, built from the game the pane is showing it for — which is why
// this is a function where the other three are records: the subject arrives with the
// screen (`Menu.screen`), not from the model's other fields.
//
// **The picker is the one thing on it that isn't the subject's own.** Which boards a
// family has is a fact about the games (`Game.families`); which of them the menu is
// *offering* is this render's. A family the list is offering one board of gets no
// section at all, exactly as its row gets no segment.
let gameInfoScreen = (model, dispatch, info: GameInfo.t): MenuGameInfoScreen.props => {
  let choice = (v: Game.variant): MenuVariantPicker.choice => {
    mark: GameVariant.forVariant(v),
    selected: v.game.id == info.id,
    // A pick moves the screen to that board and does nothing else: the table and the
    // family's chosen board are the segment's to change, not this control's, whether or
    // not the board being read about is the one being played (`OpenGameInfo`).
    onChoose: () => dispatch(OpenGameInfo(GameInfo.forGame(v.game))),
  }

  let picker = (family: Game.family): option<MenuVariantPicker.props> =>
    switch offeredVariants(switcher.primaryScenes(), family) {
    | siblings if Array.length(siblings) > 1 =>
      Some({
        game: family.name,
        noun: GameVariant.nounFor(family),
        choices: siblings->Array.map(choice),
      })
    | _ => None
    }

  {
    info,
    variants: ?(Game.byId(info.id)->Option.flatMap(Game.familyOf)->Option.flatMap(picker)),
    tilt: model.settings.cardTilt,
    onClose: () => dispatch(CloseMenu),
    onBackToMenu: () => dispatch(BackToMenu),
  }
}

// The adaptive update-check control, or `None` while the service-worker state
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

// The About screen: one tap below the main menu, where its button is, and so back out
// to that menu rather than sideways into Settings. It holds the build string and both
// update controls — the check, and the ↻ Update that switches to a build already
// waiting.
//
// The check is a ready-made node so the screen stays a dumb layout: whether there is a
// check to offer at all turns on the one thing only this file knows, which is whether
// `Refresh.detect` has reported a service-worker state yet. The tap that opens this
// screen is what kicks that detection off (see `mainScreen`'s `onOpenAbout` above), so
// by the time a player is here the answer has landed.
let aboutScreen = (model, dispatch): MenuAboutScreen.props => {
  version: model.version,
  buildTime: model.buildTime,
  updateVisible: model.updateAvailable,
  onReload: () => dispatch(Reload),
  refresh: refreshControl(model, dispatch)->Option.mapOr(Html.empty, RefreshControl.make),
  onClose: () => dispatch(CloseMenu),
  onBackToMenu: () => dispatch(BackToMenu),
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
  // The drop-down debug console. Only its shell is JSX; the scrollback itself
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
    about={aboutScreen(model, dispatch)}
    gameInfo={info => gameInfoScreen(model, dispatch, info)}
  />
  // Over the menu rather than inside it, and in the tree only while it's up: the field
  // takes focus as it mounts, so a dialog that were merely hidden between opens would
  // have taken focus once, at startup, and never again.
  {model.seedDialogOpen ? SeedDialog.make(seedDialog(model, dispatch)) : Html.empty}
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
    // The menu opens on its main screen; Settings and Debug are swap-ins.
    menuScreen: Menu.Main,
    // The debug console is closed on every load — it's opened by a keypress and
    // never remembered, so a rendered screenshot or link-preview image can't show one.
    consoleOpen: false,
    // …but *where* it opens is remembered: the mode is a deliberate choice, so
    // it survives a reload. Nothing shows until a keypress opens the panel, so a
    // screenshot taken on a load with `docked` saved still sees an untouched board.
    consoleDock: consoleDockMode,
    // The Settings screen's opening state, read by the screen itself from where each
    // of its settings lives — and already published to the refs, the shared motion
    // state and the document root above, so the app is acting on it before this loop
    // exists.
    settings: settingsInit,
    // Debug overlay starts off each session (not persisted); the model keeps it
    // across rotations.
    cutoutDebug: false,
    // The cascade's own defaults, which is what a reload resets the sliders to.
    cascade: cascadeFade.contents,
    // Mirror the persisted console-logging preference so the switch opens in
    // the right position; the `DebugLog` gate itself was seeded above.
    debugLog: debugLogEnabled,
    // The scene the switcher mounted on its way up — read straight off it,
    // since the mount above happened before this loop existed and so before any
    // message could carry the news. Every later change arrives as `SceneActivated`.
    // Unlike `canUndo` and `dealSeed` below this needs no capturing ref: the value is
    // the switcher's own, not something a board reported into a callback.
    activeScene: switcher.active,
    // …and which variant each family's row opens showing, worked out the same way and at
    // the same moment, off the scene the switcher mounted (`openingVariants`).
    variants: openingVariants,
    // Seeded from the board's opening history report: a fresh deal reports
    // `false` (nothing to undo yet), but a resumed game with a restored undo stack
    // reports `true`, and that report already fired during the switcher's initial
    // mount above — before `dispatch` existed — so it's read back from
    // `initialCanUndo` here rather than hardcoded off.
    canUndo: initialCanUndo.contents,
    // The refresh button starts hidden until `Refresh.detect` reports the
    // service-worker state; not busy until an action runs.
    refreshMode: None,
    refreshBusy: false,
    // The share row is filled in when the Debug screen opens (`ShareLink`), not at
    // startup — there's no point encoding a board nobody has asked to share.
    shareUrl: None,
    shareStatus: None,
    // …and the Autoplay row has nothing to report until it is pressed.
    autoplayStatus: None,
    // Seeded from the board's opening deal report, for the same reason
    // `canUndo` is: it fired during the switcher's initial mount above, before
    // `dispatch` existed. On a plain open that report *is* the deal number the Share
    // button offers, so reading it back here is what lets the button work on the
    // first menu open rather than only after a re-deal.
    dealSeed: initialDealSeed.contents,
    shareDealStatus: None,
    // The seed dialog is raised by a press and opens empty, so there is nothing for a
    // load to restore — and every later open finds it this way again.
    seedDialogOpen: false,
    seedInput: "",
  },
  ~update,
  ~view,
)

// Now that `dispatch` exists, let a scene row close the menu through it — and let a
// scene change move the menu's highlight the same way.
closeMenu := (() => dispatch(CloseMenu))
reportScene := (id => dispatch(SceneActivated(id)))

// …and arm the debug console's keys: ` drops it over the board, ` or Escape puts
// it away. A window listener, so it works wherever the focus happens to be — the board
// is plain DOM with nothing focusable in the way.
DebugConsole.installKeys(
  ~onToggle=() => dispatch(ToggleConsole),
  ~onClose=() => dispatch(CloseConsole),
  // ⇧` steps it round its four placements instead. The board is asked *here*, at the
  // keypress, whether it can spare the width — the answer is live layout, so it can't
  // come from inside the loop's pure update.
  ~onDock=() => dispatch(ToggleConsoleDock(dockFits())),
)

// …and wire what the console's input line *does* with a typed line. The grammar
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
  // house rule has no switch anywhere, so the console is the only way to reach it:
  // the board reads the ref live at each move, so it takes hold on the very next one.
  | Command.Set({setting, on}) =>
    switch setting {
    | Options.AutoCollect =>
      if options.contents.autoCollect != on {
        dispatch(SettingsMsg(MenuSettingsScreen.ToggleAutoCollect))
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
    // goes straight to the live board, which lays it out with its own game's deal.
    // Don't build the board out here: a console command that reaches for a specific
    // game's deal is a console command deciding which game a number belongs to.
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

// Resume the shake grant on the first tap. With `wantsShake` set, the switch
// opened optimistically `On`, but iOS may require transient activation to (re)confirm
// the grant, and it can have been revoked behind us — so we defer to the first user
// gesture rather than prompting at startup. This one-shot `pointerdown` listener asks
// `Motion.requestAccess` (which resolves silently if the grant survived the reload)
// and routes the outcome back through the loop: `On` starts listening, `Blocked` snaps
// the switch to off with its explanation. This is the spike's first-click listener,
// promoted from a hack to the resume path. Only armed when the switch actually opened
// listening — an off, blocked, or unavailable start has nothing to resume.
if MenuSettingsScreen.listening(settingsInit) {
  let rec onFirstTap = _event => {
    WebDom.removeWindowListener("pointerdown", onFirstTap)
    Motion.requestAccess()
    ->Promise.thenResolve(state => dispatch(SettingsMsg(MenuSettingsScreen.WiggleResolved(state))))
    ->ignore
  }
  WebDom.addWindowListener("pointerdown", onFirstTap)
}

// …and let the board's history reports reach the loop, so Undo enables and
// disables as moves are played and undone.
reportHistory := (canUndo => dispatch(HistoryChanged(canUndo)))

// …and the same for the deal number, so the Share button follows the board: a
// New Game's fresh deal, a Restart's same one, a scene switch to a board with none.
reportDeal := (seed => dispatch(DealChanged(seed)))

// Refuse the browser's double-tap-to-zoom gesture app-wide. `styles/base.css`
// already asks for this with `touch-action: manipulation`, which iOS ignores in the
// home-screen web app; `TapZoom` enforces the same policy in the touch layer. Armed
// once here rather than per-scene, since the listener is on `document`.
TapZoom.arm()

// Detect the service-worker state up front so the Settings refresh button opens
// with the right label. It's re-detected each time Settings opens too (see
// the view), which also covers the first-load race where the worker registers
// just after this runs.
Refresh.detect(mode => dispatch(RefreshDetected(mode)))

// Now that `dispatch` exists, register the worker and let its callbacks drive
// the loop. Stash the returned updater so the Reload message can reach it.
updateSW := Some(registerSW(makeOptions(~onNeedRefresh=() => dispatch(UpdateAvailable))))
