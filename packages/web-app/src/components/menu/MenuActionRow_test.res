// The action row (the Debug screen's "Share game state"), exercised in isolation. What
// separates it from `<MenuToggleRow>` is that it does something once rather than
// holding a state, and everything below follows from that.
open Vitest
open TestDom

let render = (~enabled, ~desc="Copy a link that reopens this exact game.", ~onClick=() => ()) =>
  Html.create(MenuActionRow.make({label: "Share game state", desc, enabled, onClick}))

let text = (row, selector) => row->textIn(selector)

describe("MenuActionRow", () => {
  test("shows the label and its description in the toggle row's stack", () => {
    let row = render(~enabled=true)
    expect(row->text(".menu-row__label"))->toBe("Share game state")
    expect(row->text(".menu-row__desc"))->toBe("Copy a link that reopens this exact game.")
  })

  test("carries no switch, since it does something once rather than holding a state", () => {
    // A switch appearing here would claim the row holds a state it doesn't.
    let row = render(~enabled=true)
    expect(row->find(".menu-row__switch")->Option.isSome)->toBe(false)
  })

  test("takes the caller's line as its description, so a status doesn't add a row", () => {
    // The Debug screen folds "where the link went" into `desc` rather than rendering
    // a line of its own — that's what keeps the row's height fixed as the status
    // comes and goes.
    expect(render(~enabled=true, ~desc="Link copied to clipboard.")->text(".menu-row__desc"))->toBe(
      "Link copied to clipboard.",
    )
  })

  test("runs its action when tapped", () => {
    let taps = ref(0)
    render(~enabled=true, ~onClick=() => taps := taps.contents + 1)->click
    expect(taps.contents)->toBe(1)
  })

  test("is really disabled when there's nothing to do, not merely muted", () => {
    // The real attribute, so the button emits no click at all — the handler guard
    // behind it is only belt and braces.
    let taps = ref(0)
    let row = render(~enabled=false, ~onClick=() => taps := taps.contents + 1)
    expect(row->hasAttr("disabled"))->toBe(true)
    row->click
    expect(taps.contents)->toBe(0)
    expect(render(~enabled=true)->hasAttr("disabled"))->toBe(false)
  })
})
