// The menu's main screen, exercised in isolation now that it's a component of its
// own (#307).
//
// `Menu_test` pins what **Share Seed** does through the whole pane (#98) and
// `MenuGameButton_test` pins the button itself; this file pins what's left — the
// screen's own *arrangement*, the thing a refactor here could quietly change:
//
// 1. **Three game buttons, in that order** — New, Restart, Share Seed. The share
//    tests below (and `Menu_test`'s) reach the third one positionally, so the order
//    is load-bearing beyond how it looks.
// 2. **The share line is always there.** Empty most of the time, but rendered — a
//    confirmation that appeared out of nothing would shove every section below it
//    down the panel as it came and went.
// 3. **The Games rows are drawn from the list handed in** (#337), in order, as
//    `<MenuRow>`s, with the highlight on whichever one says it's selected. The
//    switcher hands over the list and builds no DOM, so this is where its rows are
//    pinned.
// 4. **The Settings button sits in the bottom group.** `menu-section--bottom` is what
//    pushes it to the foot of the panel; without the class it drifts up under Games.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest
open TestDom

let render = (
  ~shareDealSeed=None,
  ~shareDealStatus=None,
  ~onNewGame=() => (),
  ~onRestart=() => (),
  ~onShareDeal=() => (),
  ~onOpenSettings=() => (),
  ~games: array<MenuRow.entry>=[],
) =>
  Html.create(
    MenuMainScreen.make({
      onClose: () => (),
      onNewGame,
      onRestart,
      shareDealSeed,
      shareDealStatus,
      onShareDeal,
      games,
      onOpenSettings,
    }),
  )

let gameButtons = (screen): array<string> =>
  screen->findAll(".menu-buttons button")->Array.map(text)

describe("MenuMainScreen (#307)", () => {
  test("offers New, Restart and Share Seed, in that order", () => {
    expect(render(~shareDealSeed=Some(4242))->gameButtons)->toEqual([
      "New",
      "Restart",
      "Share Seed 4242",
    ])
  })

  test("wires each game button to its own action", () => {
    let log = []
    let screen = render(
      ~shareDealSeed=Some(1),
      ~onNewGame=() => log->Array.push("new"),
      ~onRestart=() => log->Array.push("restart"),
      ~onShareDeal=() => log->Array.push("share"),
    )
    screen->findAll(".menu-buttons button")->Array.forEach(click)
    expect(log)->toEqual(["new", "restart", "share"])
  })

  test("keeps the share line's slot even when it has nothing to say", () => {
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
    // The switcher's rows, now that they arrive as data (#337): the labels in order,
    // and the highlight — `menu-row--active` plus `aria-current` — on the scene
    // mounted. A second game would list beneath the first, which is what this section
    // is a section for.
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
    let taps = ref(0)
    let screen = render(~onOpenSettings=() => taps := taps.contents + 1)
    let button = screen->find(".menu-section--bottom .menu-button")
    expect(button->Option.mapOr("<missing>", text))->toBe("Settings")
    button->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })
})
