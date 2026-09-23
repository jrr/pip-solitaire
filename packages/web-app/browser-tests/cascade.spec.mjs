// The cascade's claims where they can be measured: a seeded pose repeating to the byte,
// cards landing on whole device pixels, and a resize ending a run.
//
// The instrument is `getImageData` on the overlay rather than a screenshot: a screenshot
// is the composite, and cannot tell what the canvas drew from what is behind it.

import { expect, test } from "@playwright/test"

// 1.5 deliberately: the ratio at which a whole CSS pixel is *not* a whole device pixel.
// At an integer ratio the snapped and unsnapped runs draw the same pixels and the
// comparison below is unfalsifiable.
test.use({ viewport: { width: 1100, height: 900 }, deviceScaleFactor: 1.5 })

/** Open the scene and wait for the sprite sheet, which decodes asynchronously. */
async function open(page, query = "") {
  await page.goto(`/?scene=cascade${query}`)
  await expect(page.locator(".cascade-scene[data-cascade]")).toBeVisible()
}

const scene = (page) => page.locator(".cascade-scene")

/**
 * Turn the fade off — the trail that keeps everything, which is what the fade is against.
 * A toggle rather than a knob because a persistence is a length, and "never" is not one.
 */
const noFade = async (page) => {
  const toggle = page.locator(".cascade-toggle", { hasText: "no fade" })
  await toggle.click()
  await expect(toggle).toHaveClass(/cascade-toggle--on/)
}

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
 * How many device pixels are painted at all, how many *partially*, and how many at full
 * strength.
 *
 * `partial` is the instrument for the snap: a blit on the grid is a copy with the
 * bitmap's own hard edges, and one off it smears every edge across two columns of
 * half-lit pixels. `full` is the instrument for the fade: everything but the stamp that
 * went down last has been dimmed at least once.
 */
const ink = (page) =>
  page.evaluate(() => {
    const canvas = document.querySelector(".cascade-overlay")
    const { data } = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height)
    let painted = 0
    let partial = 0
    let full = 0
    for (let i = 3; i < data.length; i += 4) {
      if (data[i] > 0) painted++
      if (data[i] > 8 && data[i] < 247) partial++
      if (data[i] >= 250) full++
    }
    return { painted, partial, full }
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
    // The sprites were built at the same number: two that disagree draw perfectly good
    // cards, softer by the ratio between them, with nothing saying so.
    await expect(scene(page)).toHaveAttribute("data-ratio", "1.5")
    await expect(page.locator(".cascade-status")).toContainText("@1.5×")
  })

  test("keeps the whole trail, dimmed rather than cleared", async ({ page }) => {
    await open(page, "&cascade=pose")
    const { painted } = await ink(page)
    const flying = Number((await page.locator(".cascade-status").innerText()).match(/(\d+) in flight/)[1])
    // A card is 135×189 device pixels here, and the overlay holds many times what the
    // cards in flight account for: the trail is the drawing.
    expect(painted).toBeGreaterThan(flying * 135 * 189 * 3)
  })
})

test.describe("a seeded cascade", () => {
  test("replays to the pixel", async ({ page }) => {
    // Frozen, so this compares the cascades and not the two loads' frame timing.
    await open(page, "&cascade=pose&seed=7")
    const first = await picture(page)
    await open(page, "&cascade=pose&seed=7")
    expect(await picture(page)).toBe(first)
  })

  test("is drawn again at the new size on a resize, having nothing to lose", async ({ page }) => {
    // A live run ends on a resize (below) because the wipe costs it a trail it cannot
    // recompute; a pose is a pure function of the box and the seed.
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

test.describe("the fade behind the cards", () => {
  test("leaves the newest stamp the brightest thing on the surface", async ({ page }) => {
    await open(page, "&cascade=pose&seed=7")
    const faded = await ink(page)
    // What is still at full strength is the stamp that went down last and no more: a
    // twentieth of the drawing would be a fade that isn't reaching most of it.
    expect(faded.full).toBeLessThan(faded.painted * 0.05)

    // The same pose with the fade off, which is the trail this animation started with.
    // Nothing else about the run changes, so what the two differ in is brightness.
    await noFade(page)
    const flat = await ink(page)
    expect(flat.full).toBeGreaterThan(flat.painted * 0.95)

    // Dimmed, not erased. A fade multiplies alpha and eight-bit alpha rounds, so a stamp
    // settles at a residue rather than at nothing — the pixels a cascade has touched stay
    // touched, and the trail is still the drawing. `Canvas.dim` has the arithmetic.
    expect(faded.painted).toBeGreaterThan(flat.painted * 0.99)
  })
})

test.describe("the device-pixel snap", () => {
  test("costs a card its resampled edges at a fractional ratio", async ({ page }) => {
    await open(page, "&cascade=pose&seed=4")
    // With the fade on, every pixel behind the cards is partially lit and `partial` counts
    // the trail rather than its edges — which is the instrument this test is holding. So
    // the fade comes off first, for both halves of the comparison.
    await noFade(page)
    const snapped = await ink(page)

    // The same cascade with the snap off: the only difference is where the blits land.
    await page.locator(".cascade-toggle", { hasText: "whole pixels" }).click()
    await expect(scene(page)).toHaveAttribute("data-snap", "off")
    const loose = await ink(page)

    // Same picture to within a device pixel, so what changed is not how much was drawn.
    expect(Math.abs(loose.painted - snapped.painted)).toBeLessThan(snapped.painted * 0.01)
    // 1.4× against 1.7× measured. They are not further apart because it is a *trail*:
    // most resampled edges are painted over by the next stamp, leaving the swath's.
    expect(loose.partial).toBeGreaterThan(snapped.partial * 1.4)
  })
})

test.describe("a live run", () => {
  test("launches all 52 and settles once the last one leaves", async ({ page }) => {
    await open(page, "&seed=3")
    await expect(scene(page)).toHaveAttribute("data-cascade", "running")
    // The fastest launch the knob offers, so the run is a test's length rather than a
    // minute — no second code path needed.
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
    // The store followed the new CSS size, and following it cost every pixel drawn.
    expect((await ink(page)).painted).toBe(0)
    const { store, css } = await surface(page)
    expect(store.width).toBe(Math.round(css.width * 1.5))
  })
})
