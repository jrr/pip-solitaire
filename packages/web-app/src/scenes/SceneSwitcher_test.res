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
// The grouping is three-way but only two of them are drawn: the primary rows and the
// `Demo` scenes, with a `Game` scene that isn't primary listed nowhere at all. Fake
// scenes stand in for the real list so each outcome is exercised at once, whichever
// games a build happens to list.

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
    expect(switcher.primaryScenes()->Array.map(scene => (scene.id, scene.label)))->toEqual([
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
    // The non-primary scene is a demo, so it is an entry in the debug group — the
    // games list holds the primary game alone.
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
  // Two games and two demos, so all three outcomes are distinguishable, and only the
  // launch default promoted: a game that isn't released is listed nowhere — not under
  // "scenes" among the render demos — and stays that way until it is.
  let scenes = mounts => [
    game(~id="freecell", ~mounts),
    countingScene(~id="gallery", ~mounts),
    game(~id="klondike", ~mounts),
    countingScene(~id="motion", ~mounts),
  ]

  let labels = entries => entries->Array.map((entry: MenuDisclosure.entry) => entry.label)

  test("splits into the primary row and the demos, and offers a withheld game in neither", () => {
    // Klondike is a game with no top-level row, so it is on no list at all: the
    // demos group is for demos, and a game filed there would read as a render demo
    // between Gallery and Motion.
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(~default="freecell", scenes(mounts))
    expect(switcher.primaryScenes()->Array.map(scene => scene.id))->toEqual(["freecell"])
    expect(switcher.debugScenes()->labels)->toEqual(["gallery", "motion"])
  })

  test("a withheld game keeps its scene, which is still reachable by id", () => {
    // What's left of a game with no row: `?game=` and `ensureActive` still mount it,
    // which is the difference between withholding a game and dropping it.
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(~default="freecell", scenes(mounts))
    switcher.select("klondike")
    expect(mounts.contents)->toBe(2) // freecell's opening mount, then klondike's
    // …and it still doesn't join a list by being the one on the table.
    expect(switcher.primaryScenes()->Array.map(scene => scene.id))->toEqual(["freecell"])
    expect(switcher.debugScenes()->labels)->toEqual(["gallery", "motion"])
  })

  test("a deep link opens the demos group only when it lands inside it", () => {
    // The highlighted row has to be visible rather than hidden behind a collapsed
    // disclosure — and a link onto a scene with no row in there, the primary game's or
    // a withheld game's alike, leaves it shut.
    let mounts = ref(0)
    let openness = switcher => switcher.SceneSwitcher.debugScenesOpen
    expect(SceneSwitcher.render(~default="freecell", scenes(mounts))->openness)->toBe(false)
    expect(
      SceneSwitcher.render(~default="freecell", ~forced="klondike", scenes(mounts))->openness,
    )->toBe(false)
    expect(
      SceneSwitcher.render(~default="freecell", ~forced="motion", scenes(mounts))->openness,
    )->toBe(true)
  })

  test("a demo named as the launch default keeps its top-level row and only that", () => {
    // The primary is still the launch default, whatever its kind — and it must not
    // also appear in the demos group, or the menu would list it twice. The games it
    // leaves behind are withheld rather than demoted into that group.
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(~default="gallery", scenes(mounts))
    expect(switcher.primaryScenes()->Array.map(scene => scene.id))->toEqual(["gallery"])
    expect(switcher.debugScenes()->labels)->toEqual(["motion"])
  })
})

