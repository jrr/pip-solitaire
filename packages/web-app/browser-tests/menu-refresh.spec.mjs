// The update check is the About screen's, and About is one tap from the main menu — so
// the check is two taps from a board, without passing through Settings.
//
// Why this can't be a unit test. Whether there is an update check to offer at all is
// `Main`'s: it turns on whether `Refresh.detect` has reported a service-worker state
// yet, and `Main` is the entry point, so importing it mounts the app, registers a worker
// and takes over `<body>`. Only a walk reaches the screen with the detection behind it.
//
// **What this pins is that the About button carries the detection with it.** The check
// is absent until a state has been reported, and the tap that opens About is the only
// thing that can report one for a player who never opens Settings — so a check present
// here is the whole of that wiring, and a check missing means About was promoted out of
// Settings without its `Refresh.detect` coming along (`Main`'s `onOpenAbout`).
//
// Whether the check reads "Refresh" or "Check for updates" is `Refresh.mode`'s business
// and depends on whether this build registered a worker — pinning it here would tie the
// test to the PWA plugin's behaviour under `vite preview`.
import { expect, test } from "@playwright/test"

test.use({ viewport: { width: 480, height: 900 } })

test("About is a tap from the main menu, and brings the update check with it", async ({ page }) => {
  await page.goto("/?game=freecell&animate=off")
  await page.getByRole("button", { name: /Open menu/ }).click()

  // Nothing of the build on the main menu itself: no check, and no ↻ Update band with
  // nothing waiting — the band is absent rather than reserved, so a box kept for it
  // would show up here as a gap under the title (`UpdateButton.res`). Its presence
  // can't be walked (that needs a worker to actually install a newer build), so this is
  // the half a walk can see.
  await expect(page.locator(".menu-refresh")).toHaveCount(0)
  await expect(page.locator(".menu-update")).toHaveCount(0)

  // Settings and About are siblings at the foot of the menu, in that order.
  const foot = page.locator(".menu-section--bottom .menu-button")
  await expect(foot).toHaveText(["Settings", "About"])

  // Straight to About, never touching Settings: the check is here, which is the
  // detection having been kicked off by this very tap. The screen names the app rather
  // than itself, so the wordmark is in its body and the header bar is two buttons with
  // nothing between them.
  await page.getByRole("button", { name: "About", exact: true }).click()
  await expect(page.locator(".menu-refresh")).toHaveCount(1)
  await expect(page.locator(".menu-title")).toHaveText("Pip")
  await expect(page.locator(".menu-panel__header .menu-title")).toHaveCount(0)

  // And its way back is the menu it was opened from, not sideways into Settings.
  await page.getByRole("button", { name: /Back to menu/ }).click()
  await expect(foot).toHaveText(["Settings", "About"])
})

test("Settings offers no update check of its own", async ({ page }) => {
  // The check comes and goes with the worker detection, so it belongs on the one screen
  // that is about the build. Settings opening the detection but never showing a control
  // is what lets that screen's own foot stay a fixed height.
  await page.goto("/?game=freecell&animate=off")
  await page.getByRole("button", { name: /Open menu/ }).click()
  await page.getByRole("button", { name: "Settings", exact: true }).click()
  await expect(page.locator(".menu-refresh")).toHaveCount(0)
  await expect(page.locator(".menu-update")).toHaveCount(0)
})

test("the source link goes to the repository, in a tab of its own", async ({ page }) => {
  // Marked with GitHub's own mark, which is drawn rather than fetched: an icon that
  // renders as a blank box is the failure this catches, and it is invisible to a unit
  // test — jsdom draws nothing.
  await page.goto("/?game=freecell&animate=off")
  await page.getByRole("button", { name: /Open menu/ }).click()
  await page.getByRole("button", { name: "About", exact: true }).click()

  const link = page.locator(".about-link")
  await expect(link).toHaveAttribute("href", "https://github.com/jrr/pip-solitaire")
  await expect(link).toHaveAttribute("target", "_blank")
  await expect(link).toHaveText("jrr/pip-solitaire")

  // The mark is drawn at the size of the line it labels, and the link is held to the
  // width of its own words rather than stretched across the panel.
  const mark = await link.locator(".about-link__mark").boundingBox()
  const box = await link.boundingBox()
  const panel = await page.locator(".menu-panel").boundingBox()
  expect(mark.width).toBeGreaterThan(10)
  expect(mark.width).toBeLessThan(24)
  expect(box.width).toBeLessThan(panel.width / 2)
})
