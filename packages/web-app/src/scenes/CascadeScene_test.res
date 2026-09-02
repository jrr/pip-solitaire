// The chrome around the cascade: that the controls exist and say what they are set to,
// and that a scene which cannot rasterize a card says so rather than showing an empty box.
// The pixels are `browser-tests/cascade.spec.mjs`'s.
//
// The stubs are `TrailScene_test`'s: jsdom answers the way an engine with no 2D
// implementation does, and `fetch` rejects rather than leaving the runner on a socket.
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
    // `None` leaves the scene's default in place rather than refusing the link.
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
    // The browser suite and the screenshot report both wait on that attribute appearing.
    expect(TestDom.hasAttr(sceneNode(host), "data-cascade"))->toBe(false)
  })

  test("puts every number that decides the feel on a slider", () => {
    // Nothing that changes how it looks may be reachable only by editing source.
    let (host, _) = mount()
    let knobs =
      TestDom.findAll(host, ".cascade-knob input")->Array.map(
        input => TestDom.attrOr(input, "data-knob"),
      )
    expect(knobs)->toEqual([
      "gravity",
      "bounciness",
      "bouncinessVariance",
      "speed",
      "speedVariance",
      "launchInterval",
      "trail",
    ])
  })

  let readout = (host, knob) =>
    TestDom.textIn(host, `.cascade-knob[data-knob="${knob}"] .cascade-knob__value`)

  test("shows each knob's value, not just where its slider sits", () => {
    let (host, _) = mount()
    let gravity = TestDom.find(host, `input[data-knob="gravity"]`)->Option.getOrThrow
    // Earth, which the slider reaches on purpose.
    TestDom.typeInto(gravity, "9.81")
    expect(readout(host, "gravity"))->toBe("9.81 m/s² · 1 g")
  })

  test("opens on four tenths of a g, which is the fact metres are there to tell", () => {
    // The cascade is slow motion, and the unit is what makes that legible.
    let (host, _) = mount()
    expect(readout(host, "gravity"))->toBe("4 m/s² · 0.41 g")
    expect(readout(host, "speed"))->toBe("0.4 m/s")
  })

  test("says what band a ± makes, rather than leaving it to be worked out", () => {
    let (host, _) = mount()
    expect(readout(host, "speedVariance"))->toBe("± 0.1 · 0.3–0.5 m/s")
    expect(readout(host, "bouncinessVariance"))->toBe("± 0.15 · 0.65–0.95")
  })

  test("and moves that band when the value under it moves, not only when ± does", () => {
    // A row repainted only when it is dragged shows a band the run stopped using.
    let (host, _) = mount()
    let speed = TestDom.find(host, `input[data-knob="speed"]`)->Option.getOrThrow
    TestDom.typeInto(speed, "1")
    expect(readout(host, "speedVariance"))->toBe("± 0.1 · 0.9–1.1 m/s")
  })

  test("says what a deck at the launch interval costs, not just the interval", () => {
    // The one knob whose number is a fraction of what you actually wait for.
    let (host, _) = mount()
    let launch = TestDom.find(host, `input[data-knob="launchInterval"]`)->Option.getOrThrow
    expect(TestDom.attrOr(launch, "max"))->toBe("2000")
    TestDom.typeInto(launch, "2000")
    expect(readout(host, "launchInterval"))->toBe("2000 ms · 52 cards in 104s")
  })

  test("opens on the largest card its stage has room for", () => {
    // A phone's stage, a desktop's, a wall, and a scene not laid out yet (which measures
    // zero and gets the smallest).
    expect(CascadeScene.fitCardSize(~stageWidth=374.))->toBe(40.)
    expect(CascadeScene.fitCardSize(~stageWidth=1056.))->toBe(90.)
    expect(CascadeScene.fitCardSize(~stageWidth=2000.))->toBe(140.)
    expect(CascadeScene.fitCardSize(~stageWidth=0.))->toBe(40.)
  })

  test("takes the card size a button asks for instead", () => {
    // The three sizes are the claim that the motion is in card-widths.
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

  test("draws on whole device pixels unless you ask it not to", () => {
    let (host, _) = mount()
    let scene = sceneNode(host)
    expect(TestDom.attrOr(scene, "data-snap"))->toBe("on")
    let snap =
      TestDom.findAll(host, ".cascade-toggle")
      ->Array.find(button => TestDom.text(button) == "whole pixels")
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
