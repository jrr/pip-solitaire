# Rendering

The web app's UI is ReScript JSX compiled in **preserve mode** onto **Preact**.
The compiler doesn't lower the JSX it type-checks: it emits real JSX syntax into
the `.res.mjs` output and leaves the lowering to whatever bundles that output.
Preact then owns the diff.

That one decision is the reason for `runtime/Html.res`, for the JSX arrangement
having to be restated in three places, and for `scripts/lib/load-jsx-module.mjs`.
This page is the whole of it.

## The pipeline

```
TopBar.res
   │   rescript      packages/web-app/rescript.json:
   │                   "jsx": { "version": 4, "module": "Html", "preserve": true }
   ▼
TopBar.res.mjs       real JSX:  <svg className={"top-bar__icon"} viewBox={"0 0 24 24"}>…
   │   Oxc           lang: jsx · jsx: {runtime: automatic, importSource: preact}
   ▼
preact/jsx-runtime   Preact diffs, patches, owns the DOM
```

Each stage owns one thing, and the split is what the rest of this page turns on:

- **ReScript** type-checks the JSX against the module named by `jsx.module` —
  `Html` — and then writes the JSX out unchanged. It never emits a call.
- **Oxc**, the transformer inside Vite's bundler, decides what the JSX actually
  *becomes*. Which is to say: the `@module("preact/jsx-runtime")` paths in
  `Html.res` are read by the type checker; `jsx.importSource` is what the browser
  runs. They have to name the same runtime, and nothing checks that they do.
- **`Html.res`** owns the three things the app needs from the arrangement: the
  types the transform checks against, the props a DOM element accepts
  (`elementProps`), and the small surface the app calls — `string`, `array`,
  `empty`, `node`, `create`, `mount`.

Preserve mode was chosen over the generic transform because it puts a real,
inspectable JSX tree in the output and lets Preact's own tooling see it. The bill
comes due in the next two sections.

## The JSX settings, in three places

`.res.mjs` is not a JSX file extension, and every tool here decides how to parse a
file from its extension alone. So two things have to be said, in every pipeline
that reads the compiled output: that these files may contain JSX at all, and what
it becomes. The first is the one that gets forgotten, because the option that says
it is a different option in each of the three vocabularies below — `lang`,
`moduleTypes`, `loader` — while the second, the Preact runtime, is spelled almost
the same way everywhere.

| where | which route | reached by |
|---|---|---|
| `res-jsx-plugin.js` | a `pre` plugin over `.res.mjs`, so the JSX is gone before any of Vite's own extension-keyed machinery parses the module | `mise run bundle`, `mise run dev`, `mise run test` |
| `vite.config.js` → `optimizeDeps.rolldownOptions` | the dev server's dependency scanner: a Rolldown pass of its own, which runs none of the app's plugins | `mise run dev` |
| `scripts/lib/load-jsx-module.mjs` | a one-off esbuild `build()` for bare Node | `mise run icons` |

That the first row covers three pipelines at once is the reason it is a plugin
rather than a config block: a `pre` transform is the one hook the build, the dev
server and the test run all honour, and lowering there means nothing downstream
ever has to be told `.res.mjs` is special. Vite's own `oxc` option looks like the
shorter way to say it and is a trap — `oxc: {include, lang: "jsx", …}` serves the
dev server and the test run, and then the bundled build hands those same options
to a native Rolldown plugin that reads the extension and ignores the `lang`.

**Nothing checks that the three agree**, and they didn't once: `bundle`, `test`
and `browsertest` were all green while `vite` printed a screenful of *"The JSX
syntax extension is not currently enabled"* on every start.

Two details make that failure quieter than it sounds:

- **The scanner keys `moduleTypes` on the file's real extension.** `.mjs` is the
  entry that matters; a `.js` one is never consulted for the compiled output, so
  adding one out of caution buys nothing and hides that the `.mjs` key is the
  whole of it.
- **A dependency-scan failure is not fatal to Vite.** It logs, skips
  pre-bundling, and serves anyway — so the app comes up looking perfectly fine.
  And a warm `node_modules/.vite` skips the scan entirely, so the breakage is
  invisible until someone's dep cache is cold.

