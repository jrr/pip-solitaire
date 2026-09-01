// The half of the `cascade` scene that isn't pixels.
//
// Whether the cascade *looks* right is what the scene itself is for, and whether it
// draws where it says it does is `browser-tests/cascade.spec.mjs`, which has an engine
// to draw with and a buffer to read back. What is worth pinning without one is the
// chrome around the physics: that the controls exist and say what they are set to, and
// that a scene which cannot rasterize a single card says so rather than showing an
// empty box.
//
// The stubs are `TrailScene_test`'s, for its reasons: jsdom is made to answer the way
// an engine with no 2D implementation does, and `fetch` rejects immediately rather than
// leaving the runner waiting on a socket that isn't there.
%%raw(`
  if (globalThis.HTMLCanvasElement) {
    globalThis.HTMLCanvasElement.prototype.getContext = () => null
  }
  globalThis.fetch = () => Promise.reject(new Error("no network in jsdom"))
`)

open Vitest

let mount = (~mode=CascadeScene.Live, ~seed=1) => {
  let host = TestDom.host("div")
  let scene = CascadeScene.make(~mode, ~seed)
  let teardown = scene.mount(host)
  (host, teardown)
}

let sceneNode = host => TestDom.find(host, ".cascade-scene")->Option.getOrThrow

describe("the cascade scene's mode", () => {
  test("reads `?cascade=`, and ignores anything it doesn't recognise", () => {
    expect(CascadeScene.modeFromString("pose"))->toEqual(Some(CascadeScene.Pose))
    expect(CascadeScene.modeFromString("live"))->toEqual(Some(CascadeScene.Live))
    // `None` leaves the scene's own default in place rather than refusing the link.
    expect(CascadeScene.modeFromString("frozen"))->toEqual(None)
  })
})

describe("the cascade scene, on an engine that can't draw", () => {
  test("mounts a stage with a transparent overlay filling it", () => {
    let (host, _) = mount()
    expect(TestDom.has(host, ".cascade-stage canvas.cascade-overlay"))->toBe(true)
  })

  test("says what it couldn't do instead of showing an empty box", () => {
    let (host, _) = mount()
    expect(TestDom.textIn(host, ".cascade-status"))->toBe("rasterizing 52 cards…")
    // No `data-cascade` until there is a cascade — the browser suite and the
    // screenshot report both wait on that attribute appearing.
    expect(TestDom.hasAttr(sceneNode(host), "data-cascade"))->toBe(false)
  })

  test("puts every number that decides the feel on a slider", () => {
    // The scene's premise: a cascade is tuned by looking at it, so nothing that
    // changes how it looks may be reachable only by editing source.
    let (host, _) = mount()
    let knobs =
      TestDom.findAll(host, ".cascade-knob input")->Array.map(
        input => TestDom.attrOr(input, "data-knob"),
      )
    expect(knobs)->toEqual(["gravity", "restitution", "slowest", "fastest", "launch", "trail"])
  })

  test("shows each knob's value, not just where its slider sits", () => {
    let (host, _) = mount()
    let gravity = TestDom.find(host, `input[data-knob="gravity"]`)->Option.getOrThrow
    TestDom.typeInto(gravity, "40")
    expect(TestDom.textIn(host, ".cascade-knob__value"))->toBe("40 cw/s²")
  })

  test("says what a deck at the launch interval costs, not just the interval", () => {
    // The interval is the one knob whose number is a fraction of what you actually
    // wait for, and its range now reaches a run of most of two minutes — so the total
    // is on the slider rather than left to be discovered by watching one.
    let (host, _) = mount()
    let launch = TestDom.find(host, `input[data-knob="launch"]`)->Option.getOrThrow
    expect(TestDom.attrOr(launch, "max"))->toBe("2000")
    TestDom.typeInto(launch, "2000")
    expect(TestDom.textIn(host, ".cascade-knob__value--wide"))->toBe("2000 ms · 52 cards in 104s")
  })

  test("opens on the largest card its stage has room for", () => {
    // A phone's stage, a desktop's, and a wall. Below the smallest there is nothing to
    // fall back to but the smallest — which is also what a scene that hasn't been laid
    // out yet asks for, since it measures zero.
    expect(CascadeScene.fitCardSize(~stageWidth=374.))->toBe(40.)
    expect(CascadeScene.fitCardSize(~stageWidth=1056.))->toBe(90.)
    expect(CascadeScene.fitCardSize(~stageWidth=2000.))->toBe(140.)
    expect(CascadeScene.fitCardSize(~stageWidth=0.))->toBe(40.)
  })

  test("takes the card size a button asks for instead", () => {
    // The three sizes are the claim that the motion is in card-widths: a cascade that
    // reads the same at 40px and 140px is one whose gravity means something.
    let (host, _) = mount()
    let scene = sceneNode(host)
    let large =
      TestDom.findAll(host, ".cascade-toggle")
      ->Array.find(button => TestDom.text(button) == "140px")
      ->Option.getOrThrow
    TestDom.click(large)
    expect(TestDom.attrOr(scene, "data-card"))->toBe("140")
    expect(TestDom.classes(large)->String.includes("cascade-toggle--on"))->toBe(true)
  })

  test("snaps to the device grid unless you ask it not to", () => {
    let (host, _) = mount()
    let scene = sceneNode(host)
    expect(TestDom.attrOr(scene, "data-snap"))->toBe("on")
    let snap =
      TestDom.findAll(host, ".cascade-toggle")
      ->Array.find(button => TestDom.text(button) == "device snap")
      ->Option.getOrThrow
    TestDom.click(snap)
    expect(TestDom.attrOr(scene, "data-snap"))->toBe("off")
  })

  test("replays the seed it was given, and moves on when asked for another", () => {
    let (host, _) = mount(~seed=7)
    let scene = sceneNode(host)
    expect(TestDom.attrOr(scene, "data-seed"))->toBe("7")
    let next =
      TestDom.findAll(host, ".cascade-action")
      ->Array.find(button => TestDom.text(button) == "Next seed")
      ->Option.getOrThrow
    TestDom.click(next)
    expect(TestDom.attrOr(scene, "data-seed"))->toBe("8")
  })

  test("won't offer to pause a pose, which has no loop to stop", () => {
    let (host, _) = mount(~mode=CascadeScene.Pose)
    let pause =
      TestDom.findAll(host, ".cascade-action")
      ->Array.find(button => TestDom.text(button) == "Pause")
      ->Option.getOrThrow
    expect(TestDom.hasAttr(pause, "disabled"))->toBe(true)
  })

  test("tears down without the container having to be cleared first", () => {
    let (_, teardown) = mount()
    teardown()
  })
})
