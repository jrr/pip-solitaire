// The Debug screen's "Copy seed" row (#98).
//
// The row exists so a deal can be *shared*: the number it shows is what the other
// player pastes into `?seed=` to be dealt the identical board. That makes two things
// worth pinning, and they're what this file tests.
//
// 1. **The number on screen is the deal number.** If the row rendered anything else —
//    an index, a truncated value, a label that drifted from the seed it copies — the
//    share would quietly send someone to a different board. So the assertions look for
//    the exact seed in the row's text and in the copy button's accessible name.
// 2. **A failed copy says so.** `navigator.clipboard` is absent on an insecure origin
//    (a phone hitting a dev box over LAN, exactly the setup where you'd want to read a
//    deal number), and the write can be denied. The row must not claim "Copied" in
//    those cases — a silent no-op leaves the player believing a number is on their
//    clipboard when it isn't.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which need no DOM beyond what jsdom gives.
open Vitest

@get external textContent: Html.element => string = "textContent"
@send external querySelector: (Html.element, string) => Nullable.t<Html.element> = "querySelector"
@send external getAttribute: (Html.element, string) => Nullable.t<string> = "getAttribute"

let render = (~seed, ~copied): Html.element =>
  Html.create(Menu.copySeedRow(~seed, ~copied, ~onCopy=() => ()))

let button = (row): option<Html.element> =>
  row->querySelector(".menu-copy__button")->Nullable.toOption

// The button's label — "Copy" at rest, "Copied" only after a copy that landed.
let buttonLabel = (row): string =>
  switch row->button {
  | Some(b) => b->textContent
  | None => "<no button>"
  }

describe("Menu copy-seed row (#98)", () => {
  test("shows the deal number that a `?seed=` share would carry", () => {
    let row = render(~seed=123456, ~copied=None)
    // The seed itself, and the `?seed=` form to paste it into — both name the number
    // the recipient needs, so a player can act on the row without copying at all.
    expect(row->textContent->String.includes("123456"))->toBe(true)
    expect(row->textContent->String.includes("?seed=123456"))->toBe(true)
  })

  test("names the seed in the copy button's accessible label", () => {
    // The visible label is a bare "Copy"; screen-reader users need to know *what*.
    let row = render(~seed=777, ~copied=None)
    let label = switch row->button {
    | Some(b) => b->getAttribute("aria-label")->Nullable.toOption->Option.getOr("")
    | None => ""
    }
    expect(label)->toBe("Copy seed 777")
  })

  test("confirms only a copy that actually landed", () => {
    expect(render(~seed=1, ~copied=None)->buttonLabel)->toBe("Copy")
    expect(render(~seed=1, ~copied=Some(true))->buttonLabel)->toBe("Copied")
    // The regression that matters: a *failed* copy must never read as success.
    expect(render(~seed=1, ~copied=Some(false))->buttonLabel)->toBe("Copy")
  })

  test("explains a failed copy instead of failing silently", () => {
    let failed = render(~seed=42, ~copied=Some(false))
    expect(failed->textContent->String.includes("Couldn't copy"))->toBe(true)
    // …and the seed stays on screen, so it can still be read off and typed by hand —
    // the whole fallback on a browser where the clipboard API isn't available.
    expect(failed->textContent->String.includes("42"))->toBe(true)
  })
})
