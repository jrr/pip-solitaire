// The `AboutFooter`: two elements, in an order, with nothing between them that can
// change height. It is anchored at the foot of the panel, so anything here that grew
// would shove the settings above it — which is why the update controls, the two things
// about a build that come and go, live on the About screen this button opens rather than
// in here (see `AboutFooter.res`, `MenuAboutScreen_test`).
open Vitest
open TestDom

let render = (~onOpenAbout=() => ()): Html.element =>
  Html.create(
    AboutFooter.make({version: "1.2.3", buildTime: "2026-07-23T20:20:00.000Z", onOpenAbout}),
  )

describe("AboutFooter", () => {
  test("is a button over the build string, and nothing else", () => {
    // The button is what a hand comes down here for; the version is its caption. No
    // heading over the pair: "About" said over a build string says it twice, and the
    // screen this sits on is already titled — the band's `aria-label` is the half of a
    // heading that was doing work.
    let footer = render()
    expect(footer->attrOr("aria-label"))->toBe("About")
    expect(footer->children->Array.map(tag))->toEqual(["BUTTON", "DIV"])
    expect(footer->findAll("h2")->Array.length)->toBe(0)
    expect(footer->find("button")->Option.mapOr("", text))->toBe("About")
    expect(footer->find("#version-badge")->Option.mapOr("", text))->toBe(
      "v1.2.3 · " ++ VersionBadge.formatBuildTime("2026-07-23T20:20:00.000Z"),
    )
  })

  test("the button asks for the About screen", () => {
    let log = []
    render(~onOpenAbout=() => log->Array.push("about"))->find("button")->Option.forEach(click)
    expect(log)->toEqual(["about"])
  })
})
