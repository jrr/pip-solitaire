// Boot the *dev* server the way a developer does, load the app in a real browser,
// and read what the server printed. **A rendered page is not enough to pass** —
// the seam this guards is a dev-server-only esbuild config that breaks without
// breaking the page, so anything the server calls an error fails the run. The
// seam, and why `mise run ci` cannot cover it, are in docs/rendering.md § The
// three esbuild settings, in four places.
//
// Two things this deliberately does not do:
//
//   - **It doesn't use Vite's JS API.** `createServer()` — the way `startPreview`
//     serves the built site in lib/preview-app.mjs — survives a scan failure
//     without a fuss. `vite` the command is what `mise run dev` runs, so it is
//     what gets tested.
//   - **It doesn't read readiness out of the server's greeting.** A child's
//     stdout is block-buffered when it isn't a terminal, so on CI the banner
//     lands in one lump *after* the process is killed: a wait on that regex times
//     out against a server that was up the whole time. Readiness is a port that
//     answers; the transcript is only read at the end, once the pipes have
//     drained.
import { spawn } from "node:child_process";
import path from "node:path";
import { launchChromium, webAppRoot } from "./lib/preview-app.mjs";

// The `vite` binary itself, not `pnpm run dev` around it: a signal sent to the
// package-manager wrapper doesn't necessarily reach the server it started.
const VITE = path.resolve(webAppRoot, "node_modules", ".bin", "vite");

// `--strictPort` so a busy port fails loudly here rather than moving the server
// somewhere this script isn't looking.
const PORT = 5199;
const BASE = `http://localhost:${PORT}`;

const BOOT_TIMEOUT_MS = 60_000;
const RENDER_TIMEOUT_MS = 30_000;
const SHUTDOWN_TIMEOUT_MS = 5_000;
const SERVER_TROUBLE = /\[ERROR\]|Failed to run dependency scan|Internal server error/;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function startDevServer() {
  const server = spawn(VITE, ["--port", String(PORT), "--strictPort"], {
    cwd: webAppRoot,
    stdio: ["ignore", "pipe", "pipe"],
  });

  const transcript = [];
  server.stdout.on("data", (chunk) => transcript.push(chunk.toString()));
  server.stderr.on("data", (chunk) => transcript.push(chunk.toString()));

  let exited = null;
  server.on("exit", (code) => (exited = code));

  return { server, transcript, exitedWith: () => exited };
}

/** Resolves when the server answers, rejects when it never does (or dies first). */
async function waitForServer(exitedWith) {
  const deadline = Date.now() + BOOT_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (exitedWith() !== null) {
      throw new Error(`the dev server exited with code ${exitedWith()} before serving`);
    }
    try {
      const response = await fetch(BASE, { signal: AbortSignal.timeout(2_000) });
      if (response.ok) return;
    } catch {
      // Not up yet — that's the normal case for the first second or so.
    }
    await sleep(250);
  }
  throw new Error(`the dev server didn't answer on ${BASE} within ${BOOT_TIMEOUT_MS}ms`);
}

/** SIGTERM, then wait for the pipes to drain so the transcript is complete. */
async function stopDevServer(server) {
  if (server.exitCode !== null) return;
  const closed = new Promise((resolve) => server.once("close", resolve));
  server.kill("SIGTERM");
  await Promise.race([closed, sleep(SHUTDOWN_TIMEOUT_MS).then(() => server.kill("SIGKILL"))]);
}

const { server, transcript, exitedWith } = startDevServer();
let browser;
let failure;

try {
  await waitForServer(exitedWith);
  console.log(`  dev server up at ${BASE}`);

  browser = await launchChromium();
  const page = await browser.newPage();

  // A JSX-lowering failure reaches the page as a module that never evaluates, so
  // watch for both symptoms: the error, and the app simply never appearing.
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });

  await page.goto(BASE, { waitUntil: "domcontentloaded" });
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
  console.log("  top bar and a dealt board rendered, with a clean console");
} catch (error) {
  failure = error;
} finally {
  await browser?.close();
  await stopDevServer(server);
}

// Only now is the transcript complete (see the note about buffering above).
if (!failure) {
  const complaints = transcript
    .join("")
    .split("\n")
    .filter((line) => SERVER_TROUBLE.test(line));
  if (complaints.length > 0) {
    failure = new Error(`the dev server reported trouble:\n  ${complaints.slice(0, 5).join("\n  ")}`);
  }
}

if (failure) {
  // The server's own output is where the useful half of a failure lives.
  if (transcript.length > 0) console.error(transcript.join(""));
  console.error(`dev-smoke: ${failure.message}`);
  process.exit(1);
}
console.log("dev-smoke: ok, and the server had nothing to complain about");
process.exit(0);
