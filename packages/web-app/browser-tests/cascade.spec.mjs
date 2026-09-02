// The cascade (issue #227) where its claims can actually be measured: in a real
// engine, reading the overlay's own buffer back.
//
// Three of them can only be checked here. **A seed replays exactly** — same picture,
// to the byte, on a second load. **A card lands on whole device pixels** — which is
// invisible in any single rendering and obvious as a count of half-lit edge pixels
// when you turn the snap off. **A resize ends the run** rather than rescaling it,
// because assigning `canvas.width` wipes the surface and there is no way around that.
//
// The instrument is `getImageData` on the overlay rather than a screenshot, for the
// reason `trail.spec.mjs` gives: a screenshot is the composite, and the composite
// cannot tell what the canvas drew from what the page put behind it.

import { expect, test } from "@playwright/test"

// **1.5, deliberately.** It is the ratio at which a whole CSS pixel is *not* a whole
// device pixel — reachable with one browser-zoom step, and the entire reason the snap
// exists. At an integer ratio the snapped and unsnapped runs draw the same pixels and
// the comparison below is unfalsifiable.
test.use({ viewport: { width: 1100, height: 900 }, deviceScaleFactor: 1.5 })

/** Open the scene and wait for the sprite sheet, which decodes asynchronously. */
async function open(page, query = "") {
  await page.goto(`/?scene=cascade${query}`)
  await expect(page.locator(".cascade-scene[data-cascade]")).toBeVisible()
}

const scene = (page) => page.locator(".cascade-scene")

/** The overlay's backing store and the box it covers, as the page sees them. */
const surface = (page) =>
  page.evaluate(() => {
    const canvas = document.querySelector(".cascade-overlay")
    const box = canvas.getBoundingClientRect()
    return {
      store: { width: canvas.width, height: canvas.height },
      css: { width: box.width, height: box.height },
      dpr: window.devicePixelRatio,
    }
  })

/**
 * What is on the overlay: how many device pixels are painted at all, and how many are
 * painted *partially*.
 *
 * The second number is the instrument for the snap. A sprite blitted onto the device
 * grid is a copy: its edges are the bitmap's own, which are hard. Blitted half a device
 * pixel off, it is resampled, and every edge is smeared across two columns of
 * half-lit pixels — so the partial count is the size of the resampling, in pixels.
 */
const ink = (page) =>
  page.evaluate(() => {
    const canvas = document.querySelector(".cascade-overlay")
    const { data } = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height)
    let painted = 0
    let partial = 0
    for (let i = 3; i < data.length; i += 4) {
      if (data[i] > 0) painted++
      if (data[i] > 8 && data[i] < 247) partial++
    }
    return { painted, partial }
  })

/** The overlay's pixels as an opaque string, for "is this the same picture" questions. */
const picture = (page) =>
  page.evaluate(() => document.querySelector(".cascade-overlay").toDataURL())

test.describe("the cascade's surface", () => {
  test("is the CSS box times the capped ratio, and the sprites agree", async ({ page }) => {
    await open(page, "&cascade=pose")
    const { store, css, dpr } = await surface(page)
    expect(dpr).toBe(1.5)
    expect(store.width).toBe(Math.round(css.width * dpr))
    expect(store.height).toBe(Math.round(css.height * dpr))
    // The number the *sprites* were built at is the same one: two that disagree draw
    // perfectly good cards, softer by the ratio between them, with nothing saying so.
    await expect(scene(page)).toHaveAttribute("data-ratio", "1.5")
    await expect(page.locator(".cascade-status")).toContainText("@1.5×")
  })

  test("keeps the whole trail, because nothing is ever cleared", async ({ page }) => {
    await open(page, "&cascade=pose")
    const { painted } = await ink(page)
    const flying = Number((await page.locator(".cascade-status").innerText()).match(/(\d+) in flight/)[1])
    // A card is 90 CSS px wide at 1.5×, so 135×189 device pixels. What is on the
    // overlay is many times what the cards in flight could account for — which is the
    // effect: the trail is the drawing, and the cards are only its leading edge.
    expect(painted).toBeGreaterThan(flying * 135 * 189 * 3)
  })
})

