// Verify the landscape control rail clears the shaded scene band in all four
// chrome regimes: `data-cutout` left/right × `data-notch-wings` on/off.
//
// Why this can't be a unit test. The rules under test live in
// `@media (orientation: landscape) and (max-height: 500px)` blocks, and jsdom only
// evaluates a media rule whose media list contains the literal token `screen`
// (see jsdom's living/helpers/style-rules.js) — ours don't, so jsdom skips the
// blocks wholesale and every regime reads back the base `#top-bar` margins. The
// cascade question is therefore only answerable in a real engine, which puts this
// in the same bucket as `verify-win`: a headless-Chromium check driven by a mise
// task rather than part of `mise run test`.
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
// script tests the CSS contract *given* the attributes; the detection that produces
// them is unit-tested in CutoutSide_test.res.
import { chromium } from "playwright";
import { preview } from "vite";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const webAppRoot = path.resolve(here, "..");

// The same executable resolution `verify-win`/`screenshots` use: the environment's
// pre-installed Chromium when there is one, else whatever `playwright install` got.
function resolveExecutablePath() {
  const explicit = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
  if (explicit && fs.existsSync(explicit)) return explicit;
  const preinstalled = "/opt/pw-browsers/chromium";
  if (fs.existsSync(preinstalled)) return preinstalled;
  return undefined;
}

// A landscape phone: wide, and under the 500px `max-height` that keys the rail
// regime. Chromium reports every `env(safe-area-inset-*)` as 0, which is fine —
// the regression is in an *unconditional* margin, so it shows up at zero insets
// too. Real insets only change how far the rail sits from the screen edge, not
// whether it overlaps the band.
const VIEWPORT = { width: 844, height: 390 };

// 0.5rem at the root font size — the gap the rail is meant to leave before the
// band in the two regimes that place one.
const EXPECTED_GAP = 8;
const TOLERANCE = 0.5;

const REGIMES = [
  { cutout: "left", wings: "on" },
  { cutout: "left", wings: "off" },
  { cutout: "right", wings: "on" },
  { cutout: "right", wings: "off" },
];

async function main() {
  const server = await preview({
    root: webAppRoot,
    preview: { port: 0, strictPort: false, open: false },
    logLevel: "warn",
  });
  const base = server.resolvedUrls.local[0].replace(/\/$/, "");
  // A dealt board, animation off, so the scene band and rail are settled and the
  // measurement isn't racing the opening deal.
  const target = `${base}/?scene=freecell&state=midgame&animate=off`;

  const browser = await chromium.launch({ executablePath: resolveExecutablePath() });
  const failures = [];
  try {
    const context = await browser.newContext({ viewport: VIEWPORT });
    const page = await context.newPage();
    await page.goto(target, { waitUntil: "load" });
    await page.waitForSelector(".drop-rows .drop-zone", { state: "attached", timeout: 15000 });

    for (const { cutout, wings } of REGIMES) {
      const measured = await page.evaluate(
        ([cutoutSide, wingsMode]) => {
          const html = document.documentElement;
          html.setAttribute("data-cutout", cutoutSide);
          if (wingsMode === "off") html.setAttribute("data-notch-wings", "off");
          else html.removeAttribute("data-notch-wings");

          const bar = document.getElementById("top-bar").getBoundingClientRect();
          const band = document.getElementById("scene-box").getBoundingClientRect();
          // The rail is on whichever edge the cutout is, and the band on the other,
          // so the gap between them is measured from opposite faces per side.
          const gap = cutoutSide === "right" ? bar.left - band.right : band.left - bar.right;
          return {
            gap,
            barLeft: bar.left,
            barRight: bar.right,
            bandLeft: band.left,
            bandRight: band.right,
            marginLeft: getComputedStyle(document.getElementById("top-bar")).marginLeft,
            marginRight: getComputedStyle(document.getElementById("top-bar")).marginRight,
          };
        },
        [cutout, wings],
      );

      const label = `cutout=${cutout} wings=${wings}`;
      const ok = Math.abs(measured.gap - EXPECTED_GAP) <= TOLERANCE;
      console.log(
        `${ok ? "ok  " : "FAIL"} ${label.padEnd(26)} ` +
          `gap=${measured.gap.toFixed(1)}px (expected ${EXPECTED_GAP}) ` +
          `rail=[${measured.barLeft.toFixed(1)}, ${measured.barRight.toFixed(1)}] ` +
          `band=[${measured.bandLeft.toFixed(1)}, ${measured.bandRight.toFixed(1)}] ` +
          `margin L=${measured.marginLeft} R=${measured.marginRight}`,
      );
      if (!ok) {
        failures.push(
          `${label}: rail→band gap ${measured.gap.toFixed(1)}px, expected ${EXPECTED_GAP}px` +
            (measured.gap < 0 ? " — the rail overlaps the shaded band" : ""),
        );
      }
    }
  } finally {
    await browser.close();
    server.httpServer.close();
  }

  if (failures.length > 0) {
    console.error(`\nverify-rail: ${failures.length} of ${REGIMES.length} regimes wrong:`);
    for (const f of failures) console.error(`  - ${f}`);
    process.exit(1);
  }
  console.log(`\nverify-rail: all ${REGIMES.length} regimes clear the band by ${EXPECTED_GAP}px.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
