// The game info screen, exercised in isolation. What `GameInfo` decides is pinned in
// `GameInfo_test`; what's left here is the screen's own arrangement — that the game
// names the header, and that the link out is a real link.
open Vitest
open TestDom

let render = (
  ~game=Game.freecell,
  ~variants=?,
  ~tilt=false,
  ~onClose=() => (),
  ~onBackToMenu=() => (),
) =>
  Html.create(
    MenuGameInfoScreen.make({
      info: GameInfo.forGame(game),
      ?variants,
      tilt,
      onClose,
      onBackToMenu,
    }),
  )

// The picker as `Main` builds one: every board of a family, with `game` the one the
// screen is about. What it draws is `MenuVariantPicker`'s claim; what this file asks is
// where the screen puts it and whether it is there at all.
let pickerFor = (family: Game.family, ~on: Game.t): MenuVariantPicker.props => {
  game: family.name,
  noun: GameVariant.nounFor(family),
  choices: family.variants->Array.map((v): MenuVariantPicker.choice => {
    mark: GameVariant.forVariant(v),
    selected: v.game.id == on.id,
    onChoose: () => (),
  }),
}

describe("MenuGameInfoScreen", () => {
  test("wears the game's name as its title", () => {
    // The one thing that tells this screen from the other three at a glance, and the
    // reason its subject travels in `Menu.screen` rather than in a props record built
    // on every render. Which name that is — a board's own, or its family's — is
    // `GameInfo`'s (`nameOf`), tested there.
    expect(render(~game=Game.simpleSimon)->textIn(".menu-title"))->toBe("Simple Simon")
    expect(render(~game=Game.spiderette)->textIn(".menu-title"))->toBe("Spiderette")
  })

  test("shows the opening board, in the table's own markup, above the numbers", () => {
    // A still of the board and not a board: one image, named for a reader, with a card
    // per card FreeCell deals. What the still gets right is `BoardPreview_test`'s.
    let screen = render()
    let still = screen->find(".game-info__preview .board-preview")->Option.getOrThrow
    expect(still->attrOr("role"))->toBe("img")
    expect(still->attrOr("aria-label"))->toBe("FreeCell, as dealt")
    expect(still->findAll(".stacking-card")->Array.length)->toBe(52)
  })

  test("draws every size of a family in one box, so the picker moves nothing below it", () => {
    // The screen hands the still the family's box (`GameInfo.previewBox`) rather than
    // letting each board size its own picture: without it, picking Micro grew the mat by
    // half again and carried the numbers, the picker and the link down the panel with
    // it. Which box that is, is `GameInfo`'s (`previewBoxFor`), tested there.
    let shapeOf = game => render(~game)->find(".board-preview")->Option.getOrThrow->attrOr("style")
    expect(shapeOf(Game.micro))->toBe(shapeOf(Game.freecell))
    expect(shapeOf(Game.mini))->toBe(shapeOf(Game.freecell))
  })

  test("lays the still's cards as the Sloppy placement setting has the table's", () => {
    // The setting reaches the screen as a prop, so a flip redraws the still with the
    // next render — tilted with the table, square with it.
    let tilted = screen => screen->findAll(".stacking-card[style*='--card-rot']")->Array.length
    expect(tilted(render(~tilt=true)))->toBe(52)
    expect(tilted(render(~tilt=false)))->toBe(0)
  })

  test("says what the game is in a paragraph, the same one for every board of a family", () => {
    // The copy is generic on purpose: it describes FreeCell, not the size in hand, so
    // the picker under it changes the board and the numbers and leaves the words alone.
    // Which words those are is `GameInfo`'s (`descriptionFor`), tested there.
    let prose = game => render(~game)->textIn(".game-info__prose")
    expect(prose(Game.freecell)->String.startsWith("Build down"))->toBe(true)
    expect(prose(Game.micro))->toBe(prose(Game.freecell))
    // The stock is the whole of what Spiderette's paragraph says that Simple Simon's
    // doesn't, so it is what tells the two apart on screen.
    expect(prose(Game.spiderette)->String.includes("stock"))->toBe(true)
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

  test("offers the family's other boards, headed with the word for what they vary in", () => {
    let screen = render(
      ~game=Game.spiderette,
      ~variants=pickerFor(Game.spideretteFamily, ~on=Game.spiderette),
    )
    // "PACK" on screen — the heading is uppercased by the stylesheet, so the word here is
    // the picker's own and nothing on this screen knows which families there are.
    expect(screen->textIn("[aria-label='pack'] .menu-section__heading"))->toBe("pack")
    expect(screen->findAll(".menu-variant-picker__choice")->Array.length)->toBe(3)
  })

  test("describes the game first and offers the one control last", () => {
    // Picture, the numbers counting it, how it plays, the rules in full — and then the
    // picker, the only control on a screen that is otherwise all description.
    let screen = render(~game=Game.mini, ~variants=pickerFor(Game.freecellFamily, ~on=Game.mini))
    expect(
      screen->findAll(".menu-screen > *")->Array.map(el => el->attrOr("aria-label")),
    )->toEqual(["preview", "numbers", "how it plays", "reference", "size"])
  })

  test("has no such section at all on a game that is a game on its own", () => {
    // Not an empty band: Simple Simon has no family, so there is no choice to offer and
    // nothing for a heading to head — and the screen ends on the link out.
    let screen = render(~game=Game.simpleSimon)
    expect(screen->findAll(".menu-variant-picker")->Array.length)->toBe(0)
    expect(
      screen->findAll(".menu-screen > *")->Array.map(el => el->attrOr("aria-label")),
    )->toEqual(["preview", "numbers", "how it plays", "reference"])
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
