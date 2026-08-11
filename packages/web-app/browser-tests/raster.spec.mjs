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
// So this measures pixels. The `raster` scene draws all 52 cards one of three
// ways — live `CardArt.svg`, or either `CardRaster` strategy — in the same grid
// cells, so this shoots a card under `?raster=live` and again under the strategy
// and diffs the two shots. That is the same flip the scene is built around: the
// cell geometry is identical across renderings, so the comparison is of one card
// against itself rather than of two neighbours.
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
//   svg     mean 1.2-2.4 · hard 1.3-3.8%
//   canvas  mean 1.6-2.9 · hard 1.9-4.4%
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

// A roomy desktop viewport at 1× so a cell is exactly one card width of real
// pixels and the shots line up without any device-pixel rounding to reason about.
test.use({ viewport: { width: 1200, height: 900 }, deviceScaleFactor: 1 })

/**
 * Open the scene on one rendering and wait for it to be showing. `data-raster`
 * lands once the 52 bitmaps are in (the decodes are async, so there's nothing
 * else to wait on) — and immediately for `live`, which builds nothing.
 */
async function open(page, rendering) {
  await page.goto(`/?scene=raster&raster=${rendering}`)
  await expect(page.locator('.raster-scene[data-raster="ready"]')).toBeVisible()
  await expect(page.locator(".raster-scene")).toHaveAttribute("data-rendering", rendering)
}

const cell = (page, index) => page.locator(".raster-cell").nth(index)

