// The menu's Settings screen, exercised in isolation — both halves of it, since the
// screen now owns its state as well as its rows.
//
// The rows themselves are pinned by `MenuToggleRow_test` / `MenuWiggleRow_test` /
// `MenuNavRow_test`. What's left to the *view* cases is what the screen decides — which
// rows are there, in what order, and which message each of them sends.
//
// The `update` cases are the other half: what a message does to the model, and which
// kinds of reach its effect uses. They can ask that at all because `update` takes its
// reach as an `env` — a recording one here — and returns the effect rather than running
// it. What the live env's writers actually *hit* is the one thing this file can't see,
// and is what `browser-tests/settings-reach.spec.mjs` covers.
open Vitest
open TestDom

// A settings model, everything off unless a case says otherwise.
let model = (
  ~autoCollect=false,
  ~cardTilt=false,
  ~wiggle=Motion.Off,
  ~wantsShake=false,
  ~victoryAnimation=false,
  ~notchDisplay=false,
  ~revealed=false,
  ~taps=0,
): MenuSettingsScreen.model => {
  autoCollect,
  cardTilt,
  wiggle,
  wantsShake,
  victoryAnimation,
  notchDisplay,
  hidden: {revealed, taps},
}

let render = (~model as m=model(), ~dispatch=_ => (), ~onOpenDebug=() => ()) =>
  Html.create(
    MenuSettingsScreen.make({
      model: m,
      dispatch,
      onClose: () => (),
      onBackToMenu: () => (),
      onOpenDebug,
    }),
  )

// The screen rendered with a recorder for a dispatcher, so a case can click and read
// back what it sent.
let renderRecording = (~model as m=model()) => {
  let sent = []
  (render(~model=m, ~dispatch=msg => sent->Array.push(msg)), sent)
}

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
    let labels = rowLabels(render(~model=model(~revealed=false)))
    expect(labels->Array.includes("Wiggle Waggle"))->toBe(false)
    expect(labels->Array.includes("Victory animation"))->toBe(false)
  })

  test("slots the hidden settings in beside the others once revealed, not under one", () => {
    // Between Sloppy placement and the notch row rather than nested under either: all
    // of them are independent settings.
    expect(rowLabels(render(~model=model(~revealed=true))))->toEqual([
      "Auto-collect",
      "Sloppy placement",
      "Wiggle Waggle",
      "Victory animation",
      "Display content around notch",
    ])
  })

  test("sends each switch's own message", () => {
    // Five rows that look alike: a crossed wire here would be invisible. Wiggle Waggle
    // is shown listening so that its tap is the one branch that resolves to a message
    // synchronously — turning it *on* asks the OS first (`askMotion`).
    let (screen, sent) = renderRecording(~model=model(~revealed=true, ~wiggle=Motion.On))
    screen->findAll("[aria-label=\"Settings\"] .menu-row--switch")->Array.forEach(click)
    expect(sent)->toEqual([
      MenuSettingsScreen.ToggleAutoCollect,
      ToggleCardTilt,
      WiggleOff,
      ToggleVictoryAnimation,
      ToggleNotchDisplay,
    ])
  })

  test("shows each switch in the state it was handed", () => {
    // The crossed-wire check's static twin.
    expect(onRowLabels(render(~model=model(~autoCollect=true))))->toEqual(["Auto-collect"])
    expect(onRowLabels(render(~model=model(~cardTilt=true, ~notchDisplay=true))))->toEqual([
      "Sloppy placement",
      "Display content around notch",
    ])
    expect(onRowLabels(render(~model=model(~revealed=true, ~victoryAnimation=true))))->toEqual([
      "Victory animation",
    ])
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
    let (screen, sent) = renderRecording()
    screen->find(".menu-title")->Option.forEach(click)
    expect(sent)->toEqual([MenuSettingsScreen.TitleTapped])
  })
})

// A stand-in for the four kinds of reach, recording which were used and the snapshot
// each was handed. `log` is in the order the effect performed them.
let recorder = () => {
  let log = []
  let saved: ref<option<MenuSettingsScreen.model>> = ref(None)
  let env: MenuSettingsScreen.env = {
    publish: _ => log->Array.push("publish"),
    board: request =>
      log->Array.push(
        switch request {
        | MenuSettingsScreen.Relayout => "board:relayout"
        | ShakeStart => "board:shake-start"
        | ShakeStop => "board:shake-stop"
        },
      ),
    root: _ => log->Array.push("root"),
    persist: snapshot => {
      saved := Some(snapshot)
      log->Array.push("persist")
    },
  }
  (env, log, saved)
}

// One message against one model, with the effect run: the model it lands on, what the
// effect reached for, and the snapshot storage was handed.
let run = (~model as m, msg) => {
  let (env, log, saved) = recorder()
  let (next, effect) = MenuSettingsScreen.update(env, msg, m)
  effect()
  (next, log, saved.contents)
}

