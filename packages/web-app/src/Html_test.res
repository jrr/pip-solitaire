// Tests for the hand-rolled `Html` runtime — its SVG support (#35) and its
// keyed child diffing (#309).
//
// SVG support (#35):
//   1. <svg> and its descendants are created in the SVG namespace (so a browser
//      draws them as vector graphics), while ordinary HTML tags are not.
//   2. Generic `attrs` (viewBox, d, fill, hyphenated stroke-width, …) are set.
//   3. An attribute-only change *patches the existing node in place* — the same
//      DOM node is reused, its attribute updated, and a dropped attribute
//      removed — rather than tearing the subtree down and rebuilding it.
//
// Keyed diffing (#309): a child rendered with a `key` is matched to last
// render's child with the same key wherever it moved to, so reordering a list
// *moves* its DOM nodes instead of rebuilding them. Every assertion below turns
// on physical node identity (`===`), because that is the whole property: a
// rebuilt node is a different node, and loses whatever was live on the old one
// — a running CSS transition or WAAPI animation, focus, scroll position.
//
// These run under jsdom (see vitest.config.js), which implements namespaces and
// attribute reflection.
open Vitest

let svgNS = "http://www.w3.org/2000/svg"
let htmlNS = "http://www.w3.org/1999/xhtml"

// A few read-side DOM bindings the runtime itself doesn't need but the assertions
// do. `Html.element` so they line up with the nodes `Html.create` returns.
@get external namespaceURI: Html.element => string = "namespaceURI"
@send external getAttribute: (Html.element, string) => Nullable.t<string> = "getAttribute"
@get external firstChild: Html.element => Html.element = "firstChild"

// The parent's live children, as an array, for the identity assertions below.
type nodeList
@get external childNodes: Html.element => nodeList = "childNodes"
@send external nodeAt: (nodeList, int) => Html.element = "item"
@get external nodeCount: nodeList => int = "length"
let kidsOf = parent => {
  let list = childNodes(parent)
  Array.fromInitializer(~length=nodeCount(list), i => nodeAt(list, i))
}
// Each child is labelled by its `id`, so a list reads as ["a", "b", "c"] and a
// failure says which child ended up where rather than just "not the same node".
let labelsOf = parent =>
  kidsOf(parent)->Array.map(n => getAttribute(n, "id")->Nullable.getOr("<none>"))

// Are these the very same DOM nodes, in this order? It has to be `===` node by
// node: `toEqual` compares DOM nodes *structurally*, and a node rebuilt from the
// same vnode is structurally equal to the one it replaced — which is precisely
// the difference these tests exist to catch. Order is asserted separately with
// `labelsOf`, which is what gives a readable diff when one of these fails.
let sameNodes = (actual, expected) =>
  Array.length(actual) == Array.length(expected) &&
    actual->Array.everyWithIndex((n, i) => n === expected->Array.getUnsafe(i))

describe("Html SVG support", () => {
  test("creates <svg> and its descendants in the SVG namespace", () => {
    let dom = Html.create(
      <svg>
        <circle />
      </svg>,
    )
    expect(namespaceURI(dom))->toBe(svgNS)
    expect(namespaceURI(firstChild(dom)))->toBe(svgNS)
  })

  test("keeps ordinary HTML tags in the HTML namespace", () => {
    let dom = Html.create(
      <div>
        <span />
      </div>,
    )
    expect(namespaceURI(dom))->toBe(htmlNS)
    expect(namespaceURI(firstChild(dom)))->toBe(htmlNS)
  })

  test("sets generic attributes, including hyphenated ones", () => {
    let dom = Html.create(
      <svg attrs={[("viewBox", "0 0 10 10"), ("stroke-width", "2")]}>
        <circle />
      </svg>,
    )
    expect(getAttribute(dom, "viewBox")->Nullable.toOption)->toEqual(Some("0 0 10 10"))
    expect(getAttribute(dom, "stroke-width")->Nullable.toOption)->toEqual(Some("2"))
  })

  test("patches an attribute change in place, reusing the node", () => {
    // Render an initial <svg><circle fill=red .../></svg> into a container.
    let before =
      <svg>
        <circle attrs={[("fill", "red"), ("r", "5")]} />
      </svg>
    let container = Html.create(<div />)
    Html.patchChildren(container, [], [before])

    let circleBefore = firstChild(firstChild(container))
    expect(getAttribute(circleBefore, "fill")->Nullable.toOption)->toEqual(Some("red"))

    // Patch to a new tree that only changes `fill` and drops `r`.
    let after =
      <svg>
        <circle attrs={[("fill", "blue")]} />
      </svg>
    Html.patchChildren(container, [before], [after])

    let circleAfter = firstChild(firstChild(container))
    // Same physical DOM node — patched, not recreated.
    expect(circleAfter === circleBefore)->toBe(true)
    // The changed attribute is updated…
    expect(getAttribute(circleAfter, "fill")->Nullable.toOption)->toEqual(Some("blue"))
    // …and the dropped attribute is removed (idempotent: absent ⇒ removed).
    expect(getAttribute(circleAfter, "r")->Nullable.toOption)->toEqual(None)
  })
})

