// The browser-driven test suite (issue #243): the checks that need a real
// engine — layout, `calc()`, media queries, resolved transform matrices, live
// transitions, pointer input — none of which jsdom has. Those are the cases that
// can't live in `mise run test` (Vitest + jsdom, over the compiled ReScript), so
// they run here instead, against the *bundled* site.
//
// Run it with `mise run verify`, which bundles first. For anything else the CLI
// offers — `--ui`, `--headed`, `-g <pattern>`, `--trace on`, `show-report` — use
// the passthrough task: `mise run playwright -- test --headed -g rail` (bundle
// first, or run `mise run verify` once).
//
// Deliberately *not* wired into `mise run ci`: `ci` stays browser-free, and this
// suite needs `bundle` (a built dist/) where the unit tests only need `build`.
// CI runs it as its own job after `mise run playwright-install`.

import { defineConfig } from "@playwright/test"
import { resolveChromiumExecutable } from "./scripts/lib/preview-app.mjs"

// A fixed port, unlike the ephemeral one the screenshot/og-image scripts take:
// Playwright's `webServer` polls a URL to know the server is up, so it has to
// know the port in advance.
const PORT = 4173

export default defineConfig({
  testDir: "./browser-tests",
  // The suite is timing-sensitive in places (the finish sweep samples angles a
  // known number of milliseconds in), so don't let a file be split across
  // parallel workers within itself.
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  // CI machines are noisy neighbours for a suite that measures animation
  // timing: one worker, and a couple of retries with a trace on the first.
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: `http://localhost:${PORT}`,
    browserName: "chromium",
    trace: "on-first-retry",
    launchOptions: { executablePath: resolveChromiumExecutable() },
  },
  // Serve the real bundle, the way it ships — the same Vite preview server the
  // screenshot report drives (see scripts/lib/preview-app.mjs). Locally an
  // already-running `mise run preview` on this port is reused.
  webServer: {
    command: `pnpm run preview --port ${PORT} --strictPort`,
    url: `http://localhost:${PORT}/`,
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
})
