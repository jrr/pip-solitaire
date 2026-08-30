// The top bar: Menu on one side, Undo on the other.
//
// Both of its controls carry state that is *only* visible in an attribute, which is
// what this file is for — the pip and the disabled Undo look obvious on screen and
// say nothing to a screen reader unless the ARIA moves with them:
//
// 1. **The update pip is decorative, and the Menu button's name carries the news.**
//    A green dot appears when a new build is waiting. It's `aria-hidden`, so
//    the only way that state reaches assistive tech is the button's `aria-label`
//    changing with it. If the two ever came apart, the visual half would still look
//    right.
// 2. **Undo is disabled by the real attribute, and `aria-disabled` is absent rather
//    than "false" when the action is available.** An enumerated ARIA attribute set
//    to "false" is not the same as no attribute, and "no undo available" announced
//    on every fresh deal is noise.
// 3. **The undo glyph is drawn, not typed** — an inline `<svg>`, because U+21B6
//    isn't in Libre Franklin and each platform would substitute a different
//    fallback face for that one character (see `TopBar.res`). It's `aria-hidden`,
//    so the button is named by its label rather than by its artwork.
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
