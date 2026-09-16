// The ↻ Update button in both its shapes, and the one thing that differs between them:
// what happens when there is nothing to update. The main menu's band is *absent* then —
// a box reserved for it would be a permanent gap under the title — and the About
// screen's inline one is *reserved*, because the row it rides must not change height.
// Those two are easy to write the same way by accident, and neither failure shows up in
// the screen that placed it.
open Vitest
open TestDom

let render = (~variant, ~visible, ~onReload=() => ()) =>
  Html.create(UpdateButton.make({variant, visible, onReload}))

// Rendered into a host, for the case where the answer is *no button*: `Html.create`
// hands back a fragment for an empty vnode, which has nothing to ask questions of.
let placed = (~variant, ~visible) =>
  Html.create(<div> {UpdateButton.make({variant, visible, onReload: () => ()})} </div>)

describe("UpdateButton", () => {
  test("says the same thing in both shapes, which is why it is one component", () => {
    // The word, the title and the accessible name are the part that would quietly
    // diverge if each screen spelt its own.
    let band = render(~variant=UpdateButton.Band, ~visible=true)
    let inline = render(~variant=UpdateButton.Inline, ~visible=true)
    [band, inline]->Array.forEach(
      button => {
        expect(button->tag)->toBe("BUTTON")
        expect(button->text)->toBe("↻ Update")
        expect(button->attrOr("title"))->toBe("Update available — reload")
        expect(button->attrOr("aria-label"))->toBe("Update now — reload to the new version")
        expect(button->classes->String.includes("menu-update"))->toBe(true)
      },
    )
    expect(band->classes->String.includes("menu-update--band"))->toBe(true)
    expect(inline->classes->String.includes("menu-update--inline"))->toBe(true)
  })

  test("leaves the band out entirely when there is nothing to update", () => {
    // Not a hidden box: the main menu has no anchored row for it to reserve, so a
    // reserve would read as a gap between the title and the first section.
    expect(placed(~variant=UpdateButton.Band, ~visible=false)->find(".menu-update"))->toEqual(None)
    // …where the inline one in the same state is there, hidden.
    expect(
      placed(~variant=UpdateButton.Inline, ~visible=false)->find(".menu-update")->Option.isSome,
    )->toBe(true)
  })

  test("reserves the inline one instead, with visibility rather than `hidden`", () => {
    // `hidden` (⇒ `display: none`) collapses the box and brings back the reflow the
    // reserve exists to prevent. `aria-hidden` mirrors what `visibility` already does to
    // the tab order.
    let reserved = render(~variant=UpdateButton.Inline, ~visible=false)
    expect(reserved->hasAttr("hidden"))->toBe(false)
    expect(reserved->classes->String.includes("menu-update--hidden"))->toBe(true)
    expect(reserved->attrOr("aria-hidden"))->toBe("true")
    let offered = render(~variant=UpdateButton.Inline, ~visible=true)
    expect(offered->classes->String.includes("menu-update--hidden"))->toBe(false)
    expect(offered->attrOr("aria-hidden"))->toBe("false")
  })

  test("asks for the waiting build to be installed", () => {
    let log = []
    render(
      ~variant=UpdateButton.Band,
      ~visible=true,
      ~onReload=() => log->Array.push("reload"),
    )->click
    expect(log)->toEqual(["reload"])
  })
})
