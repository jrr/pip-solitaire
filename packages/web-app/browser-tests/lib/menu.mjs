// Shared readings of the main menu for the browser suite.
//
// Not a spec file — Playwright only collects `*.spec.mjs` from browser-tests/,
// so helpers live here beside them.

import { expect } from "@playwright/test"

/**
 * The deal number the menu names, which four suites want and none of them owns:
 * the seed of the board on the table. It is the "this game" heading that says it,
 * after the game's own name, so that both controls under the heading — Restart and
 * Share — are visibly about the same board. There is no element at all on a board with no seed, which
 * is why this is a locator to assert against rather than a string to read.
 *
 * Its text is the number behind a `#` — "#24680", the heading's own spelling (see
 * MenuSection.res) — so assert against that rather than the bare digits. A negative
 * assertion especially: `not.toHaveText("13579")` passes against "#13579" for the
 * wrong reason, and passes just as well against a seed that never changed.
 */
export const menuSeed = (page) => page.locator('[aria-label="this game"] .menu-section__value')

/**
 * The Settings screen, from the menu's main one. Waiting on a row rather than on the
 * title, so a walk that carries on to tap something is looking at a screen that has
 * finished arriving.
 */
export const openSettings = async (page) => {
  await page.getByRole("button", { name: "Settings", exact: true }).click()
  await expect(page.getByRole("switch", { name: /^Auto-collect/ })).toBeVisible()
}

/**
 * Flip **Beta features** the way a tester would, and come back to the games list: into
 * Settings, ten taps on the title for the hidden rows (`HiddenOptions`), the switch,
 * then Back to menu. No reload — the flip is meant to land on the very next render of
 * the menu it returns to, which is what the walk leaves the caller looking at.
 *
 * The reveal is itself a *toggle* and it is persisted, so the taps are conditional: ten
 * more on a screen already showing the rows would put them away again.
 *
 * One flag stands in front of every half-finished feature, which is why this walk is
 * here rather than copied into each suite that needs one of them on.
 */
export const setBetaFeatures = async (page, on) => {
  await openSettings(page)
  const beta = page.getByRole("switch", { name: /^Beta features/ })
  if (!(await beta.isVisible())) {
    for (let i = 0; i < 10; i++) {
      await page.locator(".menu-title").click()
    }
    await expect(beta).toBeVisible()
  }
  await beta.click()
  await expect(beta).toHaveAttribute("aria-checked", String(on))
  await page.getByRole("button", { name: "Back to menu" }).click()
}
