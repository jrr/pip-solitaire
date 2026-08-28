// Publishes which side a display cutout (notch / front camera) sits on to the
// CSS, as a `data-cutout` attribute on the document root, so the landscape chrome
// can move its control rail onto the cutout side — letting the rail's dead space
// share the strip that's unsafe anyway, and handing the clear side wholly to the
// cards (cutout-aware orientation, #179 follow-up).
//
// This was first attempted by comparing the two `env(safe-area-inset-*)` values,
// on the assumption the cutout side would report the larger inset. On-device that
// proved false: iOS insets *both* landscape sides symmetrically (e.g. L50 R50)
// regardless of which end the notch is on, so the insets carry no side signal at
// all. What *does* distinguish the two landscape rotations is the orientation
// angle, so the side is read from that instead. (A useful corollary of the
// symmetric insets: the cards are already held clear of the notch on both sides,
// so this attribute only steers where the rail sits, never card safety.)

// The modern signal: `screen.orientation.angle` (0 / 90 / 180 / 270). Guarded as
// Nullable because `screen.orientation` is absent on older iOS.
type screenOrientation = {"angle": float}
@val @scope(("window", "screen"))
external screenOrientation: Nullable.t<screenOrientation> = "orientation"
// The legacy fallback: `window.orientation` (0 / 90 / -90 / 180), for engines
// without `screen.orientation`. `undefined` off touch devices, hence Nullable.
@val @scope("window") external windowOrientation: Nullable.t<float> = "orientation"

@val @scope("document") external documentElement: WebDom.element = "documentElement"
@val @scope("window")
external addWindowListener: (string, unit => unit) => unit = "addEventListener"

// `screen.orientation.angle` is the viewport's clockwise rotation. On an iPhone
// the notch lives at the top edge in portrait, so a 90° rotation swings it to the
// left and 270° to the right (confirmed on-device: screen:90 ⇒ notch left). Only
// the two landscape angles name a side; portrait / upside-down expose none.
let sideOfScreenAngle = angle =>
  if angle == 90. {
    "left"
  } else if angle == 270. {
    "right"
  } else {
    "none"
  }

// `window.orientation` agrees at 90 (notch left) but uses the opposite sign for
// the other landscape: -90 ⇒ notch right.
let sideOfWindowAngle = angle =>
  if angle == 90. {
    "left"
  } else if angle == -90. {
    "right"
  } else {
    "none"
  }

// Resolve the cutout side, preferring the modern angle and falling back to the
// legacy one; `"none"` when neither is available (e.g. a desktop / jsdom host).
let side = (~screenAngle, ~windowAngle) =>
  switch screenAngle {
  | Some(a) => sideOfScreenAngle(a)
  | None =>
    switch windowAngle {
    | Some(a) => sideOfWindowAngle(a)
    | None => "none"
    }
  }

let read = () =>
  side(
    ~screenAngle=screenOrientation->Nullable.toOption->Option.map(o => o["angle"]),
    ~windowAngle=windowOrientation->Nullable.toOption,
  )

// Publish the side once, and keep it current on rotate/resize.
let install = () => {
  let refresh = () => documentElement->WebDom.setAttribute("data-cutout", read())
  refresh()
  addWindowListener("resize", refresh)
  addWindowListener("orientationchange", refresh)
}
