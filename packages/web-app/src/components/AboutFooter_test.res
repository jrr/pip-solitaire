// Size-stability test for the `AboutFooter` component (#201).
//
// The bug this guards against: the update block used to be rendered with `hidden`
// (`display: none`) when no update was waiting, so the footer collapsed most of
// the time and then expanded — shoving the version line and everything above it —
// the moment an update arrived. The footer is now a single row (version line left,
// short **↻ Update** button right); the button stays laid out at all times and is
// hidden with *visibility* (`menu-update--hidden`) when there's nothing to update,
// so the row is the same height in both states.
//
// See `RefreshControl_test` for why the assertion is structural rather than
// pixel-measured: jsdom has no layout engine, so we pin the size-determining tree
// (element tags + nesting) — which a box-collapsing `display: none` would change
// but a `visibility: hidden` reserve would not — plus the specific regression
// guard that the button never falls back to the `hidden` attribute.
open Vitest
open TestDom

// The size-determining shape of a rendered subtree: tag + children skeleton, with
// text and attributes stripped. A button hidden with `visibility` keeps its box
// (so the skeleton is unchanged); one hidden with `display: none` would not — but
// the browser still reports the element, so the skeleton alone can't catch a
// regression to `hidden`. The dedicated attribute check below does.
let rec skeleton = (el: Html.element): string => {
  let parts = el->children->Array.map(skeleton)
  let inner = parts->Array.length == 0 ? "" : `(${parts->Array.join(",")})`
  el->tag ++ inner
}

let render = (~updateVisible): Html.element =>
  Html.create(
    AboutFooter.make({
      version: "1.2.3",
      buildTime: "2026-07-23T20:20:00.000Z",
      updateVisible,
      onReload: () => (),
      // The update-check slot; empty here so the size-stability assertions turn on
      // the update button alone (its presence is what used to reflow the footer).
      refresh: Html.empty,
    }),
  )

let button = (footer): option<Html.element> => footer->find(".menu-update__button")

describe("AboutFooter size stability (#201)", () => {
  let noUpdate = render(~updateVisible=false)
  let updateWaiting = render(~updateVisible=true)

  test("renders the identical box skeleton whether or not an update is waiting", () => {
    expect(skeleton(updateWaiting))->toBe(skeleton(noUpdate))
  })

  test("keeps the Update button in the DOM when hidden, so its box stays reserved", () => {
    // Present in both states — reserved with `visibility`, not conjured on arrival.
    expect(noUpdate->button->Option.isSome)->toBe(true)
    expect(updateWaiting->button->Option.isSome)->toBe(true)
  })

  test(
    "hides the button with the visibility class, never the collapsing `hidden` attribute",
    () => {
      // The regression guard: `hidden` (⇒ `display: none`) would collapse the box and
      // bring the wiggle straight back. The hidden state must reserve with the class.
      switch noUpdate->button {
      | Some(b) =>
        expect(b->hasAttr("hidden"))->toBe(false)
        expect(b->classes->String.includes("menu-update--hidden"))->toBe(true)
      | None => expect("button present")->toBe("button missing")
      }
      // When an update is waiting the button is fully shown (no reserve class).
      switch updateWaiting->button {
      | Some(b) => expect(b->classes->String.includes("menu-update--hidden"))->toBe(false)
      | None => expect("button present")->toBe("button missing")
      }
    },
  )
})
