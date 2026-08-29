// The two mechanics the victory overlay rests on (issue #226), measured where
// they exist: in a real engine, with a real pointer, reading the overlay's own
// buffer back.
//
// Nothing here is about *motion* — where a card goes is #227's question. What is
// being pinned is the surface:
//
//   1  a transparent canvas over live DOM: the cards underneath show through,
//      and the canvas doesn't take the hit-testing away from them
//   2  the hand-off: a card that was a DOM node is a sprite on the canvas, in the
//      same place, and is then the card the pointer carries
//
// …plus the two facts about a backing store that the integration has to design
// around: it is `css × ratio` for one capped ratio shared with the sprite cache,
// and assigning `canvas.width` wipes everything drawn.
//
// The instrument throughout is `getImageData` on the overlay itself rather than a
// screenshot: what a screenshot shows is the *composite* of the canvas over the
// cards, which is exactly the picture that can't tell "the sprite is drawn" from
// "the card is still in the DOM". Reading the overlay's own pixels can.

import { expect, test } from "@playwright/test"

// A retina-ish device ratio, because the cap only means anything above it: at
// `deviceScaleFactor: 1` every cap in the toggle collapses to 1 and the store
// arithmetic is unfalsifiable. (The 1× case — a cap is a ceiling, not a setting —
// is pinned in the jsdom test, which reports a ratio of 1.)
test.use({ viewport: { width: 900, height: 800 }, deviceScaleFactor: 3 })

async function open(page) {
  await page.goto("/?scene=trail")
  // The sprites are built asynchronously (an <img> decode of the sheet); this
  // attribute is the only signal that they're in.
  await expect(page.locator('.trail-scene[data-trail="ready"]')).toBeVisible()
}

/** The overlay's backing store and the box it covers, as the page sees them. */
const overlay = (page) =>
  page.evaluate(() => {
    const canvas = document.querySelector(".trail-overlay")
    const box = canvas.getBoundingClientRect()
    return {
      store: { width: canvas.width, height: canvas.height },
      css: { width: box.width, height: box.height },
      left: box.left,
      top: box.top,
      dpr: window.devicePixelRatio,
    }
  })

/**
 * The average `red - blue` of an 11x11 CSS-pixel patch of the overlay, at
 * overlay-local coordinates — negative for the black suits, positive for the red
 * ones, ~0 for blank canvas or the card's own white face. Which card is being
 * drawn is otherwise unanswerable from the pixels: every sprite is the same size
 * in the same place, and only the ink differs.
 *
 * `alpha` comes back from the same read, because "did anything get drawn here"
 * and "what colour is it" are the two questions every check below asks.
 */
const sample = (page, x, y) =>
  page.evaluate(
    ([x, y]) => {
      const canvas = document.querySelector(".trail-overlay")
      const box = canvas.getBoundingClientRect()
      // getImageData works in backing-store pixels and ignores the context
      // transform, so the CSS coordinates have to be scaled by hand.
      const ratio = canvas.width / box.width
      const half = 5
      const sx = Math.round((x - half) * ratio)
      const sy = Math.round((y - half) * ratio)
      const size = Math.max(1, Math.round(half * 2 * ratio))
      const { data } = canvas.getContext("2d").getImageData(sx, sy, size, size)
      let alpha = 0
      let tint = 0
      for (let i = 0; i < data.length; i += 4) {
        alpha = Math.max(alpha, data[i + 3])
        tint += data[i] - data[i + 2]
      }
      return { alpha, tint: tint / (data.length / 4) }
    },
    [x, y],
  )

/** Drag the pointer across the stage, leaving a trail; coordinates are viewport. */
async function sweep(page, from, to) {
  await page.mouse.move(from.x, from.y)
  await page.mouse.move(to.x, to.y, { steps: 20 })
}

const stage = (page) => page.locator(".trail-stage")
const cards = (page) => page.locator(".trail-stage .stacking-card")