That is the seam `mise run dev-smoke` exists to guard. It boots `vite` the
command (not Vite's JS API, which survives a scan failure without complaint),
loads the page in a real browser, **and reads the server's output** — a rendered
page alone is not enough to pass.

## Node can't import the compiled output

Bare Node can't `import` a `.res.mjs` that carries JSX; `<svg …>` is a syntax
error there. The build scripts that render art without a browser
(`scripts/generate/icons.mjs`, which builds the app icons from the real `IconArt`
vnodes) do import exactly such modules.

So they go through `scripts/lib/load-jsx-module.mjs`: esbuild bundles the module,
lowers its JSX onto Preact, and the result is imported from memory as a data URL.
Nothing is written to disk. It also drops CSS to the `empty` loader, since a
component imports its own stylesheet and there is no document here to apply it to.

This file is the clearest single cost of preserve mode: with the generic JSX
transform the output would be plain function calls that Node runs as-is, and it
wouldn't exist. Any new Node-side consumer of compiled ReScript goes through it
rather than around it.

## What the binding shape has to get right

Two properties of `Html.res` are load-bearing, and both fail quietly. The
reasoning is here, and only here. The code carries the warning on the definition
it guards and points back to this section rather than arguing it a second time.

**1. The jsx functions must be `@module` externals.** With plain `let` bindings
the compiler quietly falls back to lowering JSX into calls on this module: the
old hand-rolled behaviour, with none of the new runtime, and no error anywhere.

**2. The types must mirror `@rescript/react`'s.** `component<'props>` is a
transparent alias for `'props => vnode` via `%component_identity`, and
`string`/`array` are `%identity`. An abstract component type makes `<>…</>` emit
`<prim => JsxRuntime.Fragment(prim)>`, which is not valid JSX and no bundler will
parse; a non-identity `array` wraps every children list in a runtime call.

The transform's contract itself is ordinary: `<Comp prop=… />` → `jsx(Comp.make,
props)`, `<div>…</div>` → `Elements.jsx("div", props)`, `<>…</>` →
`jsx(jsxFragment, props)`, plus the `*Keyed` variants when a `key=` is present.
Under preserve mode none of these are ever *called* — they type-check the JSX and
name the module the emitted `import` points at.

## Attributes are typed props, not a string map

`Html.elementProps` is a record of the attributes this app actually uses, each a
typed field, with `@as` giving the exact DOM name where ReScript can't spell it
(every hyphenated attribute, and `type`). Values are props rather than
`setAttribute` strings: `disabled` is a `bool`, not a presence flag; the ARIA
fields are strings, because those are enumerated attributes whose value is the
literal text `"true"`/`"false"` and an absent one differs from `"false"`.

**There is no generic escape hatch.** An attribute the record doesn't name can't
be set, so attribute names are checked by the compiler — and adding one is a
field, reviewed like any other line.

`@rescript/runtime` ships `JsxDOM.domProps`, which covers most of the list and
still doesn't fit, for three reasons: its `style` is a typed record and
`RasterScene` sets a CSS *custom property*; its `ref` is an opaque React-shaped
`domRef` and the splice host needs a callback; and its event types are React's
synthetic ones rather than the DOM events Preact hands you.

## What the app leans on Preact for

Not Preact's own behaviour — keyed matching, attribute patching and namespace
handling are its to test. Four properties are the app's, and each would fail
*silently* if the runtime under it changed, so `runtime/Html_test.res` pins them:

1. **SVG lands in the SVG namespace.** Every card, the app icon and the spinner
   are real vector nodes. An `<svg>` built in the HTML namespace draws nothing at
   all — no error, a blank card.
2. **A re-render reuses the DOM node.** Card motion is Web Animations on live
   nodes and the CSS transitions run on class changes; a node rebuilt rather than
   patched restarts both.
3. **Components are plain `props => vnode` functions**, driven by the Elm loop.
4. **A spliced subtree is left alone** — see below.

`Html.mount` is that loop: `update` is pure state and may return a command (a
`unit => unit` effect, `noEffect` for none) run after the render; each dispatch
re-derives the whole view and hands it to Preact. It re-renders only when the
model actually changed (physical equality), so a message that merely fires an
effect touches no DOM at all.

## `create` renders once — which is why components can't use hooks

`create` answers with the real DOM node a vnode describes, for callers that want
a node rather than a view: `TableScene` builds each of the 52 cards' `<svg>` this
way, and every component test in the package renders through it under jsdom.
Preact has no "render me a node" entry point, so `create` renders into a
throwaway host and lifts the nodes out of it. A component whose root is a
fragment (several menu screens) produces *several* top-level nodes, so the answer
has two shapes: one node comes back as itself, several come back in a
`DocumentFragment` — which `querySelector` searches and `appendChild` splices in
without adding a wrapper.

The host is then discarded, so **nothing ever renders into it again**: a
component reached through `create` renders exactly once, for ever. `useState`
there would hold state no re-render could read back, and a `useEffect` cleanup
would never run — both failing silently.

So **a component reachable from `create` must stay pure.** Hooks exist but
are only meaningful inside the tree `mount` owns and diffs. That is the entry
condition on `src/components/` described in `CLAUDE.md` § Where things live, and
it covers more of the app than it sounds like.

## Splicing a subtree the diff doesn't own

Some children belong to somebody else: `SceneSwitcher`'s scene container, the
debug console's scrollback, a rasterized card. Preact has no vnode that *is* a
live DOM node, so `Html.node` wraps one in a host element and puts it in through
a callback ref; the host is `display: contents` (`styles/base.css`) so it adds
nothing to layout, and re-rendering around it neither re-appends nor rebuilds it.

The consequence to remember is in the CSS: **a splice puts a host between parent
and child, so a child combinator won't reach across one.** Write `.parent .child`,
not `.parent > .child`.

## Rendering to markup instead of to the DOM

`runtime/StaticRender.res` serializes the *same* vnodes to a string, via Preact's
own `preact-render-to-string` rather than a walk of our own. That's what the icon
generator and `CardRaster` use, and it is why the app icon can't drift from the
on-screen card design — both come from one source, read through the same typed
props. It costs a second Preact package in the bundle graph (~3 KB gzip), because
`CardRaster` is app code and not only a build script.

## Before you change the build

1. Changing how the JSX is lowered means changing it in **all three** places
   above, each in its own vocabulary.
2. Run `mise run dev-smoke` after any build-config change. `mise run ci` will not
   catch a broken dev server; that task is the only thing that does.
3. Adding an attribute means adding a field to `Html.elementProps`, with `@as` if
   the DOM name is hyphenated or a keyword. There is no escape hatch by design.
4. Reaching for a hook means checking which side of `create` / `mount` the
   component is on. If it's reachable from `create`, it must stay pure.
5. Adding a Node script that imports compiled ReScript means going through
   `scripts/lib/load-jsx-module.mjs`.
6. If the JSX runtime itself ever changes, the `@module` paths in `Html.res` and
   the import source in all three places have to move together.
