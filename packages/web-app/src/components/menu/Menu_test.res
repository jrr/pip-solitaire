// The main menu's **Share Seed** button.
//
// The button hands over a link to the *deal* on the table — `?seed=N`, which deals
// the identical board wherever it's opened.
//
// `Menu` takes a props record per screen, so only the main screen's is
// interesting here — the other two are built because the pane's record wants
// them, not because anything places them while `screen` is `Main`.
open Vitest
open TestDom

// The two screens this file never shows, and the footer under all three. Scenery:
// held fixed across every case, and never placed while `screen` is `Main`.
let settings: MenuSettingsScreen.props = {
  onClose: () => (),
  onBackToMenu: () => (),
  onOpenDebug: () => (),
  onTapSettingsTitle: () => (),
  autoCollect: true,
  onToggleAutoCollect: () => (),
  cardTilt: true,
  onToggleCardTilt: () => (),
  wiggle: Motion.Off,
  onToggleWiggle: () => (),
  revealHidden: false,
  notchDisplay: true,
  onToggleNotchDisplay: () => (),
}

let debug: MenuDebugScreen.props = {
  onClose: () => (),
  onBackToSettings: () => (),
  cutoutDebug: false,
  onToggleCutoutDebug: () => (),
  debugLog: false,
  onToggleDebugLog: () => (),
  shareEnabled: false,
  shareStatus: None,
  onShareGame: () => (),
  // The debug groups; empty stand-ins here.
  gameScenes: [],
  gameScenesOpen: false,
  debugScenes: [],
  debugScenesOpen: false,
  debugStates: [],
}

let about: AboutFooter.props = {
  version: "1.2.3",
  buildTime: "2026-08-14T04:00:00.000Z",
  updateVisible: false,
  onReload: () => (),
  refresh: Html.empty,
}

// The main menu, opened, with everything but the seed-sharing fields held fixed.
let render = (~seed, ~status): Html.element =>
  Html.create(
    Menu.make({
      open_: true,
      screen: Menu.Main,
      onClose: () => (),
      main: {
        onClose: () => (),
        onNewGame: () => (),
        onEnterSeed: () => (),
        onRestart: () => (),
        // The three under test.
        shareDealSeed: seed,
        shareDealStatus: status,
        onShareDeal: () => (),
        games: [],
        onOpenSettings: () => (),
      },
      settings,
      debug,
      about,
    }),
  )

// The Share Seed button — the second of the "this game" buttons.
let shareButton = (menu): option<Html.element> =>
  menu->find(`[aria-label="this game"] .menu-buttons button:nth-child(2)`)

// The line beneath the buttons: where a link just went, or why the button is dark.
let line = (menu): string =>
  switch menu->find(".menu-share-line") {
  | Some(el) => el->text
  | None => "<no line>"
  }

// Is the line's element there at all? An empty line and an absent one read the same
// through `line`, and only one of them holds the layout still.
let hasLine = (menu): bool => menu->find(".menu-share-line")->Option.isSome

describe("Menu Share Seed button", () => {
  test("names the seed on the table, which is what the link carries", () => {
    // On the button itself, so the label and the number a player would read out are
    // one control rather than a caption that has to be associated with it. Render
    // anything else here — an index, the previous deal's number — and the share sends
    // someone to a different board, which is the one failure this button can't afford.
    let text = switch render(~seed=Some(123456), ~status=None)->shareButton {
    | Some(b) => b->text
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
      ->find(".menu-button__value")
      ->Option.mapOr("<none>", text)
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
    | Some(b) => b->text
    | None => "<no button>"
    }
    expect(text)->toBe("Share Seed")
  })

  test("disables the button on a board with no seed, and says why", () => {
    // A demo scene, or a game resumed from a save that predates seeds being kept: there
    // is no board to point at, so the button has nothing to share.
    let menu = render(~seed=None, ~status=None)
    switch menu->shareButton {
    | Some(b) => expect(b->hasAttr("disabled"))->toBe(true)
    | None => expect("share button")->toBe("missing")
    }
    expect(menu->line)->toBe("No seed for this board.")
    // …and it's the real attribute, so the button emits no click at all — the reason
    // the handler guard behind it is only belt and braces.
    expect(render(~seed=Some(1), ~status=None)->shareButton->Option.isSome)->toBe(true)
    switch render(~seed=Some(1), ~status=None)->shareButton {
    | Some(b) => expect(b->hasAttr("disabled"))->toBe(false)
    | None => expect("share button")->toBe("missing")
    }
  })

  test("reports where the link went on the line, leaving the button alone", () => {
    // The confirmation takes the slot that was empty a moment ago; the button keeps
    // naming its seed throughout, since nothing about the deal has changed.
    let menu = render(~seed=Some(24680), ~status=Some("Link copied to clipboard."))
    expect(menu->line)->toBe("Link copied to clipboard.")
    let text = switch menu->shareButton {
    | Some(b) => b->text
    | None => "<no button>"
    }
    expect(text)->toBe("Share Seed 24680")
  })

  test("still offers the share while a status is up", () => {
    // The status is transient chrome, not a state change: the deal hasn't gone
    // anywhere, so a second press must still be possible.
    switch render(~seed=Some(24680), ~status=Some("Link copied to clipboard."))->shareButton {
    | Some(b) => expect(b->hasAttr("disabled"))->toBe(false)
    | None => expect("share button")->toBe("missing")
    }
  })
})
