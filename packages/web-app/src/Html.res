// A tiny hand-rolled JSX runtime — no React, no framework, no dependency.
//
// ReScript's *generic* JSX transform ("jsx": {"module": "Html"} in rescript.json)
// lowers JSX into calls on THIS module. The view is a *description* — a `vnode`
// tree — and `mount` reconciles it against the real DOM: on each change it diffs
// the new tree against the previous one and patches in place, reusing DOM nodes
// wherever the shape matches. That reuse is what lets a state change update an
// element's class (say, to reverse a spin) without tearing the node down and
// restarting its CSS animation.
//
// The transform's contract (discovered from the compiler's own output):
//   <div class=..>{x}</div>   →  Elements.jsx("div", {className:.., children:?someElement(x)})
//   <div>{a}{b}</div>         →  Elements.jsxs("div", {children:?Some(array([a, b]))})
//   <Comp prop=.. />          →  jsx(Comp.make, {prop:..})
//   <>{a}{b}</>               →  jsxs(jsxFragment, {children:?Some(array([a, b]))})

type element // a real DOM Node
type domEvent
type nodeList

@val @scope("document") external make: string => element = "createElement"
@val @scope("document") external textNode: string => element = "createTextNode"
@val @scope("document") external fragment: unit => element = "createDocumentFragment"
@send external appendChild: (element, element) => element = "appendChild"
@send external removeChild: (element, element) => element = "removeChild"
@send
external replaceChild: (element, ~newNode: element, ~oldNode: element) => element = "replaceChild"
@send external setAttribute: (element, string, string) => unit = "setAttribute"
@send external removeAttribute: (element, string) => unit = "removeAttribute"
@set external setTextContent: (element, string) => unit = "textContent"
@send external addEventListener: (element, string, domEvent => unit) => unit = "addEventListener"
@get external childNodes: element => nodeList = "childNodes"
@send external nodeAt: (nodeList, int) => element = "item"
@get external lastChild: element => Nullable.t<element> = "lastChild"

// The current click handler is stashed on the node itself, so one stable
// listener can forward to it. Patching then swaps the handler by re-stashing —
// no add/removeEventListener churn, and no dangling closures.
@set external setClick: (element, option<domEvent => unit>) => unit = "_onClick"
@get external getClick: element => option<domEvent => unit> = "_onClick"

// --- Custom events (outward DOM CustomEvents) --------------------------------
// A component defines its own events in ReScript (see OutwardEvents) and fires
// them from a host element with `emit`; `on` is the listener side. `composed`
// lets the event cross the shadow-DOM boundary.
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

// --- Virtual nodes -----------------------------------------------------------
type rec vnode =
  | VNode({tag: string, props: elementProps, children: array<vnode>})
  | VText(string)
  | VGroup(array<vnode>) // sibling group from `array`; flattened when materialised
and elementProps = {
  id?: string,
  className?: string,
  hidden?: bool,
  onClick?: domEvent => unit,
  children?: vnode,
}

// Text child: `{Html.string("hi")}` inside JSX.
let string = s => VText(s)
// Combine sibling children; flattened out when a node's children are built.
let array = xs => VGroup(xs)

// Capitalized <Component/> → jsx(Component.make, props); a component is just a
// function from its props to a vnode.
let jsx = (component, props) => component(props)
let jsxs = jsx

// Fragments (<>…</>): a component whose only prop is its already-combined children.
type fragmentProps = {children?: vnode}
let jsxFragment = (props: fragmentProps) => props.children->Option.getOr(VGroup([]))

// Expand VGroups so a node's children are a flat list of VNode/VText, each of
// which maps to exactly one real DOM node (keeps the positional diff simple).
let childrenOf = (c: option<vnode>): array<vnode> => {
  let acc = []
  let rec go = n =>
    switch n {
    | VGroup(xs) => xs->Array.forEach(go)
    | leaf => acc->Array.push(leaf)
    }
  c->Option.forEach(go)
  acc
}

