// The About screen: the app's name and what it is, the link to the source, and the
// build with its two update controls. What the ↻ Update button *is* in either of its
// shapes is `UpdateButton_test`'s; what's left here is that this screen places the
// reserved one, that the link out carries the three attributes that make it safe to
// follow, and that the name is the screen's own heading rather than the header bar's.
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
let updateButton = screen => screen->find(".menu-update")

describe("MenuAboutScreen", () => {
  test("says the app's name in its own body, with no title in the header bar", () => {
    // Every other screen is named for what it holds and its header says so; this one is
    // about the app, so the name is the content — and a heading in the bar as well would
    // be the screen's second, naming it twice.
    let screen = render()
    expect(screen->textIn(".menu-title"))->toBe("Pip")
    expect(screen->find(".menu-panel__header .menu-title")->Option.isSome)->toBe(false)
    expect(screen->find(".about-wordmark")->Option.isSome)->toBe(true)
    // …and the way back is still in the bar it left.
    expect(screen->find(".menu-panel__header .menu-back")->Option.isSome)->toBe(true)
  })

  test("reads: the name, what it is, where it came from — then the build", () => {
    // One band a reader takes in as a paragraph, and then the block they may have come
    // for, which is the one with a heading to find it by.
    let screen = render()
    let bands = screen->findAll(".menu-screen > *")
    expect(bands->Array.map(el => el->attrOr("aria-label")))->toEqual(["<missing>", "build"])
    expect(bands->Array.getUnsafe(0)->children->Array.map(tag))->toEqual(["DIV", "H1", "P", "A"])
    // The icon is the app's own, drawn from the vnode the PWA icons are rasterized from,
    // and decorative: the wordmark beside it is what a reader hears.
    expect(screen->find(".about-icon > svg")->Option.isSome)->toBe(true)
    expect(screen->find(".about-icon")->Option.mapOr("", el => el->attrOr("aria-hidden")))->toBe(
      "true",
    )
    expect(screen->textIn(".about-blurb"))->toBe(
      "I made this for myself but I hope you like it too.",
    )
    expect(screen->textIn("[aria-label='build'] .menu-section__heading"))->toBe("Build")
  })

  test("sets the build string out as the subject, version first", () => {
    // The screen the Settings footer's caption is a caption *of*: the version on its own
    // line, and the build time — the same string `VersionBadge` formats for that footer
    // — under it.
    let screen = render()
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

  test("takes the reserved shape of the Update button, inside the build row", () => {
    // The *inline* one, which keeps its box when there's nothing to update — unlike the
    // main menu's band, which is absent until there is. Reserved in a row two lines of
    // build string tall, so it comes and goes without moving the check below it.
    switch render(~refresh=check)->updateButton {
    | Some(b) =>
      expect(b->classes->String.includes("menu-update--inline"))->toBe(true)
      expect(b->classes->String.includes("menu-update--hidden"))->toBe(true)
    | None => expect("update button")->toBe("missing")
    }
    expect(
      render(~refresh=check)
      ->find(".about-build > .menu-update")
      ->Option.isSome,
    )->toBe(true)
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
