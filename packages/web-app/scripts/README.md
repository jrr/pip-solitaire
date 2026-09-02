# web-app scripts

Node scripts behind the web-app's mise tasks. Run them through the task, never
with `node` directly — the tasks carry the `depends` that build or bundle first
(see the repo-root `CLAUDE.md` on the task interface).

The directories split by **purpose**, not by mechanism:

| dir | what's in it |
| --- | --- |
| `lib/` | shared machinery, imported by the rest (and by `playwright.config.mjs` / the browser tests) — including `load-jsx-module.mjs`, which is how a Node script imports compiled ReScript that carries JSX |
| `generate/` | asset generators — they write committed files into `public/` or `src/` |
| `screenshots/` | the screenshot report: rendering it, and the two pieces that publish it |
| `autoplay/` | playing the game: read the board off the page, plan, and drag the moves |

`generate/og-image.mjs` is the awkward one: an asset generator by purpose, a
browser-driver by mechanism. Purpose wins — it writes a committed
`public/og-image.png` on the same lifecycle as the icons and fonts — and it
imports the shared browser boot from `lib/`.

## Script → task → output

| script | task | output |
| --- | --- | --- |
| `generate/fonts.mjs` | `mise run fonts` | `public/fonts/*`, `src/fonts/*` — the vendored woff2/ttf, rebuilt from their `@fontsource` sources |
| `generate/icons.mjs` | `mise run icons` | `public/*.png` — the PWA icons, composed from the real `CardArt` cards and rasterized |
| `generate/og-image.mjs` | `mise run og-image` | `public/og-image.png` — the link-preview crop of a rendered mid-game board |
| `dev-smoke.mjs` | `mise run dev-smoke` | nothing — it boots the dev server, loads the app in a browser, and fails if either the page or the server complains (see the file for why the build's green suite can't cover this) |
| `screenshots/render.mjs` | `mise run screenshots` | `screenshots/` — the report: FreeCell scenes (plus the card-raster fidelity sheet and the posed cascade) × emulated devices × orientation, and an `index.html` contact sheet |
| `screenshots/stage.mjs` | `mise run stage-screenshots -- <dir> <stamp>` | a local staging dir for `peaceiris/actions-gh-pages` to publish |
| `screenshots/hub.mjs` | `mise run screenshots-hub -- <dir>` | `<dir>/index.html` — the `/screenshots/` hub listing every published report |
| `autoplay/play.mjs` | `mise run autoplay -- <seed…>` | nothing on disk — a game played to the win overlay, and a play-by-play on stdout (`--shots <dir>` also writes screenshots) |

The three `generate/` outputs are **committed**, so those tasks only need
re-running when their inputs change. The `screenshots/` outputs are not — CI
renders and publishes them per push.

## lib/

| module | what it is |
| --- | --- |
| `preview-app.mjs` | serve the built site (Vite preview over `dist/`) and find a Chromium that exists on this machine |
| `devices.mjs` | the report's device list, built from Playwright's `devices` registry — so a phone shot gets touch events and the meta viewport, not just a phone-sized window |
| `touch.mjs` | `touchDrag()` — a finger dragging across the board, via CDP, since Playwright's `Touchscreen` only taps |

`lib/` is imported from outside `scripts/` too: `playwright.config.mjs` takes
`resolveChromiumExecutable` from `preview-app.mjs`, and the browser tests take
`touchDrag` from `touch.mjs`.

## autoplay/

Plays FreeCell in a real browser, every move a pointer drag on the rendered
board — nothing reaches into game state, which is what makes a game played this
way evidence about the *app*. Three parts:

| module | what it is |
| --- | --- |
| `read-board.mjs` | the eyes — the board read off the DOM (zone boxes, card `aria-label`s), the `settle()` wait, and the `Position` it all adds up to |
| `autoplay.mjs` | the hands — `playGame()` / `dragMove()`: plan a move, drag it, look at the board again |
| `play.mjs` | the `mise run autoplay` CLI over the above |

The **brain** isn't here: the rules and the solver live in `core`
(`Position.res`, `Solver.res`) and this imports them like any other consumer
. They used to be a JavaScript mirror of `core` kept in this directory,
which meant two copies of the rules and only a browser run to catch a drift
between them; now there is one copy, and `core`'s own tests hold the packed
search position against `Reducer` move for move. `mise run solve -- <deal>` runs
that brain with no browser attached.

`autoplay.mjs` is imported from outside `scripts/` too:
`browser-tests/autoplay.spec.mjs` plays a fixed deal end to end as a test, and
asserts that the app never once did something other than what `core` predicted.
Driving the app by hand for anything else is documented as a skill, in
`.claude/skills/play-in-browser/`.
