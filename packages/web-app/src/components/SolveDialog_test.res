// The Debug screen's "Solve" modal. The answer arrives already worked out, so the cases
// are what the panel says and which ways out it offers.
open Vitest
open TestDom

let found = "12-move solution found in 0.4 s — 3,210 positions, 9,876 moves tried."

let render = (~message=found, ~onAutoplay=None, ~onClose=() => ()) =>
  Html.create(SolveDialog.make({message, onAutoplay, onClose}))

let buttons = (dialog): array<element> => dialog->findAll(".solve-dialog__button")

describe("SolveDialog", () => {
  test("says what the solver found in its own words", () => {
    expect(render()->textIn(".solve-dialog__message"))->toBe(found)
  })

  test("offers to play a line it found, and plays it on the press", () => {
    let plays = ref(0)
    let dialog = render(~onAutoplay=Some(() => plays := plays.contents + 1))
    expect(dialog->buttons->Array.map(text))->toEqual(["Close", "Autoplay"])
    dialog->buttons->Array.getUnsafe(1)->click
    expect(plays.contents)->toBe(1)
  })

  test("offers only Close when there is nothing to play", () => {
    let dialog = render(~message="Autoplay couldn't find a way to win from here.")
    expect(dialog->buttons->Array.map(text))->toEqual(["Close"])
  })

  test("closes from the button and from the dim behind the panel", () => {
    let closes = ref(0)
    let dialog = render(~onClose=() => closes := closes.contents + 1)
    dialog->buttons->Array.getUnsafe(0)->click
    dialog->find(".solve-dialog__backdrop")->Option.forEach(click)
    expect(closes.contents)->toBe(2)
  })
})
