// Render the game at a spread of emulated devices into a self-contained
// screenshot report. CI publishes it to GitHub Pages via the deploy workflows: on
// `main` a stamped, retained history (deploy-pages.yml stages it with
// scripts/screenshots/stage.mjs and pushes via peaceiris), and on a PR a
// latest-only preview cleaned up on close (pr-preview.yml deploys this output
// directly via pr-preview-action). It shoots a spread of FreeCell scenes on a handful
// of emulated phones/tablets in both portrait and landscape, each at the device's
// *physical* pixel resolution (its real devicePixelRatio), so a change that breaks
// the board on some screen — or type that's too small to read — is visible at a
// glance in the PR's report.
//
// The devices come from Playwright's `devices` registry (lib/devices.mjs), so a
// phone shot is a phone: meta viewport honoured, touch events on, and
// `(pointer: coarse)` / `(hover: none)` resolving the way they do on the real
// thing. Before #244 this list was hand-rolled sizes, which meant the report was
// phone-shaped *desktop* Chromium and any touch-only CSS was invisible in it.
//
// How it works, end to end:
//   1. Serve the already-built web app (packages/web-app/dist) with Vite's own
//      preview server, so the report captures exactly what ships — the bundled,
//      based, service-worker'd site — not a dev build.
//   2. Drive a headless Chromium (Playwright) to each captured scene's URL — e.g.
//      `?scene=freecell&state=midgame` — the URL contract that forces the board
//      straight into a fixed position with no interaction (see src/AppUrl.res /
//      core's Scenario.res).
//   3. For each scene × device size, shoot portrait and landscape, then write an
//      index.html contact sheet next to the PNGs.
//
// Run it with `mise run screenshots` (which builds the app first). Serving the
// bundle and finding a browser are both scripts/lib/preview-app.mjs's job, shared
// with generate/og-image.mjs and the browser test suite: it launches the
// environment's pre-installed Chromium when present, otherwise the one
// `playwright install chromium` fetched — so this works both in this sandbox and
// on a clean CI runner.

import fs from "node:fs";
import path from "node:path";
import { assertBundled, launchChromium, startPreview, webAppRoot } from "../lib/preview-app.mjs";
import { contextOptions, describe, reportDevices } from "../lib/devices.mjs";

const outDir = path.join(webAppRoot, "screenshots");

// The scenes (board positions) the report captures, each via the app's URL
// contract so the shots are deterministic and need no interaction. Kept in one
// place so it's obvious what's being shot, and easy to add another scenario later.
//   - Dealt — a freshly dealt FreeCell board at rest, pinned to deal #1 (`seed=1`)
//     and shot with the fly-in suppressed (`animate=off`) so it captures the settled
//     opening layout rather than a frame mid-deal (see AppUrl's seed/animate knobs).
//   - Mid-game — a representative in-progress FreeCell layout.
//   - Finish — the finishable endgame (#132), shot to show the "Finish" button.
//   - Card raster — not a board at all: the sprite-fidelity sheet (#225), all 52
//     of the bitmaps the victory animation will blit. It's here because the failure
//     mode it guards against — a rasterization that loses the card's fonts — is
//     invisible to any assertion and obvious to an eye, which is exactly what a
//     per-PR report is for. It's shot per *device* rather than only on the desktop
//     because that failure is resolution-dependent: a sprite built at the wrong
//     device-pixel ratio reads as slightly soft, and only the retina shots show it.
//     The scene draws one rendering at a time (`?raster=live|svg|canvas`); the plain
//     query shoots its default, the sprite path that ships.
//   - Menu — the slide-over menu open on its root screen (#324), the one piece of
//     chrome the board shots never show. It's the panel that has to fit a narrow
//     phone and a notch's safe area alike, so how it lands per device is worth an
//     eye. The nested Settings/Debug screens are deliberately not shot: the root
//     screen is what the report is for.
//
// `ready` is the selector that means "this scene has settled"; scenes that draw the
// board share the default. `open` is the one escape hatch from the URL contract: a
// scene that can only be reached by touching the app (the menu is chrome model
// state, with no query parameter behind it) drives itself here, after the board has
// settled and before the shot.
const BOARD_READY = ".stacking-card";
const scenes = [
  { name: "Dealt", query: "?scene=freecell&seed=1&animate=off" },
  { name: "Mid-game", query: "?scene=freecell&state=midgame" },
  { name: "Finish", query: "?scene=freecell&state=finish" },
  {
    name: "Menu",
    query: "?scene=freecell&seed=1&animate=off",
    note: "menu opened",
    // The same click a player makes, and the same one the browser suite makes. The
    // button's accessible name grows a suffix when an update is waiting ("Open menu
    // — update available"), hence the prefix match rather than an exact one.
    open: async (page) => {
      await page.getByRole("button", { name: /^Open menu/ }).click();
      await page.waitForSelector("#menu-overlay .menu-panel", {
        state: "visible",
        timeout: 15000,
      });
    },
  },
  {
    name: "Card raster",
    query: "?scene=raster",
    // The scene sets this once all 52 bitmaps have decoded; there's nothing else
    // to wait on, since the decodes are async and start off-frame.
    ready: '.raster-scene[data-raster="ready"]',
  },
];

// The spread of devices, and the emulation profile for each orientation of each
// — see lib/devices.mjs, which builds them from Playwright's registry.
const devices = reportDevices;

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

