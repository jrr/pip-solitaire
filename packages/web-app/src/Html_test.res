// What the app needs from its JSX runtime, now that the runtime is Preact's.
//
// The file this replaces tested a reconciler we wrote: keyed matching, attribute
// patching, namespace handling. None of that is ours to test any more — testing
// it would be testing Preact. What *is* still ours is the handful of properties
// the app is built on top of, each of which would fail silently rather than
// loudly if the runtime under us changed:
//
//   1. **SVG lands in the SVG namespace.** Every card, the app icon and the
//      spinner are real vector nodes (`CardArt`). An <svg> built in the HTML
//      namespace draws nothing at all — no error, just a blank card.
//   2. **A re-render reuses the DOM node.** The board's card motion is Web
//      Animations on live nodes and its CSS transitions run on class changes; a
//      node rebuilt rather than patched silently restarts both. This is the
//      property the old runtime existed to guarantee.
//   3. **A spliced subtree is left alone.** `Html.node` hands the diff a
//      node someone else owns (the scene container, the debug console's
//      scrollback). Preact has no vnode that *is* a live node, so this goes
//      through a host element and a callback ref — and the thing to pin is that
//      re-rendering around it neither re-appends nor rebuilds it.
open Vitest

@get external namespaceURI: Html.element => string = "namespaceURI"
@get external firstChild: Html.element => Html.element = "firstChild"
@get external childElementCount: Html.element => int = "childElementCount"
@get external parentElement: Html.element => Nullable.t<Html.element> = "parentElement"
@send external getAttribute: (Html.element, string) => Nullable.t<string> = "getAttribute"
@send external querySelector: (Html.element, string) => Nullable.t<Html.element> = "querySelector"
@val @scope("document") external createElement: string => Html.element = "createElement"
@set external setTextContent: (Html.element, string) => unit = "textContent"

let svgNamespace = "http://www.w3.org/2000/svg"
let htmlNamespace = "http://www.w3.org/1999/xhtml"

let find = (root, selector) => root->querySelector(selector)->Nullable.toOption

describe("Html — SVG namespace", () => {
  test("builds <svg> and its descendants as vector nodes, not unknown HTML", () => {
    let art = Html.create(
      <svg viewBox="0 0 10 10">
        <g transform="translate(1 1)">
          <path d="M0 0 L10 10" fill="currentColor" />
        </g>
      </svg>,
    )
    expect(art->namespaceURI)->toBe(svgNamespace)
    expect(art->find("path")->Option.mapOr("<missing>", namespaceURI))->toBe(svgNamespace)
  })

  test("keeps ordinary markup in the HTML namespace", () => {
    let box = Html.create(
      <div className="box">
        <span />
      </div>,
    )
    expect(box->namespaceURI)->toBe(htmlNamespace)
    expect(box->find("span")->Option.mapOr("<missing>", namespaceURI))->toBe(htmlNamespace)
  })
})

// The Elm loop, driven the way `Main` drives it: dispatch a model, get a patch.
type msg = Bump
type model = {n: int}

let mountCounter = root => {
  Html.mount(
    ~root,
    ~init={n: 0},
    ~update=(Bump, model) => ({n: model.n + 1}, Html.noEffect),
    ~view=(model, dispatch) =>
      <div className="counter">
        <span className={model.n > 1 ? "hot" : "cold"} onClick={_ => dispatch(Bump)}>
          {Html.string(Int.toString(model.n))}
        </span>
      </div>,
  )
}

describe("Html — patching in place", () => {
  test("re-renders through the same DOM node rather than rebuilding it", () => {
    let root = createElement("div")
    let dispatch = mountCounter(root)

    let before = root->find(".counter")->Option.getOrThrow
    let liveBefore = root->find("span")->Option.getOrThrow

    dispatch(Bump)
    dispatch(Bump)

    // Same nodes — this is what lets a class change (cold → hot) run a CSS
    // transition instead of restarting one on a freshly built element.
    expect(root->find(".counter")->Option.mapOr(false, el => el === before))->toBe(true)
    expect(root->find("span")->Option.mapOr(false, el => el === liveBefore))->toBe(true)
    expect(liveBefore->getAttribute("class")->Nullable.toOption)->toBe(Some("hot"))
  })

  test("touches nothing when the model comes back unchanged", () => {
    let root = createElement("div")
    let dispatch = Html.mount(
      ~root,
      ~init={n: 0},
      // Answers with the *same* model value, so the loop's physical-equality
      // check should skip the render entirely.
      ~update=(Bump, model) => (model, Html.noEffect),
      ~view=(model, _) => <div className="counter"> {Html.string(Int.toString(model.n))} </div>,
    )
    let before = root->find(".counter")->Option.getOrThrow
    dispatch(Bump)
    expect(root->find(".counter")->Option.mapOr(false, el => el === before))->toBe(true)
  })
})

describe("Html.node — a subtree we don't own", () => {
  test("splices the very node it was given, and keeps it across re-renders", () => {
    let owned = createElement("canvas")
    owned->setTextContent("owned")

    let root = createElement("div")
    let dispatch = Html.mount(
      ~root,
      ~init={n: 0},
      ~update=(Bump, model) => ({n: model.n + 1}, Html.noEffect),
      ~view=(model, _) =>
        <div className={model.n > 0 ? "shell bumped" : "shell"}> {Html.node(owned)} </div>,
    )

    let host = root->find(".raw-host")->Option.getOrThrow
    expect(host->firstChild === owned)->toBe(true)

    dispatch(Bump)
    dispatch(Bump)

    // Still the same node, still in the same host, and still exactly one of it:
    // a ref that re-appended on every render would be just as invisible here as
    // it would be in the app, until a growing log started duplicating lines.
    expect(root->find(".raw-host")->Option.mapOr(false, el => el === host))->toBe(true)
    expect(host->childElementCount)->toBe(1)
    expect(host->firstChild === owned)->toBe(true)
    expect(owned->parentElement->Nullable.toOption->Option.mapOr(false, el => el === host))->toBe(
      true,
    )
  })
})