test.describe("trail scene — the backing store", () => {
  test("is the CSS box times the capped ratio, and the sprites agree", async ({ page }) => {
    await open(page)

    for (const cap of [2, 3, 1]) {
      await page.locator(".trail-toggle", { hasText: `${cap}×` }).click()
      await expect(page.locator('.trail-scene[data-trail="ready"]')).toBeVisible()

      const { store, css, dpr } = await overlay(page)
      const ratio = Math.min(dpr, cap)
      expect(dpr).toBeGreaterThan(1) // the premise of the whole check
      expect(store.width).toBe(Math.round(css.width * ratio))
      expect(store.height).toBe(Math.round(css.height * ratio))

      // …and the number the *sprites* were built at is the same one. Two ratios
      // that disagree draw perfectly good cards — softer by the ratio between
      // them, with nothing anywhere saying so — which is why this is asserted
      // rather than left to the eye.
      await expect(page.locator(".trail-scene")).toHaveAttribute("data-ratio", String(ratio))
      await expect(page.locator(".trail-status")).toContainText(`store @${ratio}×`)
      await expect(page.locator(".trail-status")).toContainText(`sprites @${ratio}×`)
    }
  })

  test("capping at 2 gives nothing up that 3 shows", async ({ page }) => {
    // The cap's whole justification. At `deviceScaleFactor: 3` the two caps
    // really do build different bitmaps (2400 vs 3600 device pixels across the
    // sheet), and the check is that the *drawn card* is the same picture: same
    // box, same ink, at both.
    await open(page)
    const shots = {}
    for (const cap of [3, 2]) {
      await page.locator(".trail-toggle", { hasText: `${cap}×` }).click()
      await expect(page.locator('.trail-scene[data-trail="ready"]')).toBeVisible()
      const box = await stage(page).boundingBox()
      const at = { x: box.x + box.width / 2, y: box.y + 90 }
      await page.mouse.move(at.x, at.y)
      shots[cap] = await sample(page, at.x - box.x, at.y - box.y)
    }
    expect(shots[2].alpha).toBe(shots[3].alpha)
    // The ink at the card's middle, which is the big suit glyph: same colour to
    // within antialiasing, not "some card was drawn".
    expect(Math.abs(shots[2].tint - shots[3].tint)).toBeLessThan(4)
  })
})

test.describe("trail scene — the overlay over live DOM", () => {
  test("the cards show through, and keep their own hit-testing", async ({ page }) => {
    await open(page)
    await expect(cards(page)).toHaveCount(5)

    const card = await cards(page).last().boundingBox()
    const box = await stage(page).boundingBox()
    const centre = { x: card.x + card.width / 2, y: card.y + card.height / 2 }

    // Nothing has been drawn over the card, and nothing ever fills the canvas —
    // so the overlay is genuinely transparent there rather than painting a
    // background the card happens to match.
    const over = await sample(page, centre.x - box.x, centre.y - box.y)
    expect(over.alpha).toBe(0)

    // …and the card, not the canvas, is what a pointer at that spot would hit.
    // This is the half the trail below *cannot* prove: the canvas is a child of
    // the stage, so even a canvas that swallowed events would let the stage's
    // handler see them bubble.
    const hit = await page.evaluate(
      ([x, y]) => document.elementFromPoint(x, y).closest(".stacking-card, .trail-overlay")?.className,
      [centre.x, centre.y],
    )
    expect(hit).toBe("stacking-card")
  })

  test("the sprite trails, because nothing is ever cleared", async ({ page }) => {
    await open(page)
    const box = await stage(page).boundingBox()
    const y = box.y + 90
    const from = { x: box.x + 120, y }
    const to = { x: box.x + box.width - 120, y }
    await sweep(page, from, to)

    // Both ends of the sweep are still drawn — a canvas cleared per frame would
    // hold only the last stamp — and so is the middle.
    for (const x of [from.x, (from.x + to.x) / 2, to.x]) {
      const { alpha } = await sample(page, x - box.x, y - box.y)
      expect(alpha, `nothing drawn at x=${Math.round(x - box.x)}`).toBeGreaterThan(0)
    }
  })

  test("re-assigning canvas.width wipes it", async ({ page }) => {
    // Deliberate, and the reason the integration will *end* a cascade on resize
    // rather than try to rescale one mid-flight: there is no way to resize the
    // store and keep the drawing.
    await open(page)
    const box = await stage(page).boundingBox()
    const at = { x: box.x + box.width / 2, y: box.y + 90 }
    await sweep(page, { x: at.x - 100, y: at.y }, at)
    expect((await sample(page, at.x - box.x, at.y - box.y)).alpha).toBeGreaterThan(0)

    await page.locator(".trail-action", { hasText: "canvas.width" }).click()
    expect((await sample(page, at.x - box.x, at.y - box.y)).alpha).toBe(0)
  })
})

