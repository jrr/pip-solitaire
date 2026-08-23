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
//   <div key=.. />            →  Elements.jsxKeyed("div", {..}, key, ())
//   <Comp key=.. />           →  jsxKeyed(Comp.make, {..}, key, ())
// — `key` is lifted out of the props record and passed on its own, so it is a
// property of the vnode rather than of the element (see `vnode` below).

type element // a real DOM Node
type domEvent
type nodeList

// HTML elements are created with `createElement`; SVG elements must be created
// in the SVG namespace with `createElementNS`, or the browser treats an <svg> /
// <path> as unknown HTML and never draws it. Which one a tag uses is decided by
// the `inSvg` flag threaded through create/patch below (an <svg> ancestor puts
// every descendant in this namespace).
@val @scope("document") external make: string => element = "createElement"
let svgNamespace = "http://www.w3.org/2000/svg"
@val @scope("document") external makeNS: (string, string) => element = "createElementNS"
@val @scope("document") external textNode: string => element = "createTextNode"
@val @scope("document") external fragment: unit => element = "createDocumentFragment"
@send external appendChild: (element, element) => element = "appendChild"
@send external removeChild: (element, element) => element = "removeChild"
// `before` is nullable on purpose: `insertBefore(node, null)` appends, so one
// call covers both "move this node to position i" and "put it on the end".
@send
external insertBefore: (element, ~newNode: element, ~before: Nullable.t<element>) => element =
  "insertBefore"
@send
external replaceChild: (element, ~newNode: element, ~oldNode: element) => element = "replaceChild"
@send external setAttribute: (element, string, string) => unit = "setAttribute"
@send external removeAttribute: (element, string) => unit = "removeAttribute"
@set external setTextContent: (element, string) => unit = "textContent"
@send external addEventListener: (element, string, domEvent => unit) => unit = "addEventListener"
@get external childNodes: element => nodeList = "childNodes"
// `item(i)` is null past the end of the list, which the placement pass below
// relies on to mean "append".
@send external nodeAt: (nodeList, int) => Nullable.t<element> = "item"

// The current click handler is stashed on the node itself, so one stable
// listener can forward to it. Patching then swaps the handler by re-stashing —
// no add/removeEventListener churn, and no dangling closures.
@set external setClick: (element, option<domEvent => unit>) => unit = "_onClick"
@get external getClick: element => option<domEvent => unit> = "_onClick"

// The keys of the generic `attrs` last applied to a node are stashed on the
// node too, so patching can remove any attribute that's gone in the new props
// without needing the old vnode — keeping `applyProps` idempotent (absent ⇒
// removed) on its own.
@set external setAttrKeys: (element, array<string>) => unit = "_attrKeys"
@get external getAttrKeys: element => Nullable.t<array<string>> = "_attrKeys"

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
// `key` is not a prop: ReScript's JSX transform lifts `key=` out of the props
// record and passes it as its own argument (to `jsxKeyed` rather than `jsx`),
// so it lives on the vnode itself. It identifies a child *across* a re-render,
// which is what lets `patchChildren` move a node instead of rebuilding it.
type rec vnode =
  | VNode({tag: string, key: option<string>, props: elementProps, children: array<vnode>})
  | VText(string)
  | VGroup(array<vnode>) // sibling group from `array`; flattened when materialised
  | VRaw(element) // an externally-owned real DOM node, spliced in untouched
and elementProps = {
  id?: string,
  className?: string,
  hidden?: bool,
  onClick?: domEvent => unit,
  // A generic attribute map — the escape hatch for anything without a typed
  // field above. This is what carries SVG geometry (`viewBox`, `d`, `fill`,
  // `x`/`y`, `transform`, hyphenated `stroke-width`, …), which is too open-ended
  // and too namespaced to spell out as record fields. Written as `[(name, value)
  // …]` in JSX; applied and patched idempotently by `applyProps`.
  attrs?: array<(string, string)>,
  children?: vnode,
}

// Text child: `{Html.string("hi")}` inside JSX.
let string = s => VText(s)
// Combine sibling children; flattened out when a node's children are built.
let array = xs => VGroup(xs)
// Splice a real DOM node, built elsewhere (imperatively), straight into the
// view — e.g. `{Html.node(sceneSwitcher)}`. The reconciler leaves it entirely
// alone across re-renders, so its owner keeps full control of its subtree.
let node = el => VRaw(el)

