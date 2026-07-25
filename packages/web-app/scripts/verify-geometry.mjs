// Pin the card-table geometry invariants the stylesheet and TableScene both claim.
//
// Card, zone and empty-slot footprints are produced jointly: TableScene measures
// the stage, picks a `scale`, and publishes `--card-w` / `--zone-w` / `--zone-h`
// (see `applyScale`); the CSS then re-derives the rest from those with ratio
// literals — `calc(var(--card-w) * 1.4)` for the slot's height, `* 0.1` for its
// corner, `* 0.15` for the zone's. Those literals restate facts that already exist
// in ReScript (`cardH / cardW`, `CardArt`'s `rx` over its viewBox width, and
// `zoneInset`), so the two halves can drift with nothing to catch it: the numbers
// are all plausible, and a mismatch shows up only as slightly non-concentric
// corners or a dashed slot that no longer traces the card.
//
// So rather than assert the constants, this measures the *rendered* geometry and
// checks the relationships the comments promise:
//
//   1. the empty-pile slot traces the card footprint exactly
//        (`index.html`: "A resting card ... covers it pixel-for-pixel")
//   2. both keep the 5:7 playing-card proportion
//        (`CardArt`: "A 120x168 viewBox keeps the familiar 5:7 ratio")
//   3. the slot's corner radius matches the card art's own corner
//        (`index.html`: "the card's ... 10%-of-width corner radius (the SVG
//         face's rx=12/120)")
//   4. the zone box sits a *uniform* inset outside the slot on all four sides
//        (`TableScene`: "makes the highlight frame sit an equal distance outside
//         the resting card all the way round")
//   5. the zone's corner is that same inset outside the slot's, so the two
//      rounded corners share a centre
//        (`index.html`: "the frame's radius is the slot's radius plus that inset")
//
// Everything here is read back from the live layout, so the checks hold whichever
// side of the JS/CSS seam each number is sourced from. That is the point: they are
// meant to stay green across a refactor that moves the derivation from CSS ratio
// literals into published custom properties.
//
// Note on (3): the card's `<rect>` is inset 1 unit with a centred 2-unit stroke, so
// its *painted outer* corner radius is (rx + 1) / 120, marginally larger than the
// rx / 120 the slot uses. This checks against `rx` — i.e. today's behaviour — on
// purpose; whether the slot should instead trace the painted edge is a separate
// design question, not a regression.
//
// Runs in a real engine because it needs the cascade, `calc()` resolution and real
// layout; jsdom has none of those (see `verify-rail` for the same reasoning).
import { chromium } from "playwright";
import { preview } from "vite";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const webAppRoot = path.resolve(here, "..");

function resolveExecutablePath() {
  const explicit = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
  if (explicit && fs.existsSync(explicit)) return explicit;
  const preinstalled = "/opt/pw-browsers/chromium";
  if (fs.existsSync(preinstalled)) return preinstalled;
  return undefined;
}

// The playing-card proportion the whole design is built on (5:7).
const EXPECTED_ASPECT = 7 / 5;

// Layout is snapped to 1/64px (0.015625) in Chromium, so comparisons of measured
// rects need a little room; ratios derived from them need proportionally less.
const PX_TOLERANCE = 0.1;
const RATIO_TOLERANCE = 0.002;

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
];

