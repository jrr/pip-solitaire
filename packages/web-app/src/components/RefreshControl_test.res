// Size-stability test for the `RefreshControl` component: the control has
// to render the same rows idle and busy, because a height change here reflows the
// menu around the About footer (see `RefreshControl.res`).
//
// **What "a good size test" means here.** These run under jsdom (see
// vitest.config.js), which has no layout engine — no pixel measurement. So what's
// pinned is the size-determining structure instead: the section's stacked **rows**, its
// direct child boxes.
open Vitest
open TestDom

// The section's stacked rows: the tag of each direct child element. This is what
// determines the section's height — each row is a box in the column. Nested
// content (the spinner inside the button) is deliberately not walked.
let rows = (el: Html.element): array<string> => el->children->Array.map(tag)

let render = (busy): Html.element =>
  Html.create(RefreshControl.make({label: "Check for updates", busy, onClick: () => ()}))

let hasSpinner = (el): bool => el->find(".menu-refresh__spinner")->Option.isSome

describe("RefreshControl size stability", () => {
  let idle = render(false)
  let busy = render(true)

  test("has the identical stack of rows whether idle or busy", () => {
    expect(rows(busy))->toEqual(rows(idle))
  })

  test("never renders a status line under the button", () => {
    // A line that comes and goes beneath the button is the reflow this guards
    // against, so neither state may have one.
    expect(idle->find(".menu-refresh__status")->Option.isSome)->toBe(false)
    expect(busy->find(".menu-refresh__status")->Option.isSome)->toBe(false)
  })

  test("shows the spinner only while busy, and inside the button (not as a new row)", () => {
    expect(hasSpinner(idle))->toBe(false)
    expect(hasSpinner(busy))->toBe(true)
    // The spinner is a descendant of the button, so it rides the button's line
    // rather than adding a row that would change the section's height.
    let button = busy->find(".menu-button")
    expect(button->Option.mapOr(false, hasSpinner))->toBe(true)
  })

  test("the button reads its label when idle and \"Checking…\" while busy", () => {
    let buttonText = el => el->find(".menu-button")->Option.mapOr("", text)
    expect(buttonText(idle))->toBe("Check for updates")
    expect(buttonText(busy))->toBe("Checking…")
  })
})
