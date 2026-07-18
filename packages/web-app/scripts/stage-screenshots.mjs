// Stage a rendered screenshot report (packages/web-app/screenshots) into a
// checked-out gh-pages working tree, under a timestamped directory, and
// regenerate the directory listing GitHub Pages doesn't provide on its own. This
// is the filesystem half of publishing the report to Pages — the workflow that
// calls it does the git commit/push. Splitting it this way keeps the git plumbing
// in the workflow and the HTML/copy work here, where it's easy to read and test.
//
// Reports are published under stamped, non-colliding directories so they
// accumulate as a browsable history rather than overwriting each other:
//   screenshots/branch/main/<YYYY.MM.DD>_<sha>/   (retained across main deploys)
//   screenshots/pr/<N>/<YYYY.MM.DD>_<sha>/        (removed when the PR closes)
//
// Usage:
//   node stage-screenshots.mjs <ghPagesDir> <destSubpath> [--index <listingSubpath>]
//
//   <ghPagesDir>     path to a checked-out gh-pages working tree
//   <destSubpath>    directory under it to copy the report into
//   --index <dir>    also (re)generate <dir>/index.html, a listing of its snapshot
//                    subdirs (newest first) — this is what keeps the retained
//                    history browsable, since Pages 404s a directory with no
//                    index.html.
//
// If the report has no PNGs (e.g. an upstream render failed), it exits 0 without
// touching anything, so a flaky render can never publish an empty report.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const srcDir = path.resolve(here, "..", "screenshots");

const positional = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const [ghPagesDir, destSubpath] = positional;
const indexFlag = process.argv.indexOf("--index");
const listingSubpath = indexFlag !== -1 ? process.argv[indexFlag + 1] : null;

if (!ghPagesDir || !destSubpath) {
  console.error(
    "usage: stage-screenshots.mjs <ghPagesDir> <destSubpath> [--index <listingSubpath>]",
  );
  process.exit(1);
}

const pngs = fs.existsSync(srcDir)
  ? fs.readdirSync(srcDir).filter((f) => f.endsWith(".png"))
  : [];
if (pngs.length === 0) {
  console.log(`No screenshots in ${srcDir} — nothing to stage.`);
  process.exit(0);
}

const dest = path.join(ghPagesDir, destSubpath);
fs.mkdirSync(dest, { recursive: true });
fs.cpSync(srcDir, dest, { recursive: true });
console.log(`Staged ${pngs.length} shots + report → ${destSubpath}`);

if (listingSubpath) {
  const listingDir = path.join(ghPagesDir, listingSubpath);
  const snapshots = fs
    .readdirSync(listingDir, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => e.name)
    .sort()
    .reverse(); // newest first — the `YYYY.MM.DD_sha` stamp sorts chronologically
  fs.writeFileSync(path.join(listingDir, "index.html"), listingHtml(listingSubpath, snapshots));
  console.log(`Regenerated ${listingSubpath}/index.html (${snapshots.length} snapshots)`);
}

function listingHtml(title, snapshots) {
  const items =
    snapshots.map((name) => `      <li><a href="./${name}/">${name}</a></li>`).join("\n") ||
    "      <li>(none yet)</li>";
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
    <h1>Screenshot reports</h1>
    <p><code>${title}</code> — newest first. Each is mid-game FreeCell across device sizes, portrait and landscape.</p>
    <ul>
${items}
    </ul>
  </main>
</body>
</html>
`;
}
