// The main menu's **Share Seed** button (#98).
//
// The button hands over a link to the *deal* on the table — `?seed=N`, which deals
// the identical board wherever it's opened. Two things about that are worth pinning,
// and they're what this file tests:
//
// 1. **The number on screen is the seed.** The group shows it as well as sharing it,
//    so a player can read it off (or dictate it) on a browser where the link can't be
//    delivered at all. If the line rendered anything else — an index, a stale number
//    from the previous deal — the share would quietly send someone to a different
//    board, which is the one failure a share button can't afford.
// 2. **A board with no seed offers nothing.** A demo scene, or a game resumed from a
//    save that predates seeds being kept, has no board to point at. The button must be
//    genuinely `disabled` (so no click is emitted at all) rather than lit and inert,
//    and the line must say why.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives. The props record
// is spelled out in full because `Menu` takes the whole chrome model — everything but
// the three share fields is scenery, held fixed across the cases.
open Vitest

@get external textContent: Html.element => string = "textContent"
@send external querySelector: (Html.element, string) => Nullable.t<Html.element> = "querySelector"
@send external getAttribute: (Html.element, string) => Nullable.t<string> = "getAttribute"
@send external hasAttribute: (Html.element, string) => bool = "hasAttribute"

// The main menu, opened, with everything but the seed-sharing fields held fixed.
let render = (~seed, ~status): Html.element =>
  Html.create(
    Menu.make({
      open_: true,
      screen: Menu.Main,
      onClose: () => (),
      onOpenSettings: () => (),
      onBackToMenu: () => (),
      onOpenDebug: () => (),
      onBackToSettings: () => (),
      onNewGame: () => (),
      onRestart: () => (),
      // The three under test.
      shareDealSeed: seed,
      shareDealStatus: status,
      onShareDeal: () => (),
      // The externally-owned nodes the menu splices in; empty stand-ins here.
      games: Html.make("div"),
      debugScenes: Html.make("div"),
      debugStates: Html.make("div"),
      cutoutDebug: false,
      onToggleCutoutDebug: () => (),
      debugLog: false,
      onToggleDebugLog: () => (),
      shareEnabled: false,
      shareStatus: None,
      onShareGame: () => (),
      autoCollect: true,
      onToggleAutoCollect: () => (),
      cardTilt: true,
      onToggleCardTilt: () => (),
      wiggle: Motion.Off,
      onToggleWiggle: () => (),
      notchDisplay: true,
      onToggleNotchDisplay: () => (),
      revealHidden: false,
      onTapSettingsTitle: () => (),
      refreshButton: None,
      version: "1.2.3",
      buildTime: "2026-08-14T04:00:00.000Z",
      updateVisible: false,
      onReload: () => (),
    }),
  )

// The Share Seed button — the third of the "game" buttons.
let shareButton = (menu): option<Html.element> =>
  menu->querySelector(".menu-buttons button:nth-child(3)")->Nullable.toOption

// The line beneath the buttons: the seed, or where a link just went.
let line = (menu): string =>
  switch menu->querySelector(".menu-share-line")->Nullable.toOption {
  | Some(el) => el->textContent
  | None => "<no line>"
  }

describe("Menu Share Seed button (#98)", () => {
  test("names the seed on the table, which is what the link carries", () => {
    expect(render(~seed=Some(123456), ~status=None)->line)->toBe("Seed 123456")
  })

  test("names the seed in the button's accessible label too", () => {
    // The visible label says what kind of thing goes out; the number is the entire
    // content of the link, so a screen-reader user needs it named too.
    let label = switch render(~seed=Some(777), ~status=None)->shareButton {
    | Some(b) => b->getAttribute("aria-label")->Nullable.toOption->Option.getOr("")
    | None => "<no button>"
    }
    expect(label)->toBe("Share seed 777")
  })

  test("disables the button on a board with no seed, and says why", () => {
    let menu = render(~seed=None, ~status=None)
    switch menu->shareButton {
    | Some(b) => expect(b->hasAttribute("disabled"))->toBe(true)
    | None => expect("share button")->toBe("missing")
    }
    expect(menu->line)->toBe("No seed for this board.")
    // …and it's the real attribute, so the button emits no click at all — the reason
    // the handler guard behind it is only belt and braces.
    expect(render(~seed=Some(1), ~status=None)->shareButton->Option.isSome)->toBe(true)
    switch render(~seed=Some(1), ~status=None)->shareButton {
    | Some(b) => expect(b->hasAttribute("disabled"))->toBe(false)
    | None => expect("share button")->toBe("missing")
    }
  })

  test("reports where the link went, in place of the seed", () => {
    // One slot, so a confirmation appears and clears without moving the buttons above
    // it. While it's up it wins; when it clears, the seed is back (above).
    let menu = render(~seed=Some(24680), ~status=Some("Link copied to clipboard."))
    expect(menu->line)->toBe("Link copied to clipboard.")
  })

  test("still offers the share while a status is up", () => {
    // The status is transient chrome, not a state change: the deal hasn't gone
    // anywhere, so a second press must still be possible.
    switch render(~seed=Some(24680), ~status=Some("Link copied to clipboard."))->shareButton {
    | Some(b) => expect(b->hasAttribute("disabled"))->toBe(false)
    | None => expect("share button")->toBe("missing")
    }
  })
})
