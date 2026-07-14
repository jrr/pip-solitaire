// A tiny hand-rolled JSX runtime — no React, no virtual DOM, no dependency.
//
// ReScript's *generic* JSX transform (enabled by `"jsx": {"module": "Html"}`
// in rescript.json) lowers JSX into calls on THIS module. We make `element` a
// real DOM node, so `<div/>` builds actual DOM directly. The mapping the
// compiler emits (discovered from its own output) is:
//
//   <div class=..>{x}</div>   →  Elements.jsx("div", {className:.., children:?someElement(x)})
//   <div>{a}{b}</div>         →  Elements.jsxs("div", {children:?Some(array([a, b]))})
//   <Comp prop=.. />          →  jsx(Comp.make, {prop:..})
//   <>{a}{b}</>               →  jsxs(jsxFragment, {children:?Some(array([a, b]))})
//
// So all we owe the transform is: element/text builders, `array` to combine
// siblings, `someElement` to wrap a single child, and jsx/jsxs/jsxFragment.

type element // a real DOM Node
type domEvent

@val @scope("document") external body: element = "body"
@val @scope("document") external make: string => element = "createElement"
@val @scope("document") external textNode: string => element = "createTextNode"
@val @scope("document") external fragment: unit => element = "createDocumentFragment"
@send external appendChild: (element, element) => element = "appendChild"
@send external replaceChildren: (element, element) => unit = "replaceChildren"
@send external setAttribute: (element, string, string) => unit = "setAttribute"
@send external addEventListener: (element, string, domEvent => unit) => unit = "addEventListener"

// --- Custom events (the generic "outward" seam for web components) -----------
// A component defines its own events in ReScript — name and detail shape — and
// fires them from a host element with `emit`. The JS shell that owns the
// custom-element class never has to know any of that; it just hands us the host.
// `composed: true` lets the event cross the shadow-DOM boundary.
type customEvent
@new
external makeCustomEvent: (
  string,
  {"detail": 'detail, "bubbles": bool, "composed": bool},
) => customEvent = "CustomEvent"
@send external dispatchEvent: (element, customEvent) => bool = "dispatchEvent"

let emit = (host, ~name, ~detail) =>
  dispatchEvent(
    host,
    makeCustomEvent(name, {"detail": detail, "bubbles": true, "composed": true}),
  )->ignore

// Text child helper: write `{Html.string("hi")}` inside JSX.
let string = textNode

// Combine sibling children into one node. A DocumentFragment appends flat, so
// no wrapper element shows up in the DOM.
let array = (children: array<element>) => {
  let frag = fragment()
  children->Array.forEach(c => appendChild(frag, c)->ignore)
  frag
}

// Capitalized <Component/> lowers to `jsx(Component.make, props)`; a component
// is just a function from its props record to an element.
let jsx = (component, props) => component(props)
let jsxs = jsx

// Fragments (<>…</>) are a component whose only prop is its (already-combined)
// children node.
type fragmentProps = {children?: element}
let jsxFragment = (props: fragmentProps) => props.children->Option.getOr(fragment())

module Elements = {
  // Props for lowercase DOM elements. Every field is optional (an omitted
  // attribute). Grow this record as the UI needs more (href, type_, value,
  // aria-*, draggable, …) — it's the one place attribute support is declared.
  type props = {
    id?: string,
    className?: string,
    hidden?: bool,
    onClick?: domEvent => unit,
    children?: element,
  }

  // The transform wraps a single child through `someElement`; after `array`
  // combining, children is always one node, so jsx and jsxs share a builder.
  let someElement = x => Some(x)

  let jsx = (tag: string, props: props) => {
    let el = make(tag)
    props.id->Option.forEach(v => setAttribute(el, "id", v))
    props.className->Option.forEach(v => setAttribute(el, "class", v))
    props.hidden->Option.forEach(v => v ? setAttribute(el, "hidden", "") : ())
    props.onClick->Option.forEach(f => addEventListener(el, "click", f))
    props.children->Option.forEach(c => appendChild(el, c)->ignore)
    el
  }
  let jsxs = jsx
}

// --- A minimal Elm-style loop ------------------------------------------------
// `update` is pure state, and may return a command (a `unit => unit` effect
// thunk, `noEffect` for none) run after the re-render. On every dispatch we
// rebuild `view(model)` and swap it in wholesale — no diffing. For a board of a
// few dozen nodes that's plenty; add keyed reconciliation later if profiling
// ever asks for it. Returns `dispatch` so effectful setup (event sources,
// service worker) can feed messages back in.
let noEffect = () => ()

let mount = (~root, ~init, ~update, ~view) => {
  let model = ref(init)
  let rec dispatch = msg => {
    let (next, effect) = update(msg, model.contents)
    model := next
    render()
    effect()
  }
  and render = () => replaceChildren(root, view(model.contents, dispatch))
  render()
  dispatch
}
