---
name: browser-check
description: >-
  Verify a web-app change actually renders in a real browser. Use whenever you
  touch anything under packages/web-app (Main.res, the Html JSX runtime,
  Board/Scene components, index.html, vite config, PWA setup) and want to
  confirm the built site loads in headless Chromium with no console errors —
  the automatable version of "renders in Chromium with no console errors."
  Also use to capture a screenshot of the running app.
---

# Browser check

The web-app builds real DOM (no framework); a green `mise run ci` proves it
compiles and that `Core` unit tests pass, but it does **not** prove the page
renders — a runtime error, a bad import, or a broken service-worker
registration only shows up when a browser actually loads the bundle. This skill
closes that gap through the mise task interface, so it works inside the
`@claude` agent's `Bash(mise run:*)` allowlist without any new tool grant.

## Run it

```
mise run browser-check
```

That one command does the whole thing from a clean checkout: builds the
ReScript, bundles the production site into `packages/web-app/dist`, makes sure a
headless Chromium is installed, serves the built site with Vite's preview
server, loads it in Chromium, and:

- fails (non-zero exit) if the page throws, logs any `console.error`, or never
  renders the app shell (it waits for `#greeting` to read "Sleight");
- passes with a one-line summary otherwise.

Because it exercises the real bundle in a real browser, treat a failure as a
real regression — read the printed errors and fix the code, don't work around
the check.

## Capture a screenshot

Args after `--` pass through to the check script:

```
mise run browser-check -- --screenshot shot.png
```

Writes a full-page PNG to `shot.png` (relative to where you run it). Useful for
showing what a UI change looks like in a PR comment, or eyeballing layout.
`--timeout <ms>` overrides the default 10s render wait.

## How it's wired (for maintainers)

- **`mise run browser-install`** — installs the pinned headless Chromium
  (`playwright install --with-deps chromium`). `browser-check` depends on it, so
  the check self-provisions; the `@claude` workflow (`.github/workflows/claude.yml`)
  also runs it as an explicit step so install failures surface in the CI log.
- **`packages/web-app/scripts/browser-check.mjs`** — the ~100-line script:
  Vite `preview()` to serve `dist/`, Playwright `chromium` to drive it. No test
  framework; it's a plain smoke check in the repo's hand-rolled style.
- **`playwright`** is pinned exactly in `packages/web-app/package.json` (library
  and browser build ship in lockstep — a floating range pulls a newer library
  that expects a browser build the pinned one didn't download).

To assert more (a new scene, a specific element, an interaction), extend
`browser-check.mjs` — it's plain Playwright. Keep the "no console errors" gate;
it's the cheapest catch for the class of bug this exists to find.
