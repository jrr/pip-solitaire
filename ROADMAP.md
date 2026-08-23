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
| Rendering | **Plain DOM bindings** (no rescript-react). Revisit only if composition hurts. |
| Child diffing | **Keys in the hand-rolled runtime** (#309), not Preact (#45). See below. |
| Component state | **Child Elm composition** (#308), not nested mounts. Pure `props => vnode` stays the default. See below. |
| Service worker tooling | **`vite-plugin-pwa`** — manifest, precache, build hash, and the update hook. |
| Card rendering | **SVG** cards for full visual control. |
| State ownership | **100% in `core`**, reduxey: immutable state + action variant + pure reducer. |

### Why keys rather than Preact

#45 filed the trigger for adopting Preact: *cards need keyed identity across a
diff*, **and** we need FLIP on those same nodes, **and** the way forward
otherwise is owning a keyed diff. #309 called the moment arrived. Weighed at
that point, only the third condition really held:

- The board never reorders a list of DOM children. Every card is appended once
  to one flat `playfield` and then positioned by `style.left/top` with a
  `zIndex` — a card moving cascade 3 → cascade 5 changes two numbers, not the
  tree. `TableScene` is deliberately outside the `Html` loop for that reason.
- FLIP is already covered. The board measures and animates itself through the
  Web Animations API, which is the half of the trigger a library would have
  supplied.
- Keys came to ~60 lines against a runtime we already own, and are unit-tested
  in isolation (`Html_test.res`). The zero-dependency story stays intact for an
  offline-first PWA, and `Html.node` — the escape hatch several modules use to
  own their own subtrees — has no Preact equivalent, so adopting would have
  been a migration, not a swap.

So the trigger did not fire, exactly as #45 allowed for. **Revisit if piles come
to own their cards as DOM children** (nesting, clipping, per-pile transforms),
or if the component-state decision below comes to want hooks-style local state
throughout — either makes the runtime's growth curve steeper than a dependency.

### Why child composition rather than nested mounts

Every component under `components/` is a pure `props => vnode` whose state lives
in `Main`'s single model, because `Html.mount` is the only Elm loop in the app.
**That stays the default**, and most components never need anything else. #308
was about the one place it had visibly run out: the menu.

The measured cost was the menu's chrome. `Menu.res` had **37 props**, and each of
its six settings switches was declared four times over — in `Main`'s model, on
`Menu.props`, on the screen's props, and on the row's — with `Menu` in the middle
paying six lines apiece for values it never read. Extraction (#307) had already
been tried and made the record *bigger*: the markup moved out, the plumbing
stayed and gained a hop.

Two ways to fix it were on the table, and the codebase had a precedent for each.

**Nested mount** — what `Board.res` does: a `<game-board>` custom element with a
shadow root, its own scoped `css`, its own `model`/`msg`/`update`/`view` and its
own `mount`, and a typed boundary in `InwardEvents`/`OutwardEvents`. Real
encapsulation, and the boundary is DOM events. Rejected here:

- Each one needs an owned subtree. As a custom element that means a hand-written
  `.js` shell per component, because ReScript has no class syntax (see the note
  in `game-board.js`); without one it means a module-level ref holding the div —
  the imperative pattern #300 had just finished retiring on the board boundary.
- Style scoping stopped being a benefit when #306 landed. `styles/index.css` now
  assembles one file per component in a deliberate, load-bearing order, and
  `MenuHeader`/`MenuToggleRow`/`MenuActionRow`/`MenuNavRow` are shared by all
  three menu screens — shadow-rooting any one screen splits those four
  stylesheets across the boundary.
- It tests worse. Component tests here are `Html.create(C.make(props))` under
  jsdom; a nested mount needs a mounted root and CustomEvent assertions. `Board`
  itself has no test, which is the whole of the evidence for the approach.

**Child Elm composition** — child `model`/`msg`/`update`/`view` in its own file;
the parent embeds the child's model as one field and maps its messages up through
one constructor. Chosen, because:

- The state had no other reader. Before the change, not one of the six switch
  flags was read anywhere in `Main` outside its own toggle branch and the `<Menu>`
  call — they existed purely to draw a switch.
- `update` stays a pure function, so it's unit-testable in isolation exactly like
  `core`'s `Reducer`, which is the testing story the rest of the codebase already
  has.
- It needs no runtime change at all. `Html.mount`'s `update` already returns
  `(model, effect)`, so the parent threads the child's effect straight out.

It cost two things worth knowing. The child's model is a **mirror** — of
`Preferences`, of the live refs the board reads, of a document-root attribute —
so its `update` has to write every flip through, and a setting's value must be
read from its real home rather than from the screen. And the effects that reach
the board or those refs can't be raised from inside a component, so `Main` hands
the screen an `env` of four chrome capabilities; that list is fixed, not one entry
per switch, which is what keeps it from being the prop drilling it replaced.

`MenuSettingsScreen` is the worked example: 13 props to 5, `Menu` from 37 props to
7 (its other screens got the same treatment as plain records — pass the record,
don't re-spell its fields, as #300 did), and `Main` 76 lines shorter with
`cardTilt` no longer appearing in it at all. **Revisit if a third or fourth screen
wants the same** — at that point the mapping boilerplate per child is worth
weighing against #45 again, which is now the only one of that issue's three
arguments still standing.

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
