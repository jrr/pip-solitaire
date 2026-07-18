// Web-app entry point. The *chrome* — the version badge and the "Update
// available" button that frame the scene, plus the scene picker itself — is
// expressed as ReScript JSX on the hand-rolled `Html` runtime and driven by its
// Elm-style loop, rather than the imperative createElement/setAttribute dance
// this file used to be. (The greeting and tagline are no longer permanent chrome
// at all: they've moved into their own HomeScene, shown only when "Home" is the
// selected scene — see issue #59.) The only dynamic bits of the chrome (offline-ready
// and update-available, both reported by the service worker) live in the model;
// the service-worker callbacks just `dispatch` a message and the view re-renders
// itself. The scene area underneath — the switcher and its demos — is still the
// imperative SceneSwitcher; it's spliced into the view untouched with
// `Html.node`, which is exactly how a JSX chrome wraps a subtree it doesn't own.

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
// The two capitalized components used by the view below — `<VersionBadge/>` and
// `<UpdateButton/>` — live in their own files under `src/components/`. Each is a
// `props => vnode` function; capitalized JSX lowers `<VersionBadge .../>` to
// `Html.jsx(VersionBadge.make, props)`, filling the module's `props` record from
// the attributes. See those files for why the record is spelled out by hand
// instead of derived by the `@jsx.component` sugar.

// --- The Elm loop ------------------------------------------------------------
// The chrome is a pure model + update + view. Everything reactive here is
// service-worker lifecycle: the two booleans flip when their callbacks fire.
type model = {
  version: string,
  buildTime: string,
  offlineReady: bool,
  updateAvailable: bool,
}

type msg =
  | OfflineReady // precache finished — the app now works offline
  | UpdateAvailable // a new build is waiting in the wings
  | Reload // user asked to activate the waiting worker and reload

// `updateSW` only exists once registerSW has run, which needs `dispatch`, which
// needs the loop to be mounted — so the Reload effect reaches it through a ref
// that's filled in just after mount (see below).
let updateSW: ref<option<bool => promise<unit>>> = ref(None)

let update = (msg, model) =>
  switch msg {
  | OfflineReady => ({...model, offlineReady: true}, Html.noEffect)
  | UpdateAvailable => ({...model, updateAvailable: true}, Html.noEffect)
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
// subtree. `render` hands back the picker drop-down and the scene container as
// two separate real DOM nodes; the view splices each in with `Html.node` and
// never re-renders them. The drop-down sits above the scene band; the band wraps
// only the scene. See SceneSwitcher / Scene.
// The scene list ends with one scene per *modelled game* (#62): `Game.all` is
// the source of truth, and `TableScene.make` interprets each game's rules, so a
// new game is a new value in core — no new scene code, no edit here.
//
// The URL can steer both which scene opens (`?scene=`) and which starting
// position it opens in (`?state=`): each game scene is built with the scenario the
// URL names for it (via `Scenario.forName`), or its ordinary deal when there's
// none, and the named scene is forced open below. That's the whole entry point the
// screenshot report drives (`?scene=freecell&state=midgame`).
let url = AppUrl.parse()

// A fresh seed for each New Game (#108). The seed is the future "deal number"
// (#98): random for now, so every re-deal lays out a different FreeCell board;
// a deal-number entry point can later supply a chosen seed to this same
// `freecellDeal`. `Math.random` is fine here — this is the impure view layer,
// not `core`'s deterministic deal path.
let randomSeed = () => (Math.random() *. 1_000_000.)->Float.toInt

// Only FreeCell is re-dealable: it's built from a seeded shuffle, so a new seed
// gives a genuinely new board. The fixed-layout demos have no seed to vary, so
// they get no New Game control.
let gameScene = (game: Game.t) => {
  let newDeal =
    game.id == Game.freecell.id ? Some(() => Game.freecellDeal(~seed=randomSeed())) : None
  TableScene.make(
    ~initial=?url.state->Option.flatMap(name => Scenario.forName(game, name)),
    ~newDeal?,
    game,
  )
}
let switcher = SceneSwitcher.render(
  ~forced=?url.scene,
  Array.concat(
    [HomeScene.make(), SpinnerScene.make(), SvgScene.make(), GalleryScene.make()],
    Game.all->Array.map(gameScene),
  ),
)

let view = (model, dispatch) => <>
  <main id="app">
    {Html.node(switcher.controls)}
    <section id="scene-area">
      <div id="scene-box"> {Html.node(switcher.scene)} </div>
    </section>
  </main>
  <VersionBadge
    version={model.version} buildTime={model.buildTime} offlineReady={model.offlineReady}
  />
  <UpdateButton visible={model.updateAvailable} onReload={() => dispatch(Reload)} />
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
  },
  ~update,
  ~view,
)

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
