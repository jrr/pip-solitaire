// The About screen, which is a door and a header and nothing else yet. What is worth
// pinning while it is empty is exactly that: the two ways off it go to different places,
// and it is the one screen in the pane whose back button doesn't return to the main menu.
open Vitest
open TestDom

let render = (~onClose=() => (), ~onBackToSettings=() => ()) =>
  Html.create(MenuAboutScreen.make({onClose, onBackToSettings}))

describe("MenuAboutScreen", () => {
  test("is titled About and is otherwise empty for now", () => {
    let screen = render()
    expect(screen->textIn(".menu-title"))->toBe("About")
    // The column every other screen writes into, so the first paragraph added lands in
    // the panel's own gaps rather than against the header.
    expect(screen->find(".menu-screen")->Option.mapOr("<missing>", text))->toBe("")
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
