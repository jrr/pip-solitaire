// The menu's Settings screen, exercised in isolation.
//
// The rows themselves are pinned by `MenuToggleRow_test` / `MenuWiggleRow_test` /
// `MenuNavRow_test`. What's left to this file is what the *screen* decides — which rows
// are there, in what order, and which handler each of them reaches.
open Vitest
open TestDom

let render = (
  ~revealHidden=false,
  ~autoCollect=true,
  ~cardTilt=true,
  ~wiggle=Motion.Off,
  ~victoryAnimation=false,
  ~notchDisplay=true,
  ~onToggleAutoCollect=() => (),
  ~onToggleCardTilt=() => (),
  ~onToggleWiggle=() => (),
  ~onToggleVictoryAnimation=() => (),
  ~onToggleNotchDisplay=() => (),
  ~onOpenDebug=() => (),
  ~onTapSettingsTitle=() => (),
) =>
  Html.create(
    MenuSettingsScreen.make({
      onClose: () => (),
      onBackToMenu: () => (),
      onOpenDebug,
      onTapSettingsTitle,
      autoCollect,
      onToggleAutoCollect,
      cardTilt,
      onToggleCardTilt,
      wiggle,
      onToggleWiggle,
      victoryAnimation,
      onToggleVictoryAnimation,
      revealHidden,
      notchDisplay,
      onToggleNotchDisplay,
    }),
  )

// The settings rows' labels, top to bottom.
let rowLabels = screen =>
  screen
  ->findAll("[aria-label=\"Settings\"] .menu-row--switch .menu-row__label")
  ->Array.map(text)

// Just the rows reading *on*, by name.
let onRowLabels = screen =>
  screen->findAll("[aria-label=\"Settings\"] .menu-row--on .menu-row__label")->Array.map(text)

describe("MenuSettingsScreen", () => {
  test("lists the player's preferences, top to bottom", () => {
    expect(rowLabels(render()))->toEqual([
      "Auto-collect",
      "Sloppy placement",
      "Display content around notch",
    ])
  })

  test("keeps the hidden settings out of sight until they've been found", () => {
    // Ten taps on the title reveal them (`HiddenOptions`); until then they aren't in
    // the screen at all.
    let labels = rowLabels(render(~revealHidden=false))
    expect(labels->Array.includes("Wiggle Waggle"))->toBe(false)
    expect(labels->Array.includes("Victory animation"))->toBe(false)
  })

  test("slots the hidden settings in beside the others once revealed, not under one", () => {
    // Between Sloppy placement and the notch row rather than nested under either: all
    // of them are independent settings.
    expect(rowLabels(render(~revealHidden=true)))->toEqual([
      "Auto-collect",
      "Sloppy placement",
      "Wiggle Waggle",
      "Victory animation",
      "Display content around notch",
    ])
  })

  test("wires each switch to its own setting", () => {
    // Five rows that look alike: a crossed wire here would be invisible.
    let log = []
    let screen = render(
      ~revealHidden=true,
      ~onToggleAutoCollect=() => log->Array.push("auto-collect"),
      ~onToggleCardTilt=() => log->Array.push("card-tilt"),
      ~onToggleWiggle=() => log->Array.push("wiggle"),
      ~onToggleVictoryAnimation=() => log->Array.push("victory-animation"),
      ~onToggleNotchDisplay=() => log->Array.push("notch"),
    )
    screen->findAll("[aria-label=\"Settings\"] .menu-row--switch")->Array.forEach(click)
    expect(log)->toEqual(["auto-collect", "card-tilt", "wiggle", "victory-animation", "notch"])
  })

  test("shows each switch in the state it was handed", () => {
    // The crossed-wire check's static twin.
    expect(onRowLabels(render(~autoCollect=true, ~cardTilt=false, ~notchDisplay=false)))->toEqual([
      "Auto-collect",
    ])
    expect(onRowLabels(render(~autoCollect=false, ~cardTilt=true, ~notchDisplay=true)))->toEqual([
      "Sloppy placement",
      "Display content around notch",
    ])
    expect(
      onRowLabels(
        render(
          ~revealHidden=true,
          ~autoCollect=false,
          ~cardTilt=false,
          ~notchDisplay=false,
          ~victoryAnimation=true,
        ),
      ),
    )->toEqual(["Victory animation"])
  })

  test("puts Debug in a section below the preferences, not among them", () => {
    // The debug tools moved off this screen entirely; what's left is a way in.
    let screen = render()
    expect(rowLabels(screen)->Array.includes("Debug"))->toBe(false)
    expect(screen->textIn(".menu-row--nav .menu-row__label"))->toBe("Debug")
  })

  test("opens the Debug screen from that row", () => {
    let taps = ref(0)
    let screen = render(~onOpenDebug=() => taps := taps.contents + 1)
    screen->find(".menu-row--nav")->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })

  test("counts taps on its title, which is the way in to the hidden settings", () => {
    let taps = ref(0)
    let screen = render(~onTapSettingsTitle=() => taps := taps.contents + 1)
    screen->find(".menu-title")->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })
})
