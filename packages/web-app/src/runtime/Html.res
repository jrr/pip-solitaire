// The JSX runtime: ReScript's *preserve* mode over Preact.
//
// The compiler emits real JSX into the `.res.mjs` output rather than lowering it,
// and esbuild (via Vite) lowers it onto `preact/jsx-runtime`. So Preact owns the
// diff, and this module owns three things: the types the JSX transform checks
// against, the props a DOM element accepts, and the small surface the rest of the
// app calls (`string`, `array`, `empty`, `node`, `create`, `mount`).
//
// **The pipeline, the four places the same three esbuild settings are duplicated,
// and what the app leans on Preact for are in `docs/rendering.md`.** Read that
// before changing anything about the build; nothing checks that those four agree,
// and `mise run dev-smoke` is the only task that catches them when they don't.
//
// Hooks are available in principle (#308), but see `create` below for the large
// part of this app where they are not.

// A real DOM node: what `Html.node` splices, what `Html.create` answers with, and
// what the scenes hand around.
type element
type domEvent

// A Preact vnode — the *description* of an element, which `render` reconciles
// against the real DOM. Opaque here: nothing in the app inspects one —
// `StaticRender` serializes through Preact rather than walking a vnode.
type vnode

// --- Components --------------------------------------------------------------
// A component is a plain function from its props to a vnode.
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
// There is no generic escape hatch: an attribute this record doesn't name can't be
// set, so an attribute name is checked by the compiler. Values are props, not
// `setAttribute` strings — `disabled` is a `bool`, not a presence flag.
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
  // `<details>`. Written on mount and thereafter left alone — Preact writes a prop
  // only when its value changes, so a disclosure the app opens once stays the
  // reader's to open and close (see `MenuDisclosure`).
  @as("open") open_?: bool,
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
  @as("aria-current") ariaCurrent?: string,
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
//
// Two things the binding shape must get exactly right — get either wrong and
// preserve mode either silently stops preserving or emits JSX that no bundler
// can parse:
//
//   1. **These must stay `@module` externals.** With plain `let` bindings the
//      compiler quietly falls back to lowering JSX into calls on this module,
//      which is the old behaviour with none of the new runtime.
//   2. **The types above must mirror `@rescript/react`'s**: `component<'props>`
//      a transparent alias for `'props => vnode` (via `%component_identity`),
//      `string`/`array` `%identity`. An abstract component type makes `<>…</>`
//      emit `<prim => JsxRuntime.Fragment(prim)>`, which is not valid JSX; a
//      non-identity `array` wraps every children list in a runtime call.
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
// string and an array as children, so neither costs anything at runtime.
external string: string => vnode = "%identity"
external array: array<vnode> => vnode = "%identity"

// Nothing at all — the branch of a conditional that has no node to show. A dozen
// such branches across the app each spelled this `array([])`, which reads as "an
// empty group of children" where what it means is "nothing". `null` is what Preact
// itself takes for nothing, and unlike a fresh `[]` per call site it is a value
// there is only one of.
let empty: vnode = %raw("null")

// --- Preact --------------------------------------------------------------
@module("preact") external renderInto: (vnode, element) => unit = "render"
@val @scope("document") external make: string => element = "createElement"
@send external appendChild: (element, element) => element = "appendChild"
@send external replaceChildren: (element, element) => unit = "replaceChildren"
@send external contains: (element, element) => bool = "contains"
@get external firstChild: element => Nullable.t<element> = "firstChild"
@get external childCount: element => int = "childElementCount"
@val @scope("document") external fragment: unit => element = "createDocumentFragment"

// --- Splicing a subtree we don't own -----------------------------------------
// A host element whose children belong to somebody else (`SceneSwitcher`'s scene
// container, the debug console's scrollback, a rasterized card). Preact has no
// vnode that *is* a live DOM node, so the node goes in through a callback ref on a
// host element, and the host is `display: contents` (see styles/base.css) so it
// adds nothing to layout.
//
// **A splice puts this host between parent and child, so a CSS child combinator
// won't reach across one.** Write `.parent .child`, not `.parent > .child`
// (`RasterScene.css`'s `.raster-cell .card-art` is the one that had to learn this).
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
          // which is every re-render, so this runs constantly — hence the guard,
          // which skips the work once the node is where it belongs.
          //
          // `replaceChildren` rather than `appendChild` for the case where it
          // isn't: a host handed a *different* node than last time must end up
          // holding that one rather than both. Every call site today hands over a
          // node that is stable for the life of its position, so nothing depends
          // on this — which is exactly why it should be the host's rule and not
          // an unwritten condition on eight callers (a duplicated node would show
          // up as a doubled scene or a doubled log, with nothing to point at).
          if !contains(host, props.node) {
            replaceChildren(host, props.node)
          }
        | None => ()
        },
    },
  )

let node = el => jsx(rawHost, {node: el})

// --- Rendering a vnode to a detached node ------------------------------------
// `create` answers with the real DOM node a vnode describes, for the callers
// that want a node rather than a view: `TableScene` builds each card's <svg>
// this way, and every component test renders through it under jsdom. Preact has
// no "render me a node" entry point, so it renders into a throwaway host and the
// nodes are lifted out of it — one comes back as itself, several (a component
// whose root is a fragment) in a DocumentFragment. See `docs/rendering.md`.
//
// **What comes back is a node, not a mounted tree, and this is the one rule to
// know before reaching for hooks (#308).** The host is thrown away, so nothing
// ever renders into it again: a component reached through `create` renders
// exactly once, for ever. `useState` in one would hold state that no re-render
// could ever read back, and a `useEffect` cleanup would never run — both failing
// silently, which is the worst way for a constraint to be discovered.
//
// So: **a component reachable from `create` must stay pure.** Hooks are only
// meaningful inside the tree `mount` owns and diffs. That covers more of the app
// than it sounds like — `TableScene` builds all 52 cards this way, and every
// component test in the package renders through here — so it is closer to a
// property of the component layer than to a caveat on one function.
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
