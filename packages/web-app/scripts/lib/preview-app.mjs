// Shared boot for everything that drives the *built* web app in a headless
// browser: the screenshot report, the link-preview image, and the
// `@playwright/test` suite in ../../browser-tests.
//
// All of those need the same two things — the real bundle served the way it
// ships (Vite's own preview server over packages/web-app/dist, not a dev
// build), and a Chromium that actually exists on this machine. Each script used
// to carry its own copy of both; they live here now so there's one answer to
// "which browser?" and one place that knows a task forgot to bundle first.
//
// The Playwright suite doesn't call `startPreview` — `playwright.config.mjs`
// boots the same server through its `webServer` option so the run owns the
// port and the readiness wait — but it does share `resolveChromiumExecutable`,
// which is the half that differs by environment.

// `@playwright/test` is the only Playwright package here, and it re-exports the
// whole browser API alongside the runner. Depending on it *and* on `playwright`
// lets the two resolve to different versions under pnpm's isolated layout, at
// which point the specs and the runner are separate instances and every
// `test.use()` throws — so the scripts take `chromium` from the runner package.
import { chromium } from "@playwright/test"
import { preview } from "vite"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))

/** packages/web-app — the Vite root every one of these scripts serves. */
export const webAppRoot = path.resolve(here, "..", "..")

// The pre-installed Chromium in managed environments is a specific revision that
// may not match the playwright package's default; launching it by path sidesteps
// the version check (see the env's browser notes). On a clean CI runner neither
// exists and we fall through to Playwright's own resolution — i.e. whatever
// `mise run playwright-install` fetched.
export function resolveChromiumExecutable() {
  const explicit = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE
  if (explicit && fs.existsSync(explicit)) return explicit
  const preinstalled = "/opt/pw-browsers/chromium"
  if (fs.existsSync(preinstalled)) return preinstalled
  return undefined
}

/**
 * Fail early, with the fix in the message, when dist/ isn't there. Every caller
 * is behind a mise task that `depends = ["bundle"]`, so this only fires when a
 * script is run by hand.
 */
export function assertBundled(taskName) {
  if (!fs.existsSync(path.join(webAppRoot, "dist", "index.html"))) {
    throw new Error(
      `packages/web-app/dist is not built — run \`mise run bundle\` first (the ${taskName} task depends on it).`,
    )
  }
}

/**
 * Serve the built site on an ephemeral port. Returns the base URL (no trailing
 * slash) and a `close` that shuts the server down.
 */
export async function startPreview() {
  const server = await preview({
    root: webAppRoot,
    preview: { port: 0, strictPort: false, open: false },
    logLevel: "warn",
  })
  return {
    base: server.resolvedUrls.local[0].replace(/\/$/, ""),
    close: async () => await server.httpServer.close(),
  }
}

/**
 * A headless Chromium, resolved as above. `options` passes straight through to
 * `chromium.launch` — `{ headless: false }` is the one that gets used, so a human
 * can watch `mise run autoplay -- --headed` play a game.
 */
export async function launchChromium(options = {}) {
  return await chromium.launch({ executablePath: resolveChromiumExecutable(), ...options })
}
