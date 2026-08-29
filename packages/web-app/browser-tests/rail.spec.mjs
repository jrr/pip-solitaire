// The landscape control rail must clear the shaded scene band in all four chrome
// regimes: `data-cutout` left/right × `data-notch-wings` on/off.
//
// Why this can't be a unit test. The rules under test live in
// `@media (orientation: landscape) and (max-height: 500px)` blocks, and jsdom only
// evaluates a media rule whose media list contains the literal token `screen`
// (see jsdom's living/helpers/style-rules.js) — ours don't, so jsdom skips the
// blocks wholesale and every regime reads back the base `#top-bar` margins. The
// cascade question is therefore only answerable in a real engine, which is what
// this suite is for.
//
// What it pins. The rail and the band are positioned by *margins that cancel each
// other* — body pads by `env(safe-area-inset-*) + 1.5rem`, then `#top-bar` and
// `#scene-area` claw portions of that back with negative margins, differently per
// regime. That makes the regimes easy to break one at a time, and the failure is
// silent: nothing overflows, the rail just creeps over the play area. So rather
// than assert specific margin values (which encode the arithmetic twice), this
// measures the one invariant that has to hold in every regime — the rail sits
// wholly *beside* the band, never over it — plus that the gap is the intended
// 0.5rem.
//
// A regression this catches (#204 follow-up): `html[data-notch-wings="off"]
// #top-bar { margin-left: -0.75rem }` tied on specificity (1,1,1) with
// `html[data-cutout="right"] #top-bar`'s shorthand and won on source order,
// clobbering the right-hand rail's 0.5rem gap and overhanging the band by 12px.
//
// `data-cutout` is stamped from the orientation angle, which headless Chromium
// reports as 0 — so the attributes are set directly here. That's deliberate: this
// tests the CSS contract *given* the attributes; the detection that produces them
// is unit-tested in CutoutSide_test.res.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

// A landscape phone: wide, and under the 500px `max-height` that keys the rail
// regime. Chromium reports every `env(safe-area-inset-*)` as 0, which is fine —
// the regression is in an *unconditional* margin, so it shows up at zero insets
// too. Real insets only change how far the rail sits from the screen edge, not
// whether it overlaps the band.
test.use({ viewport: { width: 844, height: 390 } })

// 0.5rem at the root font size — the gap the rail is meant to leave before the
// band in the two regimes that place one. `toBeCloseTo(_, 0)` allows half a pixel.
const EXPECTED_GAP = 8
const GAP_DIGITS = 0

const REGIMES = [
  { cutout: "left", wings: "on" },
  { cutout: "left", wings: "off" },
  { cutout: "right", wings: "on" },
  { cutout: "right", wings: "off" },
]

// Stamp one regime onto <html> and measure the rail against the band. The rail is
// on whichever edge the cutout is, and the band on the other, so the gap between
// them is measured from opposite faces per side.
function measureRegime([cutoutSide, wingsMode]) {
  const html = document.documentElement
  html.setAttribute("data-cutout", cutoutSide)
  if (wingsMode === "off") html.setAttribute("data-notch-wings", "off")
  else html.removeAttribute("data-notch-wings")

  const topBar = document.getElementById("top-bar")
  const bar = topBar.getBoundingClientRect()
  const band = document.getElementById("scene-box").getBoundingClientRect()
  return {
    gap: cutoutSide === "right" ? bar.left - band.right : band.left - bar.right,
    barLeft: bar.left,
    barRight: bar.right,
    bandLeft: band.left,
    bandRight: band.right,
    marginLeft: getComputedStyle(topBar).marginLeft,
    marginRight: getComputedStyle(topBar).marginRight,
  }
}

for (const { cutout, wings } of REGIMES) {
  test(`the rail clears the scene band with cutout=${cutout} wings=${wings}`, async ({ page }) => {
    // A dealt board, animation off, so the scene band and rail are settled and the
    // measurement isn't racing the opening deal.
    await page.goto("/?game=freecell&state=midgame&animate=off")
    await expect(page.locator(".drop-rows .drop-zone").first()).toBeAttached()
    await settleBoard(page)

    const m = await page.evaluate(measureRegime, [cutout, wings])

    // A negative gap means the rail overlaps the shaded band — the failure this
    // exists to catch. The rendered positions ride along in the message so a
    // break shows which side moved.
    const where =
      `rail=[${m.barLeft.toFixed(1)}, ${m.barRight.toFixed(1)}] ` +
      `band=[${m.bandLeft.toFixed(1)}, ${m.bandRight.toFixed(1)}] ` +
      `margin L=${m.marginLeft} R=${m.marginRight}`
    expect(m.gap, `rail→band gap (${where})`).toBeCloseTo(EXPECTED_GAP, GAP_DIGITS)
  })
}
