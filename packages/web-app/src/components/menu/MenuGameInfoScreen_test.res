// The game info screen, exercised in isolation. What `GameInfo` decides is pinned in
// `GameInfo_test`; what's left here is the screen's own arrangement — that the game
// names the header, and that the link out is a real link.
open Vitest
open TestDom

let render = (~game=Game.freecell, ~onClose=() => (), ~onBackToMenu=() => ()) =>
  Html.create(MenuGameInfoScreen.make({info: GameInfo.forGame(game), onClose, onBackToMenu}))

describe("MenuGameInfoScreen", () => {
  test("wears the game's own name as its title", () => {
    // The one thing that tells this screen from the other three at a glance, and the
    // reason its subject travels in `Menu.screen` rather than in a props record built
    // on every render.
    expect(render(~game=Game.simpleSimon)->textIn(".menu-title"))->toBe("Simple Simon")
  })

  test("shows the board's numbers", () => {
    expect(render()->textIn(".game-info__numbers"))->toBe("8 cascades · 4 cells · 52 cards")
  })

  test("links out to the game's article in a tab of its own", () => {
    // In place would tear the board down mid-play — the app is a PWA, and there is a
    // game behind this menu. `rel` is what stops the opened page reaching back through
    // `window.opener`.
    let link = render()->find(".game-info__link")->Option.getOrThrow
    expect(link->tag)->toBe("A")
    expect(link->attrOr("href"))->toBe("https://en.wikipedia.org/wiki/FreeCell")
    expect(link->attrOr("target"))->toBe("_blank")
    expect(link->attrOr("rel"))->toBe("noopener noreferrer")
  })

  test("goes back to the main menu, where the info button was", () => {
    // Back, not out: the ✕ beside it is what closes the whole menu.
    let log = []
    let screen = render(
      ~onBackToMenu=() => log->Array.push("back"),
      ~onClose=() => log->Array.push("close"),
    )
    screen->find(".menu-back")->Option.forEach(click)
    screen->find(".menu-close")->Option.forEach(click)
    expect(log)->toEqual(["back", "close"])
  })

  test("leaves its title inert, the ten-tap gesture being the Settings screen's alone", () => {
    // The same green `menu-title` heads all four screens; only one of them unlocks the
    // hidden settings.
    let screen = render()
    screen->find(".menu-title")->Option.forEach(click)
    expect(screen->textIn(".menu-title"))->toBe("FreeCell")
  })
})
