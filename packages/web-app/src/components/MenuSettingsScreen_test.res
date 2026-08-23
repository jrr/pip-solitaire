// The menu's Settings screen, exercised in isolation.
//
// It's the first component in the app to hold its own state (#308), so there are two
// halves to pin, and the split is the point of the exercise:
//
//   - **`update`** — a pure function from a message and a model to the next model and
//     an effect, testable with no DOM at all, exactly like `core`'s `Reducer`. This is
//     what the flat-props arrangement had no equivalent of: a switch's *behaviour*
//     used to be a branch in `Main`'s update, reachable only through the whole app.
//   - **the view** — which rows are there, what state they read, and which message
//     each one sends. The rows themselves are pinned by `MenuToggleRow_test` /
//     `MenuWiggleRow_test` / `MenuNavRow_test`; what's left to this file is what the
//     *screen* decides:
//       1. **Which rows are there, and in what order.** Auto-collect, Sloppy
//          placement, (Wiggle Waggle), Display content around notch — then Debug in a
//          section of its own, below the preferences rather than among them.
//       2. **Wiggle Waggle is hidden until it's revealed** (`HiddenOptions`, #235),
//          and when it appears it appears *between* Sloppy placement and the notch row
//          rather than nested under either — the three are independent settings.
//       3. **Each switch is wired to its own setting.** Four toggles that all look
//          alike is exactly the arrangement where a crossed wire goes unnoticed — and
//          now that a click sends a *message*, the check reads the message rather than
//          watching which callback fired.
//
// Rendered through `Html.create` like the other component tests here (see
// `AboutFooter_test`), which needs no DOM beyond what jsdom gives.
open Vitest

@get external textContent: Html.element => string = "textContent"
@send external querySelector: (Html.element, string) => Nullable.t<Html.element> = "querySelector"
type nodeList
@send external querySelectorAll: (Html.element, string) => nodeList = "querySelectorAll"
@get external listLength: nodeList => int = "length"
@send external listItem: (nodeList, int) => Html.element = "item"
@send external click: Html.element => unit = "click"

// A model to render, with every field defaulted so a test names only what it's about.
// Built by hand rather than through `init`, which reads real storage.
let model = (
  ~autoCollect=true,
  ~cardTilt=true,
  ~wiggle=Motion.Off,
  ~notchDisplay=true,
  ~revealHidden=false,
  ~taps=0,
): MenuSettingsScreen.model => {
  autoCollect,
  cardTilt,
  wiggle,
  notchDisplay,
  hidden: {revealed: revealHidden, taps},
}

// An `env` that records what the chrome was asked to do instead of doing it — the
// four handles the screen can't reach on its own (see `MenuSettingsScreen.env`).
let recordingEnv = log => {
  MenuSettingsScreen.setAutoCollect: on => log->Array.push(`auto-collect:${on ? "on" : "off"}`),
  setCardTilt: on => log->Array.push(`card-tilt:${on ? "on" : "off"}`),
  relayout: () => log->Array.push("relayout"),
  setShake: on => log->Array.push(`shake:${on ? "start" : "stop"}`),
}

