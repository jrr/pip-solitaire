# web-app scripts

Node scripts behind the web-app's mise tasks. Run them through the task, never
with `node` directly — the tasks carry the `depends` that build or bundle first
(see the repo-root `CLAUDE.md` on the task interface).

The directories split by **purpose**, not by mechanism:

| dir | what's in it |
| --- | --- |
| `lib/` | shared machinery, imported by the rest (and by `playwright.config.mjs` / the browser tests) |
| `generate/` | asset generators — they write committed files into `public/` or `src/` |
| `screenshots/` | the screenshot report: rendering it, and the two pieces that publish it |

`generate/og-image.mjs` is the awkward one: an asset generator by purpose, a
browser-driver by mechanism. Purpose wins — it writes a committed
`public/og-image.png` on the same lifecycle as the icons and fonts — and it
imports the shared browser boot from `lib/`.

## Script → task → output

| script | task | output |
| --- | --- | --- |
| `generate/fonts.mjs` | `mise run fonts` | `public/fonts/*`, `src/fonts/*` — the vendored woff2/ttf, rebuilt from their `@fontsource` sources (#114) |
| `generate/icons.mjs` | `mise run icons` | `public/*.png` — the PWA icons, composed from the real `CardArt` cards and rasterized (#49) |
| `generate/og-image.mjs` | `mise run og-image` | `public/og-image.png` — the link-preview crop of a rendered mid-game board (#221) |
| `screenshots/render.mjs` | `mise run screenshots` | `screenshots/` — the report: FreeCell scenes × emulated devices × orientation, plus an `index.html` contact sheet |
| `screenshots/stage.mjs` | `mise run stage-screenshots -- <dir> <stamp>` | a local staging dir for `peaceiris/actions-gh-pages` to publish |
| `screenshots/hub.mjs` | `mise run screenshots-hub -- <dir>` | `<dir>/index.html` — the `/screenshots/` hub listing every published report |

The three `generate/` outputs are **committed**, so those tasks only need
re-running when their inputs change. The `screenshots/` outputs are not — CI
renders and publishes them per push.

## lib/

| module | what it is |
| --- | --- |
| `preview-app.mjs` | serve the built site (Vite preview over `dist/`) and find a Chromium that exists on this machine |
| `devices.mjs` | the report's device list, built from Playwright's `devices` registry — so a phone shot gets touch events and the meta viewport, not just a phone-sized window (#244) |
| `touch.mjs` | `touchDrag()` — a finger dragging across the board, via CDP, since Playwright's `Touchscreen` only taps |

`lib/` is imported from outside `scripts/` too: `playwright.config.mjs` takes
`resolveChromiumExecutable` from `preview-app.mjs`, and the browser tests take
`touchDrag` from `touch.mjs`.
