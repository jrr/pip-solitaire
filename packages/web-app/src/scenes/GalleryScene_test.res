// The gallery is a `Scene.static`: no model, no messages, no teardown of its own. What
// that costs it is nothing the switcher can tell apart from any other scene, which is
// the claim below.
open Vitest

describe("the gallery scene", () => {
  test("mounts all 52 cards into the container it's given", () => {
    let container = TestDom.host("div")
    let teardown = GalleryScene.make().mount(container)
    expect(container->TestDom.findAll(".card-art")->Array.length)->toBe(52)
    // A static scene's teardown is a no-op — the switcher clears the container
    // itself — but it must exist and be safe to call, like any other scene's.
    teardown()
  })

  test("is a scene like any other: it has the id and label the switcher lists it by", () => {
    let scene = GalleryScene.make()
    expect((scene.id, scene.label))->toEqual(("gallery", "Gallery"))
  })
})