// Run one message through `update` and run its effect, answering with the next model
// and everything the effect asked the chrome for.
let step = (msg, model) => {
  let log = []
  let (next, effect) = MenuSettingsScreen.update(~env=recordingEnv(log), msg, model)
  effect()
  (next, log)
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

// Render with a dispatch that records the messages the screen sends.
let recording = (~model as m=model()) => {
  let sent = []
  (render(~model=m, ~dispatch=msg => sent->Array.push(msg)), sent)
}

let find = (screen, selector) => screen->querySelector(selector)->Nullable.toOption

let all = (screen, selector): array<Html.element> => {
  let found = screen->querySelectorAll(selector)
  let out = []
  for i in 0 to found->listLength - 1 {
    out->Array.push(found->listItem(i))
  }
  out
}

// The settings rows' labels, top to bottom.
let rowLabels = screen =>
  screen->all("[aria-label=\"Settings\"] .menu-toggle__label")->Array.map(textContent)

describe("MenuSettingsScreen.update (#308)", () => {
  test("flips a switch and writes the flip through to the chrome", () => {
    // The model is a *mirror* — the value that matters lives in the ref the board
    // reads — so a flip is only half done until the effect has run.
    let (next, log) = model(~autoCollect=true)->step(MenuSettingsScreen.ToggleAutoCollect, _)
    expect(next.autoCollect)->toBe(false)
    expect(log)->toEqual(["auto-collect:off"])
  })

  test("relayouts the board when the tilt changes, so it shows at once", () => {
    // Without this the new tilt would only appear on the next move.
    let (next, log) = model(~cardTilt=false)->step(MenuSettingsScreen.ToggleCardTilt, _)
    expect(next.cardTilt)->toBe(true)
    expect(log)->toEqual(["card-tilt:on", "relayout"])
  })

  test("touches nothing of the board's when the notch setting changes", () => {
    // It's read entirely by the CSS through the document root, so the board has no
    // part in it (unlike the tilt above).
    let (next, log) = model(~notchDisplay=true)->step(MenuSettingsScreen.ToggleNotchDisplay, _)
    expect(next.notchDisplay)->toBe(false)
    expect(log)->toEqual([])
  })

  test("stops the board listening when Wiggle Waggle is turned off", () => {
    let (next, log) = model(~wiggle=Motion.On)->step(MenuSettingsScreen.WiggleOff, _)
    expect(next.wiggle)->toBe(Motion.Off)
    expect(log)->toEqual(["shake:stop"])
  })

  test("starts it listening when the grant comes back", () => {
    let (next, log) =
      model(~wiggle=Motion.Off)->step(MenuSettingsScreen.WiggleResolved(Motion.On), _)
    expect(next.wiggle)->toBe(Motion.On)
    expect(log)->toEqual(["shake:start"])
  })

  test("snaps the switch back and stops when the OS refuses", () => {
    // `Blocked` deliberately does *not* persist a false intent, so a grant revoked
    // behind us keeps re-asking on later launches rather than giving up.
    let (next, log) =
      model(~wiggle=Motion.On)->step(MenuSettingsScreen.WiggleResolved(Motion.Blocked), _)
    expect(next.wiggle)->toBe(Motion.Blocked)
    expect(log)->toEqual(["shake:stop"])
  })

  test("reveals the hidden settings on the tenth tap, and not before", () => {
    let ninth = model(~revealHidden=false, ~taps=8)->step(MenuSettingsScreen.TitleTapped, _)
    let (afterNinth, _) = ninth
    expect(afterNinth.hidden.revealed)->toBe(false)

    let (afterTenth, _) = afterNinth->step(MenuSettingsScreen.TitleTapped, _)
    expect(afterTenth.hidden.revealed)->toBe(true)
    // …and the run starts over, so the next ten hide them again.
    expect(afterTenth.hidden.taps)->toBe(0)
  })

  test("forgets a part-finished run of taps, keeping the reveal", () => {
    // The way out of the screen: the counter spans one uninterrupted visit.
    let left = MenuSettingsScreen.forgetTaps(model(~revealHidden=true, ~taps=7))
    expect(left.hidden.taps)->toBe(0)
    expect(left.hidden.revealed)->toBe(true)
  })

  test("leaves an already-clear model physically alone, so it can't force a render", () => {
    // `Html.mount` skips the re-render when the model comes back identical; that has
    // to survive the trip through the child (see `Main`'s SettingsMsg branch).
    let clear = model(~taps=0)
    expect(MenuSettingsScreen.forgetTaps(clear) === clear)->toBe(true)
  })
})

describe("MenuSettingsScreen", () => {
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
    expect(
      rowLabels(render(~model=model(~revealHidden=false)))->Array.includes("Wiggle Waggle"),
    )->toBe(false)
  })

  test("slots Wiggle Waggle in beside the others once revealed, not under one", () => {
    expect(rowLabels(render(~model=model(~revealHidden=true))))->toEqual([
      "Auto-collect",
      "Sloppy placement",
      "Wiggle Waggle",
      "Display content around notch",
    ])
  })

  test("wires each switch to its own message", () => {
    // Four rows that look alike: a crossed wire here would be invisible. Wiggle
    // Waggle is shown *on* so its tap is the plain `WiggleOff` — turning it on asks
    // the OS for the motion grant under the real click instead, which is the view's
    // one piece of behaviour and not a message at all.
    let (screen, sent) = recording(~model=model(~revealHidden=true, ~wiggle=Motion.On))
    screen->all("[aria-label=\"Settings\"] .menu-toggle")->Array.forEach(click)
    expect(sent)->toEqual([
      MenuSettingsScreen.ToggleAutoCollect,
      MenuSettingsScreen.ToggleCardTilt,
      MenuSettingsScreen.WiggleOff,
      MenuSettingsScreen.ToggleNotchDisplay,
    ])
  })

  test("shows each switch in the state its model is in", () => {
    // Which rows read *on*, by name — the crossed-wire check's static twin.
    let states = screen =>
      screen
      ->all("[aria-label=\"Settings\"] .menu-toggle--on .menu-toggle__label")
      ->Array.map(textContent)
    expect(
      states(render(~model=model(~autoCollect=true, ~cardTilt=false, ~notchDisplay=false))),
    )->toEqual(["Auto-collect"])
    expect(
      states(render(~model=model(~autoCollect=false, ~cardTilt=true, ~notchDisplay=true))),
    )->toEqual(["Sloppy placement", "Display content around notch"])
  })

  test("puts Debug in a section below the preferences, not among them", () => {
    // The debug tools moved off this screen entirely (#191); what's left is a way in.
    let screen = render()
    expect(rowLabels(screen)->Array.includes("Debug"))->toBe(false)
    expect(screen->find(".menu-nav-row__label")->Option.mapOr("<missing>", textContent))->toBe(
      "Debug",
    )
  })

  test("opens the Debug screen from that row", () => {
    // Navigation stays a callback rather than a message: where the back button and
    // the Debug row go is the pane's business, not this screen's.
    let taps = ref(0)
    let screen = render(~onOpenDebug=() => taps := taps.contents + 1)
    screen->find(".menu-nav-row")->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })

  test("counts taps on its title, which is the way in to the hidden settings", () => {
    let (screen, sent) = recording()
    screen->find(".menu-title")->Option.forEach(click)
    expect(sent)->toEqual([MenuSettingsScreen.TitleTapped])
  })
})