describe("MenuSettingsScreen.update", () => {
  test("holds its effect until it's run, so the model can be checked on its own", () => {
    let (env, log, _) = recorder()
    let (next, effect) = MenuSettingsScreen.update(env, ToggleAutoCollect, model())
    expect(next.autoCollect)->toBe(true)
    expect(log)->toEqual([])
    effect()
    expect(log)->toEqual(["publish", "persist"])
  })

  test("flips only the setting its message names", () => {
    let (next, _, _) = run(~model=model(~cardTilt=true, ~notchDisplay=true), ToggleAutoCollect)
    expect((next.autoCollect, next.cardTilt, next.notchDisplay))->toEqual((true, true, true))
  })

  test("writes auto-collect into the live options and storage, and asks the board nothing", () => {
    // Nothing to ask: the board reads the flag at each move, so the next one is already
    // playing by it.
    let (_, log, saved) = run(~model=model(), ToggleAutoCollect)
    expect(log)->toEqual(["publish", "persist"])
    expect(saved->Option.map(s => s.autoCollect))->toEqual(Some(true))
  })

  test("re-lays the board when the tilt flips, rather than waiting for the next move", () => {
    let (_, log, _) = run(~model=model(~cardTilt=true), ToggleCardTilt)
    expect(log)->toEqual(["publish", "persist", "board:relayout"])
  })

  test("puts the notch preference on the document root, never through the board", () => {
    // The one setting the board never reads — it's a root attribute the CSS keys off.
    let (next, log, saved) = run(~model=model(~notchDisplay=true), ToggleNotchDisplay)
    expect(next.notchDisplay)->toBe(false)
    expect(log)->toEqual(["root", "persist"])
    expect(saved->Option.map(s => s.notchDisplay))->toEqual(Some(false))
  })

  test("changes only what the next win does when the victory animation flips", () => {
    let (next, log, _) = run(~model=model(), ToggleVictoryAnimation)
    expect(next.victoryAnimation)->toBe(true)
    expect(log)->toEqual(["publish", "persist"])
  })

  test("stops the board and drops the intent when Wiggle Waggle is switched off", () => {
    let (next, log, saved) = run(~model=model(~wiggle=Motion.On, ~wantsShake=true), WiggleOff)
    expect(next.wiggle)->toBe(Motion.Off)
    expect(log)->toEqual(["publish", "persist", "board:shake-stop"])
    expect(saved->Option.map(s => s.wantsShake))->toEqual(Some(false))
  })

  test("starts the board listening once the grant resolves", () => {
    let (next, log, saved) = run(~model=model(), WiggleResolved(Motion.On))
    expect(next.wiggle)->toBe(Motion.On)
    expect(log)->toEqual(["publish", "persist", "board:shake-start"])
    expect(saved->Option.map(s => s.wantsShake))->toEqual(Some(true))
  })

  test("leaves the saved intent alone when the OS refuses, so a revoked grant is re-asked", () => {
    // The switch snaps back to off and the board stops, but a stored `true` stays true:
    // persisting the refusal would give up on a grant that may well come back.
    let (next, log, saved) = run(
      ~model=model(~wiggle=Motion.On, ~wantsShake=true),
      WiggleResolved(Motion.Blocked),
    )
    expect(next.wiggle)->toBe(Motion.Blocked)
    expect(log)->toEqual(["publish", "persist", "board:shake-stop"])
    expect(saved->Option.map(s => s.wantsShake))->toEqual(Some(true))
  })

  test("asks nothing of the board when motion turns out to be unavailable", () => {
    let (next, log, _) = run(~model=model(), WiggleResolved(Motion.Unavailable(NoSensor)))
    expect(next.wiggle)->toEqual(Motion.Unavailable(NoSensor))
    expect(log)->toEqual(["publish", "persist"])
  })

  test("counts the first nine title taps quietly and persists the tenth", () => {
    // The tenth is the one that flips the reveal, and the only one worth a write.
    let ninth = run(~model=model(~taps=8), TitleTapped)
    let (afterNinth, quiet, _) = ninth
    expect(afterNinth.hidden.revealed)->toBe(false)
    expect(quiet)->toEqual([])

    let (afterTenth, log, saved) = run(~model=afterNinth, TitleTapped)
    expect(afterTenth.hidden.revealed)->toBe(true)
    expect(afterTenth.hidden.taps)->toBe(0)
    expect(log)->toEqual(["persist"])
    expect(saved->Option.map(s => s.hidden.revealed))->toEqual(Some(true))
  })
})

describe("MenuSettingsScreen.freshVisit", () => {
  test("abandons a part-finished run of reveal taps without hiding what's showing", () => {
    let fresh = MenuSettingsScreen.freshVisit(model(~revealed=true, ~taps=7))
    expect(fresh.hidden.taps)->toBe(0)
    expect(fresh.hidden.revealed)->toBe(true)
  })

  test("hands back the very same model when there's no run to abandon", () => {
    // Physically the same, so the driver's loop can skip the re-render — every screen
    // change in `Main` goes through here, and most of them have nothing to clear.
    let settled = model(~taps=0)
    expect(MenuSettingsScreen.freshVisit(settled) === settled)->toBe(true)
  })
})
