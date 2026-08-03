// Tapping a scene row activates its scene — but a tap on the row for the scene
// *already showing* must not tear that scene down and mount it again. The rows
// are real DOM buttons, so a fake scene that counts its mounts is enough to
// check this in jsdom; no layout or input engine needed.

open Vitest

@send
external querySelector: (WebDom.element, string) => Nullable.t<WebDom.element> = "querySelector"
@send external click: WebDom.element => unit = "click"

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
    switch switcher.controls->querySelector(".scene-menu__row")->Nullable.toOption {
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
    switch switcher.controls->querySelector(".scene-menu__row")->Nullable.toOption {
    | Some(row) => row->click
    | None => expect("the freecell row")->toBe("but it wasn't rendered")
    }
    expect(reselects.contents)->toBe(1)
    expect(mounts.contents)->toBe(1)
  })

  test("tapping a different scene's row does mount it", () => {
    // The guard is "don't re-mount what's already up", not "don't mount" — a row for
    // another scene still switches to it, and reports an activation rather than a
    // reselect.
    let freecell = ref(0)
    let demo = ref(0)
    let reselects = ref(0)
    let switcher = SceneSwitcher.render(
      ~default="freecell",
      ~onReselect=() => reselects := reselects.contents + 1,
      [countingScene(~id="freecell", ~mounts=freecell), countingScene(~id="demo", ~mounts=demo)],
    )
    // The non-primary scene's row lives in the debug group, not the games list.
    switch switcher.debugScenes->querySelector(".scene-menu__row")->Nullable.toOption {
    | Some(row) => row->click
    | None => expect("the demo row")->toBe("but it wasn't rendered")
    }
    expect(demo.contents)->toBe(1)
    expect(reselects.contents)->toBe(0)
  })
})
