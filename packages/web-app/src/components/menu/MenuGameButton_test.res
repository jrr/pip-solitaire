// The "game" action button — Random, Enter Seed, Restart, Share Seed — exercised in
// isolation.
//
// `Menu_test` already pins what Share Seed does *through the menu*; what's left to this
// file is the button's own contract, which all four lean on equally.
open Vitest
open TestDom

let render = (~label="Share Seed", ~enabled=true, ~onClick=() => ()) =>
  Html.create(MenuGameButton.make({label, enabled, onClick}))

describe("MenuGameButton", () => {
  test("is its label and nothing else", () => {
    // No number on the button, whatever board is up: which deal the section is about is
    // the heading's to say (`MenuSection`'s `headingValue`), which is what keeps all
    // four buttons the same size.
    expect(render(~label="Random")->text)->toBe("Random")
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