module Elements = {
  // Props for lowercase DOM elements. Grow this record as the UI needs more
  // (href, type_, value, draggable, aria-*, …) — the one place attributes live.
  type props = elementProps
  // The transform wraps a single child through `someElement`; after `array`
  // combining, children is one vnode, so jsx and jsxs share a builder.
  let someElement = x => Some(x)
  let jsx = (tag: string, props: props) => VNode({tag, props, children: childrenOf(props.children)})
  let jsxs = jsx
}

// --- Reconciler --------------------------------------------------------------
// Set/clear the flat attributes an elementProps can carry, idempotently — the
// same function serves both creation and patching (absent field => removed).
let applyProps = (el, props: elementProps) => {
  switch props.id {
  | Some(v) => setAttribute(el, "id", v)
  | None => removeAttribute(el, "id")
  }
  switch props.className {
  | Some(v) => setAttribute(el, "class", v)
  | None => removeAttribute(el, "class")
  }
  switch props.hidden {
  | Some(true) => setAttribute(el, "hidden", "")
  | _ => removeAttribute(el, "hidden")
  }
  setClick(el, props.onClick)
}

// Build a real DOM node from a vnode (used for first render and for subtrees the
// diff decides to replace wholesale).
let rec create = vnode =>
  switch vnode {
  | VText(s) => textNode(s)
  | VGroup(xs) =>
    let frag = fragment()
    xs->Array.forEach(x => appendChild(frag, create(x))->ignore)
    frag
  | VNode({tag, props, children}) =>
    let el = make(tag)
    applyProps(el, props)
    // One listener, attached once; it forwards to whatever handler is stashed.
    addEventListener(el, "click", ev =>
      switch getClick(el) {
      | Some(h) => h(ev)
      | None => ()
      }
    )
    children->Array.forEach(c => appendChild(el, create(c))->ignore)
    el
  }

// Patch one DOM node to match `newV`, given the `oldV` it currently reflects.
let rec patch = (parent, dom, oldV, newV) =>
  switch (oldV, newV) {
  | (VText(a), VText(b)) =>
    if a != b {
      setTextContent(dom, b)
    }
  | (VNode({tag: t1, children: oldKids, _}), VNode({tag: t2, props, children: newKids, _}))
    if t1 == t2 =>
    // Same tag → reuse this node: just update its attributes and its children.
    applyProps(dom, props)
    patchChildren(dom, oldKids, newKids)
  | (_, _) => replaceChild(parent, ~newNode=create(newV), ~oldNode=dom)->ignore
  }
// Positional diff of a parent's children: patch the overlap, then append or
// trim the tail. No keys yet — fine for fixed structure; add keys when a list
// can reorder.
and patchChildren = (parent, oldKids, newKids) => {
  let oldLen = Array.length(oldKids)
  let newLen = Array.length(newKids)
  let shared = oldLen < newLen ? oldLen : newLen
  for i in 0 to shared - 1 {
    patch(
      parent,
      nodeAt(childNodes(parent), i),
      oldKids->Array.getUnsafe(i),
      newKids->Array.getUnsafe(i),
    )
  }
  for i in oldLen to newLen - 1 {
    appendChild(parent, create(newKids->Array.getUnsafe(i)))->ignore
  }
  for _ in 1 to oldLen - newLen {
    switch lastChild(parent)->Nullable.toOption {
    | Some(n) => removeChild(parent, n)->ignore
    | None => ()
    }
  }
}

// --- A minimal Elm-style loop ------------------------------------------------
// `update` is pure state and may return a command (a `unit => unit` effect,
// `noEffect` for none) run after the patch. Each dispatch re-derives the view
// and reconciles it against the previous one, so unchanged nodes stay put.
let noEffect = () => ()

let mount = (~root, ~init, ~update, ~view) => {
  let model = ref(init)
  let prev = ref([]) // previous flattened top-level children
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
  and render = () => {
    let nextKids = childrenOf(Some(view(model.contents, dispatch)))
    patchChildren(root, prev.contents, nextKids)
    prev := nextKids
  }
  render()
  dispatch
}
