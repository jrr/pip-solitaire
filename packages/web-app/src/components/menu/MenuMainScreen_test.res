// The menu's main screen, exercised in isolation.
//
// `Menu_test` pins what **Share** does through the whole pane and
// `MenuGameButton_test` pins the button itself; this file pins what's left — the
// screen's own *arrangement*, the thing a refactor here could quietly change.
open Vitest
open TestDom

let render = (
  ~gameName=Some("FreeCell"),
  ~shareDealSeed=None,
  ~shareDealStatus=None,
  ~onNewGame=() => (),
  ~onEnterSeed=() => (),
  ~onRestart=() => (),
  ~onShareDeal=() => (),
  ~onOpenSettings=() => (),
  ~games: array<MenuGameRow.props>=[],
) =>
  Html.create(
    MenuMainScreen.make({
      onClose: () => (),
      onNewGame,
      onEnterSeed,
      onRestart,
      gameName,
      shareDealSeed,
      shareDealStatus,
      onShareDeal,
      games,
      onOpenSettings,
    }),
  )

// A section by its accessible name, which is how the two groups of controls are told
// apart now that there are two.
let section = (screen, label): element => screen->find(`[aria-label="${label}"]`)->Option.getOrThrow

describe("MenuMainScreen", () => {
  test("splits the controls into the board in hand and a board to open", () => {
    // Which board you get is the question a player has, so it's the one the screen
    // asks: "this game" is what can be done with the one on the table, "new game" the
    // two ways to a board that isn't this one. The board in hand leads, being the one
    // already on the screen behind the menu. The share tests below (and `Menu_test`'s)
    // reach Share positionally within its group, so the order inside each is
    // load-bearing beyond how it looks.
    let screen = render(~shareDealSeed=Some(4242))
    expect(screen->section("this game")->findAll("button")->Array.map(text))->toEqual([
      "Restart",
      "Share",
    ])
    expect(screen->section("new game")->findAll("button")->Array.map(text))->toEqual([
      "New Deal",
      "Enter Seed",
    ])
    // …and in that order down the panel, which is what the aria lookups above can't see.
    expect(screen->findAll(".menu-section__heading")->Array.map(text))->toEqual([
      "FreeCell #4242",
      "Don’t like it?",
      "Games",
    ])
  })

  test("names the game and its deal on the heading of the section that acts on them", () => {
    // Both buttons under it are about that one board — Restart re-deals it, Share hands
    // over a link to it — so the number belongs to the group, not to either control.
    // Keeping it off the buttons is also what lets the four be one grid: a label that
    // grows by five digits on some boards can't line up with the pair above.
    let screen = render(~gameName=Some("Simple Simon"), ~shareDealSeed=Some(4242))
    expect(screen->section("this game")->textIn(".menu-section__heading"))->toBe(
      "Simple Simon #4242",
    )
  })

  test("falls back to naming the section on a scene that is no game", () => {
    // A demo has no game behind it and no seed to name: the heading says what the
    // group is, and the share line below says why the button is dark.
    let screen = render(~gameName=None, ~shareDealSeed=None)
    expect(screen->section("this game")->textIn(".menu-section__heading"))->toBe("this game")
    expect(screen->find(".menu-section__value")->Option.isSome)->toBe(false)
  })

  test("leaves the heading bare on a board with no seed", () => {
    // A game resumed from a save written before seeds were kept: the game is still
    // named, and there is simply no number after it rather than a stray gap.
    let screen = render(~shareDealSeed=None)
    expect(screen->section("this game")->textIn(".menu-section__heading"))->toBe("FreeCell")
    expect(screen->find(".menu-section__value")->Option.isSome)->toBe(false)
  })

  test("wires each game button to its own action", () => {
    let log = []
    let screen = render(
      ~shareDealSeed=Some(1),
      ~onNewGame=() => log->Array.push("new"),
      ~onEnterSeed=() => log->Array.push("enter seed"),
      ~onRestart=() => log->Array.push("restart"),
      ~onShareDeal=() => log->Array.push("share"),
    )
    screen->findAll(".menu-buttons button")->Array.forEach(click)
    expect(log)->toEqual(["restart", "share", "new", "enter seed"])
  })

  test("asks for the seed dialog rather than holding a field of its own", () => {
    // Enter Seed reports the press and stops there: the typing, the parse and the
    // deal are all `SeedDialog`'s, raised over this screen by the chrome. A field
    // here would be a second place a deal number could be typed.
    let screen = render()
    expect(screen->has("input"))->toBe(false)
  })

  test("keeps the share line's slot even when it has nothing to say", () => {
    // Empty but rendered: a confirmation that appeared out of nothing would shove every
    // section below it down the panel as it came and went.
    let quiet = render(~shareDealSeed=Some(9))
    expect(quiet->find(".menu-share-line")->Option.isSome)->toBe(true)
    expect(quiet->textIn(".menu-share-line"))->toBe("")
  })

  test("uses the line to report a share, or to say why there's nothing to share", () => {
    expect(render(~shareDealSeed=None)->find(".menu-share-line")->Option.mapOr("", text))->toBe(
      "No seed for this board.",
    )
    expect(
      render(~shareDealSeed=Some(9), ~shareDealStatus=Some("Link copied to clipboard."))
      ->find(".menu-share-line")
      ->Option.mapOr("", text),
    )->toBe("Link copied to clipboard.")
  })

  test("draws the games it's given as rows, marking the one that's showing", () => {
    // The switcher's rows, which arrive as data: the labels in order, and the highlight
    // — `menu-row--active` plus `aria-current` — on the scene mounted. The switcher
    // builds no DOM of its own, so this is where its rows are pinned. A second game
    // would list beneath the first, which is what this section is a section for.
    //
    // Neither row is handed an `onInfo`, so these are the class lists of the plain
    // row — the shape the list keeps while the Game info flag is off.
    let taps = []
    let screen = render(
      ~games=[
        {label: "freecell", selected: true, onSelect: () => taps->Array.push("freecell")},
        {label: "spider", selected: false, onSelect: () => taps->Array.push("spider")},
      ],
    )
    let rows = screen->findAll("nav .menu-row")
    expect(rows->Array.map(text))->toEqual(["freecell", "spider"])
    expect(rows->Array.map(classes))->toEqual([
      "menu-row menu-row--action menu-row--active",
      "menu-row menu-row--action",
    ])
    expect(rows->Array.map(row => row->attr("aria-current")))->toEqual([Some("true"), None])
    // …and each row runs its own action.
    rows->Array.forEach(click)
    expect(taps)->toEqual(["freecell", "spider"])
  })

  test("gives a game an info button only when it was handed somewhere to go", () => {
    // The Game info flag, as this screen sees it: a game with an `onInfo` gets the
    // segmented row, one without gets the plain full-width button it always had. Both
    // shapes in one render, because the flag is a *list*-wide fact everywhere else and
    // this is the only place that could quietly make it a per-row one.
    let opened = []
    let screen = render(
      ~games=[
        {
          label: "FreeCell",
          selected: true,
          onSelect: () => (),
          onInfo: () => opened->Array.push("FreeCell"),
        },
        {label: "Simple Simon", selected: false, onSelect: () => ()},
      ],
    )
    expect(
      screen->findAll("nav .menu-game-row__info")->Array.map(el => el->attrOr("aria-label")),
    )->toEqual(["About FreeCell"])
    screen->findAll("nav .menu-game-row__info")->Array.forEach(click)
    expect(opened)->toEqual(["FreeCell"])
    // …and the rows themselves are unchanged: two of them, in order, whichever shape
    // each took.
    expect(screen->findAll("nav .menu-row")->Array.map(text))->toEqual(["FreeCell", "Simple Simon"])
  })

  test("hangs the Settings button off the bottom group, above the About footer", () => {
    // `menu-section--bottom` is what pushes it to the foot of the panel; without the
    // class it drifts up under Games.
    let taps = ref(0)
    let screen = render(~onOpenSettings=() => taps := taps.contents + 1)
    let button = screen->find(".menu-section--bottom .menu-button")
    expect(button->Option.mapOr("<missing>", text))->toBe("Settings")
    button->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })
})