test.describe("trail scene — the hand-off", () => {
  test("the card leaves the DOM and lands on the canvas in the same place", async ({ page }) => {
    await open(page)
    const box = await stage(page).boundingBox()
    // The topmost card is the one handed off — nothing overlaps it, so its
    // sprite can be stamped without painting over a neighbour.
    const seat = await cards(page).last().boundingBox()

    await page.locator(".trail-action", { hasText: "Hand off" }).click()
    await expect(cards(page)).toHaveCount(4)

    const local = (x, y) => sample(page, x - box.x, y - box.y)
    // In register, to within a pixel or two: opaque inside the card's own box…
    expect((await local(seat.x + seat.width / 2, seat.y + seat.height / 2)).alpha).toBeGreaterThan(
      200,
    )
    expect((await local(seat.x + 8, seat.y + seat.height / 2)).alpha).toBeGreaterThan(200)
    // …and nothing outside it. A sprite drawn at the pointer's coordinate space
    // instead of the canvas's, or onto a store sized from the wrong box, misses
    // by more than this.
    expect((await local(seat.x - 12, seat.y + seat.height / 2)).alpha).toBe(0)
    expect((await local(seat.x + seat.width / 2, seat.y - 12)).alpha).toBe(0)
  })

  test("and is then the card the pointer carries", async ({ page }) => {
    await open(page)
    const box = await stage(page).boundingBox()
    // Somewhere the backdrop fan doesn't reach, so the sample is of the trail
    // and nothing else.
    const at = { x: box.x + box.width - 140, y: box.y + 90 }

    // Before: the pointer carries the ace of *spades*, so the ink at the card's
    // middle glyph is black — blue channel at least as strong as red.
    await page.mouse.move(at.x, at.y)
    const before = await sample(page, at.x - box.x, at.y - box.y)
    expect(before.alpha).toBeGreaterThan(0)
    expect(before.tint).toBeLessThanOrEqual(0)

    // The topmost backdrop card is the ace of *hearts*. After the hand-off the
    // pointer is carrying it, which the ink says and nothing else can: every
    // sprite is the same size in the same place.
    await page.locator(".trail-action", { hasText: "Hand off" }).click()
    await page.locator(".trail-action", { hasText: "canvas.width" }).click() // a clean surface
    await page.mouse.move(at.x + 1, at.y)
    await page.mouse.move(at.x, at.y)
    const after = await sample(page, at.x - box.x, at.y - box.y)
    expect(after.alpha).toBeGreaterThan(0)
    expect(after.tint).toBeGreaterThan(0)
  })

  test("stops offering the hand-off once the backdrop is empty", async ({ page }) => {
    await open(page)
    const handOff = page.locator(".trail-action", { hasText: "Hand off" })
    for (let i = 0; i < 5; i++) await handOff.click()
    await expect(cards(page)).toHaveCount(0)
    await expect(handOff).toBeDisabled()
  })
})
