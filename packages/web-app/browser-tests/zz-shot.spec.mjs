// TEMPORARY — delete.
import { test } from "@playwright/test"

const out = "/tmp/claude-0/-home-user-pip-solitaire/4c7c3b98-e417-53fe-b933-0f0a8ec9c158/scratchpad"

test.use({ viewport: { width: 1100, height: 900 }, deviceScaleFactor: 1 })

test("pose", async ({ page }) => {
  await page.goto("/?scene=cascade&cascade=pose&seed=24680")
  await page.waitForSelector('.cascade-scene[data-cascade="posed"]')
  await page.screenshot({ path: `${out}/metric-default.png` })
})

test("earth", async ({ page }) => {
  await page.goto("/?scene=cascade&cascade=pose&seed=24680")
  await page.waitForSelector('.cascade-scene[data-cascade="posed"]')
  await page.locator('input[data-knob="gravity"]').fill("9.8")
  await page.locator('input[data-knob="fastest"]').fill("2.5")
  await page.locator('input[data-knob="slowest"]').fill("1.2")
  await page.waitForTimeout(600)
  await page.screenshot({ path: `${out}/metric-earth.png` })
})
