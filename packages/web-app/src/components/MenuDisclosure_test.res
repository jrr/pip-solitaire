// The menu's collapsible group (`MenuDisclosure`), now that the Debug screen's two
// of them — "scenes" and "states" — are one component rather than twelve lines of
// JSX beside forty lines of `createElement` (#336).
//
// The states half of this file is `DebugStates_test`'s, carried over: it was the
// only one of the two that could be tested at all, since the scenes group reached
// the menu as an opaque `Html.element`. What's worth pinning:
//
// 1. **One row per entry, in the order given.** The rows are scenes to mount and
//    positions a tap drops the board into; a menu that reordered or dropped one
//    would send a tester to a board they didn't ask for.
// 2. **Each row runs its own entry's action.** Rows that look alike is exactly the
//    arrangement where a crossed wire goes unnoticed — the same reason
//    `MenuSettingsScreen_test` checks its four switches by name.
// 3. **It opens collapsed unless asked, and never writes `open` for the closed
//    case.** The group hides a long list under a summary; the attribute is the
//    browser's to write from a click, and a diff with an opinion about it would slam
//    the group shut under a reader on the next re-render. `open_` is the one
//    exception, and exists for the deep link (`?scene=gallery`) that lands on a row
//    inside the group.
// 4. **`selected` marks a row, and only when asked.** It's the active scene's
//    highlight; the state rows leave it off and must come out plain.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest
open TestDom

let render = (~summary="states", ~open_=?, entries: array<MenuDisclosure.entry>) =>
  Html.create(MenuDisclosure.make({summary, entries, ?open_}))

let labelled = (label, onSelect): MenuDisclosure.entry => {label, onSelect}
let inert = label => labelled(label, () => ())

let rowLabels = group => group->findAll(".scene-menu__row")->Array.map(text)

describe("MenuDisclosure (#336)", () => {
  test("is a native disclosure, labelled and closed", () => {
    let group = render([inert("Mid-game")])
    expect(group->tag)->toBe("DETAILS")
    expect(group->textIn("summary"))->toBe("states")
    // No `open` attribute — the group starts collapsed, and from here on the
    // attribute belongs to the browser rather than to the diff.
    expect(group->hasAttr("open"))->toBe(false)
  })

  test("takes its summary from the caller, so both groups are this component", () => {
    expect(render(~summary="scenes", [inert("Gallery")])->textIn("summary"))->toBe("scenes")
  })

  test("opens from the start when asked", () => {
    // `SceneSwitcher` asks when the app opened on a scene inside the group (a
    // `?scene=gallery` link), so the highlighted row isn't hidden behind it.
    expect(render(~open_=true, [inert("Gallery")])->hasAttr("open"))->toBe(true)
  })

  test("leaves `open` alone when it isn't asked for", () => {
    // Explicitly `false` reads the same as absent, and must stay absent: writing it
    // is what would give the diff an opinion to impose on a reader's own click.
    expect(render(~open_=false, [inert("Gallery")])->hasAttr("open"))->toBe(false)
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

  test("highlights the selected row, and only that one", () => {
    // The scene rows' active highlight, which used to be a class the switcher wrote
    // onto its own buttons as scenes changed.
    let group = render([
      {label: "Gallery", onSelect: () => (), selected: false},
      {label: "Raster", onSelect: () => (), selected: true},
      inert("Motion"),
    ])
    expect(group->findAll(".scene-menu__row--active")->Array.map(text))->toEqual(["Raster"])
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
