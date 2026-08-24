// The menu's Settings screen, exercised in isolation now that it's a component of
// its own (#307).
//
// The rows themselves are pinned by `MenuToggleRow_test` / `MenuWiggleRow_test` /
// `MenuNavRow_test`. What's left to this file is what the *screen* decides:
//
// 1. **Which rows are there, and in what order.** Auto-collect, Sloppy placement,
//    (Wiggle Waggle), Display content around notch — then Debug in a section of its
//    own, below the preferences rather than among them.
// 2. **Wiggle Waggle is hidden until it's revealed** (`HiddenOptions`, #235), and
//    when it appears it appears *between* Sloppy placement and the notch row rather
//    than nested under either — the three are independent settings.
// 3. **Each switch is wired to its own setting.** Four toggles that all look alike is
//    exactly the arrangement where a crossed wire goes unnoticed.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest
open TestDom

let render = (
  ~revealHidden=false,
  ~autoCollect=true,
  ~cardTilt=true,
  ~wiggle=Motion.Off,
  ~notchDisplay=true,
  ~onToggleAutoCollect=() => (),
  ~onToggleCardTilt=() => (),
  ~onToggleWiggle=() => (),
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

describe("MenuSettingsScreen (#307)", () => {
  test("lists the player's preferences, top to bottom", () => {
    expect(rowLabels(render()))->toEqual([
      "Auto-collect",
      "Sloppy placement",
      "Display content around notch",
    ])
  })

  test("keeps Wiggle Waggle out of sight until it's been found", () => {
    // Ten taps on the title reveal it (`HiddenOptions`); until then it isn't in the
    // screen at all.
    expect(rowLabels(render(~revealHidden=false))->Array.includes("Wiggle Waggle"))->toBe(false)
  })

  test("slots Wiggle Waggle in beside the others once revealed, not under one", () => {
    expect(rowLabels(render(~revealHidden=true)))->toEqual([
      "Auto-collect",
      "Sloppy placement",
      "Wiggle Waggle",
      "Display content around notch",
    ])
  })

  test("wires each switch to its own setting", () => {
    // Four rows that look alike: a crossed wire here would be invisible.
    let log = []
    let screen = render(
      ~revealHidden=true,
      ~onToggleAutoCollect=() => log->Array.push("auto-collect"),
      ~onToggleCardTilt=() => log->Array.push("card-tilt"),
      ~onToggleWiggle=() => log->Array.push("wiggle"),
      ~onToggleNotchDisplay=() => log->Array.push("notch"),
    )
    screen->findAll("[aria-label=\"Settings\"] .menu-row--switch")->Array.forEach(click)
    expect(log)->toEqual(["auto-collect", "card-tilt", "wiggle", "notch"])
  })

  test("shows each switch in the state it was handed", () => {
    // Which rows read *on*, by name — the crossed-wire check's static twin.
    let states = screen =>
      screen
      ->findAll("[aria-label=\"Settings\"] .menu-row--on .menu-row__label")
      ->Array.map(text)
    expect(states(render(~autoCollect=true, ~cardTilt=false, ~notchDisplay=false)))->toEqual([
      "Auto-collect",
    ])
    expect(states(render(~autoCollect=false, ~cardTilt=true, ~notchDisplay=true)))->toEqual([
      "Sloppy placement",
      "Display content around notch",
    ])
  })

  test("puts Debug in a section below the preferences, not among them", () => {
    // The debug tools moved off this screen entirely (#191); what's left is a way in.
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
