// The QR code's drawing. The encoding is `uqr`'s, so what's pinned here is the part
// this module owns: the grid it asks for, the path it draws from it, and the refusal
// it turns an oversized link into.
open Vitest
open TestDom

describe("QrCode", () => {
  test("keeps the standard's four-module quiet zone inside the image", () => {
    // Version 1 is 21 modules a side; the margin adds four on each edge.
    let matrix = QrCode.matrix("pip")->Option.getOrThrow
    expect(matrix.size)->toBe(21 + 2 * QrCode.quietZone)
    expect(matrix.data->Array.getUnsafe(0)->Array.some(dark => dark))->toBe(false)
  })

  test("draws a run of dark modules as one subpath", () => {
    let matrix: QrCode.matrix = {size: 3, data: [[true, true, false], [false, false, true]]}
    expect(QrCode.path(matrix))->toBe("M0 0h2v1h-2zM2 1h1v1h-1z")
  })

  test("answers None for a link too long for any QR code, rather than throwing", () => {
    // A game-state link carries the whole undo history, so a long game can get here.
    expect(QrCode.matrix(String.repeat("x", 5000)))->toBe(None)
  })

  test("sizes the image to the grid, quiet zone included", () => {
    let matrix = QrCode.matrix("pip")->Option.getOrThrow
    let svg = Html.create(QrCode.make({matrix, label: "code"}))
    expect(svg->attrOr("viewBox"))->toBe("0 0 29 29")
    expect(svg->attrOr("aria-label"))->toBe("code")
  })
})
