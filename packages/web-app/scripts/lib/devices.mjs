// The devices the screenshot report is shot on — taken from Playwright's own
// `devices` registry rather than a hand-rolled `{ width, height, dpr }` list
// (issue #244).
//
// The registry entry for a phone is a `DeviceDescriptor`: viewport, screen,
// deviceScaleFactor, userAgent, and — the two that matter here — `isMobile` and
// `hasTouch`. Per the API docs `isMobile` is "whether the meta viewport tag is
// taken into account and touch events are enabled". A hand-set viewport gets
// neither, so a phone-*sized* context still reported `ontouchstart: false` and
// `maxTouchPoints: 0`, and `@media (hover: hover)` / `(pointer: coarse)`
// resolved the desktop way: we were shooting phone-shaped desktop Chromium.
// Spreading the descriptor into `newContext` fixes both, so the report shows the
// CSS regime a real phone actually gets.
//
// Two consequences worth knowing:
//   - The registry carries a separate `"<device> landscape"` entry per device,
//     whose viewport is the device rotated *and* re-fitted around the browser
//     chrome — so orientation comes from the registry too, rather than from
//     swapping width/height ourselves.
//   - The iOS descriptors carry a Safari user-agent and `defaultBrowserType:
//     "webkit"`, while the report drives Chromium. That's the documented way to
//     use them (`browser.newContext(devices['iPhone 13'])`), and the app doesn't
//     sniff the UA — what we're after is the viewport/DPR/touch profile.
//
// The desktop entry has no registry equivalent (there are no desktop
// descriptors), so it stays hand-written — deliberately mouse-and-hover, which
// is now a real distinction rather than an accident of the harness.

import { devices } from "@playwright/test"

/** A wide desktop: the only entry with no registry equivalent. */
const desktop = {
  viewport: { width: 1920, height: 1080 },
  deviceScaleFactor: 1,
  isMobile: false,
  hasTouch: false,
}

/**
 * Each device names the orientations it's shot in and the context options for
 * each — a small phone and a tablet both ways up, plus a wide desktop shot
 * landscape only (a portrait 1080-wide desktop isn't a real target, and the wide
 * layout is the point: past ~1064px the card row caps its width and the stage
 * grows side margins instead of gaps — see TableScene's `--rows-max-w`).
 *
 * The names are the report's labels; the registry keys they map to are right
 * there beside them. (iPhone 13 Mini and iPhone SE share the same 375-wide CSS
 * size, so the mini stands in for the SE here — same width, taller, 3× display.)
 */
export const reportDevices = [
  {
    name: "iPhone 13 mini",
    orientations: {
      portrait: devices["iPhone 13 Mini"],
      landscape: devices["iPhone 13 Mini landscape"],
    },
  },
  {
    name: "iPad mini",
    orientations: {
      portrait: devices["iPad Mini"],
      landscape: devices["iPad Mini landscape"],
    },
  },
  {
    name: "Desktop",
    orientations: { landscape: desktop },
  },
]

/**
 * The context options for one shot, as a plain object to spread into
 * `browser.newContext`. `defaultBrowserType` is part of the descriptor but not a
 * context option — it tells `test.use` which engine the device implies — so drop
 * it rather than hand `newContext` a key it has no use for.
 */
export function contextOptions(descriptor) {
  const { defaultBrowserType: _ignored, ...options } = descriptor
  return options
}

/** A one-line summary of what a descriptor emulates, for the report's captions. */
export function describe(descriptor) {
  const { width, height } = descriptor.viewport
  const dpr = descriptor.deviceScaleFactor ?? 1
  return {
    width,
    height,
    dpr,
    pxWidth: Math.round(width * dpr),
    pxHeight: Math.round(height * dpr),
    input: descriptor.hasTouch ? "touch" : "mouse",
  }
}
