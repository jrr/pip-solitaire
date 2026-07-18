// One-off verification (issue #121): drive the built app to the near-won FreeCell
// position, play the single winning move by dragging the pending King onto its
// foundation, and confirm the win overlay appears. Not wired into CI — a manual
// check that the web win behaviour works end-to-end in a real browser.
import { chromium } from "playwright";
import { preview } from "vite";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const webAppRoot = path.resolve(here, "..");

function resolveExecutablePath() {
  const explicit = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
  if (explicit && fs.existsSync(explicit)) return explicit;
  const preinstalled = "/opt/pw-browsers/chromium";
  if (fs.existsSync(preinstalled)) return preinstalled;
  return undefined;
}

async function main() {
  const server = await preview({
    root: webAppRoot,
    preview: { port: 0, strictPort: false, open: false },
    logLevel: "warn",
  });
  const base = server.resolvedUrls.local[0].replace(/\/$/, "");
  const target = `${base}/?scene=freecell&state=almost-won`;

  const browser = await chromium.launch({ executablePath: resolveExecutablePath() });
  try {
    const context = await browser.newContext({ viewport: { width: 800, height: 1000 } });
    const page = await context.newPage();
    await page.goto(target, { waitUntil: "load" });
    await page.waitForSelector(".stacking-card", { state: "visible", timeout: 15000 });
    await page.waitForTimeout(600);

    // Three foundations should already read "complete" (the ✓ frame).
    const completeBefore = await page.locator(".drop-zone--complete").count();

    // The pending King rests alone in the first free cell (drop zone 0); its
    // foundation is the last drop zone (4 cells, then 4 foundations, Clubs last —
    // zone 7). The King is centred in its cell, so grabbing from the cell's centre
    // picks it up. Drag it to the foundation and drop.
    const cell = await page.locator(".drop-zone").nth(0).boundingBox();
    const fBox = await page.locator(".drop-zone").nth(7).boundingBox();
    const from = { x: cell.x + cell.width / 2, y: cell.y + cell.height / 2 };
    const to = { x: fBox.x + fBox.width / 2, y: fBox.y + fBox.height / 2 };

    await page.mouse.move(from.x, from.y);
    await page.mouse.down();
    // A few incremental moves so pointermove fires and the hover highlight updates.
    for (let i = 1; i <= 6; i++) {
      await page.mouse.move(
        from.x + ((to.x - from.x) * i) / 6,
        from.y + ((to.y - from.y) * i) / 6,
      );
    }
    await page.mouse.up();
    await page.waitForTimeout(400);

    const overlay = await page.locator(".win-overlay").count();
    const title = await page.locator(".win-panel__title").textContent().catch(() => null);
    const completeAfter = await page.locator(".drop-zone--complete").count();

    console.log("complete foundations before move:", completeBefore, "(expect 3)");
    console.log("complete foundations after move: ", completeAfter, "(expect 4)");
    console.log("win overlay present:", overlay === 1, `(title: ${JSON.stringify(title)})`);

    // Now click New Game and confirm the overlay is torn down and a fresh board deals.
    await page.locator(".win-panel__button").click();
    await page.waitForTimeout(400);
    const overlayAfterNewGame = await page.locator(".win-overlay").count();
    const completeAfterNewGame = await page.locator(".drop-zone--complete").count();
    console.log("win overlay after New Game:", overlayAfterNewGame, "(expect 0)");
    console.log("complete foundations after New Game:", completeAfterNewGame, "(expect 0)");

    const ok =
      completeBefore === 3 && completeAfter === 4 && overlay === 1 && overlayAfterNewGame === 0;
    console.log(ok ? "\nVERIFY: PASS" : "\nVERIFY: FAIL");
    if (!ok) process.exitCode = 1;
  } finally {
    await browser.close();
    await server.httpServer.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
