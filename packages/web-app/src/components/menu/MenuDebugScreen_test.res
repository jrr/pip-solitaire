// The menu's Debug screen, exercised in isolation.
//
// The rows themselves are pinned by `MenuToggleRow_test` / `MenuActionRow_test`. What
// this file pins is what the *screen* decides:
//
// 1. **The two developer toggles, wired to their own settings** — the safe-area
//    overlay and console logging.
// 2. **"Share game state" swaps its description for the status**, rather than growing
//    a line of its own. The row would change height as the confirmation came and went
//    otherwise, shoving the scene lists below it.
// 3. **It's disabled while there's nothing to share** — a scene with no game, or the
//    moment between opening the screen and the encode resolving — and says which.
// 4. **Each list lands as its own group, in order.** Every one of them is the same
//    component (`<MenuDisclosure>`), which is exactly why the screen has to be pinned on
//    giving each its own entries: calls that differ only in their data are calls that
//    can be crossed. The "games" group is placed only when it has entries, so
//    the default here — no extra games — is still scenes then states.
// 5. **Back goes one step, to Settings** — not all the way out of the pane.
open Vitest
open TestDom

let debugScenes: array<MenuDisclosure.entry> = [
  {label: "Gallery", onSelect: () => ()},
  {label: "Raster", onSelect: () => ()},
]

let debugStates: array<MenuDisclosure.entry> = [
  {label: "Mid-game", onSelect: () => ()},
  {label: "Almost won", onSelect: () => ()},
]

let render = (
  ~gameScenes: array<MenuDisclosure.entry>=[],
  ~gameScenesOpen=false,
  ~debugScenesOpen=false,
  ~shareEnabled=true,
  ~shareStatus=None,
  ~cutoutDebug=false,
  ~debugLog=false,
  ~onToggleCutoutDebug=() => (),
  ~onToggleDebugLog=() => (),
  ~onShareGame=() => (),
  ~onBackToSettings=() => (),
) =>
  Html.create(
    MenuDebugScreen.make({
      onClose: () => (),
      onBackToSettings,
      cutoutDebug,
      onToggleCutoutDebug,
      debugLog,
      onToggleDebugLog,
      shareEnabled,
      shareStatus,
      onShareGame,
      gameScenes,
      gameScenesOpen,
      debugScenes,
      debugScenesOpen,
      debugStates,
    }),
  )

let shareDesc = screen => screen->textIn(".menu-row--action .menu-row__desc")

describe("MenuDebugScreen", () => {
  test("offers the two developer toggles", () => {
    expect(render()->findAll(".menu-row--switch .menu-row__label")->Array.map(text))->toEqual([
      "Safe-area overlay",
      "Console logging",
    ])
  })

  test("wires each toggle to its own setting", () => {
    let log = []
    let screen = render(
      ~onToggleCutoutDebug=() => log->Array.push("cutout"),
      ~onToggleDebugLog=() => log->Array.push("debug-log"),
    )
    screen->findAll(".menu-row--switch")->Array.forEach(click)
    expect(log)->toEqual(["cutout", "debug-log"])
  })

  test("explains what a game-state share hands over", () => {
    expect(render(~shareEnabled=true)->shareDesc)->toBe(
      "Copy a link that reopens this exact game, undo history and all.",
    )
  })

  test("reports where the link went in the row's own description", () => {
    // Not a line of its own: the row would change height as the status came and
    // went, shoving the scene lists below it down the panel.
    let screen = render(~shareEnabled=true, ~shareStatus=Some("Link copied to clipboard."))
    expect(screen->shareDesc)->toBe("Link copied to clipboard.")
    expect(screen->findAll(".menu-row--action .menu-row__desc")->Array.length)->toBe(1)
  })

  test("is really disabled with no game to share, and says so", () => {
    let taps = ref(0)
    let screen = render(~shareEnabled=false, ~onShareGame=() => taps := taps.contents + 1)
    expect(screen->shareDesc)->toBe("No game on screen to share.")
    switch screen->find(".menu-row--action") {
    | Some(row) =>
      expect(row->hasAttr("disabled"))->toBe(true)
      row->click
      expect(taps.contents)->toBe(0)
    | None => expect("share row")->toBe("missing")
    }
  })

  test("shares the game state when the row is live", () => {
    let taps = ref(0)
    let screen = render(~shareEnabled=true, ~onShareGame=() => taps := taps.contents + 1)
    screen->find(".menu-row--action")->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })

  test("renders the two groups, scenes first, each with its own entries", () => {
    let screen = render()
    expect(screen->findAll(".scene-menu__group > summary")->Array.map(text))->toEqual([
      "scenes",
      "states",
    ])
    let rowsIn = index =>
      switch screen->findAll(".scene-menu__group")->Array.get(index) {
      | Some(group) => group->findAll(".scene-menu__group-body .menu-row")->Array.map(text)
      | None => ["<no such group>"]
      }
    expect(rowsIn(0))->toEqual(["Gallery", "Raster"])
    expect(rowsIn(1))->toEqual(["Mid-game", "Almost won"])
  })

  test("places the games group above the other two, when there is one", () => {
    // A second game belongs among the games, not under "scenes" between Gallery and
    // Motion — which is where the switcher's old primary-vs-rest split put it.
    let screen = render(~gameScenes=[{label: "Klondike", onSelect: () => ()}])
    expect(screen->findAll(".scene-menu__group > summary")->Array.map(text))->toEqual([
      "games",
      "scenes",
      "states",
    ])
    expect(
      screen
      ->findAll(".scene-menu__group")
      ->Array.get(0)
      ->Option.mapOr(
        ["<no games group>"],
        group => group->findAll(".scene-menu__group-body .menu-row")->Array.map(text),
      ),
    )->toEqual(["Klondike"])
  })

  test("leaves the games group out entirely when it's empty", () => {
    // Today's shape: FreeCell is the only game and it already has the main menu's
    // games row, so this screen shows no games group at all — an empty `<details>`
    // would be a summary opening onto nothing.
    expect(render()->findAll(".scene-menu__group > summary")->Array.map(text))->toEqual([
      "scenes",
      "states",
    ])
  })

  test("opens whichever group the switcher says the app landed inside", () => {
    // A `?scene=gallery` deep link: the highlighted row has to be visible rather
    // than hidden behind a collapsed disclosure. The other groups are unaffected.
    let open_ = screen =>
      screen->findAll(".scene-menu__group")->Array.map(group => group->hasAttr("open"))
    expect(render(~debugScenesOpen=true)->open_)->toEqual([true, false])
    expect(render(~debugScenesOpen=false)->open_)->toEqual([false, false])
    let games: array<MenuDisclosure.entry> = [{label: "Klondike", onSelect: () => ()}]
    expect(render(~gameScenes=games, ~gameScenesOpen=true)->open_)->toEqual([true, false, false])
    expect(render(~gameScenes=games, ~debugScenesOpen=true)->open_)->toEqual([false, true, false])
  })

  test("goes back one step, to Settings — not all the way out", () => {
    let taps = ref(0)
    let screen = render(~onBackToSettings=() => taps := taps.contents + 1)
    expect(
      screen
      ->find(".menu-back")
      ->Option.mapOr("<missing>", b => b->attrOr("aria-label")),
    )->toBe("Back to settings")
    screen->find(".menu-back")->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })
})
