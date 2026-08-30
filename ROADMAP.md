# Roadmap: Installable PWA FreeCell

Working toward an installable, offline-capable Progressive Web App that plays
FreeCell, with drag-and-drop and animation, built on the existing pnpm +
ReScript + Vite monorepo.

## The load-bearing principle

**All game state and rules live in `core` as immutable data plus pure
transition functions. The CLI and the web app are both just drivers/renderers
over the same model.**

Concretely, we want a "reduxey" (Elm-architecture) shape in `core`:

- A single immutable `state` value describing the whole game.
- An `action` variant type describing every legal thing the player can do
  (`Move`, `Deal`, `Undo`, `AutoFoundation`, …).
- A pure `reducer: (state, action) => state` (illegal actions are rejected,
  returning the state unchanged or an explicit error).
- The UI holds only *transient* view state (what's being dragged, cursor
  offset, in-flight animations) and `dispatch`es actions into `core`.

Everything the project wants falls out of this one decision:

- **Unit-tested rules** — test the reducer directly, no UI needed.
- **Exercisable via CLI** — the CLI is a text driver that dispatches actions.
- **Undo/redo** — keep a stack of prior `state` values; undo is a pop.
- **Deterministic deals** — a seeded shuffle makes tests and shareable deal
  numbers possible.
- **Offline resume** — serialize `state` to localStorage.

## Decisions

| Decision | Choice |
|---|---|
| Rendering | **ReScript JSX in preserve mode over Preact** (no rescript-react). See below. |
| Child diffing | **Preact's**, reached through `Html.res`'s bindings. Was ours; see below. |
| Service worker tooling | **`vite-plugin-pwa`** — manifest, precache, build hash, and the update hook. |
| Card rendering | **SVG** cards for full visual control. |
| State ownership | **100% in `core`**, reduxey: immutable state + action variant + pure reducer. |

### Why Preact now, after saying no twice

#45 filed the trigger for adopting Preact and #309 declined it, on grounds that
were right at the time: the board never reorders a list of DOM children, FLIP was
already covered by the Web Animations API, and keys came to ~60 lines against a
runtime we owned. What tipped it later wasn't the keys — it was the two things
that decision named as its own revisit conditions, plus a measurement.

- **The runtime's growth curve.** #308 wants hooks-style local state. That is the
  second thing #309 said to revisit on, and it is where a hand-rolled runtime
  stops being ~400 lines you can hold in your head.
- **`Html.node` does have an equivalent.** #309's blocker — splicing a subtree
  the app owns — is a host element with a callback ref, `display: contents` so it
  adds nothing to layout. It costs one element in the tree, so a `.parent > .child`
  rule across a splice becomes a descendant selector. That was one rule.
- **Measured, not assumed.** On identical ReScript source, Preact patches a
  182-node tree in 0.130 ms against the old runtime's 0.184 ms, and costs
  +6.6 KB gzip on the app bundle (40.6 → 47.2). About 3 KB of that is
  `preact-render-to-string`, which `CardRaster` needs because Preact's vnodes are
  opaque where ours were a variant we could walk.

What the swap is *not*: a rewrite. Components are still `props => vnode`
functions, the Elm loop is unchanged, and `Html.res` keeps its public API — the
whole app compiled against the new runtime with no call-site changes at all. The
diff that followed was the honest part: typed props replacing the generic `attrs`
escape hatch, and stale comments about a reconciler we no longer own.

**What we own now** is a binding module, and three esbuild configurations that
have to agree (build, dev-server scan, Vitest) because preserve mode leaves JSX
in the compiled output for the bundler to lower. `mise run dev-smoke` exists
because nothing else checks the second one.

## How to read this

The work splits into two mostly-independent tracks. Items that have been filed
as issues are linked; the rest are sketches to be filed closer to the time.
These aren't priorities or a strict order — the only real constraints are the
dependencies noted on each item.

- **Platform track** — installability, versioning, offline, updates. No
  dependency on game logic.
- **Game track** — input/animation demos (independent of everything), then the
  card model → card table → FreeCell rules → playable FreeCell, which do have
  to happen in that order.

