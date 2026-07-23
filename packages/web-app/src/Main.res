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
//     retired Home scene), a **Game** section (New Game · Restart, #156), the
//     debug/demo scene list as tappable rows, and the About footer (build/version
//     info plus the conditional "Update now" button, #165).
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
  offlineReady: bool,
  updateAvailable: bool,
  menuOpen: bool,
  autoCollect: bool,
  cardTilt: bool,
  cutoutDebug: bool,
  canUndo: bool,
}

type msg =
  | OfflineReady // precache finished — the app now works offline
  | UpdateAvailable // a new build is waiting in the wings
  | Reload // user asked to activate the waiting worker and reload
  | ToggleMenu // the top bar's Menu button
  | CloseMenu // backdrop / close button / a scene row was tapped
  | ToggleAutoCollect // the menu's Auto-collect switch (#139)
  | ToggleCardTilt // the menu's hand-placed-tilt switch (#65)
  | ToggleCutoutDebug // the menu's safe-area overlay switch (debug)
  | HistoryChanged(bool) // whether the board can undo after a move (#85)

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

// The active board's Undo action (#85), sibling of `newGameHook`. The mounted
// `TableScene` publishes a thunk here on every build (a re-deal republishes the
// fresh board's), the switcher's `onActivate` clears it before each scene change,
// and the top bar's Undo button runs whatever is current. A debug/demo scene
// publishes none, so the button is a harmless no-op there.
let undoHook: ref<option<unit => unit>> = ref(None)

// The board's reverse channel (#85): after every state change it reports whether
// there's anything to undo so the top bar can enable/disable the button. Filled
// with a real dispatcher just after mount (like `closeMenu`); until then a no-op,
// and reset to `false` on each scene change so a non-game scene leaves the button
// disabled.
let reportHistory: ref<bool => unit> = ref(_ => ())

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

// The active board's "relayout" action (#65), sibling of `undoHook`: the mounted
// `TableScene` publishes a thunk that re-lays every resting card, so a tilt toggle
// can re-tilt the board in place at once. Cleared on each scene change and a no-op
// until the next board republishes.
let relayoutHook: ref<option<unit => unit>> = ref(None)

