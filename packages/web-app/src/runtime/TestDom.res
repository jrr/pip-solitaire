// The DOM vocabulary the unit tests share.
//
// Every component test asks the same handful of questions of a rendered node — find
// one, find all of them, read its text, read an attribute, click it — so they ask them
// through here rather than each declaring its own externals. That duplication runs deep
// when it's allowed to: `querySelector` seventeen times across the package,
// `textContent` fourteen, `click` nine, `getAttribute` eight, and byte-identical copies
// of
//
//     let find = (el, selector) => el->querySelector(selector)->Nullable.toOption
//
// Nothing here is behaviour of its own; it is the same calls with the
// `Nullable`/`NodeList` unwrapping done once rather than per file, which is the part
// that gets copied.
//
// Two conveniences worth naming, because they're what a file that goes around this one
// ends up reimplementing:
//
//   - **`findAll` answers with an array.** A `NodeList` isn't one, so draining it is the
//     same `for` loop in every file that asks. It goes here instead, and the list type
//     stays private.
//   - **`textIn` / `attrOr` fall back to `"<missing>"`.** Asserting on
//     `"<missing>"` rather than on `None` is what makes a failure read as *the
//     element wasn't there* rather than as a type mismatch, and it's the
//     convention the tests are written to.
//
// It lives in `src/runtime/` rather than beside the tests because a leaf package's modules
// are namespaced flat (`WebApp.TestDom`), so every directory under `src/` reaches it
// alike. Nothing in the app imports it, so the bundle never sees it.
//
// Not for the browser suite: that drives a real page through Playwright's own
// locators and has no use for any of this.

// The element type is `Html.element`, which `WebDom.element` is an alias of — so a
// node built by either half of the app is accepted here.
type element = Html.element

// The two live collections the DOM hands back. Private: a test gets an array.
type nodeList
type htmlCollection

@send external querySelector: (element, string) => Nullable.t<element> = "querySelector"
@send external querySelectorAll: (element, string) => nodeList = "querySelectorAll"
@get external listLength: nodeList => int = "length"
@send external listItem: (nodeList, int) => element = "item"
@get external childElements: element => htmlCollection = "children"
@get external collLength: htmlCollection => int = "length"
@send external collItem: (htmlCollection, int) => element = "item"

@get external textContent: element => string = "textContent"
@get external className: element => string = "className"
@get external tagName: element => string = "tagName"
@get external childElementCount: element => int = "childElementCount"
@send external getAttribute: (element, string) => Nullable.t<string> = "getAttribute"
@send external hasAttribute: (element, string) => bool = "hasAttribute"
@send external containsNode: (element, element) => bool = "contains"
@send external clickNode: element => unit = "click"
@val @scope("document") external createElement: string => element = "createElement"

// Driving a field: its text, and the events a browser would emit around it.
type event
@set external setValue: (element, string) => unit = "value"
@new external makeEvent: (string, {"bubbles": bool, "cancelable": bool}) => event = "Event"
@send external dispatchEvent: (element, event) => bool = "dispatchEvent"

// --- Finding ------------------------------------------------------------------

// The first descendant matching `selector`, if there is one.
let find = (root: element, selector: string): option<element> =>
  root->querySelector(selector)->Nullable.toOption

// Every descendant matching `selector`, in document order. An array, not the live
// `NodeList` the DOM answers with — a test wants `map`/`length`/`toEqual`.
let findAll = (root: element, selector: string): array<element> => {
  let found = root->querySelectorAll(selector)
  let out = []
  for i in 0 to found->listLength - 1 {
    out->Array.push(found->listItem(i))
  }
  out
}

// Is there one at all? The question a "…and nothing else renders it" assertion asks.
let has = (root: element, selector: string): bool => root->find(selector)->Option.isSome

// The element's own child elements, as an array (text nodes excluded, as `children`
// always has). What a test counts when the *shape* of a subtree is the point.
let children = (el: element): array<element> => {
  let found = el->childElements
  let out = []
  for i in 0 to found->collLength - 1 {
    out->Array.push(found->collItem(i))
  }
  out
}

let childCount = (el: element): int => el->childElementCount

let contains = (parent: element, child: element): bool => parent->containsNode(child)

// --- Reading ------------------------------------------------------------------

let text = (el: element): string => el->textContent
let classes = (el: element): string => el->className
let tag = (el: element): string => el->tagName

let attr = (el: element, name: string): option<string> => el->getAttribute(name)->Nullable.toOption

// What a field is showing. The *property*, not the `value` attribute: a controlled
// input is written by the diff as a property, and the attribute keeps whatever it
// was rendered with, so only this answers "what would the player see in there".
@get external valueProperty: element => string = "value"
let value = (el: element): string => el->valueProperty

let hasAttr = (el: element, name: string): bool => el->hasAttribute(name)

// The text of the first match, or `"<missing>"` when nothing matched — so a failed
// assertion reads as "the element wasn't there" rather than as an empty string that
// could equally mean it was there and blank.
let textIn = (root: element, selector: string): string =>
  root->find(selector)->Option.mapOr("<missing>", text)

// The same fallback for an attribute, for the same reason: absent and `""` are
// different answers and a test should be able to tell them apart.
let attrOr = (el: element, name: string): string => el->attr(name)->Option.getOr("<missing>")

// --- Acting -------------------------------------------------------------------

let click = (el: element): unit => el->clickNode

// Type into a field: put the text in, then let the `input` event out. Two steps
// because a synthetic event carries no text of its own — a handler reads it off the
// element (see `Html.inputValue`), so setting the value without the event changes
// nothing the app can see, and firing the event without setting it reports "".
//
// `bubbles`, as a real keystroke's does, so a listener anywhere up the tree sees it
// and not only one sitting on the field.
let typeInto = (el: element, text: string): unit => {
  el->setValue(text)
  el->dispatchEvent(makeEvent("input", {"bubbles": true, "cancelable": false}))->ignore
}

// Submit a form the way Enter does. `cancelable`, or the handler's
// `preventDefault` would have nothing to prevent — and jsdom, which has no
// navigation to perform, would complain about the submission it can't carry out.
let submit = (form: element): unit =>
  form->dispatchEvent(makeEvent("submit", {"bubbles": true, "cancelable": true}))->ignore

// A detached element to render or mount into. jsdom gives a document; this is the
// throwaway root the loop-driving tests hang their tree from.
let host = (tag: string): element => createElement(tag)
