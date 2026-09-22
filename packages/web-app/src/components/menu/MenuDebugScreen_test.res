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

// The cascade group as the driver hands it over: a row of chips per choice and a slider
// per number, each with the words it reads as and where a drag or a tap reports to.
let knobs = (~log=[]): array<MenuSlider.spec> => [
  {
    label: "cards",
    min: 0.,
    max: 52.,
    step: 1.,
    value: 9.,
    readout: "9 cards · 6.8s",
    onInput: cards => log->Array.push(`cards ${Float.toString(cards)}`),
  },
  {
    label: "coin",
    min: 0.01,
    max: 0.4,
    step: 0.01,
    value: 0.1,
    readout: "0.1 · a fill every 155 ms",
    onInput: coin => log->Array.push(`coin ${Float.toString(coin)}`),
  },
]

let choices = (~log=[]): array<MenuChoiceRow.spec> => {
  let chips = (~selected, labels) =>
    labels->Array.map(label => {
      MenuChoiceRow.label,
      selected: label == selected,
      onChoose: () => log->Array.push(`chose ${label}`),
    })
  [
    {
      MenuChoiceRow.label: "persistence",
      choices: chips(~selected="cards", ["never", "seconds", "cards", "run"]),
    },
    {
      MenuChoiceRow.label: "steps",
      readout: "as small as the coin allows",
      choices: chips(~selected="smooth", ["smooth", "per layer"]),
    },
  ]
}

