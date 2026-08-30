// Selecting a scene activates it — but selecting the scene *already showing* must
// not tear it down and mount it again. A fake scene that counts its mounts is enough
// to check this in jsdom; no layout or input engine needed.
//
// Nothing here clicks a button: the switcher builds no menu DOM at all, so what's
// exercised is the data it hands over. A
// primary scene is `select`ed by id, exactly as the row the chrome draws does it, and
// a debug/demo scene by running its entry's `onSelect` — the very thunk that row is
// wired to. Which scene is current is likewise read rather than looked at: `active`
// for the seed the chrome opens with, `entry.selected` for the group's highlight.
//
// The grouping is three-way: the primary row, the `Game` scenes that aren't it,
// and the `Demo` scenes. It can only be exercised here — the app has one game, so the
// games group is empty in the real scene list, which is exactly the case that makes
// this a no-op on the screen.

open Vitest

let countingScene = (~id, ~mounts, ~kind: Scene.kind=Demo): Scene.t => {
  id,
  label: id,
  kind,
  mount: _container => {
    mounts := mounts.contents + 1
    () => ()
  },
}

let game = (~id, ~mounts) => countingScene(~id, ~mounts, ~kind=Game)

describe("SceneSwitcher's games list", () => {
  test("hands the primary game over as data, and says it's the one showing", () => {
    // The scene list minus the demos, plus the id the chrome seeds its model with —
    // that pairing is the whole of the menu's highlight now.
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      [game(~id="freecell", ~mounts), countingScene(~id="gallery", ~mounts)],
    )
    expect(switcher.primaryScenes->Array.map(scene => (scene.id, scene.label)))->toEqual([
      ("freecell", "freecell"),
    ])
    expect(switcher.active)->toEqual(Some("freecell"))
    // Off to a scene in the debug group: the primary game stops being the active one,
    // which is what un-highlights its row.
    switcher.ensureActive("gallery")
    expect(switcher.active)->toEqual(Some("freecell")) // a seed, not a live reading
  })

  test("selecting the showing scene's own id doesn't re-mount it", () => {
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(~default="freecell", [game(~id="freecell", ~mounts)])
    // The initial mount.
    expect(mounts.contents)->toBe(1)
    switcher.select("freecell")
    expect(mounts.contents)->toBe(1)
  })

  test("that tap still reports a reselect, so the chrome can close the menu", () => {
    // The row acknowledges the tap even though nothing mounts — otherwise tapping
    // the game you're already in is a dead control with the menu left open over it.
    let mounts = ref(0)
    let reselects = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      ~onReselect=() => reselects := reselects.contents + 1,
      [game(~id="freecell", ~mounts)],
    )
    switcher.select("freecell")
    expect(reselects.contents)->toBe(1)
    expect(mounts.contents)->toBe(1)
  })

  test("selecting a different scene does mount it, and reports the change", () => {
    // The guard is "don't re-mount what's already up", not "don't mount" — another
    // scene still switches to it, and reports an activation rather than a reselect.
    // That activation report is how the chrome's model learns which row to highlight.
    let freecell = ref(0)
    let demo = ref(0)
    let reselects = ref(0)
    let activated = []
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      ~onActivate=(scene: Scene.t) => activated->Array.push(scene.id),
      ~onReselect=() => reselects := reselects.contents + 1,
      [game(~id="freecell", ~mounts=freecell), countingScene(~id="demo", ~mounts=demo)],
    )
    expect(activated)->toEqual(["freecell"])
    // The non-primary scene is an entry in the debug group, not one of the games —
    // the games list holds the primary game alone.
    switch switcher.debugScenes()->Array.get(0) {
    | Some(entry) => entry.onSelect()
    | None => expect("the demo entry")->toBe("but there wasn't one")
    }
    expect(demo.contents)->toBe(1)
    expect(reselects.contents)->toBe(0)
    expect(activated)->toEqual(["freecell", "demo"])
  })

  test("an id that names no scene selects nothing", () => {
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(~default="freecell", [game(~id="freecell", ~mounts)])
    switcher.select("nope")
    expect(mounts.contents)->toBe(1)
  })
})

