// The nav row that opens a deeper menu screen (the Settings screen's "Debug" entry),
// exercised in isolation.
open Vitest
open TestDom

let render = (~onClick=() => ()) => Html.create(MenuNavRow.make({label: "Debug", onClick}))

describe("MenuNavRow", () => {
  test("shows its label", () => {
    expect(
      render()
      ->find(".menu-row--nav .menu-row__label")
      ->Option.mapOr("<missing>", text),
    )->toBe("Debug")
  })

  test("marks the way onward with a chevron, not a switch", () => {
    // The one visual difference that says "goes somewhere" instead of "flips here".
    let row = render()
    expect(row->find(".menu-row__chevron")->Option.isSome)->toBe(true)
    expect(row->find(".menu-row__switch")->Option.isSome)->toBe(false)
  })

  test("hides the chevron from assistive tech, so the row is named by its label", () => {
    let chevron = render()->find(".menu-row__chevron")
    expect(chevron->Option.mapOr("<missing>", c => c->attrOr("aria-hidden")))->toBe("true")
  })

  test("goes there when tapped", () => {
    let taps = ref(0)
    render(~onClick=() => taps := taps.contents + 1)->click
    expect(taps.contents)->toBe(1)
  })
})
