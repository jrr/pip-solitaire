// Optional on-screen debugging aid for cutout-aware orientation, toggled from the
// menu's Debug section ("Safe-area overlay", persisted as `pip.cutoutDebug`,
// default off). Draws a bright frame around the browser-reported safe area and a
// centred readout of the four insets, the detected cutout side, and both
// orientation-angle APIs, so the detection can be eyeballed on any device without
// a reachable console.
//
// It only *visualises* — `CutoutSide` owns the real detection. Kept around (rather
// than deleted after the initial iPhone debugging) so a new device can be
// spot-checked the same way down the road: flip it on, rotate, read the values.

@val
external getComputedStyle: WebDom.element => {
  "paddingTop": string,
  "paddingRight": string,
  "paddingBottom": string,
  "paddingLeft": string,
} = "getComputedStyle"
@val external parseFloat: string => float = "parseFloat"
@val @scope("document") external body: WebDom.element = "body"
@val @scope("window") external innerWidth: float = "innerWidth"
@val @scope("window") external innerHeight: float = "innerHeight"
@val @scope("window")
external addWindowListener: (string, unit => unit) => unit = "addEventListener"

// The legacy, iOS-supported rotation signal (0 / 90 / -90 / 180); `undefined` on
// engines that dropped it, hence Nullable.
@val @scope("window") external windowOrientation: Nullable.t<float> = "orientation"
// The modern equivalent (0 / 90 / 180 / 270); `screen.orientation` is itself
// absent on older iOS, so guard the whole object.
type screenOrientation = {"angle": float}
@val @scope(("window", "screen"))
external screenOrientation: Nullable.t<screenOrientation> = "orientation"

// A probe carrying all four insets as paddings, read back as px (same trick as
// CutoutSide once used, extended to top/bottom for the readout).
let makeProbe = () => {
  let el = WebDom.createElement("div")
  el->WebDom.setAttribute(
    "style",
    "position:fixed;top:0;left:0;width:0;height:0;visibility:hidden;pointer-events:none;" ++ "padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)",
  )
  el
}

let px = f => (Float.isNaN(f) ? 0. : f)->Math.round->Float.toInt->Int.toString

let angleText = () =>
  switch screenOrientation->Nullable.toOption {
  | Some(o) => px(o["angle"])
  | None => "?"
  }

let winOrientationText = () =>
  switch windowOrientation->Nullable.toOption {
  | Some(a) => px(a)
  | None => "?"
  }

// The resolved cutout side, via the same angle logic the real detection uses, so
// the readout shows exactly what `CutoutSide` publishes.
let sideText = () =>
  CutoutSide.side(
    ~screenAngle=screenOrientation->Nullable.toOption->Option.map(o => o["angle"]),
    ~windowAngle=windowOrientation->Nullable.toOption,
  )

// The overlay nodes, created once by `install` and shown/hidden by `setVisible`.
// Module-level state is fine for a debug singleton.
type overlay = {frame: WebDom.element, readout: WebDom.element}
let overlay: ref<option<overlay>> = ref(None)

// Show/hide via the `hidden` attribute: the inline styles never set `display`, so
// the UA `[hidden] { display: none }` rule takes effect uncontested.
let setVisible = visible =>
  switch overlay.contents {
  | Some({frame, readout}) =>
    let apply = el =>
      visible ? el->WebDom.removeAttribute("hidden") : el->WebDom.setAttribute("hidden", "")
    apply(frame)
    apply(readout)
  | None => ()
  }

// Build the overlay (hidden or shown per `visible`) and keep it live on
// rotate/resize. Idempotent-ish: only the first call builds; call `setVisible`
// thereafter to toggle.
let install = (~visible) =>
  switch overlay.contents {
  | Some(_) => setVisible(visible)
  | None =>
    // The bright safe-area frame: styled straight off the four `env()` values, so
    // it outlines exactly what the browser reports as safe — no JS read needed.
    let frame = WebDom.createElement("div")
    frame->WebDom.setAttribute(
      "style",
      "position:fixed;top:env(safe-area-inset-top);right:env(safe-area-inset-right);" ++
      "bottom:env(safe-area-inset-bottom);left:env(safe-area-inset-left);" ++ "border:3px solid #ff2d95;box-sizing:border-box;pointer-events:none;z-index:99999",
    )
    body->WebDom.appendChild(frame)->ignore

    // The text readout, centred so it clears the top bar / side rail on every
    // orientation.
    let readout = WebDom.createElement("div")
    readout->WebDom.setAttribute(
      "style",
      "position:fixed;top:50%;left:50%;transform:translate(-50%, -50%);" ++
      "z-index:99999;pointer-events:none;font:12px/1.35 monospace;color:#fff;" ++ "background:rgba(0,0,0,0.78);padding:6px 10px;border-radius:6px;white-space:pre;text-align:left",
    )
    body->WebDom.appendChild(readout)->ignore

    let probe = makeProbe()
    body->WebDom.appendChild(probe)->ignore

    let refresh = () => {
      let cs = getComputedStyle(probe)
      let l = parseFloat(cs["paddingLeft"])
      let r = parseFloat(cs["paddingRight"])
      let t = parseFloat(cs["paddingTop"])
      let b = parseFloat(cs["paddingBottom"])
      let text =
        "cutout: " ++
        sideText() ++
        "\ninsets  L" ++
        px(l) ++
        " R" ++
        px(r) ++
        " T" ++
        px(t) ++
        " B" ++
        px(b) ++
        "\nangle   screen:" ++
        angleText() ++
        " window:" ++
        winOrientationText() ++
        "\nview    " ++
        px(innerWidth) ++
        "x" ++
        px(innerHeight)
      readout->WebDom.setTextContent(text)
    }
    refresh()
    addWindowListener("resize", refresh)
    addWindowListener("orientationchange", refresh)

    overlay := Some({frame, readout})
    setVisible(visible)
  }
