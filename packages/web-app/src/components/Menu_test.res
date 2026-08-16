// The main menu's **Share Seed** button (#98).
//
// The button hands over a link to the *deal* on the table — `?seed=N`, which deals
// the identical board wherever it's opened. Two things about that are worth pinning,
// and they're what this file tests:
//
// 1. **The number on the button is the seed.** The button shows it as well as sharing
//    it, so a player can read it off (or dictate it) on a browser where the link can't
//    be delivered at all. If it rendered anything else — an index, a stale number from
//    the previous deal — the share would quietly send someone to a different board,
//    which is the one failure a share button can't afford.
// 2. **A board with no seed offers nothing.** A demo scene, or a game resumed from a
//    save that predates seeds being kept, has no board to point at. The button must be
//    genuinely `disabled` (so no click is emitted at all) rather than lit and inert,
//    and the line beneath must say why.
// 3. **The line beneath holds its slot.** It's empty while there's nothing to report,
//    but it's still *there* — a confirmation that appeared out of nothing would shove
//    every section below it down the panel as it came and went.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives. The props record
// is spelled out in full because `Menu` takes the whole chrome model — everything but
// the three share fields is scenery, held fixed across the cases.
open Vitest

@get external textContent: Html.element => string = "textContent"
@send external querySelector: (Html.element, string) => Nullable.t<Html.element> = "querySelector"
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

// The line beneath the buttons: where a link just went, or why the button is dark.
let line = (menu): string =>
  switch menu->querySelector(".menu-share-line")->Nullable.toOption {
  | Some(el) => el->textContent
  | None => "<no line>"
  }

// Is the line's element there at all? An empty line and an absent one read the same
// through `line`, and only one of them holds the layout still.
let hasLine = (menu): bool =>
  menu->querySelector(".menu-share-line")->Nullable.toOption->Option.isSome

describe("Menu Share Seed button (#98)", () => {
  test("names the seed on the table, which is what the link carries", () => {
    // On the button itself, so the label and the number a player would read out are
    // one control rather than a caption that has to be associated with it.
    let text = switch render(~seed=Some(123456), ~status=None)->shareButton {
    | Some(b) => b->textContent
    | None => "<no button>"
    }
    expect(text)->toBe("Share Seed 123456")
  })

  test("sets the seed apart from the label, as a value rather than more prose", () => {
    // The digits are their own element so CSS can give them the mono stack and a
    // dimmer colour; without it the number reads as part of the sentence.
    let value = switch render(~seed=Some(777), ~status=None)->shareButton {
    | Some(b) =>
      b
      ->querySelector(".menu-button__value")
      ->Nullable.toOption
      ->Option.mapOr("<none>", textContent)
    | None => "<no button>"
    }
    expect(value)->toBe("777")
  })

  test("says nothing on the line while the seed is simply on the button", () => {
    // Empty, but the element is still rendered — `min-height` holds the slot so the
    // confirmation below can appear and clear without moving the panel.
    expect(render(~seed=Some(123456), ~status=None)->line)->toBe("")
    expect(render(~seed=Some(123456), ~status=None)->hasLine)->toBe(true)
  })

  test("shows the bare label when there's no seed to name", () => {
    let text = switch render(~seed=None, ~status=None)->shareButton {
    | Some(b) => b->textContent
    | None => "<no button>"
    }
    expect(text)->toBe("Share Seed")
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

  test("reports where the link went on the line, leaving the button alone", () => {
    // The confirmation takes the slot that was empty a moment ago; the button keeps
    // naming its seed throughout, since nothing about the deal has changed.
    let menu = render(~seed=Some(24680), ~status=Some("Link copied to clipboard."))
    expect(menu->line)->toBe("Link copied to clipboard.")
    let text = switch menu->shareButton {
    | Some(b) => b->textContent
    | None => "<no button>"
    }
    expect(text)->toBe("Share Seed 24680")
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
