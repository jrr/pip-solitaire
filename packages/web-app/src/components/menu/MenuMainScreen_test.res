// The menu's main screen, exercised in isolation now that it's a component of its
// own (#307).
//
// `Menu_test` pins what **Share Seed** does through the whole pane (#98) and
// `MenuGameButton_test` pins the button itself; this file pins what's left — the
// screen's own *arrangement*, which is the part that used to be spelled out inline in
// `Menu` and is the thing a refactor here could quietly change:
//
// 1. **Three game buttons, in that order** — New, Restart, Share Seed. The share
//    tests below (and `Menu_test`'s) reach the third one positionally, so the order
//    is load-bearing beyond how it looks.
// 2. **The share line is always there.** Empty most of the time, but rendered — a
//    confirmation that appeared out of nothing would shove every section below it
//    down the panel as it came and went.
// 3. **The Games rows are spliced, not rebuilt.** SceneSwitcher owns that node; the
//    screen must hand back the very same element it was given.
// 4. **The Settings button sits in the bottom group.** `menu-section--bottom` is what
//    pushes it to the foot of the panel; without the class it drifts up under Games.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest
open TestDom

let games = Html.make("div")

let render = (
  ~shareDealSeed=None,
  ~shareDealStatus=None,
  ~onNewGame=() => (),
  ~onRestart=() => (),
  ~onShareDeal=() => (),
  ~onOpenSettings=() => (),
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

  test("splices SceneSwitcher's own rows in rather than rebuilding them", () => {
    // The very same node, so the switcher's subtree is left alone across
    // open/close re-renders.
    let screen = render()
    expect(screen->contains(games))->toBe(true)
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
