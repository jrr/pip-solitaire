// The About footer — the way through to the About screen, and the build string under it
// — belongs to the Settings screen and to no other. The update controls it used to hold
// are one screen further in, on About, where the build string is the subject.
//
// Why this can't be a unit test. Which screen the footer appears under is the pane's
// (`Menu`), and whether there is an update check to offer at all is `Main`'s — it turns
// on whether `Refresh.detect` has reported a service-worker state yet, and `Main` is the
// entry point, so importing it mounts the app, registers a worker and takes over
// `<body>`. A walk is the only thing that sees both.
//
// What it pins is the *shape* of the rule rather than a label: the footer is absent on
// the main menu in both directions (before ever visiting Settings, and again on the way
// back out), absent a level deeper on Debug, and present on Settings once the detection
// has landed. Whether the check reads "Refresh" or "Check for updates" is
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
  const version = page.locator("#version-badge")
  await expect(footer).toHaveCount(0)
  await expect(version).toHaveCount(0)

  // Nor is there an ↻ Update band with nothing waiting: the main menu's is absent
  // rather than reserved, so a box kept for it would show up here as a gap under the
  // title (`UpdateButton.res`). Its presence can't be walked — that needs a service
  // worker to actually install a newer build — so this is the half a walk can see.
  await expect(page.locator(".menu-update")).toHaveCount(0)

  await page.getByRole("button", { name: "Settings", exact: true }).click()
  await expect(footer).toHaveCount(1)
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

test("the About screen holds the build string and the update check", async ({ page }) => {
  // The button at the foot of Settings opens one level down, so its way back is to
  // Settings rather than out to the menu — and what it opens is where the build string
  // is the subject rather than a caption, with the update check on it.
  await page.goto("/?game=freecell&animate=off")
  await page.getByRole("button", { name: /Open menu/ }).click()
  await page.getByRole("button", { name: "Settings", exact: true }).click()

  // The check is *not* on Settings: it comes and goes with the worker detection, and
  // nothing in that footer may change height.
  await expect(page.locator(".menu-refresh")).toHaveCount(0)

  await page.getByRole("button", { name: "About", exact: true }).click()
  // The screen names the app rather than itself, in its own body — so the header bar is
  // two buttons and nothing between them.
  await expect(page.locator(".menu-title")).toHaveText("Pip")
  await expect(page.locator(".menu-panel__header .menu-title")).toHaveCount(0)
  await expect(page.locator(".menu-refresh")).toHaveCount(1)
  await expect(page.locator(".menu-footer")).toHaveCount(0)

  // The version, set bigger here than the caption it is in the footer — the claim the
  // stylesheet makes and only a browser can check.
  const here = await page.locator(".about-build__version").boundingBox()
  await page.getByRole("button", { name: /Back to settings/ }).click()
  const caption = await page.locator("#version-badge").boundingBox()
  expect(here.height).toBeGreaterThan(caption.height)

  await expect(page.locator(".menu-title")).toHaveText("Settings")
  await expect(page.locator(".menu-footer")).toHaveCount(1)
})

test("the source link goes to the repository, in a tab of its own", async ({ page }) => {
  // Marked with GitHub's own mark, which is drawn rather than fetched: an icon that
  // renders as a blank box is the failure this catches, and it is invisible to a unit
  // test — jsdom draws nothing.
  await page.goto("/?game=freecell&animate=off")
  await page.getByRole("button", { name: /Open menu/ }).click()
  await page.getByRole("button", { name: "Settings", exact: true }).click()
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
