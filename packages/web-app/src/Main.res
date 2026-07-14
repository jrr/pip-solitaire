// Web-app entry point. Builds the page with plain DOM bindings (no framework),
// shows the baked-in build version in a corner "about" badge, and wires the
// service-worker update lifecycle so a new deploy surfaces an "Update
// available" button that activates the waiting worker and reloads.

// --- Minimal DOM bindings ---------------------------------------------------
type element

@val @scope("document") external body: element = "body"
@val @scope("document") external createElement: string => element = "createElement"
@send external appendChild: (element, element) => element = "appendChild"
@send external setAttribute: (element, string, string) => unit = "setAttribute"
@send external getAttribute: (element, string) => Nullable.t<string> = "getAttribute"
@send external removeAttribute: (element, string) => unit = "removeAttribute"
@send external addEventListener: (element, string, unit => unit) => unit = "addEventListener"
@set external setTextContent: (element, string) => unit = "textContent"

// A `card-poked` event carries the card's rotation angle in its `detail` (see
// sleight-board.js). This overload of `addEventListener` hands the listener the
// event so the container can read that payload — the "outward" half of the
// custom-element contract.
type customEvent<'detail>
@get external detail: customEvent<'detail> => 'detail = "detail"
@send
external addEventListenerCE: (element, string, customEvent<'detail> => unit) => unit =
  "addEventListener"

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
external registerSW: registerSWOptions => (bool => promise<unit>) = "registerSW"

// --- <sleight-board> custom element ------------------------------------------
// The element itself is plain JS (class extends HTMLElement); we just import its
// `register` and call it before creating one. See sleight-board.js.
@module("./sleight-board.js") external registerBoard: unit => unit = "register"

// --- Build the page ---------------------------------------------------------
// Layout and colors live in the stylesheet in index.html; here we just build
// the semantic structure and hang ids off it. A centered <main> holds the
// greeting heading and a short tagline describing the app.
let app = createElement("main")
setAttribute(app, "id", "app")

let greeting = createElement("h1")
setAttribute(greeting, "id", "greeting")
setTextContent(greeting, Core.greeting())
appendChild(app, greeting)->ignore

let tagline = createElement("p")
setAttribute(tagline, "id", "tagline")
setTextContent(tagline, "An installable, offline-capable FreeCell.")
appendChild(app, tagline)->ignore

// --- Web Component spike (issue #29) -----------------------------------------
// A <sleight-board> with a spinning card, plus a container proving the boundary
// works in both directions from ReScript:
//   inward   — the flip button toggles the board's `spin` attribute; CSS reacts.
//   outward  — clicking the card fires `card-poked`; we read `detail` and show
//              the reported position in a readout.
registerBoard()

let boardSection = createElement("section")
setAttribute(boardSection, "id", "board-demo")

let board = createElement("sleight-board")
setAttribute(board, "spin", "cw")
appendChild(boardSection, board)->ignore

let flipButton = createElement("button")
setAttribute(flipButton, "id", "flip-button")
setTextContent(flipButton, "Reverse spin")
appendChild(boardSection, flipButton)->ignore

let readout = createElement("p")
setAttribute(readout, "id", "board-readout")
setTextContent(readout, "Poke the card…")
appendChild(boardSection, readout)->ignore

appendChild(app, boardSection)->ignore

// inward: the button only toggles the attribute — no imperative call into the
// element. `getAttribute` is nullable, so a missing/unknown value defaults to cw.
addEventListener(flipButton, "click", () => {
  let next = switch getAttribute(board, "spin")->Nullable.toOption {
  | Some("ccw") => "cw"
  | _ => "ccw"
  }
  setAttribute(board, "spin", next)
})

// outward: listen with a plain addEventListener and read the event's detail.
addEventListenerCE(board, "card-poked", (event: customEvent<{"angle": float}>) => {
  let d = detail(event)
  let angle = Math.round(d["angle"])->Float.toString
  setTextContent(readout, `card pointed at ${angle}°`)
})

appendChild(body, app)->ignore

// A small fixed corner badge reporting exactly which build is running. Updated
// to note offline-readiness once the service worker has finished precaching.
let versionBadge = createElement("div")
setAttribute(versionBadge, "id", "version-badge")
setTextContent(versionBadge, `v${appVersion} · ${buildTime}`)
appendChild(body, versionBadge)->ignore

// The "Update available" button. Hidden until the service worker reports a
// waiting update (onNeedRefresh); clicking it activates the new worker and
// reloads to the fresh version.
let updateButton = createElement("button")
setAttribute(updateButton, "id", "update-button")
setTextContent(updateButton, "Update available — reload")
setAttribute(updateButton, "hidden", "")
appendChild(body, updateButton)->ignore

let updateSW = registerSW(
  makeOptions(
    ~onNeedRefresh=() => removeAttribute(updateButton, "hidden"),
    ~onOfflineReady=() =>
      setTextContent(versionBadge, `v${appVersion} · ${buildTime} · offline-ready`),
  ),
)

addEventListener(updateButton, "click", () => updateSW(true)->ignore)
