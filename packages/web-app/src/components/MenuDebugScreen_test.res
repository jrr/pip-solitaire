// The menu's Debug screen, exercised in isolation now that it's a component of its
// own (#307).
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
// 4. **The scene/state lists are spliced, not rebuilt.** SceneSwitcher owns those
//    nodes; the screen must hand back the very elements it was given, in order.
// 5. **Back goes one step, to Settings** — not all the way out of the pane.
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
@send external getAttribute: (Html.element, string) => Nullable.t<string> = "getAttribute"
@send external hasAttribute: (Html.element, string) => bool = "hasAttribute"
@send external click: Html.element => unit = "click"
@send external contains: (Html.element, Html.element) => bool = "contains"

let debugScenes = Html.make("div")
let debugStates = Html.make("div")

let render = (
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
      debugScenes,
      debugStates,
    }),
  )

let find = (screen, selector) => screen->querySelector(selector)->Nullable.toOption

let all = (screen, selector): array<Html.element> => {
  let found = screen->querySelectorAll(selector)
  let out = []
  for i in 0 to found->listLength - 1 {
    out->Array.push(found->listItem(i))
  }
  out
}

let shareDesc = screen =>
  screen->find(".menu-action-row .menu-toggle__desc")->Option.mapOr("<missing>", textContent)

describe("MenuDebugScreen (#307)", () => {
  test("offers the two developer toggles", () => {
    expect(render()->all(".menu-toggle .menu-toggle__label")->Array.map(textContent))->toEqual([
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
    screen->all(".menu-toggle")->Array.forEach(click)
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
    expect(screen->all(".menu-action-row .menu-toggle__desc")->Array.length)->toBe(1)
  })

  test("is really disabled with no game to share, and says so", () => {
    let taps = ref(0)
    let screen = render(~shareEnabled=false, ~onShareGame=() => taps := taps.contents + 1)
    expect(screen->shareDesc)->toBe("No game on screen to share.")
    switch screen->find(".menu-action-row") {
    | Some(row) =>
      expect(row->hasAttribute("disabled"))->toBe(true)
      row->click
      expect(taps.contents)->toBe(0)
    | None => expect("share row")->toBe("missing")
    }
  })

  test("shares the game state when the row is live", () => {
    let taps = ref(0)
    let screen = render(~shareEnabled=true, ~onShareGame=() => taps := taps.contents + 1)
    screen->find(".menu-action-row")->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })

  test("splices the scene and state lists in rather than rebuilding them", () => {
    // The very same nodes, so the reconciler leaves the switcher's subtrees alone
    // across open/close re-renders — scenes first, then states.
    let screen = render()
    expect(screen->contains(debugScenes))->toBe(true)
    expect(screen->contains(debugStates))->toBe(true)
  })

  test("goes back one step, to Settings — not all the way out", () => {
    let taps = ref(0)
    let screen = render(~onBackToSettings=() => taps := taps.contents + 1)
    expect(
      screen
      ->find(".menu-back")
      ->Option.mapOr(
        "<missing>",
        b => b->getAttribute("aria-label")->Nullable.toOption->Option.getOr("<missing>"),
      ),
    )->toBe("Back to settings")
    screen->find(".menu-back")->Option.forEach(click)
    expect(taps.contents)->toBe(1)
  })
})
