// Does a rasterized card still look like a card? (issue #225)
//
// The victory animation blits pre-rasterized card sprites rather than animating
// 52 live SVG text subtrees, and the risk that makes rasterizing hard is
// specific: an SVG loaded through `<img>` renders in an isolated document with
// no access to the page's `@font-face` rules, and the card face is almost
// entirely text. Get it wrong and every card comes out in a fallback face with
// tofu where the pips should be — which is *not* subtle, but is also not
// something any unit test can see. It's a question about pixels.
//
// So this measures pixels. The `raster` scene lays each card out twice at card
// size — the live `CardArt.svg` beside the `CardRaster` bitmap of it — and this
// shoots both halves and diffs them, once per strategy.
//
// The decode happens back *inside the page*: Node has no PNG decoder, and the
// browser already has one plus a canvas to read pixels out of. So each shot goes
// back over the wire as a data URL, is drawn to an offscreen canvas, and the two
// pixel buffers are differenced there.
//
// Deliberately not `toHaveScreenshot`: a committed baseline would pin the card
// *design*, which is expected to change, and would need regenerating on every
// machine. What's being pinned here is that two renderings of the same design
// agree — which stays true as the design evolves.

import { expect, test } from "@playwright/test"

// The cards to compare, by index into `Deck.allCards` (core's `Cards.all`: suits
// grouped, ranks ascending — spades 0-12, hearts 13-25, diamonds 26-38,
// clubs 39-51). Chosen to cover both colours, both glyph widths ("A" vs the
// double-width "10"), and a court card.
const samples = [
  { index: 0, name: "ace of spades" },
  { index: 9, name: "ten of spades" },
  { index: 13, name: "ace of hearts" },
  { index: 38, name: "king of diamonds" },
  { index: 51, name: "king of clubs" },
]

// What counts as indistinguishable. Two independent rasterizations of the same
// vector art never agree bit-for-bit — they disagree along glyph and corner
// edges where antialiasing lands differently — so the bar is on how *much*
// disagreement, not whether there is any:
//   meanDiff  average per-channel distance over the card. A wrong font moves
//             this by tens; edge antialiasing moves it by ones.
//   hardDiff  share of pixels differing by more than a shade (`HARD_DIFF_LEVEL`)
//             in any channel. Antialiasing puts those on glyph outlines only, so
//             they stay a thin minority; a substituted glyph fills areas.
//
// The budgets differ per strategy, and **the gap is the finding** rather than an
// accident of tuning — this is where issue #225's "pick by looking" is written
// down. Measured on the sample cards below:
//
//   svg     mean 2.4-4.2 · hard 2.5-4.4%
//   canvas  mean 3.1-7.8 · hard 3.0-7.0%
//
// The SVG-with-embedded-face path is closer to the live card on every card, and
// its worst case is better than the canvas path's *best* case on the hardest
// one. That's on top of the structural argument (it renders `CardArt.body`
// itself, so it can't drift), which is why it's the default. The canvas budget
// is kept honest rather than waived: it's a real second implementation and it
// should stay roughly this good, so a regression in it still fails.
const BUDGETS = {
  svg: { meanDiff: 6, hardDiff: 0.06 },
  canvas: { meanDiff: 9, hardDiff: 0.09 },
}
const HARD_DIFF_LEVEL = 60

/** Shoot a locator and hand the PNG back as a data URL the page can decode. */
async function shoot(locator) {
  const png = await locator.screenshot()
  return `data:image/png;base64,${png.toString("base64")}`
}

/**
 * Diff two same-sized PNGs, in the page (see the header: the browser owns the
 * only PNG decoder available here). Returns the mean per-channel difference and
 * the share of pixels that differ by more than `level` in any channel — at dead
 * alignment, and at whichever of the nine ±1px offsets scores best.
 *
 * The offset scan is diagnostic, not a tolerance: nothing asserts on it. It's
 * there because "the sprite is a pixel off" and "the sprite is drawn wrong" both
 * blow the same budget, and they're completely different bugs. If a failure
 * reports its best score at ±1 it's a placement problem; if the best is still at
 * 0,0 the drawing itself has changed. The 1px border is skipped so the shifted
 * comparisons stay in bounds.
 */
