// The menu's Debug screen, exercised in isolation.
//
// The rows themselves are pinned by `MenuToggleRow_test` / `MenuActionRow_test`, so
// what's left to this file is what the *screen* decides.
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
  ~debugScenesOpen=false,
  ~solveEnabled=true,
  ~solving=false,
  ~onSolve=() => (),
  ~shareEnabled=true,
  ~cutoutDebug=false,
  ~debugLog=false,
  ~onToggleCutoutDebug=() => (),
  ~onToggleDebugLog=() => (),
  ~thinking=false,
  ~onToggleThinking=() => (),
  ~onShareGame=() => (),
  ~onClearStored=() => (),
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
      thinking,
      onToggleThinking,
      solveEnabled,
      solving,
      onSolve,
      shareEnabled,
      onShareGame,
      onClearStored,
      debugScenes,
      debugScenesOpen,
      debugStates,
    }),
  )

// The screen's own three action rows, each reached by its place in the order the screen
// puts them in — a test that silently took the first would go on passing while asking
// about the wrong row. Anchored to the section rather than to the class alone, because
// a row with nothing at its right-hand end is an action row (`MenuRow.classesFor`) and
// every scene and state entry inside the disclosures below is one too.
let solve = 0
let share = 1
let clearData = 2

let actionRow = (screen, which) =>
  screen->findAll(".menu-section > .menu-row--action")->Array.get(which)

let actionDesc = (screen, which) =>
  screen
  ->actionRow(which)
  ->Option.mapOr("<no such action row>", row => row->textIn(".menu-row__desc"))

let shareDesc = screen => screen->actionDesc(share)
let solveDesc = screen => screen->actionDesc(solve)

describe("MenuDebugScreen", () => {
  test("offers the three developer toggles", () => {
    expect(render()->findAll(".menu-row--switch .menu-row__label")->Array.map(text))->toEqual([
      "Safe-area overlay",
      "Console logging",
      "Think ahead",
    ])
  })

  test("wires each toggle to its own setting", () => {
    let log = []
    let screen = render(
      ~onToggleCutoutDebug=() => log->Array.push("cutout"),
      ~onToggleDebugLog=() => log->Array.push("debug-log"),
      ~onToggleThinking=() => log->Array.push("thinking"),
    )
    screen->findAll(".menu-row--switch")->Array.forEach(click)
    expect(log)->toEqual(["cutout", "debug-log", "thinking"])
  })

  test("offers to look for a win in the game that is on the table", () => {
    expect(render(~solveEnabled=true)->solveDesc)->toBe(
      "Look for a way to win the current game, then offer to play it.",
    )
  })

  test("hands the board over when the row is live", () => {
    let taps = ref(0)
    let screen = render(~solveEnabled=true, ~onSolve=() => taps := taps.contents + 1)
    screen->actionRow(solve)->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })

  test("is really disabled with no board to solve, and says so", () => {
    let taps = ref(0)
    let screen = render(~solveEnabled=false, ~onSolve=() => taps := taps.contents + 1)
    expect(screen->solveDesc)->toBe("No game on screen to solve.")
    switch screen->actionRow(solve) {
    | Some(row) =>
      expect(row->hasAttr("disabled"))->toBe(true)
      row->click
      expect(taps.contents)->toBe(0)
    | None => expect("solve row")->toBe("missing")
    }
  })

  test("says it is thinking in the description's place, so the row keeps its height", () => {
    let screen = render(~solving=true)
    expect(screen->solveDesc)->toBe(MenuDebugScreen.thinking)
    expect(
      screen
      ->actionRow(solve)
      ->Option.mapOr(0, row => row->findAll(".menu-row__desc")->Array.length),
    )->toBe(1)
  })

  test("explains what a game-state share hands over", () => {
    expect(render(~shareEnabled=true)->shareDesc)->toBe(
      "Show a link and QR code that reopen this exact game, undo history and all.",
    )
  })

  test("is really disabled with no game to share, and says so", () => {
    // A scene with no game, or the moment between opening the screen and the encode
    // resolving.
    let taps = ref(0)
    let screen = render(~shareEnabled=false, ~onShareGame=() => taps := taps.contents + 1)
    expect(screen->shareDesc)->toBe("No game on screen to share.")
    switch screen->actionRow(share) {
    | Some(row) =>
      expect(row->hasAttr("disabled"))->toBe(true)
      row->click
      expect(taps.contents)->toBe(0)
    | None => expect("share row")->toBe("missing")
    }
  })

  test("asks for the share dialog when the row is live", () => {
    let taps = ref(0)
    let screen = render(~shareEnabled=true, ~onShareGame=() => taps := taps.contents + 1)
    screen->actionRow(share)->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })

  test("says what clearing takes with it, since a tap is the last chance to not", () => {
    // No confirmation stands between the tap and the wipe, so the description is the
    // whole of the warning — and it has to name the settings as well as the games.
    expect(render()->actionDesc(clearData))->toBe(
      "Forget every saved game and setting on this device, then reopen the app.",
    )
  })

  test("leaves the clear row live whatever else the screen can offer", () => {
    // Unlike Share, it depends on nothing being on screen: a scene with no game has
    // storage to forget just the same.
    let taps = ref(0)
    let screen = render(~shareEnabled=false, ~onClearStored=() => taps := taps.contents + 1)
    switch screen->actionRow(clearData) {
    | Some(row) =>
      expect(row->hasAttr("disabled"))->toBe(false)
      row->click
      expect(taps.contents)->toBe(1)
    | None => expect("clear row")->toBe("missing")
    }
  })

  test("keeps the destructive row last, under the two harmless ones", () => {
    // Order is the only thing separating a tap that solves a board or copies a link
    // from one that erases the device, so it's pinned rather than left to the reading
    // order.
    expect(
      render()->findAll(".menu-section > .menu-row--action .menu-row__label")->Array.map(text),
    )->toEqual(["Solve", "Share game state", "Clear saved data"])
  })

  test("renders the two groups, scenes first, each with its own entries", () => {
    // Every group is the same component (`<MenuDisclosure>`), which is why the entries
    // are read back per group: calls that differ only in their data can be crossed.
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

  test("opens whichever group the switcher says the app landed inside", () => {
    // A `?scene=gallery` deep link: the highlighted row has to be visible rather
    // than hidden behind a collapsed disclosure. The states group is unaffected.
    let open_ = screen =>
      screen->findAll(".scene-menu__group")->Array.map(group => group->hasAttr("open"))
    expect(render(~debugScenesOpen=true)->open_)->toEqual([true, false])
    expect(render(~debugScenesOpen=false)->open_)->toEqual([false, false])
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
