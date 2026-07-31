// Verification for issue #241: the finish sweep must not re-tilt cards before it
// moves them. The hand-placed tilt (#65) is keyed on where a card *rests*, so the
// `reflowAll` that starts the sweep re-tilts every card for its foundation slot at
// once — while the flights still hold each card at its source until its staggered
// turn. Left alone that reads as the whole board twitching in place before anything
// flies. The fix defers each card's rotation to its own launch, so early in the
// sweep only the cards actually in the air have turned.
//
// Measured in a real browser: jsdom has no layout, no CSS transitions and no
// resolved transform matrices, so this can't be a case in `mise run test` — it sits
// beside `verify-win` as a headless-browser task.
//
// Checks, on the `?state=finish` board:
//   1. tilt ON  — early in the sweep, at most a couple of cards have turned (the
//      ones already launched), not the whole board.
//   2. tilt ON  — cards end the sweep tilted, at their foundation angles: a tilt at
//      the source *and* at the destination, with the turn happening in the air.
//   3. tilt OFF — every card is dead square throughout, source and destination.
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

// Run one sweep and report the angles before it starts, a beat into it, and once it
// has settled. `earlyMs` lands inside the 0.18s tilt transition the twitch used to
// run over, so a regression shows up as a boardful of turned cards.
async function sweep(page, { earlyMs }) {
  return await page.evaluate(
    async ({ earlyMs }) => {
      // A card's *rendered* angle, read off the resolved transform matrix rather
      // than the `--card-rot` property — mid-transition the property already holds
      // the destination value, while the matrix is what the player actually sees.
      const arts = [...document.querySelectorAll(".stacking-card .card-art")];
      const angle = (el) => {
        const m = new DOMMatrixReadOnly(getComputedStyle(el).transform);
        return (Math.atan2(m.b, m.a) * 180) / Math.PI;
      };
      const before = arts.map(angle);
      document.querySelector(".finish-button").click();
      await new Promise((r) => setTimeout(r, earlyMs));
      const early = arts.map(angle);
      // Let the whole staggered sweep land (the win overlay is its last act).
      await new Promise((r) => setTimeout(r, 6000));
      const after = arts.map(angle);
      return { before, early, after, won: document.querySelectorAll(".win-overlay").length };
    },
    { earlyMs },
  );
}

const turned = (a, b) => a.filter((v, i) => Math.abs(v - b[i]) > 0.2).length;
const maxAbs = (xs) => xs.reduce((m, v) => Math.max(m, Math.abs(v)), 0);

async function openBoard(context, target, { tilt }) {
  const page = await context.newPage();
  // The tilt preference is a stored flag (`pip.cardTilt`), so seed it before the app
  // boots rather than driving the menu.
  await page.addInitScript((on) => {
    window.localStorage.setItem("pip.cardTilt", on ? "true" : "false");
  }, tilt);
  await page.goto(target, { waitUntil: "load" });
  await page.waitForSelector(".finish-button", { state: "visible", timeout: 15000 });
  await page.waitForTimeout(800);
  return page;
}

async function main() {
  const server = await preview({
    root: webAppRoot,
    preview: { port: 0, strictPort: false, open: false },
    logLevel: "warn",
  });
  const base = server.resolvedUrls.local[0].replace(/\/$/, "");
  const target = `${base}/?scene=freecell&state=finish`;

  const browser = await chromium.launch({ executablePath: resolveExecutablePath() });
  const results = [];
  try {
    const context = await browser.newContext({ viewport: { width: 800, height: 1000 } });

    // 1 & 2 — the hand-placed tilt on.
    const tilted = await openBoard(context, target, { tilt: true });
    const on = await sweep(tilted, { earlyMs: 90 });
    const earlyTurned = turned(on.early, on.before);
    const sweptCards = turned(on.after, on.before);
    console.log(`tilt on:  ${on.before.length} cards, ${sweptCards} re-tilted by the sweep`);
    console.log(`tilt on:  ${earlyTurned} turned 90ms in (expect a couple, not the board)`);
    console.log(`tilt on:  max resting angle after the sweep ${maxAbs(on.after).toFixed(2)}°`);
    // The twitch turned *every* swept card at once; only the cards already in flight
    // should have moved this early. The cap is generous — it's an order-of-magnitude
    // check against the whole board swinging, not a frame-exact assertion.
    results.push(["few cards turned early in the sweep", earlyTurned <= 4 && sweptCards > 8]);
    // …and the sweep still delivers a hand-placed angle at the destination.
    results.push(["cards rest tilted once home", maxAbs(on.after) > 0.5]);
    results.push(["sweep reached the win", on.won === 1]);
    await tilted.close();

    // 3 — the hand-placed tilt off: square at the source, square at the destination.
    const square = await openBoard(context, target, { tilt: false });
    const off = await sweep(square, { earlyMs: 90 });
    const worst = Math.max(maxAbs(off.before), maxAbs(off.early), maxAbs(off.after));
    console.log(`tilt off: max angle at any point ${worst.toFixed(2)}° (expect 0)`);
    results.push(["square throughout with tilt off", worst < 0.01]);
    results.push(["sweep reached the win (tilt off)", off.won === 1]);
    await square.close();
  } finally {
    await browser.close();
    await server.httpServer.close();
  }

  console.log("");
  for (const [label, ok] of results) console.log(`${ok ? "✓" : "✗"} ${label}`);
  const ok = results.every(([, pass]) => pass);
  console.log(ok ? "\nVERIFY: PASS" : "\nVERIFY: FAIL");
  if (!ok) process.exitCode = 1;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
