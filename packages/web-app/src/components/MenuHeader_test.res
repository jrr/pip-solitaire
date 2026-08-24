// The header shared by all three menu screens, exercised in isolation now that it's
// a component of its own (#307).
//
// Two things here are load-bearing rather than cosmetic:
//
// 1. **The back button is a slot, not a fixture.** The main menu has nowhere to go
//    back to, so it renders none at all — a disabled or invisible one would still
//    take a place in the header's flex row and shift the title off centre.
// 2. **The title is only tappable on one screen.** It doubles as the hidden-options
//    tap target (`HiddenOptions`) on Settings; the identical `menu-title` renders
//    "Pip" and "Debug" elsewhere and must stay inert. `onTitleTap: None` is what
//    keeps it that way, and — because a handler that is no longer in the props is
//    dropped from the node it was on — it's also what *clears* the handler from the
//    reused <h1> when the player leaves Settings. A leak here would be invisible
//    until someone found it, which is exactly why it's pinned.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest

@get external tagName: Html.element => string = "tagName"
@get external textContent: Html.element => string = "textContent"
type htmlCollection
@get external childElements: Html.element => htmlCollection = "children"
@get external collLength: htmlCollection => int = "length"
@send external collItem: (htmlCollection, int) => Html.element = "item"
@send external querySelector: (Html.element, string) => Nullable.t<Html.element> = "querySelector"
@send external getAttribute: (Html.element, string) => Nullable.t<string> = "getAttribute"
@send external click: Html.element => unit = "click"

let render = (~title, ~back=None, ~onTitleTap=None, ~onClose=() => ()) =>
  Html.create(MenuHeader.make({title, back, onTitleTap, onClose}))

// The header's slots, left to right — which is what decides where the title sits.
let slots = (header: Html.element): array<string> => {
  let kids = header->childElements
  let out = []
  for i in 0 to kids->collLength - 1 {
    out->Array.push(kids->collItem(i)->tagName)
  }
  out
}

let find = (header, selector) => header->querySelector(selector)->Nullable.toOption

describe("MenuHeader (#307)", () => {
  test("shows the screen's title", () => {
    expect(render(~title="Settings")->find(".menu-title")->Option.mapOr("", textContent))->toBe(
      "Settings",
    )
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
      ->Option.mapOr("", b => b->getAttribute("aria-label")->Nullable.toOption->Option.getOr("")),
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

    // …and the identical title on the other screens is inert. This used to be
    // asserted at the node: the runtime this replaced stashed the current handler
    // *on the element*, where a test could read it back. A real listener leaves
    // nothing to read, so the assertion says what it always meant — tapping the
    // other screen's title counts nothing.
    let main = render(~title="Pip")
    main->find(".menu-title")->Option.forEach(click)
    expect(taps.contents)->toBe(2)
  })
})
