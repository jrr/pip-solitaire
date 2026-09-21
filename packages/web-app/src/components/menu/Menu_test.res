// The pane's own two jobs, which is all this file covers: the main menu's **Share**
// button — the button hands over a link to the *deal* on the table, `?seed=N`, which
// deals the identical board wherever it's opened — and placing the screen the `screen`
// variant names.
//
// `Menu` takes a props record per screen, so only the screen under test has anything
// interesting in its record; the others are built because the pane's record wants them,
// not because anything places them.
open Vitest
open TestDom

// The screens this file never shows. Scenery: held fixed across every case, and never
// placed while `screen` is `Main`.
let settings: MenuSettingsScreen.props = {
  model: {
    autoCollect: true,
    cardTilt: true,
    wiggle: Motion.Off,
    wantsShake: false,
    notchDisplay: true,
    betaFeatures: false,
    hidden: {revealed: false, taps: 0},
  },
  dispatch: _ => (),
  onClose: () => (),
  onBackToMenu: () => (),
  onOpenDebug: () => (),
}

let debug: MenuDebugScreen.props = {
  onClose: () => (),
  onBackToSettings: () => (),
  cutoutDebug: false,
  onToggleCutoutDebug: () => (),
  debugLog: false,
  onToggleDebugLog: () => (),
  autoplayEnabled: false,
  autoplayStatus: None,
  onAutoplay: () => (),
  shareEnabled: false,
  shareStatus: None,
  onShareGame: () => (),
  onClearStored: () => (),
  // The debug groups; empty stand-ins here.
  gameScenes: [],
  gameScenesOpen: false,
  debugScenes: [],
  debugScenesOpen: false,
  debugStates: [],
}

let about: MenuAboutScreen.props = {
  version: "1.2.3",
  buildTime: "2026-08-14T04:00:00.000Z",
  updateVisible: false,
  onReload: () => (),
  refresh: Html.empty,
  onClose: () => (),
  onBackToMenu: () => (),
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
        gameName: Some("FreeCell"),
        // The three under test.
        shareDealSeed: seed,
        shareDealStatus: status,
        onShareDeal: () => (),
        games: [],
        onOpenSettings: () => (),
        onOpenAbout: () => (),
        updateVisible: false,
        onReload: () => (),
      },
      settings,
      debug,
      // The info screen's builder — scenery too, since `screen` is `Main` throughout
      // and the pane never calls it.
      gameInfo: info => {info, tilt: false, onClose: () => (), onBackToMenu: () => ()},
      about,
    }),
  )

// The pane with a screen chosen, for the placement cases below.
let paneOn = (screen): Html.element =>
  Html.create(
    Menu.make({
      open_: true,
      screen,
      onClose: () => (),
      main: {
        onClose: () => (),
        onNewGame: () => (),
        onEnterSeed: () => (),
        onRestart: () => (),
        gameName: Some("FreeCell"),
        shareDealSeed: Some(1),
        shareDealStatus: None,
        onShareDeal: () => (),
        games: [],
        onOpenSettings: () => (),
        onOpenAbout: () => (),
        updateVisible: false,
        onReload: () => (),
      },
      settings,
      debug,
      gameInfo: info => {info, tilt: false, onClose: () => (), onBackToMenu: () => ()},
      about,
    }),
  )

describe("Menu screen placement", () => {
  test("places the screen the `screen` variant names", () => {
    // A screen that was in the variant and nowhere in the switch would be a button that
    // does nothing. About answers with the app's name rather than its own: it is the one
    // screen that puts its heading in its body (`MenuAboutScreen`).
    let titleOn = screen => paneOn(screen)->textIn(".menu-title")
    expect(titleOn(Menu.About))->toBe("Pip")
    expect(titleOn(Menu.Settings))->toBe("Settings")
    expect(titleOn(Menu.Debug))->toBe("Debug")
  })
})

// The Share button — the second of the "this game" buttons.
let shareButton = (menu): option<Html.element> =>
  menu->find(`[aria-label="this game"] .menu-buttons button:nth-child(2)`)

// The seed the section names, which is the number the button would hand out. On the
// heading rather than on the button, so it describes both controls under it.
let seedNamed = (menu): string =>
  menu->find(`[aria-label="this game"] .menu-section__value`)->Option.mapOr("<none>", text)

// The line beneath the buttons: where a link just went, or why the button is dark.
let line = (menu): string =>
  switch menu->find(".menu-share-line") {
  | Some(el) => el->text
  | None => "<no line>"
  }

// Is the line's element there at all? An empty line and an absent one read the same
// through `line`, and only one of them holds the layout still.
let hasLine = (menu): bool => menu->find(".menu-share-line")->Option.isSome

describe("Menu Share button", () => {
  test("names the seed on the table, which is what the link carries", () => {
    // Render anything else here — an index, the previous deal's number — and the share
    // sends someone to a different board, which is the one failure this feature can't
    // afford. The number is the section's heading rather than the button's label: it is
    // as true of Restart beside it, and a button that grows by five digits on some
    // boards and not others can't line up with the pair above it.
    let menu = render(~seed=Some(123456), ~status=None)
    expect(menu->seedNamed)->toBe("#123456")
    let text = switch menu->shareButton {
    | Some(b) => b->text
    | None => "<no button>"
    }
    expect(text)->toBe("Share")
  })

  test("says nothing on the line while the seed is simply named above", () => {
    // Empty, but the element is still rendered — `min-height` holds the slot so the
    // confirmation below can appear and clear without moving the panel.
    expect(render(~seed=Some(123456), ~status=None)->line)->toBe("")
    expect(render(~seed=Some(123456), ~status=None)->hasLine)->toBe(true)
  })

  test("leaves the heading bare when there's no seed to name", () => {
    // No trailing element after the game's name — an empty one would read as a gap where a
    // number belongs, and the line below is what actually explains the absence.
    expect(render(~seed=None, ~status=None)->seedNamed)->toBe("<none>")
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

  test("reports where the link went on the line, leaving the section alone", () => {
    // The confirmation takes the slot that was empty a moment ago; the heading keeps
    // naming its seed throughout, since nothing about the deal has changed.
    let menu = render(~seed=Some(24680), ~status=Some("Link copied to clipboard."))
    expect(menu->line)->toBe("Link copied to clipboard.")
    expect(menu->seedNamed)->toBe("#24680")
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
