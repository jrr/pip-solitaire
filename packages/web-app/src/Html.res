// The JSX runtime — SPIKE: ReScript's *preserve* mode over Preact.
//
// This file used to be a hand-rolled vnode type plus a reconciler (~400 lines we
// owned). It is now a set of *bindings*: ReScript 12's `"preserve": true` emits
// real JSX syntax into the `.res.mjs` output, and esbuild (via Vite, see
// vite.config.js) lowers that JSX onto `preact/jsx-runtime`. Preact owns the
// diff; this module owns only the shapes the JSX transform type-checks against
// and the small compatibility surface the rest of the app already calls.
//
// **The module's public API is deliberately unchanged**, so no component, scene
// or test had to be rewritten to try this: `Html.string`, `Html.array`,
// `Html.node`, `Html.create`, `Html.mount`, `Html.emit`/`Html.on` all still mean
// what they meant. What changed is what happens underneath them.
//
// Two things the binding shape must get exactly right, both discovered the hard
// way — get either wrong and preserve mode either silently stops preserving or
// emits JSX that no bundler can parse:
//
//   1. **The jsx functions must be `@module` externals.** With plain `let`
//      bindings the compiler quietly falls back to lowering JSX into calls on
//      this module, which is the *old* behaviour with none of the new runtime.
//   2. **The types must mirror `@rescript/react`'s**: `component<'props>` is a
//      transparent alias for `'props => vnode` (via `%component_identity`), and
//      `string`/`array` are `%identity`. An abstract component type makes
//      `<>…</>` emit `<prim => JsxRuntime.Fragment(prim)>`, which is not valid
//      JSX; a non-identity `array` wraps every children list in a runtime call.

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
// The props a lowercase DOM element accepts. Same record the app has always
// written against, so every call site still compiles: `className`, `onClick`,
// the `hidden` flag, and the generic `attrs` escape hatch that carries SVG
// geometry and ARIA.
//
// `attrs` is *not* something Preact understands — a prop literally named
// "attrs" would be set as an attribute. `attrsShim.mjs` (installed below)
// expands each pair into a real prop before Preact ever diffs the vnode. That
// shim is the one piece of runtime magic in this spike, and the one thing a
// real migration would delete: the honest end state is `JsxDOM.domProps` from
// `@rescript/runtime` (a typed `viewBox`, `d`, `ariaLabel`, … surface) and no
// escape hatch at all.
type elementProps = {
  id?: string,
  className?: string,
  hidden?: bool,
  onClick?: domEvent => unit,
  // A callback ref, called with the element on mount and `null` on unmount.
  // This is Preact's splice point, and what `node` below is built on.
  ref?: Nullable.t<element> => unit,
  // Raw markup, for the one place that needs it: an embedded <style>. Preact
  // escapes text children (including quotes, which the old serializer left
  // alone), so a stylesheet written as a text child comes out with `&quot;` in
  // it. That parses back correctly as XML, but it is a needless difference in a
  // document that gets handed to a raster engine.
  dangerouslySetInnerHTML?: {"__html": string},
  attrs?: array<(string, string)>,
  children?: vnode,
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

// Expand `attrs` pairs into real props. Installed once, on module init, before
// anything can render.
@module("./attrsShim.mjs") external installAttrsShim: unit => unit = "install"
installAttrsShim()

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
