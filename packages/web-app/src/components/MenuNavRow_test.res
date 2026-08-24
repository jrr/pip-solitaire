// The nav row that opens a deeper menu screen (the Settings screen's "Debug" entry),
// exercised in isolation now that it's a component of its own (#307).
//
// What's worth pinning: it wears a **chevron rather than a switch** — the one visual
// difference that says "goes somewhere" instead of "flips here" — and that chevron is
// `aria-hidden`, so the row's accessible name is its label and not "Debug ›".
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest

@get external textContent: Html.element => string = "textContent"
@send external querySelector: (Html.element, string) => Nullable.t<Html.element> = "querySelector"
@send external getAttribute: (Html.element, string) => Nullable.t<string> = "getAttribute"
@send external click: Html.element => unit = "click"

let render = (~onClick=() => ()) => Html.create(MenuNavRow.make({label: "Debug", onClick}))

describe("MenuNavRow (#307)", () => {
  test("shows its label", () => {
    expect(
      render()
      ->querySelector(".menu-row--nav .menu-row__label")
      ->Nullable.toOption
      ->Option.mapOr("<missing>", textContent),
    )->toBe("Debug")
  })

  test("marks the way onward with a chevron, not a switch", () => {
    let row = render()
    expect(row->querySelector(".menu-row__chevron")->Nullable.toOption->Option.isSome)->toBe(true)
    expect(row->querySelector(".menu-row__switch")->Nullable.toOption->Option.isSome)->toBe(false)
  })

  test("hides the chevron from assistive tech, so the row is named by its label", () => {
    let chevron = render()->querySelector(".menu-row__chevron")->Nullable.toOption
    expect(
      chevron->Option.mapOr(
        "<missing>",
        c => c->getAttribute("aria-hidden")->Nullable.toOption->Option.getOr("<missing>"),
      ),
    )->toBe("true")
  })

  test("goes there when tapped", () => {
    let taps = ref(0)
    render(~onClick=() => taps := taps.contents + 1)->click
    expect(taps.contents)->toBe(1)
  })
})
