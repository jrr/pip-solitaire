// The About footer — the update check, the About button and the build string — belongs
// to the Settings screen and to no other.
//
// Why this can't be a unit test. The footer's appearance reads two things at once:
// whether `Refresh.detect` has reported a service-worker state yet, which is `Main`'s
// (and `Main` is the entry point — importing it mounts the app, registers a worker and
// takes over `<body>`, so there is nothing for a Vitest file to call), and which screen
// is showing, which is the pane's. A walk is the only thing that sees both.
//
// What it pins is the *shape* of the rule rather than a label: the footer is absent on
// the main menu in both directions (before ever visiting Settings, and again on the way
// back out), absent a level deeper on Debug, and present on Settings once the detection
// has landed. Whether the button reads "Refresh" or "Check for updates" is
// `Refresh.mode`'s business and depends on whether this build registered a worker —
// pinning it here would tie the test to the PWA plugin's behaviour under `vite preview`.
//
// The detection is kicked off by opening Settings, which is why the first assertion has
// to happen before that tap: a control that appeared on the main menu would mean the
// screen half of the rule had been dropped.
import { expect, test } from "@playwright/test"

test.use({ viewport: { width: 480, height: 900 } })

test("the About footer is the Settings screen's, and no other screen's", async ({ page }) => {
  await page.goto("/?game=freecell&animate=off")
  await page.getByRole("button", { name: /Open menu/ }).click()

  const footer = page.locator(".menu-footer")
  const refresh = page.locator(".menu-refresh")
  const version = page.locator("#version-badge")
  await expect(footer).toHaveCount(0)
  await expect(version).toHaveCount(0)

  await page.getByRole("button", { name: "Settings", exact: true }).click()
  await expect(footer).toHaveCount(1)
  await expect(refresh).toHaveCount(1)
  await expect(version).toHaveCount(1)

  // One level deeper is a screen about the build's tools, not about the build: the
  // footer doesn't follow it down.
  await page.getByRole("button", { name: "Debug" }).click()
  await expect(footer).toHaveCount(0)
  await page.getByRole("button", { name: /Back to settings/ }).click()
  await expect(footer).toHaveCount(1)

  // Back out to the main menu: gone again, now that a worker state *has* been
  // detected. That's the half of the rule a screen-blind implementation would miss.
  await page.getByRole("button", { name: /Back to menu/ }).click()
  await expect(footer).toHaveCount(0)
})

test("the About button opens its screen, and comes back to Settings", async ({ page }) => {
  // The pair at the foot of Settings: the update check acts in place, and About goes
  // somewhere — one level down, so its way back is to Settings rather than out to the
  // menu. The screen it opens is deliberately empty for now; what is pinned here is the
  // door, which is the part the copy will arrive behind.
  await page.goto("/?game=freecell&animate=off")
  await page.getByRole("button", { name: /Open menu/ }).click()
  await page.getByRole("button", { name: "Settings", exact: true }).click()

  await page.getByRole("button", { name: "About", exact: true }).click()
  await expect(page.locator(".menu-title")).toHaveText("About")
  // Nothing followed it down: the footer it was pressed in is a Settings fixture.
  await expect(page.locator(".menu-footer")).toHaveCount(0)

  await page.getByRole("button", { name: /Back to settings/ }).click()
  await expect(page.locator(".menu-title")).toHaveText("Settings")
  await expect(page.locator(".menu-footer")).toHaveCount(1)
})