describe("SceneSwitcher's debug group", () => {
  test("hands the demo scenes over as entries, with the mounted one selected", () => {
    // The highlight is a field on the entry, read fresh each time the menu renders.
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      [
        game(~id="freecell", ~mounts),
        countingScene(~id="gallery", ~mounts),
        countingScene(~id="motion", ~mounts),
      ],
    )
    let selection = () =>
      switcher.debugScenes()->Array.map(entry => (entry.label, entry.selected->Option.getOr(false)))
    // Opened on the primary game, so neither demo is current.
    expect(selection())->toEqual([("gallery", false), ("motion", false)])
    switcher.ensureActive("motion")
    expect(selection())->toEqual([("gallery", false), ("motion", true)])
  })

  test("asks for the group open when the app lands on a scene inside it", () => {
    // A `?scene=gallery` deep link, so the highlighted row isn't hidden behind a
    // collapsed disclosure; landing on the primary game leaves it closed.
    let mounts = ref(0)
    let scenes = [game(~id="freecell", ~mounts), countingScene(~id="gallery", ~mounts)]
    expect(SceneSwitcher.render(~default="freecell", scenes).debugScenesOpen)->toBe(false)
    expect(
      SceneSwitcher.render(~default="freecell", ~forced="gallery", scenes).debugScenesOpen,
    )->toBe(true)
  })

  test("reports the scene a deep link lands on as the active one", () => {
    // What the chrome seeds its model with on a `?scene=` open: the forced scene, so
    // the games row it *isn't* opens un-highlighted.
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      ~forced="gallery",
      [game(~id="freecell", ~mounts), countingScene(~id="gallery", ~mounts)],
    )
    expect(switcher.active)->toEqual(Some("gallery"))
  })
})

describe("SceneSwitcher's grouping by kind", () => {
  // Two games and two demos, so the three groups are all distinguishable. The real
  // scene list can't do this yet — there is one game — which is the point: the
  // grouping is pinned here so a second game lands where it belongs on the day it
  // arrives, rather than under "scenes" among the render demos.
  let scenes = mounts => [
    game(~id="freecell", ~mounts),
    countingScene(~id="gallery", ~mounts),
    game(~id="klondike", ~mounts),
    countingScene(~id="motion", ~mounts),
  ]

  let labels = entries => entries->Array.map((entry: MenuDisclosure.entry) => entry.label)

  test("splits into the primary row, the other games, and the demos", () => {
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(~default="freecell", scenes(mounts))
    expect(switcher.primaryScenes->Array.map(scene => scene.id))->toEqual(["freecell"])
    expect(switcher.gameScenes()->labels)->toEqual(["klondike"])
    expect(switcher.debugScenes()->labels)->toEqual(["gallery", "motion"])
  })

  test("the games group is empty when the only game is the primary one", () => {
    // Today's scene list, and the reason this change shows up nowhere on screen:
    // an empty group is one `MenuDebugScreen` doesn't place.
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      [
        game(~id="freecell", ~mounts),
        countingScene(~id="gallery", ~mounts),
        countingScene(~id="motion", ~mounts),
      ],
    )
    expect(switcher.gameScenes())->toEqual([])
    expect(switcher.debugScenes()->labels)->toEqual(["gallery", "motion"])
  })

  test("a games row mounts its scene, and takes the highlight with it", () => {
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(~default="freecell", scenes(mounts))
    let selection = () =>
      switcher.gameScenes()->Array.map(entry => (entry.label, entry.selected->Option.getOr(false)))
    expect(selection())->toEqual([("klondike", false)])
    switch switcher.gameScenes()->Array.get(0) {
    | Some(entry) => entry.onSelect()
    | None => expect("the klondike entry")->toBe("but there wasn't one")
    }
    expect(mounts.contents)->toBe(2) // freecell's opening mount, then klondike's
    expect(selection())->toEqual([("klondike", true)])
  })

  test("a deep link opens the group holding the scene it lands on", () => {
    // Generalized from the one flag: whichever group the initial scene is in opens,
    // and a link that lands on the primary game's own row opens neither.
    let mounts = ref(0)
    let openness = switcher => (switcher.SceneSwitcher.gameScenesOpen, switcher.debugScenesOpen)
    expect(SceneSwitcher.render(~default="freecell", scenes(mounts))->openness)->toEqual((
      false,
      false,
    ))
    expect(
      SceneSwitcher.render(~default="freecell", ~forced="klondike", scenes(mounts))->openness,
    )->toEqual((true, false))
    expect(
      SceneSwitcher.render(~default="freecell", ~forced="motion", scenes(mounts))->openness,
    )->toEqual((false, true))
  })

  test("a demo named as the launch default keeps its top-level row and only that", () => {
    // The primary is still the launch default, whatever its kind — and it must not
    // also appear in the demos group, or the menu would list it twice.
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(~default="gallery", scenes(mounts))
    expect(switcher.primaryScenes->Array.map(scene => scene.id))->toEqual(["gallery"])
    expect(switcher.gameScenes()->labels)->toEqual(["freecell", "klondike"])
    expect(switcher.debugScenes()->labels)->toEqual(["motion"])
  })
})
