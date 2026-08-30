// The header shared by all three menu screens, exercised in isolation. What differs
// between the three is which of its slots are filled, so every case here is one
// rendering with a different set of them.
open Vitest
open TestDom

let render = (~title, ~back=None, ~onTitleTap=None, ~onClose=() => ()) =>
  Html.create(MenuHeader.make({title, back, onTitleTap, onClose}))

// The header's slots, left to right — which is what decides where the title sits.
let slots = (header: Html.element): array<string> => header->children->Array.map(tag)

describe("MenuHeader", () => {
  test("shows the screen's title", () => {
    expect(render(~title="Settings")->find(".menu-title")->Option.mapOr("", text))->toBe("Settings")
  })

  test("leaves the back slot genuinely empty on a screen with nowhere to go back to", () => {
    // Not a hidden button holding its place: an element there would take a slot in
    // the header's flex row and push the title off centre.
    let main = render(~title="Pip")
    expect(main->find(".menu-back")->Option.isSome)->toBe(false)
    expect(main->slots)->toEqual(["H1", "BUTTON"])
  })

  test("puts the back button ahead of the title when there is somewhere to go", () => {
    let settings = render(~title="Settings", ~back=Some({label: "Back to menu", onClick: () => ()}))
    expect(settings->slots)->toEqual(["BUTTON", "H1", "BUTTON"])
    // "‹ Back" is the same text on every screen, so the accessible name is the only
    // thing that says *where* it goes.
    expect(
      settings
      ->find(".menu-back")
      ->Option.mapOr("", b => b->attr("aria-label")->Option.getOr("")),
    )->toBe("Back to menu")
  })

  test("goes back when the back button is tapped", () => {
    let taps = ref(0)
    let header = render(
      ~title="Debug",
      ~back=Some({label: "Back to settings", onClick: () => taps := taps.contents + 1}),
    )
    header->find(".menu-back")->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })

  test("closes the whole menu from the ✕ on every screen", () => {
    let taps = ref(0)
    let header = render(~title="Pip", ~onClose=() => taps := taps.contents + 1)
    header->find(".menu-close")->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })

  test("counts taps on the title only where a screen asked for them", () => {
    let taps = ref(0)
    let settings = render(~title="Settings", ~onTitleTap=Some(() => taps := taps.contents + 1))
    settings->find(".menu-title")->Option.forEach(click)
    settings->find(".menu-title")->Option.forEach(click)
    expect(taps.contents)->toBe(2)

    // …and the identical title on the other screens is inert — it doubles as the
    // hidden-options tap target (`HiddenOptions`) on Settings alone. `onTitleTap: None`
    // is also what *clears* the handler off the reused <h1> on the way out of Settings,
    // since a handler no longer in the props is dropped from the node it was on. A real
    // listener leaves nothing on the element for a test to read back, so this is
    // asserted through behaviour: tapping the other screen's title counts nothing.
    let main = render(~title="Pip")
    main->find(".menu-title")->Option.forEach(click)
    expect(taps.contents)->toBe(2)
  })
})
