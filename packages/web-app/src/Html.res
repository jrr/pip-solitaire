// The JSX runtime: ReScript's *preserve* mode over Preact.
//
// ReScript 12 compiles this package with `"jsx": {"module": "Html", "preserve":
// true}`, which emits real JSX syntax into the `.res.mjs` output; esbuild (via
// Vite — see vite.config.js) lowers that JSX onto `preact/jsx-runtime`. So Preact
// owns the diff, and this module owns three things: the types the JSX transform
// checks against, the props a DOM element accepts, and the small surface the rest
// of the app calls (`string`, `array`, `node`, `create`, `mount`, `emit`/`on`).
//
// It replaced a hand-rolled vnode type and reconciler — about 400 lines, keys and
// all (#309). What the app gets for the ~5 KB gzip that Preact costs: somebody
// else's edge cases (namespaces, attribute-vs-property, event handling), and a
// hooks story available the day local component state is wanted (#308). What it
// keeps: the same Elm loop, the same `props => vnode` components, and node
// identity across a re-render, which is what stops a class change restarting a
// CSS transition (all three pinned in `Html_test`).
//
// Two things the binding shape must get exactly right, both discovered the hard
// way — get either wrong and preserve mode either silently stops preserving or
// emits JSX that no bundler can parse:
//
//   1. **The jsx functions must be `@module` externals.** With plain `let`
//      bindings the compiler quietly falls back to lowering JSX into calls on
//      this module, which is the old behaviour with none of the new runtime.
//   2. **The types must mirror `@rescript/react`'s**: `component<'props>` is a
//      transparent alias for `'props => vnode` (via `%component_identity`), and
//      `string`/`array` are `%identity`. An abstract component type makes
//      `<>…</>` emit `<prim => JsxRuntime.Fragment(prim)>`, which is not valid
//      JSX; a non-identity `array` wraps every children list in a runtime call.
//
// The same three esbuild settings appear in vite.config.js (twice — the build and
// the dev server's dependency scanner take different paths), in vitest.config.js,
// and in scripts/lib/load-jsx-module.mjs for the Node scripts. Nothing checks that
// they agree; `mise run dev-smoke` is what catches it when they don't.

// A real DOM node. Unchanged meaning: this is what `Html.node` splices, what
// `Html.create` answers with, and what the scenes hand around.
type element
type domEvent

// A Preact vnode — the *description* of an element, which `render` reconciles
// against the real DOM. Opaque here: nothing in the app inspects one any more
// (the one place that did, `StaticRender`, now serializes through Preact).
type vnode

// --- Components --------------------------------------------------------------
// A component is a plain function from its props to a vnode, exactly as before.
// `component` is a transparent alias rather than an abstract type — the JSX
// transform needs `Comp.make` (a `props => vnode`) to unify with the first
// argument of `jsx`, and `%component_identity` is what lets `@jsx.component`
// hand one over without a wrapper.
type componentLike<'props, 'return> = 'props => 'return
type component<'props> = componentLike<'props, vnode>
external component: componentLike<'props, vnode> => component<'props> = "%component_identity"