let update = (msg, model) =>
  switch msg {
  | OfflineReady => ({...model, offlineReady: true}, Html.noEffect)
  | UpdateAvailable => ({...model, updateAvailable: true}, Html.noEffect)
  | ToggleMenu => ({...model, menuOpen: !model.menuOpen}, Html.noEffect)
  | HistoryChanged(canUndo) =>
    canUndo == model.canUndo ? (model, Html.noEffect) : ({...model, canUndo}, Html.noEffect) // no change — don't re-render
  | CloseMenu =>
    model.menuOpen ? ({...model, menuOpen: false}, Html.noEffect) : (model, Html.noEffect)
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
  | ToggleCutoutDebug =>
    let cutoutDebug = !model.cutoutDebug
    (
      {...model, cutoutDebug},
      // Show/hide the overlay at once. Not persisted — it's a debug aid, on only
      // for the session; the model state carries it across rotations regardless.
      () => CutoutDebug.setVisible(cutoutDebug),
    )
  | Reload => (
      model, // no state change — just run the effect
      () =>
        switch updateSW.contents {
        | Some(reload) => reload(true)->ignore
        | None => ()
        },
    )
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
  // Open FreeCell from a fresh random seed on each load too (#108/#98), so a plain
  // reload lays out a new board instead of always deal #1 — matching what New Game
  // does. A `?seed=` pins that deal number instead (#98), so a link — and the
  // screenshot report's dealt-board shot — lands on the same board every time. The
  // fixed module-level `Game.freecell` (seed 1) stays the deterministic fallback for
  // a forced `?state=` scenario, which screenshots depend on: when a state is forced
  // we mount the fixed deal so `Scenario.forName` derives from the exact same board
  // the report expects. The fixed-layout demos have no seed to vary, so they mount
  // as-is.
  let opening =
    isFreecell && url.state->Option.isNone
      ? Game.freecellDeal(~seed=url.seed->Option.getOr(randomSeed()))
      : game
  let newDeal = isFreecell ? Some(() => Game.freecellDeal(~seed=randomSeed())) : None
  TableScene.make(
    ~initial=?url.state->Option.flatMap(name => Scenario.forName(game, name)),
    ~newDeal?,
    ~publishNewGame=hook => newGameHook := Some(hook),
    ~publishRestart=hook => restartHook := Some(hook),
    ~publishLoadState=hook => loadStateHook := Some(hook),
    ~publishUndo=hook => undoHook := Some(hook),
    ~publishRelayout=hook => relayoutHook := Some(hook),
    ~onHistory=canUndo => reportHistory.contents(canUndo),
    ~options,
    ~tiltEnabled,
    // Skip the opening-deal fly-in when the URL asks for `?animate=off`, so the
    // board is shown already dealt (the same instant placement reduced-motion gives).
    ~skipDealAnimation=!url.animate,
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
    relayoutHook := None
    // Drop the outgoing board's undo and reset the top bar's button to disabled;
    // the mounting scene republishes and reports its own history (#85).
    undoHook := None
    reportHistory.contents(false)
    closeMenu.contents()
  },
  Array.concat(
    [SpinnerScene.make(), SvgScene.make(), GalleryScene.make()],
    Game.all->Array.map(gameScene),
  ),
)

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
  <Menu
    open_={model.menuOpen}
    onClose={() => dispatch(CloseMenu)}
    onNewGame={() => {
      newGameHook.contents->Option.forEach(newGame => newGame())
      dispatch(CloseMenu)
    }}
    onRestart={() => {
      restartHook.contents->Option.forEach(restart => restart())
      dispatch(CloseMenu)
    }}
    games={switcher.controls}
    debugScenes={switcher.debugScenes}
    debugStates={debugStates}
    cutoutDebug={model.cutoutDebug}
    onToggleCutoutDebug={() => dispatch(ToggleCutoutDebug)}
    autoCollect={model.autoCollect}
    onToggleAutoCollect={() => dispatch(ToggleAutoCollect)}
    cardTilt={model.cardTilt}
    onToggleCardTilt={() => dispatch(ToggleCardTilt)}
    version={model.version}
    buildTime={model.buildTime}
    offlineReady={model.offlineReady}
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

// The safe-area debug overlay (a menu Debug-section toggle): built once here,
// hidden, and flipped live by ToggleCutoutDebug. A developer aid for spot-checking
// cutout detection on a device; session-only, not persisted.
CutoutDebug.install(~visible=false)

let dispatch = Html.mount(
  ~root,
  ~init={
    version: appVersion,
    buildTime,
    offlineReady: false,
    updateAvailable: false,
    menuOpen: false,
    // Mirror the persisted preferences so the menu's switches open in the right
    // position (the board reads the `options` and `tiltEnabled` refs directly).
    autoCollect: options.contents.autoCollect,
    cardTilt: tiltEnabled.contents,
    // Debug overlay starts off each session (not persisted); the model keeps it
    // across rotations.
    cutoutDebug: false,
    // Undo starts disabled; the mounted board reports its history (#85).
    canUndo: false,
  },
  ~update,
  ~view,
)

// Now that `dispatch` exists, let a scene row close the menu through it.
closeMenu := (() => dispatch(CloseMenu))

// …and let the board's history reports reach the loop, so Undo enables and
// disables as moves are played and undone (#85).
reportHistory := (canUndo => dispatch(HistoryChanged(canUndo)))

// Now that `dispatch` exists, register the worker and let its callbacks drive
// the loop. Stash the returned updater so the Reload message can reach it.
updateSW :=
  Some(
    registerSW(
      makeOptions(
        ~onNeedRefresh=() => dispatch(UpdateAvailable),
        ~onOfflineReady=() => dispatch(OfflineReady),
      ),
    ),
  )
