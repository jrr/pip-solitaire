// The link-preview metadata, as a served page carries it.
//
// What Slack, iMessage and the rest show for a pasted link comes from the `<meta>`
// tags in index.html, read before a line of the app runs. That puts it a long way from
// any code: nothing imports it, no component renders it, and it went stale unnoticed
// the moment the app had a second game to be wrong about.
//
// The rule it has to keep is that **the copy names no game**. One index.html answers
// every URL — a static host cannot vary a response by query string — so the card built
// for a Simple Simon deal link is this one, and a game named in it is a claim about all
// of them. `index.html`'s own comment has the whole of the reasoning.
//
// Checked against `Game.all` rather than against the word that happens to be wrong
// today, so a game released later is covered without this file being touched.
//
// Browser-only because it is the *built* page under test: the title goes through
// Vite's build-time substitution, and reading the tags back means serving the site.

import { expect, test } from "@playwright/test"
import * as Game from "core/src/Game.res.mjs"

const content = (page, selector) => page.locator(selector).getAttribute("content")

// The four strings an unfurler renders as words. `og:image:alt` is deliberately not
// among them: it describes the picture, and the picture really is a FreeCell board.
const COPY = [
  'meta[property="og:title"]',
  'meta[property="og:description"]',
  'meta[name="twitter:title"]',
  'meta[name="twitter:description"]',
]

test("the link-preview copy names no game, so it fits whichever one is shared", async ({
  page,
}) => {
  await page.goto("/?animate=off")

  for (const selector of COPY) {
    const text = await content(page, selector)
    expect(text, `${selector} should exist`).toBeTruthy()
    for (const game of Game.all) {
      expect(text, `${selector} names ${game.name}`).not.toContain(game.name)
    }
  }
})

// The app still says what it is — a neutral title is the point, an empty one is a bug.
test("…but still describes the app", async ({ page }) => {
  await page.goto("/?animate=off")
  expect(await content(page, 'meta[property="og:title"]')).toContain("Pip")
  expect(await content(page, 'meta[property="og:description"]')).toContain("solitaire")
  expect(await content(page, 'meta[property="og:site_name"]')).toBe("Pip")
})

// The image's own description is the exception, and stays accurate about the picture
// rather than following the copy above.
test("the image alt describes the board in the picture", async ({ page }) => {
  await page.goto("/?animate=off")
  expect(await content(page, 'meta[property="og:image:alt"]')).toContain(Game.freecell.name)
})