// A stand-in for the `<Card>` this was all for: a component, so the key has to
// travel through a `props => vnode` function to reach a DOM node.
module Item = {
  type props = {label: string}
  let make = ({label}: props) => <div id={label} />
}

// A card in a pile, near enough: one element per id, identified by its key.
let keyed = ids => ids->Array.map(id => <div key={id} id={id} />)
// The same list with no keys at all — the fallback the runtime started with.
let unkeyed = ids => ids->Array.map(id => <div id={id} />)

// Render `first` into a fresh parent and hand back the parent with the nodes it
// got, so a later patch can be checked against the *original* node identities.
let render = first => {
  let parent = Html.create(<div />)
  Html.patchChildren(parent, [], first)
  (parent, kidsOf(parent))
}

describe("Html keyed diffing (#309)", () => {
  test("moves nodes on a reorder instead of rebuilding them", () => {
    let before = keyed(["a", "b", "c"])
    let (parent, original) = render(before)

    let after = keyed(["c", "a", "b"])
    Html.patchChildren(parent, before, after)

    // The list reads in the new order…
    expect(labelsOf(parent))->toEqual(["c", "a", "b"])
    // …out of the very same three DOM nodes, moved rather than recreated.
    expect(
      sameNodes(
        kidsOf(parent),
        [original->Array.getUnsafe(2), original->Array.getUnsafe(0), original->Array.getUnsafe(1)],
      ),
    )->toBe(true)
  })

  test("without keys the same reorder overwrites nodes in place", () => {
    // The contrast that says what keys buy: positionally, child 0 is still
    // child 0, so "c" is painted onto the node that was "a" — which is exactly
    // the node whose running animation a moving card would lose.
    let before = unkeyed(["a", "b", "c"])
    let (parent, original) = render(before)

    Html.patchChildren(parent, before, unkeyed(["c", "a", "b"]))

    expect(labelsOf(parent))->toEqual(["c", "a", "b"])
    expect(kidsOf(parent)->Array.getUnsafe(0) === original->Array.getUnsafe(0))->toBe(true)
  })

  test("keeps the neighbours when a child is inserted in the middle", () => {
    let before = keyed(["a", "c"])
    let (parent, original) = render(before)

    Html.patchChildren(parent, before, keyed(["a", "b", "c"]))

    expect(labelsOf(parent))->toEqual(["a", "b", "c"])
    expect(kidsOf(parent)->Array.getUnsafe(0) === original->Array.getUnsafe(0))->toBe(true)
    expect(kidsOf(parent)->Array.getUnsafe(2) === original->Array.getUnsafe(1))->toBe(true)
  })

  test("keeps the neighbours when a child is removed from the middle", () => {
    let before = keyed(["a", "b", "c"])
    let (parent, original) = render(before)

    Html.patchChildren(parent, before, keyed(["a", "c"]))

    expect(labelsOf(parent))->toEqual(["a", "c"])
    expect(
      sameNodes(kidsOf(parent), [original->Array.getUnsafe(0), original->Array.getUnsafe(2)]),
    )->toBe(true)
  })

  test("matches keyed children by key and unkeyed ones by position, in one list", () => {
    // A pile is rarely all cards: here a fixed header sits above two keyed
    // children that swap. The header has no key and stays put by position; the
    // two below it find each other by name.
    let before = [<div id="head" />, ...keyed(["a", "b"])]
    let (parent, original) = render(before)

    let after = [<div id="head" />, ...keyed(["b", "a"])]
    Html.patchChildren(parent, before, after)

    expect(labelsOf(parent))->toEqual(["head", "b", "a"])
    expect(
      sameNodes(
        kidsOf(parent),
        [original->Array.getUnsafe(0), original->Array.getUnsafe(2), original->Array.getUnsafe(1)],
      ),
    )->toBe(true)
  })

  test("carries a key from a component onto the element it renders", () => {
    // The `<Card key=.. />` case: `key` isn't a prop the component declares —
    // the JSX transform lifts it out and the runtime lands it on the single
    // element the component returned.
    let before = ["a", "b"]->Array.map(label => <Item key={label} label />)
    let (parent, original) = render(before)

    Html.patchChildren(parent, before, ["b", "a"]->Array.map(label => <Item key={label} label />))

    expect(labelsOf(parent))->toEqual(["b", "a"])
    expect(
      sameNodes(kidsOf(parent), [original->Array.getUnsafe(1), original->Array.getUnsafe(0)]),
    )->toBe(true)
  })
})