describe("SceneSwitcher's promoted games", () => {
  // Two games up top, a third withheld and so listed nowhere, and the demos. `~primary`
  // is what promotes a game; the launch default is promoted whether or not it's named,
  // so the way home can't be configured away.
  let scenes = mounts => [
    game(~id="freecell", ~mounts),
    countingScene(~id="gallery", ~mounts),
    game(~id="simplesimon", ~mounts),
    game(~id="klondike", ~mounts),
  ]

  let labels = entries => entries->Array.map((entry: MenuDisclosure.entry) => entry.label)

  test("a promoted game gets a top-level row, and the withheld one still gets none", () => {
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      ~primary=() => ["simplesimon"],
      scenes(mounts),
    )
    expect(switcher.primaryScenes()->Array.map(scene => scene.id))->toEqual([
      "freecell",
      "simplesimon",
    ])
    expect(switcher.debugScenes()->labels)->toEqual(["gallery"])
  })

  test("the rows keep the scene list's order, whatever order they were promoted in", () => {
    // One place decides the menu's order — the scene list — so naming the ids the
    // other way round changes nothing.
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      ~primary=() => ["simplesimon", "freecell"],
      scenes(mounts),
    )
    expect(switcher.primaryScenes()->Array.map(scene => scene.id))->toEqual([
      "freecell",
      "simplesimon",
    ])
  })

  test("the launch default has a row even when it isn't named", () => {
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      ~primary=() => ["simplesimon"],
      scenes(mounts),
    )
    expect(switcher.primaryScenes()->Array.map(scene => scene.id))->toEqual([
      "freecell",
      "simplesimon",
    ])
    // …and naming it too lists it once, not twice.
    let named = SceneSwitcher.render(
      ~default="freecell",
      ~primary=() => ["freecell", "simplesimon"],
      scenes(mounts),
    )
    expect(named.primaryScenes()->Array.map(scene => scene.id))->toEqual([
      "freecell",
      "simplesimon",
    ])
  })

  test("an id that names no scene promotes nothing", () => {
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      ~primary=() => ["spider"],
      scenes(mounts),
    )
    expect(switcher.primaryScenes()->Array.map(scene => scene.id))->toEqual(["freecell"])
  })

  test("a game promoted after launch gains its row without a re-render of the scene", () => {
    // What the Beta features flag does: `~primary` answers differently on the next menu
    // render, and the game that was listed nowhere gains a top-level row with no scene
    // torn down or mounted on the way. The list is asked afresh, so the row a player
    // taps is the one the flag says should be there now — not the one the app launched
    // with.
    let mounts = ref(0)
    let promoted = ref(false)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      ~primary=() => promoted.contents ? ["simplesimon", "klondike"] : ["simplesimon"],
      scenes(mounts),
    )
    expect(switcher.primaryScenes()->Array.map(scene => scene.id))->toEqual([
      "freecell",
      "simplesimon",
    ])
    expect(switcher.debugScenes()->labels)->toEqual(["gallery"])

    promoted := true
    expect(switcher.primaryScenes()->Array.map(scene => scene.id))->toEqual([
      "freecell",
      "simplesimon",
      "klondike",
    ])
    // …and the demos group is untouched on the way: promotion is between "no list at
    // all" and the rows up top, and never through the disclosure.
    expect(switcher.debugScenes()->labels)->toEqual(["gallery"])
    expect(mounts.contents)->toBe(1) // the launch mount, and nothing since
  })

  test("selecting each promoted game by id mounts it, and the highlight follows", () => {
    // Navigation between two top-level rows, the way the menu does it: `select` by id
    // each way, with an activation reported for every real change and the row's
    // reselect for a tap on the game already showing.
    let mounts = ref(0)
    let activated = []
    let reselects = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      ~primary=() => ["simplesimon"],
      ~onActivate=(scene: Scene.t) => activated->Array.push(scene.id),
      ~onReselect=() => reselects := reselects.contents + 1,
      scenes(mounts),
    )
    expect(mounts.contents)->toBe(1)
    switcher.select("simplesimon")
    expect(mounts.contents)->toBe(2)
    switcher.select("simplesimon")
    expect(mounts.contents)->toBe(2) // already up: acknowledged, not re-dealt
    expect(reselects.contents)->toBe(1)
    switcher.select("freecell")
    expect(mounts.contents)->toBe(3)
    expect(activated)->toEqual(["freecell", "simplesimon", "freecell"])
    // Neither promoted game ever shows up in the demos group on the way.
    expect(switcher.debugScenes()->labels)->toEqual(["gallery"])
  })

  test("a deep link onto a promoted game leaves the demos group shut", () => {
    // `?game=simplesimon` lands on a row that's already visible, so there's nothing
    // to unfold; the `active` seed still names it for the chrome's highlight.
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      ~primary=() => ["simplesimon"],
      ~forced="simplesimon",
      scenes(mounts),
    )
    expect(switcher.active)->toEqual(Some("simplesimon"))
    expect(switcher.debugScenesOpen)->toBe(false)
  })
})
