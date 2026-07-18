// Build the payload that publishes the retained `main` screenshot history to
// GitHub Pages: the freshly rendered report under a stamped directory, plus a
// regenerated listing page (GitHub Pages has no directory autoindex, so the
// accumulated snapshots would otherwise be reachable only by guessing URLs).
//
// This is only the *filesystem* half — it writes a local staging directory that
// `peaceiris/actions-gh-pages` then commits to gh-pages with `keep_files: true`,
// so the action owns all the git/branch mechanics and this script owns none. The
// PR side doesn't use this at all: there, `rossjrw/pr-preview-action` deploys the
// report directly (latest-only, auto-removed on close).
//
// Usage:
//   node stage-screenshots.mjs <stagingDir> <stamp> [--existing <jsonArray>] [--title <t>]
//
//   <stagingDir>   local dir to build (published as-is into screenshots/branch/main)
//   <stamp>        this snapshot's dir name, e.g. 2026.07.28_abc1234
//   --existing     JSON array of the stamps already on gh-pages (from a `gh api`
//                  contents read); merged with <stamp> to build the listing
//   --title        heading/subtitle for the listing page (default "main")
//
// If the render produced no PNGs (an upstream failure), it exits 0 and writes
// nothing, so the workflow can detect the empty staging dir and skip publishing.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const srcDir = path.resolve(here, "..", "screenshots");

const argv = process.argv.slice(2);
const positional = argv.filter((a, i) => !a.startsWith("--") && !argv[i - 1]?.startsWith("--"));
const [stagingDir, stamp] = positional;
const opt = (name) => {
  const i = argv.indexOf(`--${name}`);
  return i !== -1 ? argv[i + 1] : undefined;
};
const title = opt("title") ?? "main";
const existing = JSON.parse(opt("existing") ?? "[]");

if (!stagingDir || !stamp) {
  console.error("usage: stage-screenshots.mjs <stagingDir> <stamp> [--existing <json>] [--title <t>]");
  process.exit(1);
}

const pngs = fs.existsSync(srcDir)
  ? fs.readdirSync(srcDir).filter((f) => f.endsWith(".png"))
  : [];
if (pngs.length === 0) {
  console.log(`No screenshots in ${srcDir} — nothing to stage.`);
  process.exit(0);
}

// The snapshot itself.
const snapshotDir = path.join(stagingDir, stamp);
fs.mkdirSync(snapshotDir, { recursive: true });
fs.cpSync(srcDir, snapshotDir, { recursive: true });

// The listing: this snapshot plus everything already published, newest first.
// (`keep_files: true` preserves the old snapshot dirs; this page re-lists them.)
const stamps = [...new Set([stamp, ...existing])].sort().reverse();
fs.writeFileSync(path.join(stagingDir, "index.html"), listingHtml(title, stamps));
console.log(`Staged ${pngs.length} shots under ${stamp}; listing has ${stamps.length} snapshot(s).`);

function listingHtml(title, stamps) {
  const items = stamps.map((name) => `      <li><a href="./${name}/">${name}</a></li>`).join("\n");
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Screenshot reports — ${title}</title>
  <style>
    :root { color-scheme: dark; }
    body {
      margin: 0; padding: 2rem;
      font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
      background: radial-gradient(130% 120% at 50% 0%, #13233b 0%, #0b1220 60%);
      color: #e2e8f0;
    }
    main { max-width: 48rem; margin: 0 auto; }
    h1 { font-size: 1.3rem; margin: 0 0 0.25rem; }
    p { color: #94a3b8; margin: 0 0 1.5rem; }
    ul { list-style: none; padding: 0; margin: 0; }
    li { margin: 0.4rem 0; }
    a { color: #86efac; text-decoration: none; font: 15px ui-monospace, "SF Mono", Menlo, monospace; }
    a:hover { text-decoration: underline; }
    code { color: #86efac; }
  </style>
</head>
<body>
  <main>
    <h1>Screenshot reports — <code>${title}</code></h1>
    <p>Mid-game FreeCell across device sizes, portrait and landscape. Newest first.</p>
    <ul>
${items}
    </ul>
  </main>
</body>
</html>
`;
}