// --- Props -------------------------------------------------------------------
// The props a lowercase DOM element accepts: the attributes this app actually
// uses, each one a typed field. `@as` gives the exact DOM name where ReScript
// can't spell it — every hyphenated attribute, and `type` (a keyword).
//
// This replaced a generic `attrs?: array<(string, string)>` escape hatch, which
// was how the old hand-rolled runtime took attributes (it applied them with
// `setAttribute`). Preact reads props, so the pair-list needed a hook on
// `options.vnode` to expand it, and that hook had to special-case `("disabled",
// "")` — a presence flag to `setAttribute`, a falsy value to Preact. Both are
// gone: an attribute name is now checked by the compiler, and `disabled` is a
// `bool`.
//
// `@rescript/runtime` ships `JsxDOM.domProps`, which covers most of this list.
// It doesn't fit here for three reasons, each load-bearing: `style` is a typed
// record there, and `RasterScene` sets a CSS *custom property*; `ref` is an
// opaque React-shaped `domRef`, and the splice host below needs a callback; and
// its event types are React's synthetic ones rather than the DOM events Preact
// hands you. Adding a field when a new attribute is wanted is the cost, and a
// cheap one — it also means new attribute names get read by a reviewer.
type elementProps = {
  // --- structure and state ---
  id?: string,
  className?: string,
  hidden?: bool,
  disabled?: bool,
  @as("type") type_?: string,
  title?: string,
  role?: string,
  // A raw CSS declaration string. Kept a string rather than a typed record
  // because the raster scene passes a custom property (`--raster-card-w`).
  style?: string,
  onClick?: domEvent => unit,
  // A callback ref, called with the element on mount and `null` on unmount.
  // This is Preact's splice point, and what `node` below is built on.
  ref?: Nullable.t<element> => unit,
  // Raw markup, for the one place that needs it: the embedded <style> in the
  // card raster's standalone SVG. Preact escapes text children (including
  // quotes, which the old serializer left alone), so a stylesheet written as a
  // text child comes out with `&quot;` in it — valid XML, needless difference.
  dangerouslySetInnerHTML?: {"__html": string},
  children?: vnode,
  // --- ARIA. Strings, not bools: these are enumerated attributes whose value
  // is the literal text "true"/"false", and an absent one differs from "false".
  @as("aria-label") ariaLabel?: string,
  @as("aria-hidden") ariaHidden?: string,
  @as("aria-live") ariaLive?: string,
  @as("aria-busy") ariaBusy?: string,
  @as("aria-checked") ariaChecked?: string,
  @as("aria-disabled") ariaDisabled?: string,
  // --- data-*, read by the browser tests and by CSS ---
  @as("data-rendering") dataRendering?: string,
  @as("data-raster") dataRaster?: string,
  // --- SVG. The card art, the app icon and the spinner are all real vector
  // nodes (see CardArt), so the geometry lives here rather than in a stylesheet.
  xmlns?: string,
  viewBox?: string,
  focusable?: string,
  width?: string,
  height?: string,
  x?: string,
  y?: string,
  dx?: string,
  dy?: string,
  rx?: string,
  ry?: string,
  cx?: string,
  cy?: string,
  r?: string,
  d?: string,
  fill?: string,
  stroke?: string,
  @as("stroke-width") strokeWidth?: string,
  @as("stroke-linejoin") strokeLinejoin?: string,
  transform?: string,
  filter?: string,
  offset?: string,
  @as("stop-color") stopColor?: string,
  gradientUnits?: string,
  stdDeviation?: string,
  @as("flood-color") floodColor?: string,
  @as("flood-opacity") floodOpacity?: string,
  @as("font-size") fontSize?: string,
  @as("font-family") fontFamily?: string,
  @as("font-weight") fontWeight?: string,
  @as("text-anchor") textAnchor?: string,
}

type fragmentProps = {children?: vnode}

// --- The JSX transform's contract -------------------------------------------
// `<Comp prop=… />` → `jsx(Comp.make, props)`, `<div>…</div>` →
// `Elements.jsx("div", props)`, `<>…</>` → `jsx(jsxFragment, props)`, and the
// `*Keyed` variants when a `key=` is present. Under preserve mode none of these
// are actually *called*: they type-check the JSX and name the module the
// emitted `import` points at.
@module("preact/jsx-runtime") external jsx: (component<'props>, 'props) => vnode = "jsx"
@module("preact/jsx-runtime") external jsxs: (component<'props>, 'props) => vnode = "jsxs"
@module("preact/jsx-runtime")
external jsxKeyed: (component<'props>, 'props, ~key: string=?, unit) => vnode = "jsx"
@module("preact/jsx-runtime")
external jsxsKeyed: (component<'props>, 'props, ~key: string=?, unit) => vnode = "jsxs"
@module("preact/jsx-runtime") external jsxFragment: component<fragmentProps> = "Fragment"

module Elements = {
  type props = elementProps
  external someElement: 'a => option<vnode> = "%identity"
  @module("preact/jsx-runtime") external jsx: (string, props) => vnode = "jsx"
  @module("preact/jsx-runtime") external jsxs: (string, props) => vnode = "jsxs"
  @module("preact/jsx-runtime")
  external jsxKeyed: (string, props, ~key: string=?, unit) => vnode = "jsx"
  @module("preact/jsx-runtime")
  external jsxsKeyed: (string, props, ~key: string=?, unit) => vnode = "jsxs"
}

// Text and sibling groups. Both are `%identity` because Preact already accepts a
// string and an array as children — which is also why children now cost nothing
// at runtime, where the old runtime allocated a `VText`/`VGroup` for each.
external string: string => vnode = "%identity"
external array: array<vnode> => vnode = "%identity"

// --- Preact --------------------------------------------------------------
@module("preact") external renderInto: (vnode, element) => unit = "render"
@val @scope("document") external make: string => element = "createElement"
@send external appendChild: (element, element) => element = "appendChild"
@send external contains: (element, element) => bool = "contains"
@get external firstChild: element => Nullable.t<element> = "firstChild"
@get external childCount: element => int = "childElementCount"
@val @scope("document") external fragment: unit => element = "createDocumentFragment"

