// The raised panel, worn twice: that the win panel and the "enter seed" modal are
// still one look.
//
// They share no class and no box — one is sized by its contents inside the board, the
// other is chrome sized to a phone's width — so what makes them a family is the
// `--panel-*` tokens in styles/base.css, and nothing but this checks that they still
// agree. The failure it is here for is the one custom properties fail with: a typo'd
// `var(--panel-bgg)` is not an error, it is an invalid value that drops the whole
// declaration, so a panel loses its background and goes on rendering. Nothing throws,
// no unit test sees it — the classes are all still there — and the two screens simply
// stop matching.
//
// It compares the two against **each other**, never against a hex. Repainting the
// panels is then one edit to the tokens and this test still passes, which is the whole
// point of their being tokens; what it will not let past is one of them being
// repainted alone.

import { expect, test } from "@playwright/test"
import { settleBoard } from "./lib/board.mjs"

test.use({ viewport: { width: 430, height: 932 } })

// The declarations the tokens carry. Not the panels' own dimensions — padding, gap and
// the title's size are deliberately different in the two — just what they hold in
// common.
const PANEL_BOX = ["backgroundColor", "borderTopWidth", "borderTopStyle", "borderTopColor",
                   "borderRadius", "boxShadow"]
const BUTTON = ["padding", "font", "color", "backgroundColor", "borderRadius"]

const styleOf = (page, selector, properties) =>
  page.locator(selector).first().evaluate(
    (el, properties) =>
      Object.fromEntries(properties.map((p) => [p, getComputedStyle(el)[p]])),
    properties,
  )

// Every reading one screen offers, as one object to compare with the other's.
async function panelLook(page, { panel, button, quietButton, title, subtitle }) {
  return {
    panel: await styleOf(page, panel, PANEL_BOX),
    button: await styleOf(page, button, BUTTON),
    quietButton: await styleOf(page, quietButton, ["backgroundColor"]),
    title: await styleOf(page, title, ["color"]),
    subtitle: await styleOf(page, subtitle, ["color"]),
  }
}

// A panel that has lost a token reads as transparent rather than as slate, and
// `toEqual` between two broken screens would still pass. So: whatever the palette is,
// the panel is painted and its border is drawn.
function expectPainted(look) {
  expect(look.panel.backgroundColor).not.toBe("rgba(0, 0, 0, 0)")
  expect(look.panel.borderTopStyle).toBe("solid")
  expect(look.panel.borderTopWidth).not.toBe("0px")
  expect(look.button.backgroundColor).not.toBe("rgba(0, 0, 0, 0)")
  expect(look.panel.boxShadow).not.toBe("none")
}

async function seedDialogLook(page) {
  await page.goto("/?game=freecell&seed=24680&animate=off")
  await settleBoard(page)
  await page.getByRole("button", { name: /^Open menu/ }).click()
  await page.getByRole("button", { name: "Enter Seed", exact: true }).click()
  await page.waitForSelector("#seed-dialog")
  return panelLook(page, {
    panel: ".seed-dialog__panel",
    button: ".seed-dialog__button:not(.seed-dialog__button--cancel)",
    quietButton: ".seed-dialog__button--cancel",
    title: ".seed-dialog__title",
    subtitle: ".seed-dialog__hint",
  })
}

async function winPanelLook(page) {
  // `?state=almost-won` is one move from home: the pending King rests alone in the
  // first free cell and its foundation is the last zone. The same drag win.spec.mjs
  // makes, which is the only way to raise this panel.
  await page.goto("/?game=freecell&state=almost-won&animate=off")
  await settleBoard(page)
  const from = await page.locator(".drop-zone").nth(0).boundingBox()
  const to = await page.locator(".drop-zone").nth(7).boundingBox()
  const start = { x: from.x + from.width / 2, y: from.y + from.height / 2 }
  await page.mouse.move(start.x, start.y)
  await page.mouse.down()
  for (let i = 1; i <= 6; i++) {
    await page.mouse.move(start.x + ((to.x - from.x) * i) / 6, start.y + ((to.y - from.y) * i) / 6)
  }
  await page.mouse.up()
  await page.waitForSelector(".win-overlay")
  return panelLook(page, {
    panel: ".win-panel",
    button: ".win-panel__button:not(.win-panel__button--share)",
    quietButton: ".win-panel__button--share",
    title: ".win-panel__title",
    subtitle: ".win-panel__stats",
  })
}

test("the seed dialog and the win panel are painted the same", async ({ page }) => {
  const seed = await seedDialogLook(page)
  const win = await winPanelLook(page)

  expectPainted(seed)
  expectPainted(win)
  expect(seed).toEqual(win)
})

test("the Finish button takes the panel's colours and keeps its own box", async ({ page }) => {
  // The third consumer, and the one that shows what the tokens are scoped to: it is a
  // control floating on the board rather than anything on a panel, so it wears the
  // family's green and gold at its own larger size.
  const win = await winPanelLook(page)

  await page.goto("/?game=freecell&state=finish&animate=off")
  await settleBoard(page)
  const finish = await styleOf(page, ".finish-button", [
    ...BUTTON,
    "borderTopColor",
    "borderTopWidth",
  ])

  expect(finish.backgroundColor).toBe(win.button.backgroundColor)
  expect(finish.color).toBe(win.button.color)
  expect(finish.borderTopColor).toBe(win.panel.borderTopColor)
  expect(finish.borderTopWidth).toBe(win.panel.borderTopWidth)
  // Its own box, which is why the padding and radius tokens stop at the panels.
  expect(finish.padding).not.toBe(win.button.padding)
  expect(finish.borderRadius).not.toBe(win.button.borderRadius)
})
