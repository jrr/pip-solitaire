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
// 4. **`selected` is orthogonal to the kind, in the class list and in ARIA.** It
//    marks the row currently in effect out of a set (the mounted scene), so it has
//    to sit *alongside* the kind modifier rather than replace it, and `aria-current`
//    follows the same absent-not-"false" rule as `aria-checked` above.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest
open TestDom

let render = (
  ~label="Auto-collect",
  ~desc=?,
  ~trailing=?,
  ~enabled=?,
  ~selected=?,
  ~onClick=() => (),
) => Html.create(MenuRow.make({label, ?desc, ?trailing, ?enabled, ?selected, onClick}))

let has = (row, selector) => row->find(selector)->Option.isSome
let text = (row, selector) => row->textIn(selector)
let attr = (row, name) => row->attr(name)

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
    expect(render(~trailing=MenuRow.Switch(false))->classes)->toBe("menu-row menu-row--switch")
    expect(render(~trailing=MenuRow.Switch(true))->classes)->toBe(
      "menu-row menu-row--switch menu-row--on",
    )
    expect(render(~trailing=MenuRow.Chevron)->classes)->toBe("menu-row menu-row--nav")
    // `Nothing` is the default, and it is a kind like the others rather than the
    // absence of one — `--action` is what carries the disabled styling.
    expect(render(~trailing=MenuRow.Nothing)->classes)->toBe("menu-row menu-row--action")
    expect(render()->classes)->toBe("menu-row menu-row--action")
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

  test("marks the selected row alongside its kind, not instead of it", () => {
    // The highlight is a state the row is *in*, so `--active` is appended to
    // whichever kind it is; a scene row is an action row that happens to be current.
    expect(render(~selected=true)->classes)->toBe("menu-row menu-row--action menu-row--active")
    // Orthogonal to the trailing, which is the whole reason this is a prop rather
    // than a fourth `trailing`: a switch row can be the selected one too.
    expect(render(~selected=true, ~trailing=MenuRow.Switch(true))->classes)->toBe(
      "menu-row menu-row--switch menu-row--on menu-row--active",
    )
    // Unselected is the default, and adds nothing.
    expect(render(~selected=false)->classes)->toBe("menu-row menu-row--action")
    expect(render()->classes)->toBe("menu-row menu-row--action")
  })

  test("announces the selected row with aria-current, and says nothing otherwise", () => {
    // Navigation rows — a tap changes what's mounted — so `aria-current`, not
    // `aria-selected`.
    expect(render(~selected=true)->attr("aria-current"))->toBe(Some("true"))
    // Absent, not "false", exactly as with `aria-checked` above: an enumerated
    // attribute that isn't there is how the other rows say they aren't the current
    // one, and it's what keeps them from each announcing a negative.
    expect(render(~selected=false)->attr("aria-current"))->toBe(None)
    expect(render()->hasAttr("aria-current"))->toBe(false)
  })

  test("hides the chevron from assistive tech, so the row is named by its label", () => {
    let chevron = render(~trailing=MenuRow.Chevron)->find(".menu-row__chevron")
    expect(chevron->Option.isSome)->toBe(true)
    expect(chevron->Option.flatMap(c => c->attr("aria-hidden")))->toBe(Some("true"))
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
    expect(row->hasAttr("disabled"))->toBe(true)
    row->click
    expect(taps.contents)->toBe(0)
    // Enabled is the default, and it renders no attribute at all.
    expect(render()->hasAttr("disabled"))->toBe(false)
  })
})
