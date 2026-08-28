// Selecting a scene activates it — but selecting the scene *already showing* must
// not tear it down and mount it again. A fake scene that counts its mounts is enough
// to check this in jsdom; no layout or input engine needed.
//
// Nothing here clicks a button any more. The switcher builds no menu DOM at all (#337
// finished what #336 started), so what's exercised is the data it hands over: a
// primary scene is `select`ed by id, exactly as the row the chrome draws does it, and
// a debug/demo scene by running its entry's `onSelect` — the very thunk that row is
// wired to. Which scene is current is likewise read rather than looked at: `active`
// for the seed the chrome opens with, `entry.selected` for the group's highlight.

open Vitest

let countingScene = (~id, ~mounts): Scene.t => {
  id,
  label: id,
  mount: _container => {
    mounts := mounts.contents + 1
    () => ()
  },
}

describe("SceneSwitcher's games list", () => {
  test("hands the primary game over as data, and says it's the one showing", () => {
    // The scene list minus the demos, plus the id the chrome seeds its model with —
    // that pairing is the whole of the menu's highlight now.
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      [countingScene(~id="freecell", ~mounts), countingScene(~id="gallery", ~mounts)],
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
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      [countingScene(~id="freecell", ~mounts)],
    )
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
      [countingScene(~id="freecell", ~mounts)],
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
      [countingScene(~id="freecell", ~mounts=freecell), countingScene(~id="demo", ~mounts=demo)],
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
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      [countingScene(~id="freecell", ~mounts)],
    )
    switcher.select("nope")
    expect(mounts.contents)->toBe(1)
  })
})

describe("SceneSwitcher's debug group (#336)", () => {
  test("hands the demo scenes over as entries, with the mounted one selected", () => {
    // The highlight the switcher used to write onto its own buttons is now a field
    // on the entry, read fresh each time the menu renders.
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      [
        countingScene(~id="freecell", ~mounts),
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
    let scenes = [countingScene(~id="freecell", ~mounts), countingScene(~id="gallery", ~mounts)]
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
      [countingScene(~id="freecell", ~mounts), countingScene(~id="gallery", ~mounts)],
    )
    expect(switcher.active)->toEqual(Some("gallery"))
  })
})
