// The `raster` scene's one piece of pure vocabulary: the three renderings and
// their `?raster=` names.
//
// The scene itself is pixels and needs a browser (browser-tests/raster.spec.mjs).
// What's worth pinning without one is the naming, because `AppUrl` parses the
// URL knob through here and a name that stopped round-tripping wouldn't fail —
// it would quietly open the scene's default instead, so a link that says
// `?raster=canvas` would show SVG sprites and look almost right.
open Vitest

describe("RasterScene renderings", () => {
  test("every rendering round-trips through the `?raster=` URL knob", () => {
    RasterScene.renderings->Array.forEach(
      rendering =>
        expect(RasterScene.renderingFromString(RasterScene.renderingId(rendering)))->toEqual(
          Some(rendering),
        ),
    )
  })

  test("the ids are the ones the links and the browser suite use", () => {
    expect(RasterScene.renderings->Array.map(RasterScene.renderingId))->toEqual(["live", "sprite"])
  })

  test("an unknown name is ignored rather than guessed at", () => {
    expect(RasterScene.renderingFromString("webgl"))->toEqual(None)
  })

  // The keyboard shortcut is `renderings` indexed by key number, and the button
  // labels are numbered from the same array, so the order *is* the mapping.
  test("the order is the 1/2 key mapping", () => {
    expect(RasterScene.renderings->Array.map(RasterScene.renderingLabel))->toEqual([
      "Live SVG",
      "Sprite",
    ])
  })
})
