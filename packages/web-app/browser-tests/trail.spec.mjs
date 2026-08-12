// The two mechanics the victory overlay rests on (issue #226).
//
// The `trail` scene exists to prove them before the animation is written:
// a transparent canvas over live DOM, and a resting card handed off from the DOM
// to the canvas. Both are questions about pixels and about a real compositor, so
// neither is answerable in jsdom — the unit tests can only check that the scene
// survives having no canvas at all.
//
// Everything here reads the overlay's own pixels back with `getImageData`. The
// canvas is drawn from a sheet that was itself rasterized from an SVG *data URL*,
// which is same-origin and doesn't taint it (the raster suite relies on the same
// thing), so the buffer is readable.

import { expect, test } from "@playwright/test"

// A 3× device so the cap has something to bite on: `min(devicePixelRatio, cap)`
// is only interesting where the device ratio is above the cap. At 1× every cap
// resolves to the same number and the backing-store assertions below would pass
// without testing anything.
test.use({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 3 })

async function open(page) {
  await page.goto("/?scene=trail")
  // The sprite build is async — there's nothing else to wait on.
  await expect(page.locator('.trail-scene[data-trail="ready"]')).toBeVisible()
}

const stage = (page) => page.locator(".trail-stage")
const canvas = (page) => page.locator(".trail-canvas")

/**
 * Read the overlay back: how many of its pixels have been drawn on, and the
 * alpha at a given list of stage (CSS-pixel) positions. Sampling is done in
 * device pixels, so the positions are scaled by the ratio the backing store was
 * sized at — which is itself derived from the canvas, not assumed.
 */
async function inspect(page, points = []) {
  return await page.evaluate((points) => {
    const el = document.querySelector(".trail-canvas")
    const ctx = el.getContext("2d")
    const { width, height } = el
    const { data } = ctx.getImageData(0, 0, width, height)
    let painted = 0
    for (let i = 3; i < data.length; i += 4) if (data[i] > 0) painted++
    const ratio = width / el.getBoundingClientRect().width
    const alphaAt = points.map(([x, y]) => {
      const px = Math.round(x * ratio)
      const py = Math.round(y * ratio)
      return data[(py * width + px) * 4 + 3]
    })
    return { width, height, painted, total: width * height, ratio, alphaAt }
  }, points)
}

/** Drag the pointer left-to-right across the stage, drawing as it goes. */
async function sweep(page, { fromRatio = 0.15, toRatio = 0.85, yRatio = 0.5, steps = 24 } = {}) {
  const box = await stage(page).boundingBox()
  const y = box.y + box.height * yRatio
  const from = box.x + box.width * fromRatio
  const to = box.x + box.width * toRatio
  for (let i = 0; i <= steps; i++) {
    await page.mouse.move(from + ((to - from) * i) / steps, y)
  }
  return box
}

test.describe("trail scene — the canvas over live DOM", () => {
  test("the overlay starts empty and covers the backdrop exactly", async ({ page }) => {
    await open(page)

    // Same box, so a pointer position measured against the stage means the same
    // thing on the canvas — the assumption every draw call here rests on.
    const stageBox = await stage(page).boundingBox()
    const canvasBox = await canvas(page).boundingBox()
    expect(canvasBox.x).toBeCloseTo(stageBox.x, 1)
    expect(canvasBox.y).toBeCloseTo(stageBox.y, 1)
    expect(canvasBox.width).toBeCloseTo(stageBox.width, 1)
    expect(canvasBox.height).toBeCloseTo(stageBox.height, 1)

    // Nothing drawn yet: every pixel transparent, so the whole backdrop shows
    // through. This is the first mechanic, stated as a number.
    const before = await inspect(page)
    expect(before.painted).toBe(0)
  })

  test("the DOM underneath keeps receiving pointer events", async ({ page }) => {
    await open(page)
    // The other half of "the overlay doesn't take the page over": a card covered
    // by the canvas is still what the browser hit-tests at that point.
    const card = page.locator(".trail-stage .stacking-card").first()
    const box = await card.boundingBox()
    const topmost = await page.evaluate(
      ([x, y]) => document.elementFromPoint(x, y)?.closest(".stacking-card") !== null,
      [box.x + box.width / 2, box.y + box.height / 2],
    )
    expect(topmost).toBe(true)
  })

  test("the trail persists — drawing never clears what came before", async ({ page }) => {
    await open(page)
    const box = await sweep(page, { toRatio: 0.5 })

    const half = await inspect(page)
    expect(half.painted).toBeGreaterThan(0)

    // A point the first half of the sweep painted. If drawing cleared, this is
    // what would be gone by the end of the second half.
    const early = [box.width * 0.2, box.height * 0.5]
    const [earlyAlphaBefore] = (await inspect(page, [early])).alphaAt
    expect(earlyAlphaBefore).toBeGreaterThan(0)

    await sweep(page, { fromRatio: 0.5, toRatio: 0.9 })
    const full = await inspect(page, [early])
    expect(full.painted).toBeGreaterThan(half.painted)
    expect(full.alphaAt[0]).toBe(earlyAlphaBefore)
  })
})

