# CSS layers

The app's CSS is **one file per component, imported by that component**. Nothing
keeps a list of stylesheets, so nothing pins the order they arrive in — Vite
appends each sheet wherever the module graph reaches it. What decides the cascade
instead is `@layer`, declared once in `web-app/src/styles/index.css`:

```css
@layer foundations, components, scenes, overrides;
```

This page is why that line exists and what it costs. The declaration and the
four foundation imports are the whole of `index.css`; everything else lives
beside the component it styles.

## Where a rule lives

A rule goes in the file for the thing it styles — `components/TopBar.css` beside
`TopBar.res`, `scenes/TableScene.css` beside `TableScene.res` — and the component
pulls it in with one line at the top of the module:

```rescript
%%raw(`import "./TopBar.css"`)
```

So adding, renaming or deleting a component touches exactly the component. The
sheets under `src/styles/` are the leftovers, the ones no single component can be
said to own:

| | layer | |
|---|---|---|
| `styles/fonts.css` | `foundations` | the two self-hosted faces |
| `styles/base.css` | `foundations` | the reset, the custom properties, the safe-area padding |
| `styles/app-shell.css` | `foundations` | `#app` / `#scene-area` / the page's own frame |
| `styles/landscape-rail.css` | `overrides` | the short-landscape rail, which restyles three components at once |

Those four are imported by `index.css`, which `index.html` links directly — see
[Why the declaration comes first](#why-the-declaration-comes-first) for why it's
a `<link>` and not another component import.

Everything else sits in the layer its directory suggests: `components/` and
`components/menu/` in `components`, `scenes/` and `cards/CardArt.css` in
`scenes`, `debug/DebugConsole.css` mostly in `components` — with one deliberate
exception, below.

## The three rules

### 1. Every sheet must declare a layer

An unlayered rule beats **every** layered rule, no matter how specific. So a
sheet that forgets its `@layer` wrapper doesn't misorder slightly — it wins
outright, and silently: the page still renders, just wrong, and only wherever
that sheet happens to collide with another.

There is no partial migration and no "just this one file". Nothing in the normal
build catches a miss either — it isn't a syntax error, and the ReScript compiler
never sees CSS. The only thing that does is
`web-app/browser-tests/css-layers.spec.mjs`, which reads the cascade the browser
actually built and asserts that every top-level rule on the page is a layer
statement or a layer block.

### 2. A later layer beats an earlier one even when it is less specific

This is the whole point of the ordering, and also the trap. Specificity only
breaks ties *within* a layer; across layers, the later layer wins first.

The live example is the debug console's side dock, which has to narrow the board:

| | selector | specificity | layer |
|---|---|---|---|
| the dock | `html[data-console-dock="side"] .table-board` | (0,2,1) | `overrides` |
| the board | `.table-board { width: 100% }` | (0,1,0) | `scenes` |

The dock's rule is the more specific of the two, so on a flat cascade it would
win anyway — but that isn't what's holding it up. `scenes` is a *later* layer
than `components`, so if that rule sat in `components` with the rest of
`DebugConsole.css`, the **less** specific `.table-board` would beat it outright
and docking would stop narrowing the board. (`browser-tests/debug-console.spec.mjs`
catches exactly that.) It's in `overrides` for that reason, in its own `@layer`
block inside a file that is otherwise `components`.

The rule to take from it: **a rule that reaches out of its own component to
restyle another one belongs in `overrides`**, whatever its specificity says. The
landscape rail is the other case — it restyles the top bar, the menu and the
board, so the whole file is `overrides`.

### 3. Ties inside a layer break on source order — don't lean on one

Within a layer the cascade still falls back to source order, and that order is
now the module graph's: dependency-first, so a component's own sheet lands after
the sheets of the components it builds on (`CardArt.css` before `TableScene.css`,
which is the direction those two want anyway).

It is not written down anywhere and not tested. Nothing in the app relies on a
tie between two sheets inside one layer; keep it that way. When a rule needs to
beat another file, reach for the next layer out.

Ties **within one file** are a different matter — those are ordinary CSS and
perfectly load-bearing. `landscape-rail.css` has the worked example: two
`(1,1,1)` `#top-bar` rules where the later one would win the tie and shouldn't,
so the later one carries a `:not([data-cutout="right"])` guard to exclude the
case the earlier rule owns. The comment there explains the failure it fixes, and
`browser-tests/rail.spec.mjs` pins all four regimes.

## Why the declaration comes first

`@layer a, b, c;` as a *statement* fixes the order up front. A layer that is
merely first *mentioned* by a block gets appended in arrival order instead —
which is exactly the module-graph order the statement exists to make irrelevant.

That's why `index.css` is linked from `index.html` rather than imported by a
component: the link is render-blocking and lands before any component's sheet, so
the statement is always the first rule the page sees.
`css-layers.spec.mjs` pins it at index 0 and checks that the four names are
declared exactly once.

## Adding a rule, adding a file

Adding a **rule** needs no thought: put it in the sheet for the thing it styles.

Adding a **file** means two things, and only two:

1. wrap the whole sheet in the layer it belongs to (`@layer components { … }`);
2. import it from the component that renders the thing, with the `%%raw` line.

If it's a rule that restyles a component other than its own, it goes in
`overrides` — either its own file, or a second `@layer overrides { … }` block
inside the sheet it otherwise belongs to, the way `DebugConsole.css` does it.

## What gates a styling change

CSS is not covered by `mise run format`, and the unit tests never evaluate it —
jsdom has no layout engine, and it skips a media query whose media list doesn't
carry the literal token `screen`. So the gate is a real browser:

```
mise run browsertest    # css-layers, debug-console, rail, menu-layering, …
mise run screenshots    # device-resolution renders, to look at
```
