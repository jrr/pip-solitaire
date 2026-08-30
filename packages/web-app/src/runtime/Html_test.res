// What the app needs from its JSX runtime, as against what Preact owes its own
// test suite. Every property pinned below would fail *silently* if the runtime
// under us changed, which is the whole reason it is worth a test; the list and
// the case for each are `docs/rendering.md` § What the app leans on Preact for.
open Vitest
open TestDom

@get external namespaceURI: Html.element => string = "namespaceURI"
@get external firstChild: Html.element => Html.element = "firstChild"
@get external parentElement: Html.element => Nullable.t<Html.element> = "parentElement"
@set external setTextContent: (Html.element, string) => unit = "textContent"

let svgNamespace = "http://www.w3.org/2000/svg"
let htmlNamespace = "http://www.w3.org/1999/xhtml"

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
    let root = host("div")
    let dispatch = mountCounter(root)

    let before = root->find(".counter")->Option.getOrThrow
    let liveBefore = root->find("span")->Option.getOrThrow

    dispatch(Bump)
    dispatch(Bump)

    // Same nodes — this is what lets a class change (cold → hot) run a CSS
    // transition instead of restarting one on a freshly built element.
    expect(root->find(".counter")->Option.mapOr(false, el => el === before))->toBe(true)
    expect(root->find("span")->Option.mapOr(false, el => el === liveBefore))->toBe(true)
    expect(liveBefore->attr("class"))->toBe(Some("hot"))
  })

  test("touches nothing when the model comes back unchanged", () => {
    let root = host("div")
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
    let owned = host("canvas")
    owned->setTextContent("owned")

    let root = host("div")
    let dispatch = Html.mount(
      ~root,
      ~init={n: 0},
      ~update=(Bump, model) => ({n: model.n + 1}, Html.noEffect),
      ~view=(model, _) =>
        <div className={model.n > 0 ? "shell bumped" : "shell"}> {Html.node(owned)} </div>,
    )

    let splice = root->find(".raw-host")->Option.getOrThrow
    expect(splice->firstChild === owned)->toBe(true)

    dispatch(Bump)
    dispatch(Bump)

    // Still the same node, still in the same host, and still exactly one of it:
    // a ref that re-appended on every render would be just as invisible here as
    // it would be in the app, until a growing log started duplicating lines.
    expect(root->find(".raw-host")->Option.mapOr(false, el => el === splice))->toBe(true)
    expect(splice->childCount)->toBe(1)
    expect(splice->firstChild === owned)->toBe(true)
    expect(owned->parentElement->Nullable.toOption->Option.mapOr(false, el => el === splice))->toBe(
      true,
    )
  })

  test("holds the node it was last given, not every node it has ever been given", () => {
    // The host is reused across a render that hands it a *different* node — the one
    // shape `Html.node` has no way to refuse, since its argument is an ordinary
    // value a view can compute. Appending would leave both in place, and the
    // symptom would be a doubled scene or a doubled log with nothing to point at.
    //
    // No call site does this today: all eight hand over a node that is stable for
    // the life of its position (a module-level `<ol>`, the scene container, a cached
    // canvas). That's precisely why the rule belongs to the host — an invariant kept
    // by eight callers agreeing is one a ninth can break.
    let first = host("canvas")
    let second = host("canvas")

    let root = host("div")
    let dispatch = Html.mount(
      ~root,
      ~init={n: 0},
      ~update=(Bump, model) => ({n: model.n + 1}, Html.noEffect),
      ~view=(model, _) => <div className="shell"> {Html.node(model.n == 0 ? first : second)} </div>,
    )

    let splice = root->find(".raw-host")->Option.getOrThrow
    expect(splice->firstChild === first)->toBe(true)

    dispatch(Bump)

    expect(splice->childCount)->toBe(1)
    expect(splice->firstChild === second)->toBe(true)
    // …and the one it replaced is out of the tree, not hidden behind it.
    expect(first->parentElement->Nullable.toOption->Option.isSome)->toBe(false)
  })
})
