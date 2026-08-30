// The one thing the layer scheme can't survive losing: a sheet that forgets its
// `@layer` wrapper wins the cascade outright and silently. The argument, and what
// the four names are, is docs/css-layers.md § The three rules.
//
// Nothing else here would catch it — it isn't a syntax error and the compiler never
// sees CSS — so this reads the cascade the browser actually built and checks the
// shape of it.
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

  // The statement in src/styles/index.css is what fixes the order — see
  // docs/css-layers.md § Why the declaration comes first.
  const statements = rules.filter((r) => r.type === "CSSLayerStatementRule")
  expect(statements.map((r) => r.names)).toEqual([LAYERS])
  expect(rules.indexOf(statements[0])).toBe(0)

  // …and every block names one of the four.
  const blocks = rules.filter((r) => r.type === "CSSLayerBlockRule")
  expect([...new Set(blocks.map((r) => r.name))].sort()).toEqual([...LAYERS].sort())
})
