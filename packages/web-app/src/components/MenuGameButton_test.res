// The "game" action button — New, Restart, Share Seed — exercised in isolation now
// that it's a component of its own (#307).
//
// `Menu_test` already pins what Share Seed does *through the menu* (#98); this file
// pins the button's own two behaviours, which the other two game buttons rely on
// just as much: a button with no `value` is a bare label and nothing else, and a
// button with one keeps the accessible name and the visible text the same string —
// the trailing space after the label is the only thing between the word and the
// digits when a screen reader concatenates them.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest

@get external textContent: Html.element => string = "textContent"
@send external querySelector: (Html.element, string) => Nullable.t<Html.element> = "querySelector"
@send external hasAttribute: (Html.element, string) => bool = "hasAttribute"
@send external click: Html.element => unit = "click"

let render = (~label="Share Seed", ~value=None, ~enabled=true, ~onClick=() => ()) =>
  Html.create(MenuGameButton.make({label, value, enabled, onClick}))

describe("MenuGameButton (#307)", () => {
  test("is the bare label when it carries no value", () => {
    let button = render(~label="New")
    expect(button->textContent)->toBe("New")
    // No empty value span left behind — it would show as a stray gap.
    expect(button->querySelector(".menu-button__value")->Nullable.toOption->Option.isSome)->toBe(
      false,
    )
  })

  test("keeps a space between the label and the value it carries", () => {
    // The accessible name is the visible text, so the two would run together as
    // "Share Seed123456" without it.
    expect(render(~value=Some("123456"))->textContent)->toBe("Share Seed 123456")
  })

  test("sets the value apart from the label, as data rather than more prose", () => {
    // Its own element so CSS can give the digits the mono stack and a dimmer colour.
    expect(
      render(~value=Some("777"))
      ->querySelector(".menu-button__value")
      ->Nullable.toOption
      ->Option.mapOr("<missing>", textContent),
    )->toBe("777")
  })

  test("acts when tapped", () => {
    let taps = ref(0)
    render(~onClick=() => taps := taps.contents + 1)->click
    expect(taps.contents)->toBe(1)
  })

  test("is really disabled when it has nothing to act on", () => {
    // The real attribute, so the button emits no click at all — the handler guard
    // behind it is only belt and braces.
    let taps = ref(0)
    let button = render(~enabled=false, ~onClick=() => taps := taps.contents + 1)
    expect(button->hasAttribute("disabled"))->toBe(true)
    button->click
    expect(taps.contents)->toBe(0)
    expect(render(~enabled=true)->hasAttribute("disabled"))->toBe(false)
  })
})
