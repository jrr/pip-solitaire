// Size-stability test for the `RefreshControl` component (#201).
//
// The bug this guards against: the Updates section used to grow a line the moment
// a status message ("Checking…") appeared and shrink back when it cleared, so the
// whole Settings screen below it reflowed. Progress is now an on-button spinner
// (`busy`) instead of a line beneath the button — the spinner rides inside the
// button's own text line, so the section is heading + button in every state, with
// no row that comes and goes.
//
// **What "a good size test" means here.** These run under jsdom (see
// vitest.config.js), which has no layout engine — no pixel measurement. So we pin
// the size-determining structure instead: the section's stacked **rows** (its
// direct child boxes). Idle and busy must produce the same rows; the spinner is
// nested *inside* the button, not a new row, so it can't change the section's
// height. We also guard that the old reflowing status line is gone for good.
open Vitest

@get external tagName: Html.element => string = "tagName"
type htmlCollection
@get external childElements: Html.element => htmlCollection = "children"
@get external collLength: htmlCollection => int = "length"
@send external collItem: (htmlCollection, int) => Html.element = "item"
@send external querySelector: (Html.element, string) => Nullable.t<Html.element> = "querySelector"
@get external textContent: Html.element => string = "textContent"

// The section's stacked rows: the tag of each direct child element. This is what
// determines the section's height — each row is a box in the column. Nested
// content (the spinner inside the button) is deliberately not walked.
let rows = (el: Html.element): array<string> => {
  let kids = el->childElements
  let out = []
  for i in 0 to kids->collLength - 1 {
    out->Array.push(kids->collItem(i)->tagName)
  }
  out
}

let render = (busy): Html.element =>
  Html.create(RefreshControl.make({label: "Check for updates", busy, onClick: () => ()}))

let hasSpinner = (el): bool =>
  el->querySelector(".menu-refresh__spinner")->Nullable.toOption->Option.isSome

describe("RefreshControl size stability (#201)", () => {
  let idle = render(false)
  let busy = render(true)

  test("has the identical stack of rows whether idle or busy", () => {
    expect(rows(busy))->toEqual(rows(idle))
  })

  test("never renders the old reflowing status line", () => {
    // The line that used to appear/disappear under the button is gone entirely —
    // its comings and goings were the wiggle.
    expect(idle->querySelector(".menu-refresh__status")->Nullable.toOption->Option.isSome)->toBe(
      false,
    )
    expect(busy->querySelector(".menu-refresh__status")->Nullable.toOption->Option.isSome)->toBe(
      false,
    )
  })

  test("shows the spinner only while busy, and inside the button (not as a new row)", () => {
    expect(hasSpinner(idle))->toBe(false)
    expect(hasSpinner(busy))->toBe(true)
    // The spinner is a descendant of the button, so it rides the button's line
    // rather than adding a row that would change the section's height.
    let button = busy->querySelector(".menu-button")->Nullable.toOption
    expect(button->Option.mapOr(false, hasSpinner))->toBe(true)
  })

  test("the button reads its label when idle and \"Checking…\" while busy", () => {
    let buttonText = el =>
      el->querySelector(".menu-button")->Nullable.toOption->Option.mapOr("", textContent)
    expect(buttonText(idle))->toBe("Check for updates")
    expect(buttonText(busy))->toBe("Checking…")
  })
})
