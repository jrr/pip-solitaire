// Render the game at a spread of device resolutions into a self-contained
// screenshot report. CI publishes it to GitHub Pages via the deploy workflows: on
// `main` a stamped, retained history (deploy-pages.yml stages it with
// scripts/stage-screenshots.mjs and pushes via peaceiris), and on a PR a
// latest-only preview cleaned up on close (pr-preview.yml deploys this output
// directly via pr-preview-action). It shoots a spread of FreeCell scenes at a handful
// of phone/tablet sizes in both portrait and landscape, each at the device's
// *physical* pixel resolution (its real devicePixelRatio), so a change that breaks
// the board on some screen — or type that's too small to read — is visible at a
// glance in the PR's report.
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
// Run it with `mise run screenshots` (which builds the app first). Browser
// resolution: it launches the environment's pre-installed Chromium when present
// (PLAYWRIGHT_CHROMIUM_EXECUTABLE or /opt/pw-browsers/chromium), otherwise the
// one `playwright install chromium` fetched — so it works both in this sandbox
// and on a clean CI runner.

import { chromium } from "playwright";
import { preview } from "vite";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const webAppRoot = path.resolve(here, "..");
const outDir = path.join(webAppRoot, "screenshots");

// The scenes (board positions) the report captures, each via the app's URL
// contract so the shots are deterministic and need no interaction. Kept in one
// place so it's obvious what's being shot, and easy to add another scenario later.
//   - Dealt — a freshly dealt FreeCell board at rest, pinned to deal #1 (`seed=1`)
//     and shot with the fly-in suppressed (`animate=off`) so it captures the settled
//     opening layout rather than a frame mid-deal (see AppUrl's seed/animate knobs).
//   - Mid-game — a representative in-progress FreeCell layout.
//   - Finish — the finishable endgame (#132), shot to show the "Finish" button.
const scenes = [
  { name: "Dealt", query: "?scene=freecell&seed=1&animate=off" },
  { name: "Mid-game", query: "?scene=freecell&state=midgame" },
  { name: "Finish", query: "?scene=freecell&state=finish" },
];

// A representative spread of devices: CSS size plus each one's real
// devicePixelRatio, so the shots rasterize at the device's *physical* pixel
// resolution and you can judge legibility, not just layout. A small phone and a
// tablet — each shot both ways up — plus a wide desktop, shot landscape only (a
// portrait 1080-wide desktop isn't a real target, and the wide layout is the
// point: past ~1064px the card row caps its width and the stage grows side
// margins instead of gaps, see TableScene's `--rows-max-w`). Each device lists
// the `orientations` it's shot in; the portrait/landscape dimensions are the
// device's smaller/larger CSS side either way, so the size can be given in either
// order. (iPhone mini and iPhone SE share the same 375-wide CSS size, so the mini
// stands in for the SE here — same width, taller, and a 3× display.)
const both = ["portrait", "landscape"];
const devices = [
  { name: "iPhone 13 mini", width: 375, height: 812, dpr: 3, orientations: both },
  { name: "iPad mini", width: 768, height: 1024, dpr: 2, orientations: both },
  { name: "Desktop", width: 1920, height: 1080, dpr: 1, orientations: ["landscape"] },
];

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

// The pre-installed Chromium in managed environments is a specific revision that
// may not match the playwright package's default; launching it by path sidesteps
// the version check (see the env's browser notes). On a clean CI runner neither
// exists and we fall through to Playwright's own resolution.
function resolveExecutablePath() {
  const explicit = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
  if (explicit && fs.existsSync(explicit)) return explicit;
  const preinstalled = "/opt/pw-browsers/chromium";
  if (fs.existsSync(preinstalled)) return preinstalled;
  return undefined;
}

function reportHtml(shots) {
  const deviceCards = (scene) =>
    devices
      .map((device) => {
        const cells = device.orientations
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
        return `
        <section class="device">
          <h3>${device.name} <span>${device.width}×${device.height} · @${device.dpr}×</span></h3>
          <div class="shots">${cells}</div>
        </section>`;
      })
      .join("");

  const scenesHtml = scenes
    .map(
      (scene) => `
      <section class="scene">
        <h2>${scene.name} <span><code>${scene.query}</code></span></h2>
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
    <p>FreeCell scenes across device sizes, portrait and landscape.</p>
  </header>
  ${scenesHtml}
</body>
</html>
`;
}

async function main() {
  if (!fs.existsSync(path.join(webAppRoot, "dist", "index.html"))) {
    throw new Error(
      "packages/web-app/dist is not built — run `mise run bundle` first (the screenshots task depends on it).",
    );
  }

  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });

  const server = await preview({
    root: webAppRoot,
    preview: { port: 0, strictPort: false, open: false },
    logLevel: "warn",
  });
  const base = server.resolvedUrls.local[0].replace(/\/$/, "");

  const browser = await chromium.launch({ executablePath: resolveExecutablePath() });
  const shots = [];
  try {
    for (const scene of scenes) {
      const target = `${base}/${scene.query}`;
      for (const device of devices) {
        // Portrait is the device's narrower side up, landscape the wider — derived
        // from min/max so a device's size can be given in either order (a desktop
        // reads naturally as its native 1920×1080).
        const portraitW = Math.min(device.width, device.height);
        const portraitH = Math.max(device.width, device.height);
        for (const orientation of device.orientations) {
          const [width, height] =
            orientation === "portrait"
              ? [portraitW, portraitH]
              : [portraitH, portraitW];

          const context = await browser.newContext({
            viewport: { width, height },
            deviceScaleFactor: device.dpr,
          });
          const page = await context.newPage();
          await page.goto(target, { waitUntil: "load" });
          // The board deals its cards on the first animation frame and settles with
          // a short CSS transition; wait for a card to exist, then a beat for the
          // fan to land, so the shot captures the resting layout.
          await page.waitForSelector(".stacking-card", { state: "visible", timeout: 15000 });
          await page.waitForTimeout(600);

          // The PNG comes out at the device's physical resolution (CSS size × dpr).
          const pxWidth = Math.round(width * device.dpr);
          const pxHeight = Math.round(height * device.dpr);
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
            `  shot ${scene.name} · ${device.name} ${orientation} (${width}×${height} CSS → ${pxWidth}×${pxHeight}px)`,
          );
          await context.close();
        }
      }
    }
  } finally {
    await browser.close();
    await server.httpServer.close();
  }

  fs.writeFileSync(path.join(outDir, "index.html"), reportHtml(shots));
  console.log(`\nWrote ${shots.length} screenshots + report to ${path.relative(process.cwd(), outDir)}/index.html`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
