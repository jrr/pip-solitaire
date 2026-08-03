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
})
