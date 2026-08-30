// The half of the `trail` scene that isn't pixels.
//
// What the scene is *for* — a trail that persists, backdrop cards showing
// through, a hand-off that lands on the exact pixel the node occupied — is a
// question about a drawing surface, and lives in `browser-tests/trail.spec.mjs`
// where there's an engine to draw with and a pointer to move.
//
// Two things are worth pinning without one, and both are the kind of mistake that
// produces a plausible-looking picture rather than an error:
//
//   - **The ratio arithmetic.** The cap, and the rule that the display always
//     wins below it. A sprite sheet built at one ratio and blitted onto a store
//     sized at another still draws cards; they're just soft, and nothing says so.
//   - **That the scene survives an engine with no 2D context.** Which is the
//     whole reason `Canvas.context2d` answers an `option` — and it isn't a
//     hypothetical for a test environment, it's this one.
//
// So jsdom's canvas is made to answer the way an engine without a 2D
// implementation does — explicitly, rather than leaving it to jsdom's own
// "not implemented" path, so what the scene is being held to is a stated
// contract. `fetch` is stubbed to reject for the same reason `matchMedia` is
// stubbed in `TableScene_test`: the scene builds sprites on mount, there is no
// engine here to rasterize them, and a rejection is a local, immediate failure
// rather than a socket the test runner has to wait out.
%%raw(`
  if (globalThis.HTMLCanvasElement) {
    globalThis.HTMLCanvasElement.prototype.getContext = () => null
  }
  globalThis.fetch = () => Promise.reject(new Error("no network in jsdom"))
`)

open Vitest

let mount = () => {
  let host = TestDom.host("div")
  let scene = TrailScene.make()
  let teardown = scene.mount(host)
  (host, teardown)
}

describe("TrailScene's pixel ratio", () => {
  test("caps the display's ratio rather than trusting it", () => {
    // 3.75 isn't a made-up number: browser zoom multiplies the device ratio, and
    // a Retina Mac one step in reports exactly this.
    expect(TrailScene.drawRatio(~display=3.75, ~cap=2.))->toBe(2.)
    expect(TrailScene.drawRatio(~display=3.75, ~cap=1.))->toBe(1.)
  })

  test("below the cap the display wins — a store finer than the screen is waste", () => {
    expect(TrailScene.drawRatio(~display=1., ~cap=3.))->toBe(1.)
    expect(TrailScene.drawRatio(~display=2., ~cap=3.))->toBe(2.)
  })

  test("the cap the scene opens on is the cache's, not one of its own", () => {
    // The whole claim of the scene's dpr note: the overlay's backing store and the
    // sprites blitted into it are built from one number. Two would type-check.
    expect(TrailScene.caps->Array.includes(CardRaster.maxPixelRatio))->toBe(true)
  })

  test("a backing-store dimension rounds rather than truncating", () => {
    expect(TrailScene.storePixels(~css=300., ~ratio=2.))->toBe(600)
    // Truncating here would leave the last row of CSS pixels drawing into
    // nothing at all.
    expect(TrailScene.storePixels(~css=360.5, ~ratio=2.))->toBe(721)
    expect(TrailScene.storePixels(~css=360.4, ~ratio=1.))->toBe(360)
  })
})

describe("the trail scene, on an engine that can't draw", () => {
  test("mounts a backdrop of real board cards under a transparent overlay", () => {
    let (host, _) = mount()
    // `.stacking-card` is TableScene's own rule, holding the real card art —
    // proving the overlay works over *those* nodes is the point of the scene, so
    // a backdrop of look-alikes would prove nothing.
    expect(TestDom.findAll(host, ".trail-stage .stacking-card")->Array.length)->toBe(
      TrailScene.backdropCards->Array.length,
    )
    expect(TestDom.findAll(host, ".trail-stage .stacking-card .card-art")->Array.length)->toBe(
      TrailScene.backdropCards->Array.length,
    )
    expect(TestDom.has(host, ".trail-stage canvas.trail-overlay"))->toBe(true)
  })

  test("opens at the cache's cap", () => {
    let (host, _) = mount()
    let scene = TestDom.find(host, ".trail-scene")->Option.getOrThrow
    expect(TestDom.attrOr(scene, "data-cap"))->toBe(Float.toString(CardRaster.maxPixelRatio))
  })

  test("asking for 3× on a 1× display still draws at 1×", () => {
    // jsdom reports `devicePixelRatio` 1, which makes it the one case the browser
    // suite (which runs at 3) can't show: the cap is a ceiling, not a setting.
    let (host, _) = mount()
    let scene = TestDom.find(host, ".trail-scene")->Option.getOrThrow
    let three =
      TestDom.findAll(host, ".trail-toggle")
      ->Array.find(button => TestDom.text(button) == "3×")
      ->Option.getOrThrow
    TestDom.click(three)
    expect(TestDom.attrOr(scene, "data-cap"))->toBe("3")
    expect(TestDom.attrOr(scene, "data-ratio"))->toBe("1")
    expect(TestDom.classes(three)->String.includes("trail-toggle--on"))->toBe(true)
  })

  test("won't hand a card off while there is no sprite to hand it off as", () => {
    // The one way this control can lose information: remove a real card from the
    // document and draw nothing in its place. Here the build can't land (no
    // engine, no fonts), so the button has to stay shut.
    let (host, _) = mount()
    let button = TestDom.find(host, ".trail-action")->Option.getOrThrow
    expect(TestDom.hasAttr(button, "disabled"))->toBe(true)
    TestDom.click(button)
    expect(TestDom.findAll(host, ".trail-stage .stacking-card")->Array.length)->toBe(
      TrailScene.backdropCards->Array.length,
    )
  })

  test("says what it couldn't do instead of showing an empty box", () => {
    let (host, _) = mount()
    // Before the build resolves either way, and with no `data-trail` to say the
    // scene is showing what it was asked for.
    expect(TestDom.textIn(host, ".trail-status"))->toBe("rasterizing 52 cards…")
    let scene = TestDom.find(host, ".trail-scene")->Option.getOrThrow
    expect(TestDom.hasAttr(scene, "data-trail"))->toBe(false)
  })

  test("tears down without the container having to be cleared first", () => {
    let (_, teardown) = mount()
    teardown()
  })
})
