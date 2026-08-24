// The About footer's update-check control appears on the Settings and Debug screens
// and never on the main menu (#112).
//
// Why this can't be a unit test. The rule reads two things at once — whether
// `Refresh.detect` has reported a service-worker state yet, and which screen is
// showing — and it now lives in `Main` (#308), where the props record for the About
// footer is assembled. `Main` is the entry point: importing it mounts the app,
// registers a service worker and takes over `<body>`, so there is nothing for a
// Vitest file to call. The rule was previously inside `Menu`, reachable from
// `Menu_test`; moving it out is what left it with no coverage, and this is where it
// goes instead.
//
// What it pins is the *shape* of the rule rather than a label: the control is absent
// on the main menu in both directions (before ever visiting Settings, and again on
// the way back out), and present on both of the deeper screens. Whether the button
// reads "Refresh" or "Check for updates" is `Refresh.mode`'s business and depends on
// whether this build registered a worker — pinning it here would tie the test to the
// PWA plugin's behaviour under `vite preview`.
//
// The detection is kicked off by opening Settings, which is why the first assertion
// has to happen before that tap: a control that appeared on the main menu would mean
// the screen half of the rule had been dropped.
import { expect, test } from "@playwright/test"

test.use({ viewport: { width: 480, height: 900 } })

test("the update-check control is on the deeper screens, never the main menu", async ({ page }) => {
  await page.goto("/?scene=freecell&animate=off")
  await page.getByRole("button", { name: /Open menu/ }).click()

  const refresh = page.locator(".menu-refresh")
  await expect(refresh).toHaveCount(0)

  await page.getByRole("button", { name: "Settings", exact: true }).click()
  await expect(refresh).toHaveCount(1)

  // …and one level deeper, where the footer is the same footer.
  await page.getByRole("button", { name: "Debug" }).click()
  await expect(refresh).toHaveCount(1)

  // Back out to the main menu: gone again, now that a worker state *has* been
  // detected. That's the half of the rule a screen-blind implementation would miss.
  await page.getByRole("button", { name: /Back to settings/ }).click()
  await page.getByRole("button", { name: /Back to menu/ }).click()
  await expect(refresh).toHaveCount(0)
})