async function comparePngs(page, a, b, level) {
  return await page.evaluate(
    async ([aUrl, bUrl, level]) => {
      const pixels = async (url) => {
        const img = new Image()
        img.src = url
        await img.decode()
        const canvas = document.createElement("canvas")
        canvas.width = img.naturalWidth
        canvas.height = img.naturalHeight
        const ctx = canvas.getContext("2d")
        ctx.drawImage(img, 0, 0)
        return {
          data: ctx.getImageData(0, 0, canvas.width, canvas.height).data,
          width: canvas.width,
          height: canvas.height,
        }
      }
      const left = await pixels(aUrl)
      const right = await pixels(bUrl)
      if (left.width !== right.width || left.height !== right.height) {
        return {
          sizeMismatch: `${left.width}x${left.height} vs ${right.width}x${right.height}`,
        }
      }
      const at = (dx, dy) => {
        let total = 0
        let hard = 0
        let count = 0
        for (let y = 1; y < left.height - 1; y++) {
          for (let x = 1; x < left.width - 1; x++) {
            const o = (y * left.width + x) * 4
            const p = ((y + dy) * left.width + (x + dx)) * 4
            const dr = Math.abs(left.data[o] - right.data[p])
            const dg = Math.abs(left.data[o + 1] - right.data[p + 1])
            const db = Math.abs(left.data[o + 2] - right.data[p + 2])
            total += dr + dg + db
            if (dr > level || dg > level || db > level) hard++
            count++
          }
        }
        return { dx, dy, meanChannelDiff: total / (count * 3), hardDiffFraction: hard / count }
      }
      const offsets = []
      for (const dy of [-1, 0, 1]) for (const dx of [-1, 0, 1]) offsets.push(at(dx, dy))
      const best = offsets.reduce((a, b) => (b.meanChannelDiff < a.meanChannelDiff ? b : a))
      return {
        width: left.width,
        height: left.height,
        ...at(0, 0),
        best,
      }
    },
    [a, b, level],
  )
}

// A roomy desktop viewport at 1× so a pair is exactly two card widths of real
// pixels and the shots line up without any device-pixel rounding to reason about.
test.use({ viewport: { width: 1200, height: 900 }, deviceScaleFactor: 1 })

for (const strategy of ["svg", "canvas"]) {
  test.describe(`raster scene — ${strategy} strategy`, () => {
    test.beforeEach(async ({ page }) => {
      await page.goto(`/?scene=raster&raster=${strategy}`)
      // The scene publishes this only once all 52 bitmaps are in — the decodes
      // are async, so there is nothing else to wait on.
      await expect(page.locator('.raster-scene[data-raster="ready"]')).toBeVisible()
    })

    test("every card has a sprite, sized to match the live card", async ({ page }) => {
      const pairs = page.locator(".raster-pair")
      await expect(pairs).toHaveCount(52)
      await expect(page.locator(".raster-pair canvas")).toHaveCount(52)

      const first = pairs.first()
      const live = await first.locator(".card-art").boundingBox()
      const sprite = await first.locator("canvas").boundingBox()
      expect(sprite.width).toBeCloseTo(live.width, 1)
      expect(sprite.height).toBeCloseTo(live.height, 1)
    })

    const budget = BUDGETS[strategy]

    for (const sample of samples) {
      test(`the ${sample.name} sprite matches the live card`, async ({ page }) => {
        const pair = page.locator(".raster-pair").nth(sample.index)
        const result = await comparePngs(
          page,
          await shoot(pair.locator(".card-art")),
          await shoot(pair.locator("canvas")),
          HARD_DIFF_LEVEL,
        )
        expect(result.sizeMismatch, `size mismatch: ${result.sizeMismatch}`).toBeUndefined()
        // Logged so a regression report says *how far off* rather than just
        // "failed", and so the two strategies can be compared by reading the run.
        console.log(
          `  ${strategy} · ${sample.name}: mean ${result.meanChannelDiff.toFixed(2)}/255, ` +
            `hard ${(result.hardDiffFraction * 100).toFixed(2)}% (${result.width}x${result.height}) ` +
            `best@${result.best.dx},${result.best.dy} mean ${result.best.meanChannelDiff.toFixed(2)}`,
        )
        expect(result.meanChannelDiff).toBeLessThan(budget.meanDiff)
        expect(result.hardDiffFraction).toBeLessThan(budget.hardDiff)
      })
    }
  })
}