let render = (
  ~cascadeKnobs=knobs(),
  ~cascadeChoices=choices(),
  ~debugScenesOpen=false,
  ~autoplayEnabled=true,
  ~autoplayStatus=None,
  ~onAutoplay=() => (),
  ~shareEnabled=true,
  ~shareStatus=None,
  ~cutoutDebug=false,
  ~debugLog=false,
  ~onToggleCutoutDebug=() => (),
  ~onToggleDebugLog=() => (),
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
      autoplayEnabled,
      autoplayStatus,
      onAutoplay,
      shareEnabled,
      shareStatus,
      onShareGame,
      onClearStored,
      cascadeKnobs,
      cascadeChoices,
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
let autoplay = 0
let share = 1
let clearData = 2

let actionRow = (screen, which) =>
  screen->findAll(".menu-section > .menu-row--action")->Array.get(which)

let actionDesc = (screen, which) =>
  screen
  ->actionRow(which)
  ->Option.mapOr("<no such action row>", row => row->textIn(".menu-row__desc"))

let shareDesc = screen => screen->actionDesc(share)
let autoplayDesc = screen => screen->actionDesc(autoplay)

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

  test("offers, in a player's own words, to solve the game that is on the table", () => {
    expect(render(~autoplayEnabled=true)->autoplayDesc)->toBe("Solve the current game for me.")
  })

  test("hands the board over when the row is live", () => {
    let taps = ref(0)
    let screen = render(~autoplayEnabled=true, ~onAutoplay=() => taps := taps.contents + 1)
    screen->actionRow(autoplay)->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })

  test("is really disabled with no board to solve, and says so", () => {
    let taps = ref(0)
    let screen = render(~autoplayEnabled=false, ~onAutoplay=() => taps := taps.contents + 1)
    expect(screen->autoplayDesc)->toBe("No game on screen to solve.")
    switch screen->actionRow(autoplay) {
    | Some(row) =>
      expect(row->hasAttr("disabled"))->toBe(true)
      row->click
      expect(taps.contents)->toBe(0)
    | None => expect("autoplay row")->toBe("missing")
    }
  })

  test("gives the solver the row's own description to answer in", () => {
    // A refusal is the whole of what a declined solve leaves behind — the board itself
    // doesn't move — so it has to be readable where the press happened, and without
    // growing the row.
    let screen = render(~autoplayStatus=Some("Autoplay couldn't find a way to win from here."))
    expect(screen->autoplayDesc)->toBe("Autoplay couldn't find a way to win from here.")
    expect(
      screen
      ->actionRow(autoplay)
      ->Option.mapOr(0, row => row->findAll(".menu-row__desc")->Array.length),
    )->toBe(1)
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
    expect(
      screen
      ->actionRow(share)
      ->Option.mapOr(0, row => row->findAll(".menu-row__desc")->Array.length),
    )->toBe(1)
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

  test("shares the game state when the row is live", () => {
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
    )->toEqual(["Autoplay", "Share game state", "Clear saved data"])
  })

  test("renders the three groups, scenes first, each with its own entries", () => {
    // Every group is the same component (`<MenuDisclosure>`), which is why the entries
    // are read back per group: calls that differ only in their data can be crossed.
    let screen = render()
    expect(screen->findAll(".scene-menu__group > summary")->Array.map(text))->toEqual([
      "scenes",
      "states",
      "cascade",
    ])
    let rowsIn = index =>
      switch screen->findAll(".scene-menu__group")->Array.get(index) {
      | Some(group) => group->findAll(".scene-menu__group-body .menu-row")->Array.map(text)
      | None => ["<no such group>"]
      }
    expect(rowsIn(0))->toEqual(["Gallery", "Raster"])
    expect(rowsIn(1))->toEqual(["Mid-game", "Almost won"])
    // The third's rows are the chips of both its pickers — which *are* `.menu-row`s,
    // that being where their box and highlight come from — and nothing else: a slider is
    // not one.
    expect(rowsIn(2))->toEqual(["never", "seconds", "cards", "run", "smooth", "per layer"])
  })

  test("puts the cascade knobs on sliders, each reading out what its number means", () => {
    // The group that governs the *game's* victory animation rather than a demo of one.
    // What the words say is the driver's business; that each knob arrives with its own
    // is this screen's.
    let screen = render()
    expect(screen->findAll(".menu-slider__label")->Array.map(text))->toEqual(["cards", "coin"])
    expect(screen->findAll(".menu-slider__readout")->Array.map(text))->toEqual([
      "9 cards · 6.8s",
      "0.1 · a fill every 155 ms",
    ])
  })

  test("offers the units as chips, with the one in effect marked", () => {
    // The persistence is one length said four ways, so which way is a choice rather than
    // a number — and `aria-current` is what says which, as on every other row here.
    let screen = render()
    let chips = screen->findAll(`.menu-choice[data-choice="persistence"] .menu-choice__chip`)
    expect(chips->Array.map(text))->toEqual(["never", "seconds", "cards", "run"])
    expect(chips->Array.map(chip => attrOr(chip, "aria-current")))->toEqual([
      "<missing>",
      "<missing>",
      "true",
      "<missing>",
    ])
  })

  test("draws a picker per choice the driver sends, each with its own readout", () => {
    // Two of them now — what the trail's length is said in, and what the fade waits for —
    // and neither is named here: a list is what lets the next one be a change in the
    // driver alone.
    let screen = render()
    expect(screen->findAll(".menu-choice__label")->Array.map(text))->toEqual([
      "persistence",
      "steps",
    ])
    expect(screen->findAll(".menu-choice__readout")->Array.map(text))->toEqual([
      "as small as the coin allows",
    ])
  })

  test("reports a drag to the knob it was on, and a tap to the chip it was on", () => {
    let log = []
    let screen = render(~cascadeKnobs=knobs(~log), ~cascadeChoices=choices(~log))
    let coin = screen->find(`input[data-knob="coin"]`)->Option.getOrThrow
    typeInto(coin, "0.25")
    let run =
      screen
      ->findAll(".menu-choice__chip")
      ->Array.find(chip => text(chip) == "run")
      ->Option.getOrThrow
    click(run)
    expect(log)->toEqual(["coin 0.25", "chose run"])
  })

  test("hands the browser the range the driver asked for", () => {
    // A slider whose bounds came from somewhere else would quietly tune something else —
    // and these bounds change with the unit, so they are the driver's to say every time.
    let screen = render()
    let cards = screen->find(`input[data-knob="cards"]`)->Option.getOrThrow
    expect((attrOr(cards, "min"), attrOr(cards, "max"), attrOr(cards, "step")))->toEqual((
      "0",
      "52",
      "1",
    ))
    expect(attrOr(cards, "type"))->toBe("range")
  })

  test("opens whichever group the switcher says the app landed inside", () => {
    // A `?scene=gallery` deep link: the highlighted row has to be visible rather
    // than hidden behind a collapsed disclosure. The states group is unaffected.
    let open_ = screen =>
      screen->findAll(".scene-menu__group")->Array.map(group => group->hasAttr("open"))
    expect(render(~debugScenesOpen=true)->open_)->toEqual([true, false, false])
    expect(render(~debugScenesOpen=false)->open_)->toEqual([false, false, false])
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
