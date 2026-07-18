// Web-app entry point. The app *opens as a game*: on startup it mounts the
// FreeCell board straight away (#109), and all the chrome — a single top bar plus
// a slide-over menu — is expressed as ReScript JSX on the hand-rolled `Html`
// runtime and driven by its Elm-style loop. The bottom of the screen is left
// clear for dragging cards; every control lives up top.
//
// The chrome is two components over the scene:
//   - `<TopBar>` — Menu · New Game · Undo-stub · conditional Update. Always
//     visible across the top.
//   - `<Menu>` — the slide-over holding the title ("Sleight", moved out of the
//     retired Home scene), the debug/demo scene list as tappable rows, and the
//     build/version info.
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
// and (nested inside them) `<UpdateButton/>` / `<VersionBadge/>` — live under
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
}

type msg =
  | OfflineReady // precache finished — the app now works offline
  | UpdateAvailable // a new build is waiting in the wings
  | Reload // user asked to activate the waiting worker and reload
  | ToggleMenu // the top bar's Menu button
  | CloseMenu // backdrop / close button / a scene row was tapped

// `updateSW` only exists once registerSW has run, which needs `dispatch`, which
// needs the loop to be mounted — so the Reload effect reaches it through a ref
// that's filled in just after mount (see below).
let updateSW: ref<option<bool => promise<unit>>> = ref(None)

// The active scene's "New Game" action, if it has one. The mounted scene
// publishes its re-deal here (see `gameScene` / `TableScene`), the switcher's
// `onActivate` clears it before each scene change, and the top bar's New Game
// button runs whatever is current. Only FreeCell publishes one today, so on a
// debug scene the button is a harmless no-op.
let newGameHook: ref<option<unit => unit>> = ref(None)

// Closing the menu means dispatching into the loop, but a scene row is an
// imperative listener built before `dispatch` exists (like `updateSW`). It
// reaches the loop through this ref, filled in just after mount.
let closeMenu: ref<unit => unit> = ref(() => ())

let update = (msg, model) =>
  switch msg {
  | OfflineReady => ({...model, offlineReady: true}, Html.noEffect)
  | UpdateAvailable => ({...model, updateAvailable: true}, Html.noEffect)
  | ToggleMenu => ({...model, menuOpen: !model.menuOpen}, Html.noEffect)
  | CloseMenu =>
    model.menuOpen ? ({...model, menuOpen: false}, Html.noEffect) : (model, Html.noEffect)
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
  let newDeal =
    game.id == Game.freecell.id ? Some(() => Game.freecellDeal(~seed=randomSeed())) : None
  TableScene.make(
    ~initial=?url.state->Option.flatMap(name => Scenario.forName(game, name)),
    ~newDeal?,
    ~publishNewGame=hook => newGameHook := Some(hook),
    game,
  )
}
let switcher = SceneSwitcher.render(
  ~default="freecell",
  ~forced=?url.scene,
  // Reset the top bar's New Game action before each scene mounts (the mounting
  // scene republishes it if re-dealable) and close the menu after a row tap.
  ~onActivate=_scene => {
    newGameHook := None
    closeMenu.contents()
  },
  Array.concat(
    [SpinnerScene.make(), SvgScene.make(), GalleryScene.make()],
    Game.all->Array.map(gameScene),
  ),
)

let view = (model, dispatch) => <>
  <main id="app">
    <TopBar
      onMenu={() => dispatch(ToggleMenu)}
      onNewGame={() =>
        switch newGameHook.contents {
        | Some(newGame) => newGame()
        | None => ()
        }}
      updateVisible={model.updateAvailable}
      onReload={() => dispatch(Reload)}
    />
    <section id="scene-area">
      <div id="scene-box"> {Html.node(switcher.scene)} </div>
    </section>
  </main>
  <Menu
    open_={model.menuOpen}
    onClose={() => dispatch(CloseMenu)}
    scenes={switcher.controls}
    version={model.version}
    buildTime={model.buildTime}
    offlineReady={model.offlineReady}
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

let dispatch = Html.mount(
  ~root,
  ~init={
    version: appVersion,
    buildTime,
    offlineReady: false,
    updateAvailable: false,
    menuOpen: false,
  },
  ~update,
  ~view,
)

// Now that `dispatch` exists, let a scene row close the menu through it.
closeMenu := (() => dispatch(CloseMenu))

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
