// The ↻ Update button: the word, the title and the accessible name, which is the whole
// reason two screens share one component rather than each spelling its own. Whether to
// offer it at all, and what it stands in place of, belongs to the screens that place it
// — `MenuMainScreen_test` and `MenuAboutScreen_test`.
open Vitest
open TestDom

// The single field is spelled out: braces around one punned identifier are a *block* to
// the parser, not a record.
let render = (~onReload=() => ()) => Html.create(UpdateButton.make({onReload: onReload}))

describe("UpdateButton", () => {
  test("is a button in the panel's own box, saying what pressing it does", () => {
    let button = render()
    expect(button->tag)->toBe("BUTTON")
    expect(button->text)->toBe("↻ Update")
    expect(button->attrOr("title"))->toBe("Update available — reload")
    expect(button->attrOr("aria-label"))->toBe("Update now — reload to the new version")
    expect(button->classes)->toBe("menu-update")
  })

  test("asks for the waiting build to be installed", () => {
    let log = []
    render(~onReload=() => log->Array.push("reload"))->click
    expect(log)->toEqual(["reload"])
  })
})
