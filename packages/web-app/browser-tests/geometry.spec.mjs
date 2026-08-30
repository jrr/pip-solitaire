// Pin the card-table geometry invariants the stylesheet and TableScene both claim.
// The geometry itself is docs/board-geometry.md.
//
// Card, zone and empty-slot footprints are produced jointly: TableScene measures the
// stage, asks TableLayout for a `scale`, and publishes the scaled footprints as custom
// properties (see `applyScale`). Every proportion between them — the 5:7 aspect, the
// corner ratios, the uniform `zoneInset` — is stated once in ReScript, so any of them
// re-derived a second time on the CSS side can drift with nothing to catch it: the
// numbers stay plausible, and a mismatch shows up only as slightly non-concentric
// corners or a dashed slot that no longer traces the card.
//
// So rather than assert the constants, this measures the *rendered* geometry and
// checks the relationships between them. Everything is read back from the live
// layout, so the checks hold whichever side of the JS/CSS seam each number is
// sourced from. That is the point: moving a derivation across the seam must not
// move a pixel.
//
// Runs in a real engine because it needs the cascade, `calc()` resolution and real
// layout; jsdom has none of those (see rail.spec.mjs for the same reasoning).

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

// The playing-card proportion the whole design is built on (5:7).
const EXPECTED_ASPECT = 7 / 5

// Layout is snapped to 1/64px (0.015625) in Chromium, so comparisons of measured
// rects need a little room; ratios derived from them need proportionally less.
// `toBeCloseTo(want, n)` allows half a unit in the nth decimal place: 0.05px here,
// 0.005 on the ratios.
const PX_DIGITS = 1
const RATIO_DIGITS = 2

// Three viewports chosen so a different term of `applyScale`'s clamp binds in each:
// the `maxScale` ceiling on a roomy desktop, the width target in portrait, the
// height target in landscape. That spreads the invariants across three different
// scale factors, which is the point — a proportion folded into a ratio literal
// shows up as drift only once the scale moves off 1.
//
// The desktop case sits *above* the design footprint (`maxScale` is 1.35, so
// `--card-w` lands at 108px), which is worth keeping: it exercises the one
// direction — scaling up — that the layout never used while the ceiling was 1.
// Deliberately no numbers here beyond the viewport sizes; the checks derive their
// expectations from what was rendered, so raising or lowering `maxScale` moves the
// measurements without needing a change on this side.
const VIEWPORTS = [
  { width: 1600, height: 1000, label: "desktop (ceiling-bound, scale = maxScale)" },
  { width: 390, height: 844, label: "portrait phone (width-bound)" },
  { width: 844, height: 390, label: "landscape phone (height-bound)" },
]

// Read the whole footprint off the live layout in one go: every invariant below
// is a relationship between these numbers, so they have to come from a single
// settled frame.
function measure() {
  const num = (s) => parseFloat(s)
  const playfield = document.querySelector(".stacking-playfield")
  const pcs = getComputedStyle(playfield)
  const slot = document.querySelector(".drop-zone__slot")
  const zone = slot.closest(".drop-zone")
  const card = document.querySelector(".stacking-card")
  const svg = card.querySelector(".card-art")
  const rect = svg.querySelector("rect")

  const slotBox = slot.getBoundingClientRect()
  const cardBox = card.getBoundingClientRect()
  const scs = getComputedStyle(slot)
  const zcs = getComputedStyle(zone)

  // The card's design box, straight off the art, so the expected proportion
  // and corner ratio come from CardArt rather than being restated here.
  const [, , vbW, vbH] = svg.getAttribute("viewBox").split(/\s+/).map(Number)

  return {
    // Published by applyScale. `--zone-h` is the *base* height: a fanned
    // zone's live height is grown past it by JS, so the uniform-inset check
    // has to use this rather than the zone's measured height.
    cardW: num(pcs.getPropertyValue("--card-w")),
    zoneW: num(pcs.getPropertyValue("--zone-w")),
    zoneH: num(pcs.getPropertyValue("--zone-h")),
    slotW: slotBox.width,
    slotH: slotBox.height,
    cardBoxW: cardBox.width,
    slotRadius: num(scs.borderTopLeftRadius),
    zoneRadius: num(zcs.borderTopLeftRadius),
    zoneBoxW: zone.getBoundingClientRect().width,
    viewBoxW: vbW,
    viewBoxH: vbH,
    artRx: num(rect.getAttribute("rx")),
  }
}

for (const viewport of VIEWPORTS) {
  test.describe(`${viewport.label} — ${viewport.width}×${viewport.height}`, () => {
    test.use({ viewport: { width: viewport.width, height: viewport.height } })

    // One page load per viewport, then every invariant asserted softly against
    // that one measurement — a break reports all the relationships it broke,
    // the way the whole footprint is derived together.
    test("the card, slot and zone footprints hold together", async ({ page }) => {
      await page.goto("/?game=freecell&state=midgame&animate=off")
      // The opening layout is sized in a pre-paint frame, so measure only once
      // the board has settled — otherwise these read an intermediate footprint.
      await settleBoard(page)
      await expect(page.locator(".drop-zone__slot").first()).toBeAttached()

      const m = await page.evaluate(measure)

      // 4/5's shared quantity: the scaled `zoneInset`, derived from the horizontal
      // axis and then required to hold on the vertical axis and on the corners.
      const insetX = (m.zoneW - m.slotW) / 2
      const insetY = (m.zoneH - m.slotH) / 2

      expect.soft(m.slotW, "slot traces the card footprint").toBeCloseTo(m.cardW, PX_DIGITS)
      expect.soft(m.cardBoxW, "resting card matches the slot width").toBeCloseTo(m.slotW, PX_DIGITS)
      expect
        .soft(m.slotH / m.slotW, "slot keeps the 5:7 proportion")
        .toBeCloseTo(EXPECTED_ASPECT, RATIO_DIGITS)
      expect
        .soft(m.viewBoxH / m.viewBoxW, "card art viewBox keeps the 5:7 proportion")
        .toBeCloseTo(EXPECTED_ASPECT, RATIO_DIGITS)
      // Against the art's `rx` on purpose: the card's `<rect>` is inset half a unit
      // with a centred 1-unit stroke, so its *painted outer* corner radius is
      // (rx + 0.5) / 120, marginally larger than the rx / 120 the slot uses. Whether
      // the slot should trace the painted edge instead is a design question, not a
      // regression.
      expect
        .soft(m.slotRadius / m.slotW, "slot corner ratio matches the card art's rx")
        .toBeCloseTo(m.artRx / m.viewBoxW, RATIO_DIGITS)
      expect.soft(insetY, "zone inset is uniform on both axes").toBeCloseTo(insetX, PX_DIGITS)
      expect
        .soft(m.zoneBoxW, "zone width is the slot plus twice the inset")
        .toBeCloseTo(m.slotW + 2 * insetX, PX_DIGITS)
      expect
        .soft(m.zoneRadius - m.slotRadius, "zone corner is concentric with the slot's")
        .toBeCloseTo(insetX, PX_DIGITS)
    })
  })
}
