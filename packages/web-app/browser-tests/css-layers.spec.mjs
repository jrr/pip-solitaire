// The one thing the layer scheme can't survive losing (#306 follow-up).
//
// Since components import their own stylesheets, no file has a fixed position in
// the bundle any more and the cascade is ordered by `@layer` instead — the four
// names declared in src/styles/index.css. That works only while *every* rule is
// inside one of them: an unlayered rule outranks every layered one no matter how
// specific, so a sheet that forgets its wrapper doesn't misorder slightly, it
// wins outright, and it does so silently — the page still renders, just wrong,
// and only wherever that sheet happens to collide with another.
//
// Nothing else here would catch it: it's not a syntax error, the compiler never
// sees CSS, and a regression would show up as some unrelated component's rule
// quietly losing. So this reads the cascade the browser actually built and
// checks the shape of it.
import { test, expect } from "@playwright/test"

const LAYERS = ["foundations", "components", "scenes", "overrides"]

/** The top-level rules of every stylesheet the built page loaded, flattened. */
const topLevelRules = (page) =>
  page.evaluate(() =>
    [...document.styleSheets].flatMap((sheet) => {
      // Same-origin only; a cross-origin sheet throws on `cssRules` and we ship none.
      let rules
      try {
        rules = [...sheet.cssRules]
      } catch {
        return []
      }
      return rules.map((rule) => ({
        type: rule.constructor.name,
        name: rule.name ?? null,
        // A statement rule (`@layer a, b;`) carries the order; a block rule carries one name.
        names: rule.nameList ? [...rule.nameList] : null,
        text: rule.cssText.slice(0, 80),
      }))
    }),
  )

test("the app's whole cascade is inside the declared layers", async ({ page }) => {
  await page.goto("/?game=freecell&animate=off")
  await expect(page.locator(".stacking-card").first()).toBeVisible()
  const rules = await topLevelRules(page)

  // Sanity: we're looking at the real thing, not an empty list.
  expect(rules.length).toBeGreaterThan(5)

  const stray = rules.filter(
    (r) => r.type !== "CSSLayerBlockRule" && r.type !== "CSSLayerStatementRule",
  )
  expect(
    stray.map((r) => `${r.type}: ${r.text}`),
    "every top-level rule belongs to a layer — see docs/css-layers.md",
  ).toEqual([])
})

test("the layer order is declared once, before anything uses it", async ({ page }) => {
  await page.goto("/?game=freecell&animate=off")
  await expect(page.locator(".stacking-card").first()).toBeVisible()
  const rules = await topLevelRules(page)

  // The statement in src/styles/index.css is what fixes the order; a layer first
  // *mentioned* by a block would be appended in arrival order instead, which is
  // exactly the module-graph order the statement exists to stop mattering.
  const statements = rules.filter((r) => r.type === "CSSLayerStatementRule")
  expect(statements.map((r) => r.names)).toEqual([LAYERS])
  expect(rules.indexOf(statements[0])).toBe(0)

  // …and every block names one of the four.
  const blocks = rules.filter((r) => r.type === "CSSLayerBlockRule")
  expect([...new Set(blocks.map((r) => r.name))].sort()).toEqual([...LAYERS].sort())
})
