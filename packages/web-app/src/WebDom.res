// Shared minimal DOM bindings for the plain-DOM scene code (no framework),
// matching the ethos of Main.res. The element type is aliased to `Html.element`
// so nodes cross freely between the two: a scene splices a node built here into
// the Preact tree with `Html.node`, and appends one rendered by `Html.create`
// with the bindings here.

type element = Html.element

@val @scope("document") external createElement: string => element = "createElement"
@send external appendChild: (element, element) => element = "appendChild"
@send external removeChild: (element, element) => element = "removeChild"
@send external remove: element => unit = "remove"
@send external setAttribute: (element, string, string) => unit = "setAttribute"
@send external removeAttribute: (element, string) => unit = "removeAttribute"
@send external addEventListener: (element, string, unit => unit) => unit = "addEventListener"
@set external setTextContent: (element, string) => unit = "textContent"

// Window-level listeners. The element bindings above hang a listener on a
// specific node, which the scene container's `clear` drops along with the node.
// A few events (device motion, orientation) only fire on `window`, so a scene
// that wants one must attach it here and — crucially — detach it in its teardown
// thunk, since clearing the container can't reach a listener that isn't on any
// scene node. Pass the *same* handler value to `removeWindowListener` that was
// given to `addWindowListener` for the removal to take. The handler is
// polymorphic over its event payload so a caller can bind whatever shape it reads.
@val @scope("window")
external addWindowListener: (string, 'event => unit) => unit = "addEventListener"
@val @scope("window")
external removeWindowListener: (string, 'event => unit) => unit = "removeEventListener"
@get external firstChild: element => Nullable.t<element> = "firstChild"

// Remove every child of an element — used to reset the shared scene container
// between scenes so the outgoing scene's nodes (and any animation they drive)
// are gone before the next one mounts.
let rec clear = parent =>
  switch parent->firstChild->Nullable.toOption {
  | Some(child) =>
    parent->removeChild(child)->ignore
    clear(parent)
  | None => ()
  }
