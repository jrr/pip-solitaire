// Headless browser smoke test for the built web-app.
//
// Serves the production build (packages/web-app/dist) with Vite's own preview
// server, loads it in headless Chromium via Playwright, and fails loudly if the
// page throws, logs a console error, or never renders the app shell. This is
// the automatable version of the "built site renders in Chromium with no
// console errors" check that used to be done by hand — driven through a mise
// task so it stays inside the agent's `mise run` allowlist (see CLAUDE.md).
//
// Prerequisites (both handled by `mise run browser-check`):
//   - the site is bundled first (`dist/` exists)              -> task `depends`
//   - a Chromium binary is installed for Playwright           -> `browser-install`
//
// Usage:
//   node scripts/browser-check.mjs [--screenshot <path>] [--timeout <ms>]
//
// Exit code is 0 on a clean render, non-zero otherwise, so CI and the task
// runner treat a broken page as a failing build.

import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";
import { preview } from "vite";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const distDir = resolve(root, "dist");

// --- args -------------------------------------------------------------------
const argv = process.argv.slice(2);
function optionValue(name) {
  const i = argv.indexOf(name);
  return i !== -1 && i + 1 < argv.length ? argv[i + 1] : undefined;
}
const screenshotPath = optionValue("--screenshot");
const timeout = Number(optionValue("--timeout") ?? 10000);

if (!existsSync(distDir)) {
  console.error(
    `✗ No build found at ${distDir}.\n` +
      `  Run \`mise run bundle\` first (or just \`mise run browser-check\`, which bundles for you).`,
  );
  process.exit(1);
}

// --- serve the built site ---------------------------------------------------
// port 0 lets the OS pick a free port, so parallel/CI runs never collide.
const server = await preview({
  root,
  preview: { port: 0, strictPort: false },
  logLevel: "warn",
});
const url = server.resolvedUrls?.local?.[0];
if (!url) {
  console.error("✗ Vite preview server did not report a local URL.");
  process.exit(1);
}

// --- drive a headless browser ----------------------------------------------
let browser;
try {
  browser = await chromium.launch();
} catch (err) {
  console.error(
    "✗ Could not launch Chromium. Install the browser first with `mise run browser-install`.\n" +
      `  Underlying error: ${err.message}`,
  );
  await closeServer(server);
  process.exit(1);
}

const consoleErrors = [];
const pageErrors = [];

const page = await browser.newPage();
page.on("console", (msg) => {
  if (msg.type() === "error") consoleErrors.push(msg.text());
});
page.on("pageerror", (err) => pageErrors.push(err.message ?? String(err)));

let renderError;
try {
  await page.goto(url, { waitUntil: "load", timeout });
  // The app builds its DOM synchronously on script load; wait for the heading
  // so we assert the bundle actually executed, not just that HTML was served.
  await page.waitForSelector("#greeting", { timeout });
  const heading = (await page.textContent("#greeting"))?.trim();
  if (heading !== "Sleight") {
    renderError = `Expected #greeting to read "Sleight", got ${JSON.stringify(heading)}.`;
  }
  if (screenshotPath) {
    await page.screenshot({ path: resolve(process.cwd(), screenshotPath), fullPage: true });
  }
} catch (err) {
  renderError = err.message ?? String(err);
} finally {
  await browser.close();
  await closeServer(server);
}

// --- report -----------------------------------------------------------------
const problems = [];
if (renderError) problems.push(`render: ${renderError}`);
for (const e of pageErrors) problems.push(`uncaught error: ${e}`);
for (const e of consoleErrors) problems.push(`console.error: ${e}`);

if (problems.length > 0) {
  console.error("✗ Browser check failed:");
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}

console.log(`✓ Browser check passed — app rendered in Chromium with no console errors (${url}).`);
if (screenshotPath) console.log(`  Screenshot written to ${screenshotPath}.`);

async function closeServer(s) {
  await new Promise((res) => s.httpServer.close(() => res()));
}
