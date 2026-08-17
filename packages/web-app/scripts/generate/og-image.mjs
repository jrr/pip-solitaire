// Link-preview image generator — the *whole* board, rendered for real (issue #221).
//
// When a link to the game is pasted into Slack/Mattermost/iMessage/Discord/etc.
// the unfurler reads the Open Graph tags in index.html and shows a card with a
// preview image (`og:image`). This script renders that image.
//
// Unlike the PWA icons — a trio of `CardArt` cards fanned over the background,
// composed as SVG and rasterized (see icons.mjs) — the preview is meant
// to look like *gameplay*, so it comes from an actually-rendered game rather than
// a hand-composed SVG. It drives the same headless-Chromium + Vite-preview rig the
// screenshot report uses (see ../screenshots/render.mjs): serve the built site, point the
// browser at the deterministic mid-game FreeCell scene (`?scene=freecell&
// state=midgame`, the URL contract from AppUrl/Scenario), and frame the board.
//
// **Frame the board, all of it.** The first cut of this script cropped a band of
// "a few short stacks" derived from the rendered layout, and in an unfurl that read
// as an accident: cascades sliced off at both edges, no free cells or foundations,
// and a fifth of the height left as bare table under the fans. A preview card is
// looked at for about a second, so it has one job — *this is a game of FreeCell* —
// and that needs the recognizable silhouette: the free-cell/foundation row across
// the top and all eight cascades fanned beneath it, whole, inside the frame.
//
// So the crop is now a fixed 1.91:1 frame (`FRAME`, the shape every unfurler
// crops to) laid over the board rather than a rectangle derived from it, and the
// board is *measured* to confirm it lands inside with margin to spare. Fixed size
// keeps the output dimensions stable, so the `og:image:width`/`height` tags in
// index.html stay true; the measurement is what stops the old failure — a layout
// change that grows the board can no longer silently start clipping it, it fails
// the run with the numbers and says which knob to turn.
//
// The frame is anchored to the *top* of the shaded scene band, not centred on the
// board, because the board is top-anchored in the band itself: taking the felt from
// above the cards would mean taking the app's top bar, so the slack goes below the
// fans, where bare table looks like bare table.
//
// High-DPI: the context is created with `deviceScaleFactor: 2`, so the frame
// rasterizes at twice the CSS resolution — the same knob the screenshot report
// uses to shoot phones at their real 2×/3× density. The unfurled card then stays
// crisp on retina displays. (Yes, the existing browser infrastructure runs a
// high-DPI profile — this is that.)
//
// Output (into packages/web-app/public/, so Vite copies it into the built site
// alongside the icons, and it's committed like them):
//   og-image.png   2400×1260 — the canonical 1200×630 OG card at 2×.
//
// It's the one public/ asset the service worker is told *not* to precache (see
// `globIgnores` in vite.config.js): only unfurlers ever fetch it, so making every
// visitor download it would be half a megabyte spent on something they never see.
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
// A mid-game board is the one that reads as *play* rather than as a fresh deal:
// cards up in the free cells, a couple of foundations started, ragged cascades.
const SCENE_QUERY = "?scene=freecell&state=midgame&animate=off";

// A roomy desktop viewport. The playfield sizes its cards to fit the stage and caps
// them at a maximum, so anything from here up renders the board at that full size
// (~1140×515 CSS px) — this only has to be comfortably bigger than `FRAME`, which
// is what's actually kept.
const VIEWPORT = { width: 1400, height: 900 };
const DEVICE_SCALE_FACTOR = 2;

// Open Graph's large-card slot is 1.91:1, and 1200×630 is its canonical size — the
// one Facebook/Slack/Mattermost/Discord all state. Shot at 2× (above) that lands as
// a 2400×1260 PNG, so the card stays sharp on a retina display and still downscales
// to exactly the size every unfurler wants.
const FRAME = { width: 1200, height: 630 };