for (const strategy of ["svg", "canvas"]) {
  test.describe(`raster scene — ${strategy} strategy`, () => {
    test("every card is a sprite, in the same box the live card occupied", async ({ page }) => {
      // The flip only means anything if nothing but the pixels moves, so this is
      // the load-bearing assertion behind every diff below: the cell a card
      // lands in is the same box under both renderings.
      await open(page, "live")
      await expect(page.locator(".raster-cell")).toHaveCount(52)
      await expect(page.locator(".raster-cell .card-art")).toHaveCount(52)
      const live = await cell(page, 0).boundingBox()

      await open(page, strategy)
      await expect(page.locator(".raster-cell")).toHaveCount(52)
      await expect(page.locator(".raster-cell canvas")).toHaveCount(52)
      const sprite = await cell(page, 0).boundingBox()

      expect(sprite.width).toBeCloseTo(live.width, 1)
      expect(sprite.height).toBeCloseTo(live.height, 1)
      expect(sprite.x).toBeCloseTo(live.x, 1)
      expect(sprite.y).toBeCloseTo(live.y, 1)
    })

    const budget = BUDGETS[strategy]

    for (const sample of samples) {
      test(`the ${sample.name} sprite matches the live card`, async ({ page }) => {
        await open(page, "live")
        const liveShot = await shoot(cell(page, sample.index))

        await open(page, strategy)
        const spriteShot = await shoot(cell(page, sample.index))

        const result = await comparePngs(page, liveShot, spriteShot, HARD_DIFF_LEVEL)
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

// The Svg strategy rasterizes the whole deck as one grid and cuts it up, and
// inlines the faces it draws with. Both of those fail *quietly*: a sheet cut at
// the wrong offset yields a neighbouring card, and an embedded face that didn't
// load leaves the card art's `sans-serif` fallback to draw the rank, which still
// produces a perfectly plausible-looking card. Neither throws. The five sample
// cards above only cover ranks A, 10 and K, so this walks all thirteen — one
// page load per rendering, then a per-rank diff against the live card.
const RANK_ONE_OF_EACH = [
  { index: 0, rank: "A" }, { index: 1, rank: "2" }, { index: 2, rank: "3" },
  { index: 3, rank: "4" }, { index: 4, rank: "5" }, { index: 5, rank: "6" },
  { index: 6, rank: "7" }, { index: 7, rank: "8" }, { index: 8, rank: "9" },
  { index: 9, rank: "10" }, { index: 10, rank: "J" }, { index: 11, rank: "Q" },
  { index: 12, rank: "K" },
]

test.describe("raster scene — the embedded rank subset", () => {
  test("every rank draws in the real face, not a fallback", async ({ page }) => {
    await open(page, "live")
    const live = []
    for (const { index } of RANK_ONE_OF_EACH) live.push(await shoot(cell(page, index)))

    await open(page, "svg")
    const worst = []
    for (const [i, { rank }] of RANK_ONE_OF_EACH.entries()) {
      const result = await comparePngs(page, live[i], await shoot(cell(page, i)), HARD_DIFF_LEVEL)
      expect(result.sizeMismatch, `size mismatch: ${result.sizeMismatch}`).toBeUndefined()
      worst.push(`${rank} ${result.meanChannelDiff.toFixed(2)}`)
      // A missing glyph is not a subtle failure — a substituted face fills area
      // rather than shifting edges, so it lands far past the antialiasing budget
      // the sample cards are held to.
      expect(result.meanChannelDiff, `rank ${rank} does not match the live card`)
        .toBeLessThan(BUDGETS.svg.meanDiff)
    }
    console.log(`  svg · per-rank mean: ${worst.join(", ")}`)
  })
})

// Moving the toggle mid-build leaves two builds in flight, and they don't take
// the same time (~270ms of decodes for svg, near-nothing for canvas once the
// document's faces are loaded), so they finish in the wrong order: the one the
// user asked for lands first and the one they abandoned lands on top of it. The
// scene has to drop the abandoned one — otherwise the grid ends up showing the
// old strategy's sprites under the new strategy's toggle, with the status line
// (which reads the cache) and the toolbar (which reads the model) disagreeing in
// the same render.
//
// Reproducing that ordering means clicking *inside* the first build, and
// unthrottled that window is a couple hundred milliseconds — narrow enough that
// a run can miss it and pass without having tested anything. So the svg build is
// held open: the woff2 bytes it fetches to inline are stalled on the wire.
//
// Only *its* request is held, by resource type — the `<img>`-side fetch, not the
// page's own `@font-face` loads (`font`), which the canvas strategy waits on and
// which must stay fast. Holding both would push them out together and close the
// gap that is the whole point.
const FONT_HOLD_MS = 1500

test.describe("raster scene — switching strategy mid-build", () => {
  test("the abandoned build doesn't land on top of the newer one", async ({ page }) => {
    await page.route("**/*.woff2", async (route) => {
      if (route.request().resourceType() === "font") return await route.continue()
      await new Promise((resolve) => setTimeout(resolve, FONT_HOLD_MS))
      await route.continue()
    })

    // `commit` rather than the default `load`: the point is to be here early,
    // and the scene mounts (and starts building) well before the page settles.
    await page.goto("/?scene=raster&raster=svg", { waitUntil: "commit" })

    // The svg build can't have finished — its fonts are still on the wire — so
    // this is a fact about the state the click is about to land in, not a race
    // with it. Without it a passing run could mean "no overlap ever happened".
    await expect(page.locator(".raster-scene__status")).toContainText("rasterizing")

    await page.locator(".raster-scene__toolbar").getByText("Canvas 2D").click()
    await expect(page.locator('.raster-scene[data-raster="ready"]')).toBeVisible()

    // Not an arbitrary settle: the assertion is that something *doesn't* happen.
    // The abandoned svg build lands after this point, and waiting past it is the
    // only way to catch it dispatching.
    await page.waitForTimeout(FONT_HOLD_MS + 1500)

    await expect(page.locator(".raster-scene__status")).toContainText("via Canvas 2D")
    // `toContainText`, not `toHaveText`: the button also carries its key number.
    await expect(page.locator(".raster-toggle--on")).toContainText("Canvas 2D")
  })
})

// The keys are the reason the scene is one-at-a-time: a difference of a few
// pixels is something you catch by flipping in place, and reaching for a button
// is slower than the afterimage lasts. Key *n* picks the *n*th rendering, which
// is also the number printed on the *n*th button — one order, three consumers
// (`renderings`, the buttons, the keys), so this walks all three.
test.describe("raster scene — the 1/2/3 keys", () => {
  test("each key picks the rendering its button is numbered with", async ({ page }) => {
    await open(page, "live")

    for (const [key, rendering, label] of [
      ["2", "svg", "SVG + embedded font"],
      ["3", "canvas", "Canvas 2D"],
      ["1", "live", "Live SVG"],
    ]) {
      await page.keyboard.press(key)
      await expect(page.locator('.raster-scene[data-raster="ready"]')).toBeVisible()
      await expect(page.locator(".raster-scene")).toHaveAttribute("data-rendering", rendering)
      await expect(page.locator(".raster-toggle--on")).toContainText(label)
    }
  })

  test("a modified press is left to the browser", async ({ page }) => {
    // ⌘1/^1 switch browser tabs; a debug scene has no business eating that.
    await open(page, "live")
    await page.keyboard.press("Meta+3")
    await page.keyboard.press("Control+3")
    await expect(page.locator(".raster-scene")).toHaveAttribute("data-rendering", "live")
  })
})
