// TEMPORARY debugging aids for cutout-aware orientation. Draws a bright border
// around the browser-reported safe area and a live readout of the four insets,
// the detected cutout side, and both orientation-angle APIs, so the behaviour
// can be eyeballed on a real device (where the console isn't reachable). Wired in
// from Main with a single `CutoutDebug.install()` call — delete this file and
// that call to remove it.
//
// The readout exists to answer one question: on iOS Safari, does
// `env(safe-area-inset-left)` actually differ from `-right` in landscape? If the
// two come back equal (iOS is known to inset *both* sides symmetrically for the
// notch), then `CutoutSide.sideFrom` can never pick a side and we need an
// orientation *angle* instead — which is why `screen.orientation.angle` and the
// legacy `window.orientation` are shown too.

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
// CutoutSide, extended to top/bottom for the readout).
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

let install = () => {
  // The bright safe-area frame: styled straight off the four `env()` values, so it
  // outlines exactly what the browser reports as safe — no JS read needed.
  let frame = WebDom.createElement("div")
  frame->WebDom.setAttribute(
    "style",
    "position:fixed;top:env(safe-area-inset-top);right:env(safe-area-inset-right);" ++
    "bottom:env(safe-area-inset-bottom);left:env(safe-area-inset-left);" ++ "border:3px solid #ff2d95;box-sizing:border-box;pointer-events:none;z-index:99999",
  )
  body->WebDom.appendChild(frame)->ignore

  // The text readout, parked just inside the top-left of the safe area.
  let readout = WebDom.createElement("div")
  readout->WebDom.setAttribute(
    "style",
    "position:fixed;top:calc(env(safe-area-inset-top) + 4px);left:calc(env(safe-area-inset-left) + 4px);" ++
    "z-index:99999;pointer-events:none;font:12px/1.35 monospace;color:#fff;" ++ "background:rgba(0,0,0,0.78);padding:4px 8px;border-radius:6px;white-space:pre;text-align:left",
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
      CutoutSide.sideFrom(l, r) ++
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
}
