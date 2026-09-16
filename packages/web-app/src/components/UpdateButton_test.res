// The ↻ Update button, and the one thing about it that isn't obvious from the markup:
// with nothing to update it renders *nothing at all*, rather than a hidden box holding
// its place. Both screens that offer it are built around that — see `UpdateButton.res`
// for where each puts it so the arrival is affordable — and a reserve slipped back in
// here would put a permanent gap on both of them.
open Vitest
open TestDom

let render = (~visible, ~onReload=() => ()) => Html.create(UpdateButton.make({visible, onReload}))

// Rendered into a host, for the case where the answer is *no button*: `Html.create`
// hands back a fragment for an empty vnode, which has nothing to ask questions of.
let placed = (~visible) =>
  Html.create(<div> {UpdateButton.make({visible, onReload: () => ()})} </div>)

describe("UpdateButton", () => {
  test("is a button in the panel's own box, saying what pressing it does", () => {
    // The word, the title and the accessible name live here rather than on the screens
    // that place it: that is the part which would quietly diverge if each spelt its own.
    let button = render(~visible=true)
    expect(button->tag)->toBe("BUTTON")
    expect(button->text)->toBe("↻ Update")
    expect(button->attrOr("title"))->toBe("Update available — reload")
    expect(button->attrOr("aria-label"))->toBe("Update now — reload to the new version")
    expect(button->classes)->toBe("menu-update")
  })

  test("renders nothing at all when there is nothing to update", () => {
    // Not a hidden box: a reserve would be a gap under the main menu's title and under
    // the About screen's heading, on every visit where no update was waiting.
    expect(placed(~visible=false)->find(".menu-update"))->toEqual(None)
    expect(placed(~visible=true)->find(".menu-update")->Option.isSome)->toBe(true)
  })

  test("asks for the waiting build to be installed", () => {
    let log = []
    render(~visible=true, ~onReload=() => log->Array.push("reload"))->click
    expect(log)->toEqual(["reload"])
  })
})
