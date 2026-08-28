// Selecting a scene activates it — but selecting the scene *already showing* must
// not tear it down and mount it again. A fake scene that counts its mounts is enough
// to check this in jsdom; no layout or input engine needed.
//
// The primary game's row is still a real DOM button the switcher owns, so that one
// is clicked. The debug/demo scenes left as data in #336 — a list of
// `<MenuDisclosure>` entries — so those are exercised by running an entry's
// `onSelect`, which is the very thunk the rendered row is wired to.

open Vitest
open TestDom

let countingScene = (~id, ~mounts): Scene.t => {
  id,
  label: id,
  mount: _container => {
    mounts := mounts.contents + 1
    () => ()
  },
}

describe("SceneSwitcher rows", () => {
  test("tapping the showing scene's own row doesn't re-mount it", () => {
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      [countingScene(~id="freecell", ~mounts)],
    )
    // The initial mount.
    expect(mounts.contents)->toBe(1)
    switch switcher.controls->find(".menu-row") {
    | Some(row) => row->click
    | None => expect("the freecell row")->toBe("but it wasn't rendered")
    }
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
    switch switcher.controls->find(".menu-row") {
    | Some(row) => row->click
    | None => expect("the freecell row")->toBe("but it wasn't rendered")
    }
    expect(reselects.contents)->toBe(1)
    expect(mounts.contents)->toBe(1)
  })

  test("selecting a different scene does mount it", () => {
    // The guard is "don't re-mount what's already up", not "don't mount" — an entry
    // for another scene still switches to it, and reports an activation rather than
    // a reselect.
    let freecell = ref(0)
    let demo = ref(0)
    let reselects = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      ~onReselect=() => reselects := reselects.contents + 1,
      [countingScene(~id="freecell", ~mounts=freecell), countingScene(~id="demo", ~mounts=demo)],
    )
    // The non-primary scene is an entry in the debug group, not a row in the games
    // list — the games list holds the primary game alone.
    expect(switcher.controls->findAll(".menu-row")->Array.length)->toBe(1)
    switch switcher.debugScenes()->Array.get(0) {
    | Some(entry) => entry.onSelect()
    | None => expect("the demo entry")->toBe("but there wasn't one")
    }
    expect(demo.contents)->toBe(1)
    expect(reselects.contents)->toBe(0)
  })

  test("marks the showing scene's row the way <MenuRow selected> does", () => {
    // The row is still built here by hand, so what it must not do is drift from the
    // component the rest of the menu uses (#335): the same `menu-row` classes, and
    // `aria-current` on the current row — absent, not "false", on one that isn't.
    let mounts = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      [countingScene(~id="freecell", ~mounts), countingScene(~id="gallery", ~mounts)],
    )
    switch switcher.controls->find(".menu-row") {
    | Some(row) =>
      expect(row->classes)->toBe("menu-row menu-row--action menu-row--active")
      expect(row->attr("aria-current"))->toBe(Some("true"))
      expect(row->textIn(".menu-row__label"))->toBe("freecell")
      // Off to a scene in the debug group: the primary row stops being current, and
      // drops the attribute rather than reporting a negative.
      switcher.ensureActive("gallery")
      expect(row->classes)->toBe("menu-row menu-row--action")
      expect(row->hasAttr("aria-current"))->toBe(false)
    | None => expect("the freecell row")->toBe("but it wasn't rendered")
    }
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
})
