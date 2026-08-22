// The action row (the Debug screen's "Share game state"), exercised in isolation now
// that it's a component of its own (#307).
//
// What's worth pinning: it carries **no switch** — that's the whole difference from
// `<MenuToggleRow>`, and a switch appearing here would claim the row holds a state it
// doesn't — and a disabled row is *genuinely* disabled rather than lit and inert, so
// a tap on it can't reach the handler.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest

@get external textContent: Html.element => string = "textContent"
@send external querySelector: (Html.element, string) => Nullable.t<Html.element> = "querySelector"
@send external hasAttribute: (Html.element, string) => bool = "hasAttribute"
@send external click: Html.element => unit = "click"

let render = (~enabled, ~desc="Copy a link that reopens this exact game.", ~onClick=() => ()) =>
  Html.create(MenuActionRow.make({label: "Share game state", desc, enabled, onClick}))

let text = (row, selector) =>
  row->querySelector(selector)->Nullable.toOption->Option.mapOr("<missing>", textContent)

describe("MenuActionRow (#307)", () => {
  test("shows the label and its description in the toggle row's stack", () => {
    let row = render(~enabled=true)
    expect(row->text(".menu-toggle__label"))->toBe("Share game state")
    expect(row->text(".menu-toggle__desc"))->toBe("Copy a link that reopens this exact game.")
  })

  test("carries no switch, since it does something once rather than holding a state", () => {
    let row = render(~enabled=true)
    expect(row->querySelector(".menu-toggle__switch")->Nullable.toOption->Option.isSome)->toBe(
      false,
    )
  })

  test("takes the caller's line as its description, so a status doesn't add a row", () => {
    // The Debug screen folds "where the link went" into `desc` rather than rendering
    // a line of its own — that's what keeps the row's height fixed as the status
    // comes and goes.
    expect(
      render(~enabled=true, ~desc="Link copied to clipboard.")->text(".menu-toggle__desc"),
    )->toBe("Link copied to clipboard.")
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
    expect(row->hasAttribute("disabled"))->toBe(true)
    row->click
    expect(taps.contents)->toBe(0)
    expect(render(~enabled=true)->hasAttribute("disabled"))->toBe(false)
  })
})
