// `NotchDisplay` reflects the "Display content around screen notch" preference
// onto the document root as `data-notch-wings`, the seam the landscape
// wing-placement CSS keys off. On (the default) clears the attribute so the base
// rules govern; off stamps "off" so the clamp overrides win. jsdom provides a real
// `document.documentElement`, so this exercises the actual attribute writes.

open Vitest
open TestDom

@val @scope("document") external documentElement: Html.element = "documentElement"

let attr = () => documentElement->attr("data-notch-wings")

describe("NotchDisplay.setEnabled", () => {
  test("off stamps data-notch-wings=off so the clamp overrides apply", () => {
    NotchDisplay.setEnabled(false)
    expect(attr())->toEqual(Some("off"))
  })

  test("on clears the attribute so the default wing placement governs", () => {
    NotchDisplay.setEnabled(false)
    NotchDisplay.setEnabled(true)
    expect(attr())->toEqual(None)
  })
})
