// Link-preview image generator — a crop of the *real* game.
//
// When a link to the game is pasted into Slack/iMessage/Twitter/etc. the
// unfurler reads the Open Graph tags in index.html and shows a card with a
// preview image (`og:image`). This script renders that image.
//
// Unlike the PWA icons — a trio of `CardArt` cards fanned over the background,
// composed as SVG and rasterized (see icons.mjs) — the preview is meant
// to look like *gameplay*, so it comes from an actually-rendered game rather than
// a hand-composed SVG. It drives the same headless-Chromium + Vite-preview rig the
// screenshot report uses (see ../screenshots/render.mjs): serve the built site, point the
// browser at the deterministic mid-game FreeCell scene (`?game=freecell&
// state=midgame`, the URL contract from AppUrl/Scenario), and crop a landscape
// band of a few cascades — the "few short stacks" the issue asks for.
//
// High-DPI: the context is created with `deviceScaleFactor: 2`, so the crop
// rasterizes at twice the CSS resolution — the same knob the screenshot report
// uses to shoot phones at their real 2×/3× density. The unfurled card then stays
// crisp on retina displays. (Yes, the existing browser infrastructure runs a
// high-DPI profile — this is that.)
//
// Output (into packages/web-app/public/, so Vite copies it into the built site
// alongside the icons, and it's committed like them):
//   og-image.png   ~1200×630, the 1.91:1 landscape most unfurlers crop to.
//
// It lives in generate/ rather than screenshots/ because purpose beats mechanism:
// it writes a committed asset into public/, on the same lifecycle as the icons and
// fonts, and only happens to reach it through a browser.
//
// Run it with `mise run og-image` (which bundles the app first). Serving the
// bundle and finding a browser come from scripts/lib/preview-app.mjs, shared with
// the screenshot renderer and the browser test suite: the environment's pre-installed
// Chromium when present, otherwise Playwright's own — so it works in this sandbox
// and on a clean CI runner (after `mise run playwright-install`).

import fs from "node:fs";
import path from "node:path";
import { assertBundled, launchChromium, startPreview, webAppRoot } from "../lib/preview-app.mjs";

const outFile = path.join(webAppRoot, "public", "og-image.png");

// The deterministic scene to shoot: the mid-game FreeCell snapshot, dealt with the
// fly-in suppressed so we capture the settled board (see AppUrl's `state`/`animate`
// knobs and Scenario.freecellMidgame). Same contract the screenshot report drives.
const SCENE_QUERY = "?game=freecell&state=midgame&animate=off";

// A tall portrait viewport so the cascades render large and their rank/pip type is
// legible in the crop; the deviceScaleFactor doubles the pixels on top of that. The
// crop itself is derived from the rendered layout below, so this only sets how big
// the cards are, not what's framed.
const VIEWPORT = { width: 900, height: 1400 };
const DEVICE_SCALE_FACTOR = 2;

// Open Graph's large-card slot is 1.91:1 (1200×630 is the canonical size). We frame
// a horizontal band of the middle cascades at that ratio and let the game's own
// dark background fill any margin, so the card reads as a slice of a real board.
const TARGET_RATIO = 1200 / 630;

// From the rendered board, compute the pixel rectangle (CSS px) to crop: a
// TARGET_RATIO-wide band centred on the cascades, tall enough to hold the deepest
// fan plus a little breathing room, and wide enough for that ratio — clamped to
// the viewport so the clip is always valid. Runs in the page so it can read live
// layout (getBoundingClientRect), which jsdom couldn't give us.
function measureCrop(ratio) {
  return ([targetRatio]) => {
    const cards = Array.from(document.querySelectorAll(".stacking-card"));
    if (cards.length === 0) throw new Error("no cards rendered");
    const rects = cards.map((c) => c.getBoundingClientRect());

    // Split the board into its two rows by vertical gap: the foundations/free-cells
    // sit in a top band, the cascades below. The largest gap between consecutive
    // card tops is the divide, so cascade cards are everything below it.
    const tops = rects.map((r) => r.top).sort((a, b) => a - b);
    let splitAt = tops[0];
    let widestGap = 0;
    for (let i = 1; i < tops.length; i++) {
      const gap = tops[i] - tops[i - 1];
      if (gap > widestGap) {
        widestGap = gap;
        splitAt = tops[i];
      }
    }
    const cascade = rects.filter((r) => r.top >= splitAt - 1);

    // The cascades' bounding band: full horizontal span, from the top of the row to
    // the bottom of the deepest fan.
    const left = Math.min(...cascade.map((r) => r.left));
    const right = Math.max(...cascade.map((r) => r.right));
    const top = Math.min(...cascade.map((r) => r.top));
    const bottom = Math.max(...cascade.map((r) => r.bottom));

    // A little padding around the fans so cards aren't flush to the edge.
    const pad = (bottom - top) * 0.06;
    let cropTop = Math.max(0, top - pad);
    let cropBottom = Math.min(window.innerHeight, bottom + pad);
    let cropHeight = cropBottom - cropTop;

    // Width follows the target ratio, centred on the cascades' midline. If that
    // overflows the viewport, fall back to the full width and derive the height
    // from the ratio instead, re-centring vertically on the band.
    const midX = (left + right) / 2;
    let cropWidth = cropHeight * targetRatio;
    let cropLeft = midX - cropWidth / 2;
    if (cropWidth > window.innerWidth) {
      cropWidth = window.innerWidth;
      cropLeft = 0;
      cropHeight = cropWidth / targetRatio;
      const midY = (cropTop + cropBottom) / 2;
      cropTop = Math.max(0, midY - cropHeight / 2);
    }
    if (cropLeft < 0) cropLeft = 0;
    if (cropLeft + cropWidth > window.innerWidth) cropLeft = window.innerWidth - cropWidth;

    return {
      x: Math.round(cropLeft),
      y: Math.round(cropTop),
      width: Math.round(cropWidth),
      height: Math.round(cropHeight),
    };
  };
}

async function main() {
  assertBundled("og-image");

  const server = await startPreview();
  const base = server.base;

  const browser = await launchChromium();
  try {
    const context = await browser.newContext({
      viewport: VIEWPORT,
      deviceScaleFactor: DEVICE_SCALE_FACTOR,
    });
    const page = await context.newPage();
    await page.goto(`${base}/${SCENE_QUERY}`, { waitUntil: "load" });
    // The board deals on the first animation frame and settles with a short CSS
    // transition; wait for a card, then a beat for the fan to land.
    await page.waitForSelector(".stacking-card", { state: "visible", timeout: 15000 });
    await page.waitForTimeout(600);

    const clip = await page.evaluate(measureCrop(TARGET_RATIO), [TARGET_RATIO]);
    fs.mkdirSync(path.dirname(outFile), { recursive: true });
    await page.screenshot({ path: outFile, clip });

    const px = (n) => Math.round(n * DEVICE_SCALE_FACTOR);
    console.log(
      `Wrote ${path.relative(process.cwd(), outFile)} — ${clip.width}×${clip.height} CSS → ${px(
        clip.width,
      )}×${px(clip.height)}px @${DEVICE_SCALE_FACTOR}×`,
    );
    await context.close();
  } finally {
    await browser.close();
    await server.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