async function main() {
  const server = await preview({
    root: webAppRoot,
    preview: { port: 0, strictPort: false, open: false },
    logLevel: "warn",
  });
  const base = server.resolvedUrls.local[0].replace(/\/$/, "");
  const target = `${base}/?scene=freecell&state=midgame&animate=off`;

  const browser = await chromium.launch({ executablePath: resolveExecutablePath() });
  const failures = [];
  try {
    for (const viewport of VIEWPORTS) {
      const context = await browser.newContext({
        viewport: { width: viewport.width, height: viewport.height },
      });
      const page = await context.newPage();
      await page.goto(target, { waitUntil: "load" });
      await page.waitForSelector(".stacking-card", { state: "attached", timeout: 15000 });
      // The opening layout is sized in a pre-paint frame; give it a beat to settle
      // so the measurements are of the final footprint, not an intermediate one.
      await page.waitForTimeout(400);

      const m = await page.evaluate(() => {
        const num = (s) => parseFloat(s);
        const playfield = document.querySelector(".stacking-playfield");
        const pcs = getComputedStyle(playfield);
        const slot = document.querySelector(".drop-zone__slot");
        const zone = slot.closest(".drop-zone");
        const card = document.querySelector(".stacking-card");
        const svg = card.querySelector(".card-art");
        const rect = svg.querySelector("rect");

        const slotBox = slot.getBoundingClientRect();
        const cardBox = card.getBoundingClientRect();
        const scs = getComputedStyle(slot);
        const zcs = getComputedStyle(zone);

        // The card's design box, straight off the art, so the expected proportion
        // and corner ratio come from CardArt rather than being restated here.
        const [, , vbW, vbH] = svg.getAttribute("viewBox").split(/\s+/).map(Number);

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
        };
      });

      // 4/5's shared quantity: the scaled `zoneInset`, derived from the horizontal
      // axis and then required to hold on the vertical axis and on the corners.
      const insetX = (m.zoneW - m.slotW) / 2;
      const insetY = (m.zoneH - m.slotH) / 2;

      const checks = [
        {
          name: "slot traces the card footprint",
          got: m.slotW,
          want: m.cardW,
          tol: PX_TOLERANCE,
          unit: "px",
        },
        {
          name: "resting card matches the slot width",
          got: m.cardBoxW,
          want: m.slotW,
          tol: PX_TOLERANCE,
          unit: "px",
        },
        {
          name: "slot keeps the 5:7 proportion",
          got: m.slotH / m.slotW,
          want: EXPECTED_ASPECT,
          tol: RATIO_TOLERANCE,
          unit: "",
        },
        {
          name: "card art viewBox keeps the 5:7 proportion",
          got: m.viewBoxH / m.viewBoxW,
          want: EXPECTED_ASPECT,
          tol: RATIO_TOLERANCE,
          unit: "",
        },
        {
          name: "slot corner ratio matches the card art's rx",
          got: m.slotRadius / m.slotW,
          want: m.artRx / m.viewBoxW,
          tol: RATIO_TOLERANCE,
          unit: "",
        },
        {
          name: "zone inset is uniform on both axes",
          got: insetY,
          want: insetX,
          tol: PX_TOLERANCE,
          unit: "px",
        },
        {
          name: "zone width is the slot plus twice the inset",
          got: m.zoneBoxW,
          want: m.slotW + 2 * insetX,
          tol: PX_TOLERANCE,
          unit: "px",
        },
        {
          name: "zone corner is concentric with the slot's",
          got: m.zoneRadius - m.slotRadius,
          want: insetX,
          tol: PX_TOLERANCE,
          unit: "px",
        },
      ];

      console.log(
        `\n${viewport.label} — ${viewport.width}x${viewport.height}  ` +
          `--card-w=${m.cardW}px inset=${insetX.toFixed(3)}px`,
      );
      for (const c of checks) {
        const ok = Math.abs(c.got - c.want) <= c.tol;
        const fmt = (v) => (c.unit === "px" ? `${v.toFixed(3)}px` : v.toFixed(5));
        console.log(`  ${ok ? "ok  " : "FAIL"} ${c.name.padEnd(46)} ${fmt(c.got)} vs ${fmt(c.want)}`);
        if (!ok) {
          failures.push(
            `${viewport.width}x${viewport.height} — ${c.name}: got ${fmt(c.got)}, expected ${fmt(c.want)}`,
          );
        }
      }
      await context.close();
    }
  } finally {
    await browser.close();
    server.httpServer.close();
  }

  if (failures.length > 0) {
    console.error(`\nverify-geometry: ${failures.length} invariant(s) broken:`);
    for (const f of failures) console.error(`  - ${f}`);
    process.exit(1);
  }
  console.log(`\nverify-geometry: all invariants hold at ${VIEWPORTS.length} viewports.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
