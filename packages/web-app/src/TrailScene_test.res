// The `trail` scene's two halves that don't need pixels (#226).
//
// What the scene is *for* is pixels — a canvas that shows the DOM through it, a
// hand-off that shouldn't visibly move anything — and that's measured in the
// browser suite (browser-tests/trail.spec.mjs). Two things are worth pinning
// without one:
//
//   - the toolbar/keyboard vocabulary, which has the same "three consumers, one
//     order" shape the raster scene's does, and
//   - that the scene *mounts* in an environment with no canvas at all. jsdom has
//     no rasterizer behind `<canvas>`, so `getContext` yields nothing; the scene
//     has to come up empty rather than throw, or it takes every other test in
//     this file down with it the moment it's added to the switcher.
open Vitest

// Read back what the scene put in the document. Declared here, as the other
// scene tests declare theirs — `WebDom` is the vocabulary the scenes *write*
// with, and none of them needs to read a rendered tree back.
@send external getAttribute: (WebDom.element, string) => Nullable.t<string> = "getAttribute"
type nodeList
@send external querySelectorAll: (WebDom.element, string) => nodeList = "querySelectorAll"
@get external nodeCount: nodeList => int = "length"

describe("TrailScene's cap toggle", () => {
  test("the order is the 1/2/3 key mapping", () => {
    // Key *n* picks the *n*th cap and each button prints its own index, so the
    // array order is the mapping — same arrangement as `RasterScene.renderings`.
    expect(TrailScene.caps)->toEqual([1., 2., 3.])
  })

  test("brackets the cap the rest of the app rasterizes at", () => {
    // The toggle only answers "does capping at 2 lose anything?" if it can show
    // both sides of that cap.
    expect(TrailScene.caps->Array.some(cap => cap < CardRaster.maxPixelRatio))->toBe(true)
    expect(TrailScene.caps->Array.some(cap => cap > CardRaster.maxPixelRatio))->toBe(true)
    expect(TrailScene.caps->Array.includes(CardRaster.maxPixelRatio))->toBe(true)
  })

  test("labels a cap the way the status line names a ratio", () => {
    expect(TrailScene.capLabel(2.))->toBe("2×")
  })
})

describe("TrailScene's backdrop", () => {
  test("the cards overlap, so lifting one out leaves a visible gap", () => {
    // The hand-off is only legible if the card that leaves was covering
    // something. A step wider than a card would fan them out into a row with
    // nothing behind anything.
    let step = TrailScene.restingX(1) -. TrailScene.restingX(0)
    expect(step < TrailScene.cardWidth)->toBe(true)
    expect(step > 0.)->toBe(true)
  })

  test("every backdrop card fits inside the stage", () => {
    // The stage clips (`overflow: hidden`), so a card resting past its bottom
    // edge would be half a card — and half a card handed off would look like a
    // hand-off bug rather than a layout one.
    TrailScene.backdropDeck->Array.forEachWithIndex(
      (_, index) =>
        expect(TrailScene.restingY(index) +. TrailScene.cardHeight <= TrailScene.stageHeight)->toBe(
          true,
        ),
    )
  })
})

describe("TrailScene without a canvas", () => {
  test("mounts, and says so, rather than throwing", () => {
    // jsdom's `<canvas>` has no context to give (see `CardRaster.context2d`),
    // which is exactly the `None` arm every draw call here is written around.
    let container = WebDom.createElement("div")
    let teardown = TrailScene.make().mount(container)

    let scene = container->WebDom.firstChild->Nullable.toOption
    expect(scene->Option.isSome)->toBe(true)
    scene->Option.forEach(
      scene => {
        // Not "building": a missing context is a different thing from a sprite
        // build that hasn't landed, and the flag the browser suite waits on has
        // to tell them apart.
        expect(scene->getAttribute("data-trail")->Nullable.toOption)->toEqual(Some("no-canvas"))
        // The backdrop is ordinary DOM and doesn't depend on the canvas at all,
        // so it's there either way.
        expect(scene->querySelectorAll(".stacking-card")->nodeCount)->toBe(
          TrailScene.backdropDeck->Array.length,
        )
      },
    )

    teardown()
  })
})