test.describe("a seeded cascade", () => {
  test("replays to the pixel", async ({ page }) => {
    // Frozen at a fixed simulated time, so this compares the cascades and not the two
    // loads' frame timing.
    await open(page, "&cascade=pose&seed=7")
    const first = await picture(page)
    await open(page, "&cascade=pose&seed=7")
    expect(await picture(page)).toBe(first)
  })

  test("is drawn again at the new size on a resize, having nothing to lose", async ({ page }) => {
    // The live run *ends* on a resize (below) because the wipe costs it a trail it
    // cannot recompute. A pose is a pure function of the box and the seed, so the same
    // wipe costs it nothing.
    await open(page, "&cascade=pose&seed=7")
    await page.setViewportSize({ width: 900, height: 760 })
    await expect(scene(page)).toHaveAttribute("data-cascade", "posed")
    await expect.poll(async () => (await ink(page)).painted).toBeGreaterThan(0)
  })

  test("and a different seed doesn't", async ({ page }) => {
    await open(page, "&cascade=pose&seed=7")
    const first = await picture(page)
    await open(page, "&cascade=pose&seed=8")
    expect(await picture(page)).not.toBe(first)
  })
})

test.describe("the device-pixel snap", () => {
  test("costs a card its resampled edges at a fractional ratio", async ({ page }) => {
    await open(page, "&cascade=pose&seed=4")
    const snapped = await ink(page)

    // The same cascade with the snap off — the only difference is where the blits
    // land, so any change in the edges is the resampling and nothing else.
    await page.locator(".cascade-toggle", { hasText: "whole pixels" }).click()
    await expect(scene(page)).toHaveAttribute("data-snap", "off")
    const loose = await ink(page)

    // Same picture, near enough: the cards are in the same places to within a device
    // pixel, so what changed is not how much was drawn (0.1% of it, measured).
    expect(Math.abs(loose.painted - snapped.painted)).toBeLessThan(snapped.painted * 0.01)
    // …and the edges in it are now half-lit across two device pixels instead of one.
    // What that looks like is the card's two ends disagreeing, because a sub-pixel
    // scale acts about the centre.
    //
    // The margin is 1.4× against 1.7× measured, and it is a *trail*, which is what
    // keeps the two from being further apart: consecutive stamps overlap by all but a
    // few pixels, so most of the resampled edges are painted over by the next card and
    // only the edge of the swath is left to count.
    expect(loose.partial).toBeGreaterThan(snapped.partial * 1.4)
  })
})

test.describe("a live run", () => {
  test("launches all 52 and settles once the last one leaves", async ({ page }) => {
    await open(page, "&seed=3")
    await expect(scene(page)).toHaveAttribute("data-cascade", "running")
    // Wound up to the fastest launch the knob offers, so the run is a test's length
    // rather than a minute. The interval is the knob it is precisely so this is
    // possible without a second code path.
    await page.locator('input[data-knob="launchInterval"]').fill("20")
    await expect(scene(page)).toHaveAttribute("data-cascade", "settled", { timeout: 30000 })
    await expect(page.locator(".cascade-status")).toContainText("52/52 launched")
    await expect(page.locator(".cascade-status")).toContainText("0 in flight")
  })

  test("ends on a resize rather than rescaling itself mid-flight", async ({ page }) => {
    await open(page, "&seed=3")
    await expect(scene(page)).toHaveAttribute("data-cascade", "running")
    await expect.poll(async () => (await ink(page)).painted).toBeGreaterThan(0)

    await page.setViewportSize({ width: 900, height: 760 })
    await expect(scene(page)).toHaveAttribute("data-cascade", "ended")
    // The store followed the element's new CSS size, and following it cost every
    // pixel already drawn: there is no resize that keeps the trail.
    expect((await ink(page)).painted).toBe(0)
    const { store, css } = await surface(page)
    expect(store.width).toBe(Math.round(css.width * 1.5))
  })
})