// Capitalized <Component/> → jsx(Component.make, props); a component is just a
// function from its props to a vnode.
let jsx = (component, props) => component(props)
let jsxs = jsx

// Attach a key to whatever a component rendered. A component is a plain
// function, so `<Card key=.. />` can only be keyed through its result: the key
// lands on the single element it returns. A component that renders text or a
// group has no one node to identify, so the key is dropped — key such a
// component's wrapper element instead.
let withKey = (key, vnode) =>
  switch (key, vnode) {
  | (Some(_), VNode({tag, props, children, _})) => VNode({tag, key, props, children})
  | (_, v) => v
  }

// <Component key=.. /> → jsxKeyed(Component.make, props, key, ()).
let jsxKeyed = (component, props, ~key=?, ()) => withKey(key, component(props))
let jsxsKeyed = jsxKeyed

// Fragments (<>…</>): a component whose only prop is its already-combined children.
type fragmentProps = {children?: vnode}
let jsxFragment = (props: fragmentProps) => props.children->Option.getOr(VGroup([]))

// Expand VGroups so a node's children are a flat list of VNode/VText, each of
// which maps to exactly one real DOM node — which is what lets `patchChildren`
// line children up with DOM nodes one for one, by key or by position.
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
  let jsx = (tag: string, props: props) => VNode({
    tag,
    key: None,
    props,
    children: childrenOf(props.children),
  })
  let jsxs = jsx
  // <div key=.. /> → jsxKeyed("div", props, key, ()): the transform hands the
  // key over separately rather than leaving it in the props record.
  let jsxKeyed = (tag: string, props: props, ~key=?, ()) => VNode({
    tag,
    key,
    props,
    children: childrenOf(props.children),
  })
  let jsxsKeyed = jsxKeyed
}

// The key a child was rendered with, if any. Only elements can carry one.
let keyOf = vnode =>
  switch vnode {
  | VNode({key, _}) => key
  | _ => None
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

  // Generic attributes: set every pair in the new map, and remove any attribute
  // that was in the *previous* map (stashed on the node) but is now gone — so an
  // attribute-only change patches in place and dropped attributes disappear.
  let newAttrs = props.attrs->Option.getOr([])
  let newKeys = newAttrs->Array.map(((k, _)) => k)
  switch getAttrKeys(el)->Nullable.toOption {
  | Some(oldKeys) =>
    oldKeys->Array.forEach(k =>
      if !(newKeys->Array.includes(k)) {
        removeAttribute(el, k)
      }
    )
  | None => ()
  }
  newAttrs->Array.forEach(((k, v)) => setAttribute(el, k, v))
  setAttrKeys(el, newKeys)
}

// Build a real DOM node from a vnode (used for first render and for subtrees the
// diff decides to replace wholesale). `inSvg` says whether this vnode sits under
// an <svg> ancestor — if so (or if it *is* the <svg>), it and its descendants
// are created in the SVG namespace so they render as vector graphics.
let rec create = (~inSvg=false, vnode) =>
  switch vnode {
  | VText(s) => textNode(s)
  | VRaw(el) => el
  | VGroup(xs) =>
    let frag = fragment()
    xs->Array.forEach(x => appendChild(frag, create(~inSvg, x))->ignore)
    frag
  | VNode({tag, props, children, _}) =>
    let inSvg = inSvg || tag == "svg"
    let el = inSvg ? makeNS(svgNamespace, tag) : make(tag)
    applyProps(el, props)
    // One listener, attached once; it forwards to whatever handler is stashed.
    addEventListener(el, "click", ev =>
      switch getClick(el) {
      | Some(h) => h(ev)
      | None => ()
      }
    )
    children->Array.forEach(c => appendChild(el, create(~inSvg, c))->ignore)
    el
  }

// Patch one DOM node to match `newV`, given the `oldV` it currently reflects,
// and answer with the node that now stands for `newV` — the same node when it
// was reused, a fresh one when the shapes were too different and it had to be
// replaced. `patchChildren` needs that answer to place the node afterwards.
// `inSvg` is threaded so a wholesale replacement rebuilds in the right namespace.
let rec patchInto = (~inSvg=false, parent, dom, oldV, newV) =>
  switch (oldV, newV) {
  | (VText(a), VText(b)) =>
    if a != b {
      setTextContent(dom, b)
    }
    dom
  | (VNode({tag: t1, children: oldKids, _}), VNode({tag: t2, props, children: newKids, _}))
    if t1 == t2 =>
    // Same tag → reuse this node: just update its attributes and its children.
    applyProps(dom, props)
    patchChildren(~inSvg=inSvg || t1 == "svg", dom, oldKids, newKids)
    dom
  | (VRaw(a), VRaw(b)) if a === b => dom // same externally-owned node → leave it be
  | (_, _) =>
    let fresh = create(~inSvg, newV)
    replaceChild(parent, ~newNode=fresh, ~oldNode=dom)->ignore
    fresh
  }

