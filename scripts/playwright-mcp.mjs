// Launcher for the Playwright MCP server (@playwright/mcp), used as the
// `command` in .mcp.json and in the @claude workflow. It's a transparent stdio
// proxy: it resolves a Chromium binary, then execs the MCP server with stdio
// inherited so the MCP client talks straight to it.
//
// Why a launcher instead of running `npx @playwright/mcp` directly:
//
//   The MCP package bundles its *own* pinned Playwright, which expects a
//   specific Chromium build. Sandboxed agent environments (Claude Code on the
//   web) ship a *pre-installed* Chromium and block Playwright's browser-download
//   CDN — so the bundled Playwright can't fetch the build it wants and the
//   browser fails to launch. Pointing it at the already-present binary with
//   `--executable-path` sidesteps the version/download problem entirely (the
//   CDP protocol is stable across nearby builds). This script finds that binary
//   wherever the current environment keeps it.
//
// Resolution order for the Chromium executable:
//   1. $PLAYWRIGHT_BROWSERS_PATH        (sandbox images set this: /opt/pw-browsers)
//   2. the per-OS default Playwright cache (`mise run browser-install` fills this)
// If none is found we launch without --executable-path and let the MCP server
// surface its own "run a browser install" error.
//
// Extra CLI args are forwarded to the server, so callers can tighten scope,
// e.g. the workflow passes `--allowed-origins` to fence the browser to the
// locally-served app. Set PLAYWRIGHT_MCP_HEADED=1 to watch it run (dev only).

import { spawn } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { homedir, platform } from "node:os";
import { join } from "node:path";

const MCP_VERSION = "0.0.78"; // pinned; bump deliberately (see scripts/README note)

// Where Playwright keeps downloaded browsers, most-specific first.
function browserRoots() {
  const roots = [];
  if (process.env.PLAYWRIGHT_BROWSERS_PATH) roots.push(process.env.PLAYWRIGHT_BROWSERS_PATH);
  const home = homedir();
  if (platform() === "darwin") roots.push(join(home, "Library", "Caches", "ms-playwright"));
  else if (platform() === "win32") roots.push(join(home, "AppData", "Local", "ms-playwright"));
  else roots.push(join(home, ".cache", "ms-playwright"));
  return roots;
}

// The chrome executable inside a `chromium-<build>` directory, per OS.
function chromeUnder(dir) {
  const rel =
    platform() === "darwin"
      ? ["chrome-mac", "Chromium.app", "Contents", "MacOS", "Chromium"]
      : platform() === "win32"
        ? ["chrome-win", "chrome.exe"]
        : ["chrome-linux", "chrome"];
  const p = join(dir, ...rel);
  return existsSync(p) ? p : undefined;
}

function resolveChromium() {
  for (const root of browserRoots()) {
    if (!existsSync(root)) continue;
    // Highest build number wins (a newer Chromium is fine for our app).
    const builds = readdirSync(root)
      .filter((name) => /^chromium-\d+$/.test(name))
      .sort((a, b) => Number(b.split("-")[1]) - Number(a.split("-")[1]));
    for (const build of builds) {
      const exe = chromeUnder(join(root, build));
      if (exe) return exe;
    }
  }
  return undefined;
}

const passthrough = process.argv.slice(2);
const args = ["-y", `@playwright/mcp@${MCP_VERSION}`];
if (!process.env.PLAYWRIGHT_MCP_HEADED) args.push("--headless");

const chromium = resolveChromium();
if (chromium) args.push("--executable-path", chromium);
else
  console.error(
    "[playwright-mcp] No pre-installed Chromium found; letting the MCP server manage its own.\n" +
      "  If it can't launch a browser, run `mise run browser-install` first.",
  );

args.push(...passthrough);

// Inherit stdio so the MCP client speaks JSON-RPC directly to the server.
const child = spawn("npx", args, { stdio: "inherit" });
child.on("exit", (code, signal) => process.exit(signal ? 1 : (code ?? 0)));
for (const sig of ["SIGINT", "SIGTERM"]) process.on(sig, () => child.kill(sig));