function reportHtml(shots) {
  const deviceCards = (scene) =>
    devices
      .map((device) => {
        const cells = Object.keys(device.orientations)
          .map((orientation) => {
            const shot = shots.find(
              (s) =>
                s.scene === scene.name &&
                s.device === device.name &&
                s.orientation === orientation,
            );
            if (!shot) return "";
            return `
            <figure>
              <figcaption>${orientation} · ${shot.width}×${shot.height} CSS · ${shot.pxWidth}×${shot.pxHeight}px</figcaption>
              <a href="${shot.file}"><img src="${shot.file}" alt="${scene.name} — ${device.name} ${orientation}" loading="lazy" /></a>
            </figure>`;
          })
          .join("");
        // The heading describes the emulated device itself, so it reads off the
        // portrait profile (the desktop, landscape-only, reads off its own) —
        // including whether the context has touch, which is now the difference
        // between the phone/tablet shots and the desktop one.
        const primary = describe(
          device.orientations.portrait ?? device.orientations.landscape,
        );
        return `
        <section class="device">
          <h3>${device.name} <span>${primary.width}×${primary.height} · @${primary.dpr}× · ${primary.input}</span></h3>
          <div class="shots">${cells}</div>
        </section>`;
      })
      .join("");

  const scenesHtml = scenes
    .map(
      (scene) => `
      <section class="scene">
        <h2>${scene.name} <span><code>${scene.query}</code>${scene.note ? ` · ${scene.note}` : ""}</span></h2>
        ${deviceCards(scene)}
      </section>`,
    )
    .join("");

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Pip — screenshot report</title>
  <style>
    :root { color-scheme: dark; }
    body {
      margin: 0; padding: 2rem;
      font-family: "Libre Franklin", sans-serif;
      background: radial-gradient(130% 120% at 50% 0%, #13233b 0%, #0b1220 60%);
      color: #e2e8f0;
    }
    header { max-width: 70rem; margin: 0 auto 2rem; }
    h1 { margin: 0 0 0.25rem; font-size: 1.6rem; }
    header p { margin: 0; color: #94a3b8; font-size: 0.95rem; }
    header code { color: #86efac; }
    .scene { max-width: 70rem; margin: 0 auto 3.5rem; }
    .scene > h2 {
      font-size: 1.35rem; margin: 0 0 1rem;
      border-bottom: 1px solid #2d4066; padding-bottom: 0.5rem;
    }
    .scene > h2 span { color: #94a3b8; font-weight: 400; font-size: 0.9rem; }
    .scene > h2 code { color: #86efac; }
    .device { margin: 0 0 2rem; }
    .device h3 {
      font-size: 1.05rem; margin: 0 0 0.75rem;
      border-bottom: 1px solid #22304a; padding-bottom: 0.4rem;
    }
    .device h3 span { color: #94a3b8; font-weight: 400; font-size: 0.85rem; }
    .shots { display: flex; flex-wrap: wrap; gap: 1.5rem; align-items: flex-start; }
    figure { margin: 0; }
    figcaption { color: #94a3b8; font-size: 0.8rem; margin-bottom: 0.4rem; }
    img {
      display: block; max-width: 100%; height: auto;
      border: 1px solid #22304a; border-radius: 8px;
      box-shadow: 0 6px 18px rgba(0, 0, 0, 0.4);
    }
    .shots > figure:last-child img { max-height: 430px; width: auto; }
  </style>
</head>
<body>
  <header>
    <h1>Pip — screenshot report</h1>
    <p>FreeCell scenes across emulated devices, portrait and landscape.</p>
  </header>
  ${scenesHtml}
</body>
</html>
`;
}

async function main() {
  assertBundled("screenshots");

  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });

  const server = await startPreview();
  const base = server.base;

  const browser = await launchChromium();
  const shots = [];
  try {
    for (const scene of scenes) {
      const target = `${base}/${scene.query}`;
      for (const device of devices) {
        // Each orientation carries its own emulation profile — the registry has a
        // separate landscape descriptor per device, rotated *and* re-fitted around
        // the browser chrome, so there's no width/height swapping to do here.
        for (const [orientation, descriptor] of Object.entries(device.orientations)) {
          const { width, height, pxWidth, pxHeight, input } = describe(descriptor);

          const context = await browser.newContext(contextOptions(descriptor));
          const page = await context.newPage();
          await page.goto(target, { waitUntil: "load" });
          // The board deals its cards on the first animation frame and settles with
          // a short CSS transition; wait for the scene's own "settled" selector, then
          // a beat for the fan to land, so the shot captures the resting layout.
          await page.waitForSelector(scene.ready ?? BOARD_READY, {
            state: "visible",
            timeout: 15000,
          });
          await page.waitForTimeout(600);

          // Scenes that aren't reachable from the URL alone drive themselves the
          // rest of the way, once the board underneath them has settled.
          if (scene.open) await scene.open(page);

          // The PNG comes out at the device's physical resolution (CSS size × dpr,
          // both from the descriptor).
          const file = `${slug(scene.name)}-${slug(device.name)}-${orientation}.png`;
          await page.screenshot({ path: path.join(outDir, file) });
          shots.push({
            scene: scene.name,
            device: device.name,
            orientation,
            width,
            height,
            pxWidth,
            pxHeight,
            file,
          });
          console.log(
            `  shot ${scene.name} · ${device.name} ${orientation} (${width}×${height} CSS → ${pxWidth}×${pxHeight}px, ${input})`,
          );
          await context.close();
        }
      }
    }
  } finally {
    await browser.close();
    await server.close();
  }

  fs.writeFileSync(path.join(outDir, "index.html"), reportHtml(shots));
  console.log(`\nWrote ${shots.length} screenshots + report to ${path.relative(process.cwd(), outDir)}/index.html`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