// Patch one DOM node in place, for callers that don't care which node came out.
and patch = (~inSvg=false, parent, dom, oldV, newV) =>
  patchInto(~inSvg, parent, dom, oldV, newV)->ignore
// Diff a parent's children. Each new child is *matched* to an old one, then
// patched onto that old child's DOM node, and finally the surviving nodes are
// put in the order the new list asks for.
//
// Matching is by key where there is one: a child rendered with `key="4S"` is
// matched to last render's `key="4S"` wherever it sat, so a list that reorders
// moves its nodes rather than rebuilding them. That matters because a rebuilt
// node is a *different* node — it loses any running CSS transition or WAAPI
// animation, its scroll position, and focus.
//
// A child with no key falls back to position, taking the next unkeyed old child
// in order. With nothing keyed that is exactly the positional diff this started
// as (child i matches old child i, the tail is appended or trimmed), so fixed
// structure keeps behaving as it always did and a list only pays for keys when
// it uses them. Mixing the two in one list is well defined for the same reason:
// the keyed children find each other by name, the rest line up by position.
//
// Sizes here are a card table's, not a feed's — a few dozen children — so the
// placement pass reads the live child list per slot rather than keeping an
// index of its own.
and patchChildren = (~inSvg=false, parent, oldKids, newKids) => {
  let oldLen = Array.length(oldKids)
  // The DOM nodes currently standing for `oldKids`, snapshotted: `childNodes` is
  // live, and the passes below move nodes about.
  let oldDoms = Array.fromInitializer(~length=oldLen, i =>
    nodeAt(childNodes(parent), i)->Nullable.toOption
  )

  // Where each key sat last time, and — for the children that had no key — the
  // old positions still up for grabs, oldest first.
  let byKey = Map.make()
  let unkeyed = []
  oldKids->Array.forEachWithIndex((v, i) =>
    switch keyOf(v) {
    | Some(k) => byKey->Map.set(k, i)
    | None => unkeyed->Array.push(i)
    }
  )
  let taken = Array.make(~length=oldLen, false)
  let nextUnkeyed = ref(0)

  // The old child this new one continues, if any.
  let matchFor = newV =>
    switch keyOf(newV) {
    | Some(k) => byKey->Map.get(k)
    | None =>
      let i = unkeyed->Array.get(nextUnkeyed.contents)
      nextUnkeyed := nextUnkeyed.contents + 1
      i
    }

  // Patch each new child onto its match (or build it fresh), collecting the
  // nodes in new-list order. Nothing is removed or moved yet, so a replacement
  // inside `patchInto` still finds the node it is replacing where it left it.
  let newDoms = newKids->Array.map(newV =>
    switch matchFor(newV) {
    | Some(i) if !(taken->Array.getUnsafe(i)) =>
      taken->Array.setUnsafe(i, true)
      switch oldDoms->Array.getUnsafe(i) {
      | Some(dom) => patchInto(~inSvg, parent, dom, oldKids->Array.getUnsafe(i), newV)
      | None => create(~inSvg, newV)
      }
    | _ => create(~inSvg, newV)
    }
  )

  // Whatever no new child claimed is gone from the view: drop it. (A node that
  // `patchInto` replaced was taken, so it is never removed twice.)
  oldDoms->Array.forEachWithIndex((dom, i) =>
    switch dom {
    | Some(n) if !(taken->Array.getUnsafe(i)) => removeChild(parent, n)->ignore
    | _ => ()
    }
  )

  // Put the survivors in order. `insertBefore` *moves* a node that is already
  // in this parent, which is what keeps identity across a reorder; past the end
  // of the list the reference node is null and it appends instead.
  newDoms->Array.forEachWithIndex((dom, i) => {
    let atSlot = nodeAt(childNodes(parent), i)
    switch atSlot->Nullable.toOption {
    | Some(here) if here === dom => ()
    | _ => insertBefore(parent, ~newNode=dom, ~before=atSlot)->ignore
    }
  })
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
