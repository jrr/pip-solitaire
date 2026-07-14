---
name: browser-check
description: >-
  Verify and interact with the web-app in a real browser. Use whenever you
  touch anything under packages/web-app (Main.res, the Html JSX runtime,
  Board/Scene components, index.html, vite config, PWA setup). Two tools: a
  deterministic `mise run browser-check` smoke gate (loads the built site in
  headless Chromium, fails on console errors, optional screenshot), and the
  Playwright MCP server (`mcp__playwright__browser_*`) for driving the running
  app turn-by-turn — clicking, typing, dragging, reading state. Reach for the
  MCP when you want to explore or confirm an interaction; reach for
  browser-check when you want a repeatable pass/fail.
---

# Browser verification & interaction

A green `mise run ci` proves the app compiles and that `Core` unit tests pass —
it does **not** prove the page renders or that a click does the right thing. The
app builds real DOM (no framework), so runtime errors, bad imports, broken
service-worker registration, or a dead event handler only surface when a browser
actually loads and drives the bundle. Two complementary tools close that gap.

## 1. `mise run browser-check` — deterministic smoke gate

```
mise run browser-check
```

One command from a clean checkout: builds ReScript, bundles the production site,
ensures a headless Chromium is installed, serves `dist/` with Vite's preview
server, loads it in Chromium, and:

- **fails** (non-zero exit) if the page throws, logs any `console.error`, or
  never renders the app shell (waits for `#greeting` to read "Sleight");
- **passes** with a one-line summary otherwise.

Runs inside the `@claude` agent's `Bash(mise run:*)` allowlist — no extra tool
grant. Treat a failure as a real regression: read the printed errors and fix the
code. Capture a screenshot for a PR comment or a layout check:

```
mise run browser-check -- --screenshot shot.png    # full-page PNG
mise run browser-check -- --timeout 20000          # override the 10s wait
```

## 2. Playwright MCP — drive the running app creatively

When you want to *interact* — click through scenes, poke the card, exercise
drag-and-drop, read the DOM after an action — use the Playwright MCP server
(configured in `.mcp.json`). It gives you `mcp__playwright__browser_*` tools you
call turn-by-turn: navigate, **snapshot** (reads the accessibility tree, so you
"see" structured page state with a `ref` for every node — no vision needed),
click/type/hover/drag by `ref`, `browser_console_messages`, `browser_evaluate`,
and more. You snapshot, decide the next action from what you see, act, snapshot
again — adaptive exploration, not a script written blind.

**Serve the app first, then drive it:**

1. Start a dev server in the **background** (Bash `run_in_background`):
   `mise run dev` → serves at `http://localhost:5173` with HMR.
2. `browser_navigate` to `http://localhost:5173`.
3. `browser_snapshot` to see the page; act on the `ref`s it returns.

The `.mcp.json` server launches through `scripts/playwright-mcp.mjs`, which
points Playwright at the environment's pre-installed Chromium (sandboxed agent
environments block Playwright's browser-download CDN, so this is required — see
the script's header). If it reports no browser, run `mise run browser-install`.

**Which tool?** browser-check for a repeatable pass/fail you can gate on (and the
CI-friendly one); the MCP for open-ended interaction and debugging. They share
the same browser install.

## How it's wired (for maintainers)

- **`mise run browser-install`** installs the pinned headless Chromium; both
  tools depend on it. The `@claude` workflow runs it as an explicit step.
- **`packages/web-app/scripts/browser-check.mjs`** — Vite `preview()` + Playwright
  `chromium`, a plain smoke check in the repo's hand-rolled style.
- **`scripts/playwright-mcp.mjs`** — launcher that resolves a Chromium binary and
  execs `@playwright/mcp` (pinned) as a transparent stdio proxy; forwards extra
  args (e.g. `--allowed-origins` to fence the browser to localhost).
- **`playwright`** is pinned exactly in `packages/web-app/package.json` (library
  and browser build ship in lockstep).

To assert more in the gate, extend `browser-check.mjs` — it's plain Playwright.
Keep the "no console errors" check; it's the cheapest catch for this class of bug.