// --- Splicing a subtree we don't own -----------------------------------------
// The replacement for the old `VRaw` node: a host element whose children belong
// to somebody else (`SceneSwitcher`'s scene container, the debug console's
// scrollback, a rasterized card). Preact has no vnode that *is* a live DOM node,
// so the node goes in through a callback ref on a host element, and the host is
// `display: contents` (see styles/base.css) so it adds nothing to layout.
//
// This is the one structural difference the swap forces: the old runtime spliced
// the node in with no wrapper at all. A rule written as `.parent > .child`
// therefore stops matching across a splice — `RasterScene.css` had exactly one
// (`.raster-cell > .card-art`) and is now a descendant selector.
// (Written as a direct `Elements.jsx` call rather than as JSX: this module *is*
// the JSX module, so JSX inside it would resolve `Html` against itself.)
type rawHostProps = {node: element}
let rawHost = (props: rawHostProps) =>
  Elements.jsx(
    "div",
    {
      className: "raw-host",
      ref: el =>
        switch el->Nullable.toOption {
        | Some(host) =>
          // Preact calls a ref again whenever the callback's identity changes,
          // which is every re-render; only append the first time.
          if !contains(host, props.node) {
            appendChild(host, props.node)->ignore
          }
        | None => ()
        },
    },
  )

let node = el => jsx(rawHost, {node: el})

// --- Custom events (outward DOM CustomEvents) --------------------------------
// Unchanged, and independent of the runtime: a component defines its own events
// in ReScript (see OutwardEvents) and fires them from a host element with
// `emit`; `on` is the listener side. `composed` lets the event cross the
// shadow-DOM boundary.
type customEvent<'detail>
@new
external makeCustomEvent: (
  string,
  {"detail": 'detail, "bubbles": bool, "composed": bool},
) => customEvent<'detail> = "CustomEvent"
@send external dispatchEvent: (element, customEvent<'detail>) => bool = "dispatchEvent"

let emit = (host, ~name, ~detail) =>
  dispatchEvent(
    host,
    makeCustomEvent(name, {"detail": detail, "bubbles": true, "composed": true}),
  )->ignore

@get external eventDetail: customEvent<'detail> => 'detail = "detail"
@send
external addCustomListener: (element, string, customEvent<'detail> => unit) => unit =
  "addEventListener"

let on = (target, ~name, handler) =>
  addCustomListener(target, name, event => handler(eventDetail(event)))

// --- Rendering a vnode to a detached node ------------------------------------
// `create` answers with the real DOM node a vnode describes, for the callers
// that want a node rather than a view: `TableScene` builds each card's <svg>
// this way, and every component test renders through it under jsdom. Preact has
// no "render me a node" entry point, so it renders into a throwaway host and the
// node is lifted out of it.
// A component whose root is a fragment (`<>…</>`, which several menu screens
// are) renders as *several* top-level nodes, so the answer matches what the old
// runtime did with a `VGroup`: one node comes back as itself, several come back
// in a DocumentFragment — which `querySelector` searches and `appendChild`
// splices in without adding a wrapper.
let create = vnode => {
  let host = make("div")
  renderInto(vnode, host)
  switch (childCount(host), firstChild(host)->Nullable.toOption) {
  | (1, Some(el)) => el
  | _ =>
    let group = fragment()
    let rec drain = () =>
      switch firstChild(host)->Nullable.toOption {
      | Some(child) =>
        appendChild(group, child)->ignore
        drain()
      | None => ()
      }
    drain()
    group
  }
}

// --- A minimal Elm-style loop ------------------------------------------------
// Unchanged in shape and in contract: `update` is pure state and may return a
// command (a `unit => unit` effect, `noEffect` for none) run after the render.
// Each dispatch re-derives the whole view and hands it to Preact, which diffs it
// against the previous tree and patches in place — so an element whose class
// changed keeps its DOM node, and a running CSS animation on it is not
// restarted. (Verified in a browser: node identity survives re-renders.)
let noEffect = () => ()

let mount = (~root, ~init, ~update, ~view) => {
  let model = ref(init)
  let rec dispatch = msg => {
    let (next, effect) = update(msg, model.contents)

    // Re-render only when the model actually changed (physical equality): a
    // message that just fires an effect (e.g. a click reported outward) touches
    // no DOM at all.
    if next !== model.contents {
      model := next
      render()
    }
    effect()
  }
  and render = () => renderInto(view(model.contents, dispatch), root)
  render()
  dispatch
}
