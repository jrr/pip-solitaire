// The About screen: the build string set as the subject, the two update controls, and
// the link to the source. What is pinned here is what a browser can't be asked about
// cheaply — that the ↻ Update button keeps its box when there is nothing to update, and
// that the link out carries the three attributes that make it safe to follow.
open Vitest
open TestDom

let render = (
  ~updateVisible=false,
  ~refresh=Html.empty,
  ~onReload=() => (),
  ~onClose=() => (),
  ~onBackToSettings=() => (),
) =>
  Html.create(
    MenuAboutScreen.make({
      version: "01e8f5f",
      buildTime: "2026-07-23T20:20:00.000Z",
      updateVisible,
      onReload,
      refresh,
      onClose,
      onBackToSettings,
    }),
  )

let check = RefreshControl.make({label: "Check for updates", busy: false, onClick: () => ()})
let updateButton = screen => screen->find(".menu-update__button")

describe("MenuAboutScreen", () => {
  test("sets the build string out as the subject, version first", () => {
    // The screen the Settings footer's caption is a caption *of*: the version on its own
    // line, and the build time — the same string `VersionBadge` formats for that footer
    // — under it.
    let screen = render()
    expect(screen->textIn(".menu-title"))->toBe("About")
    expect(screen->textIn(".about-build__version"))->toBe("v01e8f5f")
    expect(screen->textIn(".about-build__time"))->toBe(
      VersionBadge.formatBuildTime("2026-07-23T20:20:00.000Z"),
    )
  })

  test("holds both update controls, the check and the switch-over", () => {
    // They are two halves of one job — a check that found something has to have
    // somewhere to report it — so a screen with one and not the other is the bug this
    // catches.
    let screen = render(~refresh=check, ~updateVisible=true)
    expect(screen->find(".menu-refresh")->Option.mapOr("", text))->toBe("Check for updates")
    expect(screen->updateButton->Option.isSome)->toBe(true)
  })

  test("keeps the Update button's box reserved when there is nothing to update", () => {
    // Reserved with `visibility`, never the collapsing `hidden` attribute: the button
    // rides the end of the build row, and a row that changed height as an update landed
    // would move the controls under it.
    switch render(~refresh=check)->updateButton {
    | Some(b) =>
      expect(b->hasAttr("hidden"))->toBe(false)
      expect(b->classes->String.includes("menu-update--hidden"))->toBe(true)
      expect(b->attrOr("aria-hidden"))->toBe("true")
    | None => expect("update button")->toBe("missing")
    }
    switch render(~refresh=check, ~updateVisible=true)->updateButton {
    | Some(b) => expect(b->classes->String.includes("menu-update--hidden"))->toBe(false)
    | None => expect("update button")->toBe("missing")
    }
  })

  test("offers no check at all where the browser can say nothing about updates", () => {
    // `Main` hands over an empty node until a service-worker state has been detected.
    // The Update button is still there, reserved: it is hidden, never absent.
    let screen = render()
    expect(screen->find(".menu-refresh")->Option.isSome)->toBe(false)
    expect(screen->updateButton->Option.isSome)->toBe(true)
  })

  test("links to the repository, marked and in a tab of its own", () => {
    // In place would tear the board down mid-play — the app is a PWA. `rel` is what
    // stops the opened page reaching back through `window.opener`.
    let link = render()->find(".about-link")->Option.getOrThrow
    expect(link->tag)->toBe("A")
    expect(link->attrOr("href"))->toBe("https://github.com/jrr/pip-solitaire")
    expect(link->attrOr("target"))->toBe("_blank")
    expect(link->attrOr("rel"))->toBe("noopener noreferrer")
    expect(link->textIn(".about-link__name"))->toBe("jrr/pip-solitaire")
    // The mark is the link's decoration, not its name: a reader hears the repository.
    expect(
      link->find(".about-link__mark")->Option.mapOr("", el => el->attrOr("aria-hidden")),
    )->toBe("true")
  })

  test("goes back to Settings, where the button was, and closes from the ✕", () => {
    // A level below Settings, like Debug: back is one step up rather than all the way
    // out, and the ✕ beside it still closes the whole menu.
    let log = []
    let screen = render(
      ~onBackToSettings=() => log->Array.push("back"),
      ~onClose=() => log->Array.push("close"),
    )
    screen->find(".menu-back")->Option.forEach(click)
    screen->find(".menu-close")->Option.forEach(click)
    expect(log)->toEqual(["back", "close"])
  })
})