---

## Platform track

### Installable PWA shell — [#19](https://github.com/jrr/pip/issues/19)

Make the deployed web app installable to a phone home screen and desktop.

- Add `manifest.webmanifest`: `name`, `short_name`, `display: standalone`,
  `theme_color`, `background_color`, and icons (192, 512, plus a maskable icon).
- Add `apple-touch-icon` and the iOS meta tags (iOS ignores parts of the
  manifest and won't fire an install prompt).
- Add `vite-plugin-pwa` generating a service worker that precaches the app
  shell.
- Respect the GitHub Pages project subpath (`/<repo>/`) in `start_url`,
  manifest `scope`, and SW registration scope. Asset paths are already handled
  by `base: "./"`.

**Done when:** "Add to Home Screen" installs the app and it launches
standalone (no browser chrome) on Android/desktop.

### Version info, offline, and update flow — [#20](https://github.com/jrr/pip/issues/20)

Depends on the PWA shell (needs the service worker in place).

- Inject build version (git SHA + build timestamp) via a Vite `define`; show it
  in a small "about"/corner element.
- Confirm the app loads with no network (precache).
- Wire the SW update lifecycle (`vite-plugin-pwa` `onNeedRefresh`) so a new
  deploy surfaces an **"Update available" button** that activates the waiting
  worker and reloads.

**Done when:** reloading offline works; visiting online after a new deploy
shows the version and an update button that pulls the latest.

---

## Game track

### Drag-and-drop tech demo — [#21](https://github.com/jrr/pip/issues/21)

A throwaway page to learn pointer-based dragging in isolation — no game logic.

- Colored boxes draggable between drop zones using **Pointer Events**
  (`pointerdown`/`pointermove`/`pointerup` + `setPointerCapture`).
- `touch-action: none` on draggables to suppress scroll/gesture interference.
- Hit-testing to pick a drop target; snap into place on drop.

**Done when:** boxes drag smoothly between zones on both phone and desktop.

### Animation tech demo — [#22](https://github.com/jrr/pip/issues/22)

A throwaway page to learn transitions in isolation.

- **FLIP** technique via the Web Animations API: ease a box from position A to
  B after a layout change.
- Invalid-move "bounce back" animation.

**Done when:** there's a demo showing smoothly animated position changes and a
bounce-back.

### Card model in `core`

- `Suit` / `Rank` / `Card` / `Deck` types.
- **Seeded shuffle** (deterministic — testable, enables deal numbers).
- Generic pile model and move-legality primitives.
- Unit tests.

**Done when:** `core` exposes a tested card model with a deterministic shuffle.

### Card table + draggable stacks

Depends on the card model, and reuses the drag-and-drop and animation demos.

- Render cards as SVG on a table layout.
- Wire the pointer dragging + FLIP animation to move cards between free-form
  stacks — still no rules.

**Done when:** you can drag cards around between stacks in the web app.

### FreeCell rules in `core` + CLI exerciser

Depends on the card model.

- FreeCell state as a reducer: 8 cascades, 4 free cells, 4 foundations.
- Legal moves, supermoves (limited by free cells + empty columns),
  auto-to-foundation, win detection, undo/redo, numbered deals.
- Extend the CLI into a text-playable game (`deal N`, print board, `move`
  commands) driving the same reducer.
- Unit tests including known deals.

**Done when:** you can play a full game of FreeCell in the terminal and the
rules are covered by tests.

### Playable FreeCell in the PWA

Depends on the card table and the FreeCell rules.

- Bind the `core` FreeCell reducer to the card table UI; enforce legal moves.
- Animate moves and auto-complete; win screen.
- Persist the in-progress game to localStorage (resume offline).
- Undo button.

**Done when:** FreeCell is fully playable in the installed, offline-capable PWA.

---

## Stretch / later

- A second variant (Klondike) reusing `core`.
- Shareable/numbered deals, timer, and stats.
- Autosolve or hint.
- Keyboard play and accessibility.
- Playwright end-to-end tests for the drag interactions.
