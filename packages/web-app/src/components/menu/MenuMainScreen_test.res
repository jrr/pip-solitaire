// The menu's main screen, exercised in isolation.
//
// `Menu_test` pins what **Share Seed** does through the whole pane and
// `MenuGameButton_test` pins the button itself; this file pins what's left — the
// screen's own *arrangement*, the thing a refactor here could quietly change.
open Vitest
open TestDom

let render = (
  ~shareDealSeed=None,
  ~shareDealStatus=None,
  ~onNewGame=() => (),
  ~onEnterSeed=() => (),
  ~onRestart=() => (),
  ~onShareDeal=() => (),
  ~onOpenSettings=() => (),
  ~games: array<MenuRow.entry>=[],
) =>
  Html.create(
    MenuMainScreen.make({
      onClose: () => (),
      onNewGame,
      onEnterSeed,
      onRestart,
      shareDealSeed,
      shareDealStatus,
      onShareDeal,
      games,
      onOpenSettings,
    }),
  )

// A section by its accessible name, which is how the two groups of controls are told
// apart now that there are two.
let section = (screen, label): element => screen->find(`[aria-label="${label}"]`)->Option.getExn

describe("MenuMainScreen", () => {
  test("splits the controls into a board to open and the board in hand", () => {
    // Which board you get is the question a player has, so it's the one the screen
    // asks: "new game" offers the two ways to a board that isn't this one, "this
    // game" what can be done with the one on the table. The share tests below (and
    // `Menu_test`'s) reach Share Seed positionally within its group, so the order
    // inside each is load-bearing beyond how it looks.
    let screen = render(~shareDealSeed=Some(4242))
    expect(screen->section("new game")->findAll("button")->Array.map(text))->toEqual([
      "Random",
      "Enter Seed",
    ])
    expect(screen->section("this game")->findAll("button")->Array.map(text))->toEqual([
      "Restart",
      "Share Seed 4242",
    ])
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
    expect(log)->toEqual(["new", "enter seed", "restart", "share"])
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
