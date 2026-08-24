// The row every menu row is built from (`MenuRow`), and the three shapes its
// right-hand end takes.
//
// Four components used to draw this box themselves; they now hand it here, so this
// is where the box's own contract lives and their tests are free to pin only what
// each variant adds. Three things are worth pinning about a shared base like this,
// and they're what this file tests:
//
// 1. **The trailing decides the row's semantics, not just its looks.** `Switch`
//    makes it a real `role="switch"` with `aria-checked`; the other two kinds hold
//    no state, so both attributes have to be *absent* rather than "false" — an
//    announced "not checked" on a row that can't be checked is worse than silence.
// 2. **Every kind names itself in the class list.** `--switch` / `--nav` /
//    `--action` carry the styling that differs (the nav row's weight, the action
//    row's disabled look) and are how a screen's test asks for one kind of row
//    without matching the others.
// 3. **A missing description renders nothing at all**, rather than an empty
//    element — `<MenuWiggleRow>` depends on that: a healthy switch shows just its
//    title, and a stray empty `desc` span would put a gap under it.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest

@get external className: Html.element => string = "className"
@get external textContent: Html.element => string = "textContent"
@send external querySelector: (Html.element, string) => Nullable.t<Html.element> = "querySelector"
@send external getAttribute: (Html.element, string) => Nullable.t<string> = "getAttribute"
@send external hasAttribute: (Html.element, string) => bool = "hasAttribute"
@send external click: Html.element => unit = "click"

let render = (~label="Auto-collect", ~desc=?, ~trailing=?, ~enabled=?, ~onClick=() => ()) =>
  Html.create(MenuRow.make({label, ?desc, ?trailing, ?enabled, onClick}))

let find = (row, selector) => row->querySelector(selector)->Nullable.toOption
let has = (row, selector) => row->find(selector)->Option.isSome
let text = (row, selector) => row->find(selector)->Option.mapOr("<missing>", textContent)
let attr = (row, name) => row->getAttribute(name)->Nullable.toOption

describe("MenuRow", () => {
  test("is a button carrying its label, whatever kind of row it is", () => {
    // A <button> throughout: the `Html` runtime only wires clicks, so even a switch
    // is a button with a role rather than a checkbox.
    let row = render(~label="Sloppy placement")
    expect(row->attr("type"))->toBe(Some("button"))
    expect(row->text(".menu-row__label"))->toBe("Sloppy placement")
  })

  test("shows a description only where it was given one", () => {
    expect(render(~desc="Cards don't line up perfectly.")->text(".menu-row__desc"))->toBe(
      "Cards don't line up perfectly.",
    )
    // Not an empty element: the wiggle row's healthy states show a bare title.
    expect(render()->has(".menu-row__desc"))->toBe(false)
  })

  test("names its kind in the class list", () => {
    expect(render(~trailing=MenuRow.Switch(false))->className)->toBe("menu-row menu-row--switch")
    expect(render(~trailing=MenuRow.Switch(true))->className)->toBe(
      "menu-row menu-row--switch menu-row--on",
    )
    expect(render(~trailing=MenuRow.Chevron)->className)->toBe("menu-row menu-row--nav")
    // `Nothing` is the default, and it is a kind like the others rather than the
    // absence of one — `--action` is what carries the disabled styling.
    expect(render(~trailing=MenuRow.Nothing)->className)->toBe("menu-row menu-row--action")
    expect(render()->className)->toBe("menu-row menu-row--action")
  })

  test("puts a switch — and only a switch — on the right of a Switch row", () => {
    expect(render(~trailing=MenuRow.Switch(false))->has(".menu-row__switch"))->toBe(true)
    expect(render(~trailing=MenuRow.Chevron)->has(".menu-row__switch"))->toBe(false)
    expect(render()->has(".menu-row__switch"))->toBe(false)
  })

  test("announces a switch's state, and stays silent on a row that holds none", () => {
    expect(render(~trailing=MenuRow.Switch(false))->attr("role"))->toBe(Some("switch"))
    expect(render(~trailing=MenuRow.Switch(false))->attr("aria-checked"))->toBe(Some("false"))
    expect(render(~trailing=MenuRow.Switch(true))->attr("aria-checked"))->toBe(Some("true"))
    // Absent, not "false": a row that can't be checked must not report being
    // unchecked, and it isn't a switch at all.
    expect(render(~trailing=MenuRow.Chevron)->attr("role"))->toBe(None)
    expect(render(~trailing=MenuRow.Chevron)->attr("aria-checked"))->toBe(None)
    expect(render()->attr("aria-checked"))->toBe(None)
  })

  test("hides the chevron from assistive tech, so the row is named by its label", () => {
    let chevron = render(~trailing=MenuRow.Chevron)->find(".menu-row__chevron")
    expect(chevron->Option.isSome)->toBe(true)
    expect(chevron->Option.flatMap(c => c->getAttribute("aria-hidden")->Nullable.toOption))->toBe(
      Some("true"),
    )
  })

  test("runs its action when tapped", () => {
    let taps = ref(0)
    render(~onClick=() => taps := taps.contents + 1)->click
    expect(taps.contents)->toBe(1)
  })

  test("is really disabled when disabled, not merely muted", () => {
    // The real attribute, so the button emits no click at all — the handler guard
    // behind it is only belt and braces.
    let taps = ref(0)
    let row = render(~enabled=false, ~onClick=() => taps := taps.contents + 1)
    expect(row->hasAttribute("disabled"))->toBe(true)
    row->click
    expect(taps.contents)->toBe(0)
    // Enabled is the default, and it renders no attribute at all.
    expect(render()->hasAttribute("disabled"))->toBe(false)
  })
})