// How much bare table has to show between the board and each edge of the frame, in
// CSS px. This is the check, not a layout knob: if the rendered board ever stops
// clearing it, the run fails rather than quietly shipping clipped cards again. The
// top gets its own, smaller allowance — the board sits ~17px under the band's top
// edge by the playfield's own inset, and that gap is the app's, not ours to demand.
const MIN_MARGIN = 24;
const MIN_MARGIN_TOP = 8;

// Read the rendered board back out of the page: the bounding box of everything on
// the table — the fanned cards *and* the empty drop zones, since an empty free cell
// or foundation is part of the board's silhouette and clipping one would show — plus
// the top of the shaded scene band the frame anchors to. Runs in the page so it can
// read live layout (getBoundingClientRect), which jsdom couldn't give us.
function measureBoard() {
  const rects = Array.from(document.querySelectorAll(".stacking-card, .drop-zone")).map((el) =>
    el.getBoundingClientRect(),
  );
  if (rects.length === 0) throw new Error("no cards or drop zones rendered");
  const band = document.querySelector("#scene-box").getBoundingClientRect();
  return {
    left: Math.min(...rects.map((r) => r.left)),
    right: Math.max(...rects.map((r) => r.right)),
    top: Math.min(...rects.map((r) => r.top)),
    bottom: Math.max(...rects.map((r) => r.bottom)),
    bandTop: band.top,
  };
}

/**
 * Place `FRAME` over the measured board: centred on it horizontally, anchored to the
 * top of the scene band vertically (see the header note on why the slack goes below),
 * and clamped so the clip stays inside the viewport.
 */
function frameBoard(board) {
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const midX = (board.left + board.right) / 2;
  return {
    x: Math.round(clamp(midX - FRAME.width / 2, 0, VIEWPORT.width - FRAME.width)),
    y: Math.round(clamp(board.bandTop, 0, VIEWPORT.height - FRAME.height)),
    width: FRAME.width,
    height: FRAME.height,
  };
}

/**
 * The guard the old crop lacked: confirm the whole board is inside the frame with
 * `MIN_MARGIN` of table around it, and say which edge failed by how much if not.
 * Returns the four margins so the run can print them.
 */
function checkFits(board, clip) {
  const margins = {
    left: board.left - clip.x,
    right: clip.x + clip.width - board.right,
    top: board.top - clip.y,
    bottom: clip.y + clip.height - board.bottom,
  };
  const short = Object.entries(margins).filter(
    ([edge, m]) => m < (edge === "top" ? MIN_MARGIN_TOP : MIN_MARGIN),
  );
  if (short.length > 0) {
    const detail = short.map(([edge, m]) => `${edge} ${Math.round(m)}px`).join(", ");
    throw new Error(
      `the board doesn't fit the ${FRAME.width}×${FRAME.height} preview frame (${detail}). ` +
        `The rendered board is ${Math.round(board.right - board.left)}×${Math.round(
          board.bottom - board.top,
        )} CSS px. Either shrink it (a smaller VIEWPORT scales the cards down) or grow ` +
        `FRAME — and update og:image:width/height in index.html if you grow it.`,
    );
  }
  return margins;
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

    const board = await page.evaluate(measureBoard);
    const clip = frameBoard(board);
    const margins = checkFits(board, clip);

    fs.mkdirSync(path.dirname(outFile), { recursive: true });
    await page.screenshot({ path: outFile, clip });

    const px = (n) => Math.round(n * DEVICE_SCALE_FACTOR);
    const edges = ["top", "right", "bottom", "left"]
      .map((edge) => `${edge} ${Math.round(margins[edge])}`)
      .join(", ");
    console.log(
      `Wrote ${path.relative(process.cwd(), outFile)} — ${px(clip.width)}×${px(
        clip.height,
      )}px (${clip.width}×${clip.height} CSS @${DEVICE_SCALE_FACTOR}×), board ${Math.round(
        board.right - board.left,
      )}×${Math.round(board.bottom - board.top)} with margins ${edges}`,
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
