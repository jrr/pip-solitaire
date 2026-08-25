// The debug "states" group (`DebugStates`), now that it's a component rather than
// 47 lines of hand-built DOM.
//
// It had no test at all while it was a node builder — it reached the menu as an
// opaque `Html.element`, so there was nothing a component test could take hold of.
// What's worth pinning now that there is:
//
// 1. **One row per entry, in the order given.** The rows are named positions a tap
//    drops the board into, and a menu that reordered or dropped one would send a
//    tester to a board they didn't ask for.
// 2. **Each row runs its own entry's action.** Rows that look alike is exactly the
//    arrangement where a crossed wire goes unnoticed — the same reason
//    `MenuSettingsScreen_test` checks its four switches by name.
// 3. **It opens collapsed, and nothing sets `open`.** The group hides a long list
//    under a summary; the attribute is the browser's to write from a click, and a
//    diff with an opinion about it would slam the group shut under a reader on the
//    next re-render.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest
open TestDom

let render = (entries: array<DebugStates.entry>) =>
  Html.create(DebugStates.make({entries: entries}))

let labelled = (label, onSelect): DebugStates.entry => {label, onSelect}
let inert = label => labelled(label, () => ())

let rowLabels = group => group->findAll(".scene-menu__row")->Array.map(text)

describe("DebugStates", () => {
  test("is a native disclosure, labelled and closed", () => {
    let group = render([inert("Mid-game")])
    expect(group->tag)->toBe("DETAILS")
    expect(group->textIn("summary"))->toBe("states")
    // No `open` attribute — the group starts collapsed, and from here on the
    // attribute belongs to the browser rather than to the diff.
    expect(group->hasAttr("open"))->toBe(false)
  })

  test("shows one row per entry, in the order it was given", () => {
    expect(render([inert("Mid-game"), inert("Almost won"), inert("Finish")])->rowLabels)->toEqual([
      "Mid-game",
      "Almost won",
      "Finish",
    ])
  })

  test("wires each row to its own entry", () => {
    // Three rows that look alike: a crossed wire would drop the board into a
    // position nobody asked for, which reads as the board simply being wrong.
    let log = []
    let group = render([
      labelled("Mid-game", () => log->Array.push("mid")),
      labelled("Almost won", () => log->Array.push("almost")),
      labelled("Finish", () => log->Array.push("finish")),
    ])
    group->findAll(".scene-menu__row")->Array.forEach(click)
    expect(log)->toEqual(["mid", "almost", "finish"])
  })

  test("makes each row a real button, not a clickable div", () => {
    // `type="button"` matters inside a form-less panel too: it's what a keyboard
    // reaches with Tab and activates with Enter or Space.
    let rows = render([inert("Mid-game")])->findAll(".scene-menu__row")
    expect(rows->Array.map(tag))->toEqual(["BUTTON"])
    expect(rows->Array.map(row => row->attrOr("type")))->toEqual(["button"])
  })

  test("renders an empty group rather than failing on no entries", () => {
    // `Main` always has some, but an empty group is harmless and the caller simply
    // doesn't place it — better than a component that can't be asked.
    let group = render([])
    expect(group->rowLabels)->toEqual([])
    expect(group->textIn("summary"))->toBe("states")
  })
})
