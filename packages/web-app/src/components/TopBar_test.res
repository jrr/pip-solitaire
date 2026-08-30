// The top bar: Menu on one side, Undo on the other.
//
// Both of its controls carry state that is *only* visible in an attribute, which is
// what this file is for — the pip and the disabled Undo look obvious on screen and say
// nothing to a screen reader unless the ARIA moves with them, so if the two halves ever
// came apart the visual one would still look right.
open Vitest
open TestDom

let render = (~canUndo=true, ~updateVisible=false, ~onMenu=() => (), ~onUndo=() => ()) =>
  Html.create(TopBar.make({onMenu, onUndo, canUndo, updateVisible}))

let menuButton = bar => bar->find(".top-bar__button--menu")->Option.getOrThrow
let undoButton = bar => bar->find(".top-bar__button--undo")->Option.getOrThrow

describe("TopBar", () => {
  test("offers exactly two controls: Menu and Undo", () => {
    // New Game left for the menu and Update for the About footer;
    // Redo was removed outright. A third button appearing here is a regression.
    expect(render()->children->Array.map(el => el->attrOr("aria-label")))->toEqual([
      "Open menu",
      "Undo",
    ])
  })

  test("says a version is waiting, rather than only showing it", () => {
    let quiet = render(~updateVisible=false)
    expect(quiet->has(".top-bar__pip"))->toBe(false)
    expect(quiet->menuButton->attr("aria-label"))->toBe(Some("Open menu"))

    let waiting = render(~updateVisible=true)
    expect(waiting->has(".top-bar__pip"))->toBe(true)
    expect(waiting->menuButton->attr("aria-label"))->toBe(Some("Open menu — update available"))
  })

  test("keeps the pip out of the accessible name it sits inside", () => {
    // Purely decorative: the news is in the label above, and a dot read aloud after
    // "Open menu — update available" would say it twice.
    expect(
      render(~updateVisible=true)
      ->find(".top-bar__pip")
      ->Option.flatMap(pip => pip->attr("aria-hidden")),
    )->toBe(Some("true"))
  })

  test("disables Undo for real when there's nothing to step back to", () => {
    let fresh = render(~canUndo=false)
    expect(fresh->undoButton->hasAttr("disabled"))->toBe(true)
    expect(fresh->undoButton->attr("aria-disabled"))->toBe(Some("true"))

    let played = render(~canUndo=true)
    expect(played->undoButton->hasAttr("disabled"))->toBe(false)
    // Absent, not "false": an enumerated ARIA attribute reading "false" on every
    // playable board is noise, and differs from saying nothing.
    expect(played->undoButton->attr("aria-disabled"))->toBe(None)
  })

  test("draws the undo glyph rather than typing it, and hides the drawing", () => {
    // An inline `<svg>` for the reason `TopBar.res` gives; here it's the `aria-hidden`
    // that matters, so the button is named by its label rather than by its artwork.
    let icon = render()->find(".top-bar__icon")->Option.getOrThrow
    expect(icon->tag)->toBe("svg")
    expect(icon->attr("aria-hidden"))->toBe(Some("true"))
    // `focusable="false"` keeps IE/Edge's legacy SVG focus behaviour out of the tab
    // order; the button is the control, not its artwork.
    expect(icon->attr("focusable"))->toBe(Some("false"))
    expect(icon->has("path"))->toBe(true)
  })

  test("wires each button to its own action", () => {
    let log = []
    let bar = render(~onMenu=() => log->Array.push("menu"), ~onUndo=() => log->Array.push("undo"))
    bar->menuButton->click
    bar->undoButton->click
    expect(log)->toEqual(["menu", "undo"])
  })

  test("emits no undo at all while the button is disabled", () => {
    // The real attribute is what stops it — there is no handler guard behind this
    // one, so the attribute is the whole mechanism.
    let taps = ref(0)
    render(~canUndo=false, ~onUndo=() => taps := taps.contents + 1)->undoButton->click
    expect(taps.contents)->toBe(0)
  })
})