test.describe("trail scene — the hand-off", () => {
  test("a handed-off card leaves the DOM and continues on the canvas", async ({ page }) => {
    await open(page)

    const cards = page.locator(".trail-stage .stacking-card")
    const before = await cards.count()
    expect(before).toBeGreaterThan(0)

    // Where the first card is resting, in stage coordinates — the pixel the
    // sprite has to land on for the hand-off to be invisible.
    const stageBox = await stage(page).boundingBox()
    const cardBox = await cards.first().boundingBox()
    const centre = [
      cardBox.x + cardBox.width / 2 - stageBox.x,
      cardBox.y + cardBox.height / 2 - stageBox.y,
    ]

    // Nothing on the canvas there yet: whatever is visible at that point is the
    // DOM card, not a sprite.
    expect((await inspect(page, [centre])).alphaAt[0]).toBe(0)

    await page.getByRole("button", { name: "Hand off a card" }).click()

    // It left the document…
    await expect(cards).toHaveCount(before - 1)
    // …and the canvas is now painted where it was standing.
    expect((await inspect(page, [centre])).alphaAt[0]).toBeGreaterThan(0)

    // And it carries on: the handed-off card is the sprite the pointer draws
    // with, so moving away from the resting place paints somewhere new.
    const paintedAfterStamp = (await inspect(page)).painted
    await sweep(page)
    expect((await inspect(page)).painted).toBeGreaterThan(paintedAfterStamp)
  })
})

test.describe("trail scene — the backing store", () => {
  test("is cssSize × min(devicePixelRatio, cap) at every cap", async ({ page }) => {
    await open(page)
    const box = await stage(page).boundingBox()

    // The device is 3× (see `test.use`), so 1 and 2 are held under the cap and 3
    // is the device's own ratio — the toggle walks both sides of the cap the rest
    // of the app rasterizes at.
    for (const [key, cap] of [
      ["1", 1],
      ["2", 2],
      ["3", 3],
    ]) {
      await page.keyboard.press(key)
      await expect(page.locator('.trail-scene[data-trail="ready"]')).toBeVisible()
      await expect(page.locator(".trail-scene")).toHaveAttribute("data-cap", `${cap}×`)

      const measured = await inspect(page)
      expect(measured.width).toBe(Math.round(box.width * cap))
      expect(measured.height).toBe(Math.round(box.height * cap))
      // The status line reports the same ratio for the *sprites*. The two
      // agreeing is what makes a blit 1:1 rather than a resample, and it's the
      // reason the cap can't be a canvas-local decision (see CardRaster).
      await expect(page.locator(".trail-scene__status")).toContainText(`sprites @${cap}×`)
    }
  })

  test("assigning canvas.width wipes the trail", async ({ page }) => {
    await open(page)
    await sweep(page)
    expect((await inspect(page)).painted).toBeGreaterThan(0)

    // The size doesn't change — only `canvas.width` is written — and everything
    // drawn is gone. This is why the integration ends the cascade on a resize
    // rather than trying to carry it across one: there is nothing to carry.
    const before = await canvas(page).boundingBox()
    await page.getByRole("button", { name: "Re-assign canvas.width" }).click()

    const after = await inspect(page)
    expect(after.painted).toBe(0)
    const box = await canvas(page).boundingBox()
    expect(box.width).toBeCloseTo(before.width, 1)
    expect(box.height).toBeCloseTo(before.height, 1)
  })
})
