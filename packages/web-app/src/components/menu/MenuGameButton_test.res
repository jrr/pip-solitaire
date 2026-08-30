// The "game" action button — New, Restart, Share Seed — exercised in isolation.
//
// `Menu_test` already pins what Share Seed does *through the menu*; what's left to this
// file is the button's own contract, which the other two game buttons lean on just as
// much even though neither carries a value.
open Vitest
open TestDom

let render = (~label="Share Seed", ~value=None, ~enabled=true, ~onClick=() => ()) =>
  Html.create(MenuGameButton.make({label, value, enabled, onClick}))

describe("MenuGameButton", () => {
  test("is the bare label when it carries no value", () => {
    let button = render(~label="New")
    expect(button->text)->toBe("New")
    // No empty value span left behind — it would show as a stray gap.
    expect(button->find(".menu-button__value")->Option.isSome)->toBe(false)
  })

  test("keeps a space between the label and the value it carries", () => {
    // The accessible name is the visible text, so this one space is the only thing
    // between the word and the digits when a screen reader concatenates them —
    // "Share Seed123456" without it.
    expect(render(~value=Some("123456"))->text)->toBe("Share Seed 123456")
  })

  test("sets the value apart from the label, as data rather than more prose", () => {
    // Its own element so CSS can give the digits the mono stack and a dimmer colour.
    expect(
      render(~value=Some("777"))
      ->find(".menu-button__value")
      ->Option.mapOr("<missing>", text),
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
    expect(button->hasAttr("disabled"))->toBe(true)
    button->click
    expect(taps.contents)->toBe(0)
    expect(render(~enabled=true)->hasAttr("disabled"))->toBe(false)
  })
})
