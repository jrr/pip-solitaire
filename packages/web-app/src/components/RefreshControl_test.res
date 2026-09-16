// Size-stability test for the `RefreshControl` component: the control has
// to render the same box idle and busy, because a height change here reflows the
// menu around the About footer (see `RefreshControl.res`).
//
// **What "a good size test" means here.** These run under jsdom (see
// vitest.config.js), which has no layout engine — no pixel measurement. So what's
// pinned is the size-determining structure instead: that the control is one button in
// both states, and that everything the busy state adds is *inside* it.
open Vitest
open TestDom

let render = (busy): Html.element =>
  Html.create(RefreshControl.make({label: "Check for updates", busy, onClick: () => ()}))

let hasSpinner = (el): bool => el->find(".menu-refresh__spinner")->Option.isSome

describe("RefreshControl size stability", () => {
  let idle = render(false)
  let busy = render(true)

  test("is one button in both states, with nothing arriving beside it", () => {
    // The footer stands this next to the About button and sizes the pair (see
    // `AboutFooter.css`), so a wrapper here is a box inside a box and a second element
    // is a row the footer never budgeted for.
    expect((tag(idle), tag(busy)))->toEqual(("BUTTON", "BUTTON"))
    expect(idle->classes->String.includes("menu-button"))->toBe(true)
  })

  test("never renders a status line under the button", () => {
    // A line that comes and goes beneath the button is the reflow this guards
    // against, so neither state may have one.
    expect(idle->find(".menu-refresh__status")->Option.isSome)->toBe(false)
    expect(busy->find(".menu-refresh__status")->Option.isSome)->toBe(false)
  })

  test("shows the spinner only while busy, and inside the button rather than beside it", () => {
    expect(hasSpinner(idle))->toBe(false)
    expect(hasSpinner(busy))->toBe(true)
    // The button's own child, riding its line of text: the one element the busy state
    // adds is inside the box the idle state already drew.
    expect(busy->children->Array.map(tag))->toEqual(["SPAN"])
  })

  test("reads its label when idle and \"Checking…\" while busy", () => {
    expect(text(idle))->toBe("Check for updates")
    expect(text(busy))->toBe("Checking…")
  })
})
