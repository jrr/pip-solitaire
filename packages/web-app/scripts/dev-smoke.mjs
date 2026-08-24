// Boot the *dev* server the way a developer does, load the app in a real browser,
// and fail if it didn't come up. That is the whole test — but it guards a seam
// nothing else does.
//
// The compiler emits JSX into the `.res.mjs` output (`"jsx": {"preserve": true}`,
// see src/Html.res), so something downstream has to lower it, and Vite reaches
// esbuild by more than one route: the build's transform, the dev server's
// dependency scanner, and Vitest's. Each takes its own config, and nothing checks
// that they agree. They didn't once — `bundle`, `test` and `browsertest` were all
// green while `vite` printed a screenful of "The JSX syntax extension is not
// currently enabled" on every start.
//
// **A rendered page is not enough to pass**, which is what makes this more than a
// smoke test. A dependency-scan failure is *not* fatal to Vite: it logs, skips
// pre-bundling and serves anyway, and the app comes up looking fine — so the
// server's own output is checked too, and anything it calls an error fails the
// run. That is the half a browser assertion can't see.
import { spawn } from "node:child_process";
import path from "node:path";
import { launchChromium, webAppRoot } from "./lib/preview-app.mjs";

// The `vite` binary itself, not `pnpm run dev` around it: a signal sent to the
// package-manager wrapper doesn't necessarily reach the server it started, and a
// smoke test that can't stop what it started is a hang waiting to happen in CI.
const VITE = path.resolve(webAppRoot, "node_modules", ".bin", "vite");

// Vite takes the next free port when its default is busy, so the address is read
// out of the server's own greeting rather than assumed.
const READY = /Local:\s+(http:\/\/\S+)/;
// Vite keeps serving through a dependency-scan failure, so the transcript is
// where that regression shows up rather than in the page.
const SERVER_TROUBLE = /\[ERROR\]|Failed to run dependency scan|Internal server error/;
const BOOT_TIMEOUT_MS = 60_000;
const RENDER_TIMEOUT_MS = 30_000;

function startDevServer() {
  const server = spawn(VITE, [], { cwd: webAppRoot, stdio: ["ignore", "pipe", "pipe"] });

  const transcript = [];
  const address = new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`the dev server printed no URL within ${BOOT_TIMEOUT_MS}ms`)),
      BOOT_TIMEOUT_MS,
    );
    const read = (chunk) => {
      const text = chunk.toString();
      transcript.push(text);
      const match = text.match(READY);
      if (match) {
        clearTimeout(timer);
        resolve(match[1].replace(/\/$/, ""));
      }
    };
    server.stdout.on("data", read);
    server.stderr.on("data", read);
    server.on("exit", (code) => {
      clearTimeout(timer);
      reject(new Error(`the dev server exited with code ${code}`));
    });
  });

  return { server, address, transcript };
}

const { server, address, transcript } = startDevServer();
let browser;
let failure;

try {
  const base = await address;
  console.log(`  dev server up at ${base}`);

  browser = await launchChromium();
  const page = await browser.newPage();

  // A JSX-lowering failure reaches the page as a module that never evaluates, so
  // watch for both symptoms: the error, and the app simply never appearing.
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });

  await page.goto(base, { waitUntil: "domcontentloaded" });
  // The chrome is what renders through the JSX runtime (the board behind it is
  // imperative), so the top bar is the honest thing to wait for — then a card, to
  // say the scene underneath it started too.
  await page.locator("#top-bar").waitFor({ state: "visible", timeout: RENDER_TIMEOUT_MS });
  await page
    .locator(".stacking-card .card-art")
    .first()
    .waitFor({ state: "visible", timeout: RENDER_TIMEOUT_MS });

  if (errors.length > 0) {
    throw new Error(`the page reported errors:\n  ${errors.join("\n  ")}`);
  }

  const complaints = transcript.join("").split("\n").filter((line) => SERVER_TROUBLE.test(line))
  if (complaints.length > 0) {
    throw new Error(`the dev server reported trouble:\n  ${complaints.slice(0, 5).join("\n  ")}`);
  }
  console.log("  top bar and a dealt board rendered, with a clean console and a quiet server");
} catch (error) {
  failure = error;
  // The server's own output is where the useful half of a boot failure lives.
  if (transcript.length > 0) console.error(transcript.join(""));
} finally {
  await browser?.close();
  server.kill("SIGTERM");
}

// Exit explicitly: the server's pipes are still open at this point, and a
// lingering handle would leave the task sitting there looking like a hang.
if (failure) {
  console.error(`dev-smoke: ${failure.message}`);
  process.exit(1);
}
console.log("dev-smoke: ok");
process.exit(0);
