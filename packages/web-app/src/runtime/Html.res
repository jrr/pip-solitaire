// The JSX runtime: ReScript's *preserve* mode over Preact. Preact owns the diff;
// this module owns only the type surface that arrangement needs, plus the small
// API the app calls (`string`, `array`, `empty`, `node`, `create`, `mount`).
//
// **The pipeline, and the four places the same three esbuild settings are
// duplicated, are in `docs/rendering.md`.** Read it before changing anything about
// the build: nothing checks that those four agree, and `mise run dev-smoke` is the
// only task that catches them when they don't.
//
// Hooks are available in principle, but see `create` below for the large
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
// The props a lowercase DOM element accepts. Every attribute is a field here and
// there is no escape hatch, so reaching for a new one means editing this record —
// with `@as` where ReScript can't spell the DOM name (every hyphenated attribute,
// and `type`, a keyword).
//
// Why this record rather than `@rescript/runtime`'s `JsxDOM.domProps`, and why
// values are props rather than `setAttribute` strings, are in
// `docs/rendering.md` § Attributes are typed props, not a string map.
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
  // --- text entry. The seed dialog's field is the only one the diff owns (the debug
  // console's input is live DOM the module holds itself), and it is *controlled*:
  // `value` is written from the model every render and `onInput` reports each
  // keystroke back, so what's on screen is a fact the loop holds rather than one
  // the DOM keeps to itself. `onSubmit` is the field's `<form>` — Enter (and a
  // phone keyboard's Go key) reaches the action through it, which a click handler
  // on the button alone would not.
  value?: string,
  placeholder?: string,
  // Lower-case: the DOM property is `inputMode`, so Preact finds no property of
  // this name and sets the attribute, which is what the browser reads.
  @as("inputmode") inputMode?: string,
  autocomplete?: string,
  onInput?: domEvent => unit,
  onSubmit?: domEvent => unit,
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
  @as("aria-modal") ariaModal?: string,
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

// --- Reading an event ---------------------------------------------------------
// The two things a handler here ever asks of the event it was given: don't do
// the browser's default (a form submit is a page navigation otherwise), and what
// is in the field this came from — an `input` event carries no value of its own,
// so the text is read off the element the event is on.
@send external preventDefault: domEvent => unit = "preventDefault"
@get external eventTarget: domEvent => element = "target"
@get external fieldValue: element => string = "value"
let inputValue = (event: domEvent): string => event->eventTarget->fieldValue

// --- The JSX transform's contract -------------------------------------------
// **These must stay `@module` externals, and the types above must mirror
// `@rescript/react`'s.** Get either wrong and preserve mode silently stops
// preserving, or emits JSX no bundler can parse — with no error anywhere to say
// so. What each one buys, and the contract itself, are in `docs/rendering.md`
// § What the binding shape has to get right.
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
// A host element holding a live DOM node somebody else owns. **The host sits
// between parent and child, so a CSS child combinator won't reach across one** —
// write `.parent .child`, not `.parent > .child`. How the splice works, and what
// it costs, are in `docs/rendering.md` § Splicing a subtree the diff doesn't own.
//
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
// The real DOM node a vnode describes, for a caller that wants a node rather than
// a view. The answer has two shapes: one top-level node comes back as itself,
// several (a component whose root is a fragment) come back in a `DocumentFragment`.
//
// **A component reachable from here must stay pure — no hooks, ever.** It renders
// exactly once and into a host that is then discarded, so `useState` and
// `useEffect` fail silently rather than loudly. `docs/rendering.md` § `create`
// renders once has the mechanism and how much of the app it covers.
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
// `update` is pure state and may return a command — a `unit => unit` effect,
// `noEffect` for none — which runs after the render.
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
