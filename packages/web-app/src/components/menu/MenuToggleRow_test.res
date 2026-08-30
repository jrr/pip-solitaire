// The settings toggle row, exercised in isolation now that it's a component
// of its own.
//
// Three things are worth pinning about a row like this, and they're what this file
// tests: it *says* both halves of its copy (a label with no description would leave
// a setting unexplained), it *announces* its state rather than only looking the part
// (`aria-checked`, since a `<button role="switch">` has no checkedness of its own for
// assistive tech to read), and a tap actually reaches the handler.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest
open TestDom

let render = (~on, ~onToggle=() => ()): Html.element =>
  Html.create(
    MenuToggleRow.make({
      label: "Auto-collect",
      desc: "Send cards to the foundations for you as soon as they're ready.",
      on,
      onToggle,
    }),
  )

let text = (row, selector) => row->textIn(selector)

let attr = (row, name) => row->attrOr(name)

describe("MenuToggleRow", () => {
  test("shows the label and the line explaining what the setting does", () => {
    let row = render(~on=false)
    expect(row->text(".menu-row__label"))->toBe("Auto-collect")
    expect(row->text(".menu-row__desc"))->toBe(
      "Send cards to the foundations for you as soon as they're ready.",
    )
  })

  test("is a switch-role button, not a checkbox", () => {
    // The `Html` runtime only wires clicks, so the switch has to be a button; the
    // role is what tells assistive tech it holds a state.
    let row = render(~on=false)
    expect(row->attr("type"))->toBe("button")
    expect(row->attr("role"))->toBe("switch")
  })

  test("announces its state as well as showing it", () => {
    // The class slides the knob and greens the track; `aria-checked` is the half a
    // screen reader can read, so both have to move together. What each class
    // *spells* is `MenuRow`'s to pin (see MenuRow_test); what this row owes is that
    // both halves follow the bool it was handed.
    expect(render(~on=false)->classes->String.includes("menu-row--on"))->toBe(false)
    expect(render(~on=false)->attr("aria-checked"))->toBe("false")
    expect(render(~on=true)->classes->String.includes("menu-row--on"))->toBe(true)
    expect(render(~on=true)->attr("aria-checked"))->toBe("true")
  })

  test("asks to be toggled when tapped", () => {
    let taps = ref(0)
    let row = render(~on=false, ~onToggle=() => taps := taps.contents + 1)
    row->click
    row->click
    expect(taps.contents)->toBe(2)
  })
})
