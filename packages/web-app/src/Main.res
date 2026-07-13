// Web-app entry point, structured as a tiny Elm-style app on the hand-rolled
// JSX runtime in Html.res (no React, no vdom). The view is a pure function of
// the model; the service-worker lifecycle feeds messages in, and the one
// genuine side effect (reloading onto the waiting worker) travels as a command.

// --- Build version ----------------------------------------------------------
// Injected by Vite `define` at build time (see vite.config.js); "unknown" only
// if the build ran without git.
@val external appVersion: string = "__APP_VERSION__"
@val external buildTime: string = "__BUILD_TIME__"

// --- Service-worker registration (vite-plugin-pwa virtual module) -----------
// `registerSW` registers the worker (relative URL, so its scope follows the
// GitHub Pages subpath) and returns `updateSW(reloadPage)` — tell the waiting
// worker to skip waiting, then reload.
type registerSWOptions
@obj
external makeOptions: (
  ~onNeedRefresh: unit => unit=?,
  ~onOfflineReady: unit => unit=?,
) => registerSWOptions = ""

@module("virtual:pwa-register")
external registerSW: registerSWOptions => bool => promise<unit> = "registerSW"

// --- Model ------------------------------------------------------------------
type model = {
  version: string,
  buildTime: string,
  offlineReady: bool, // service worker finished precaching
  updateAvailable: bool, // a newer worker is waiting to activate
}

type msg =
  | OfflineReady
  | UpdateAvailable
  | ClickedReload

// The reload effect isn't known until `registerSW` returns `updateSW`, so the
// ClickedReload command reaches it through this ref (set once, below).
let reload = ref(Html.noEffect)

let update = (msg, model) =>
  switch msg {
  | OfflineReady => ({...model, offlineReady: true}, Html.noEffect)
  | UpdateAvailable => ({...model, updateAvailable: true}, Html.noEffect)
  | ClickedReload => (model, () => reload.contents())
  }

// --- Components --------------------------------------------------------------
// Layout and colors still live in the stylesheet in index.html; components just
// build the semantic structure and hang the same ids off it.

module Title = {
  @jsx.component
  let make = () =>
    <main id="app">
      <h1 id="greeting"> {Html.string(Core.greeting())} </h1>
      <p id="tagline"> {Html.string("An installable, offline-capable FreeCell.")} </p>
    </main>
}

// A small fixed corner badge reporting exactly which build is running, noting
// offline-readiness once the service worker has finished precaching.
module VersionBadge = {
  @jsx.component
  let make = (~version, ~buildTime, ~offlineReady) => {
    let label = offlineReady
      ? `v${version} · ${buildTime} · offline-ready`
      : `v${version} · ${buildTime}`
    <div id="version-badge"> {Html.string(label)} </div>
  }
}

// The "Update available" button. The view only renders it once an update is
// waiting, so it needs no hidden state of its own.
module UpdateButton = {
  @jsx.component
  let make = (~onReload) =>
    <button id="update-button" onClick={_ => onReload()}>
      {Html.string("Update available — reload")}
    </button>
}

let view = (model, dispatch) => <>
  <Title />
  <VersionBadge
    version={model.version} buildTime={model.buildTime} offlineReady={model.offlineReady}
  />
  {model.updateAvailable
    ? <UpdateButton onReload={() => dispatch(ClickedReload)} />
    : Html.string("")}
</>

// --- Boot -------------------------------------------------------------------
let dispatch = Html.mount(
  ~root=Html.body,
  ~init={version: appVersion, buildTime, offlineReady: false, updateAvailable: false},
  ~update,
  ~view,
)

let updateSW = registerSW(
  makeOptions(
    ~onNeedRefresh=() => dispatch(UpdateAvailable),
    ~onOfflineReady=() => dispatch(OfflineReady),
  ),
)

reload := (() => updateSW(true)->ignore)
