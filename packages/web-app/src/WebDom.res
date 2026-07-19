// Shared minimal DOM bindings for the plain-DOM scene code (no framework),
// matching the ethos of Main.res. The element type is aliased to `Html.element`
// so nodes created here are accepted by the shared Events helpers (OutwardEvents
// / InwardEvents), which speak `Html.element`.

type element = Html.element

@val @scope("document") external createElement: string => element = "createElement"
@send external appendChild: (element, element) => element = "appendChild"
@send external removeChild: (element, element) => element = "removeChild"
@send external remove: element => unit = "remove"
@send external setAttribute: (element, string, string) => unit = "setAttribute"
@send external removeAttribute: (element, string) => unit = "removeAttribute"
@send external addEventListener: (element, string, unit => unit) => unit = "addEventListener"
@set external setTextContent: (element, string) => unit = "textContent"
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
