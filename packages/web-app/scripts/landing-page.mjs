// Generate the hub page served at `/screenshots/` on GitHub Pages.
//
// GitHub Pages has no directory autoindex — a request to a dir with no
// index.html just serves the 404 page — so the accumulated `branch/<name>/` and
// `pr/pr-<N>/` reports would otherwise be reachable only by guessing URLs. This
// page is the entry point that lists them.
//
// It lists them *dynamically*, at view time, rather than being regenerated on
// every deploy: the inline script reads the gh-pages tree with GitHub's REST
// contents API (CORS-enabled, works unauthenticated for public repos) and links
// whatever `screenshots/branch/*` and `screenshots/pr/*` dirs actually exist,
// annotating each PR with its live title/state. So a new PR preview or a pruned
// one shows up here with no publish step of its own — this page is static and
// only republished when *it* changes (the deploy workflow stages it to
// `screenshots/` with keep_files, preserving the branch/ and pr/ subtrees).
//
// Usage: node landing-page.mjs <outDir>   (writes <outDir>/index.html)

import fs from "node:fs";
import path from "node:path";

const outDir = process.argv[2];
if (!outDir) {
  console.error("usage: landing-page.mjs <outDir>");
  process.exit(1);
}

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, "index.html"), html());
console.log(`Wrote screenshots hub to ${path.join(outDir, "index.html")}`);

function html() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Sleight — screenshot reports</title>
  <style>
    :root { color-scheme: dark; }
    body {
      margin: 0; padding: 2rem;
      font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
      background: radial-gradient(130% 120% at 50% 0%, #13233b 0%, #0b1220 60%);
      color: #e2e8f0;
    }
    main { max-width: 48rem; margin: 0 auto; }
    h1 { font-size: 1.4rem; margin: 0 0 0.25rem; }
    h2 { font-size: 1rem; margin: 2rem 0 0.75rem; color: #cbd5e1; }
    .lede { color: #94a3b8; margin: 0 0 0.5rem; }
    ul { list-style: none; padding: 0; margin: 0; }
    li { margin: 0.4rem 0; }
    a { color: #86efac; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .mono { font: 15px ui-monospace, "SF Mono", Menlo, monospace; }
    .meta { color: #94a3b8; font-size: 0.85rem; }
    .note { color: #94a3b8; font-size: 0.85rem; margin: 0.25rem 0 0; }
    .tag {
      font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.04em;
      padding: 0.05rem 0.4rem; border-radius: 999px; margin-left: 0.4rem;
      background: #1e3a2b; color: #86efac; vertical-align: 0.05em;
    }
    .tag.closed { background: #3a1e22; color: #fca5a5; }
    code { color: #86efac; }
  </style>
</head>
<body>
  <main>
    <h1>Sleight — screenshot reports</h1>
    <p class="lede">Mid-game FreeCell across device sizes, portrait and landscape.</p>

    <h2>Branches</h2>
    <ul id="branches"><li class="meta">Loading…</li></ul>

    <h2>Pull requests</h2>
    <ul id="prs"><li class="meta">Loading…</li></ul>
    <p class="note" id="prs-note"></p>
  </main>

  <script>
    // Serve-anywhere: derive owner/repo from the Pages URL
    // (owner.github.io/repo/screenshots/), falling back to this repo.
    const host = location.hostname;
    const owner = host.endsWith(".github.io") ? host.slice(0, -".github.io".length) : "jrr";
    const repo = location.pathname.split("/").filter(Boolean)[0] || "sleight";

    const api = (p) =>
      fetch("https://api.github.com/repos/" + owner + "/" + repo + p, {
        headers: { Accept: "application/vnd.github+json" },
      });

    // [] = published dir exists but is empty / nothing there yet (404 too);
    // null = couldn't reach the API (rate limit, offline) — a different, louder state.
    async function listDirs(sub) {
      let res;
      try {
        res = await api("/contents/screenshots/" + sub + "?ref=gh-pages");
      } catch {
        return null;
      }
      if (res.status === 404) return [];
      if (!res.ok) return null;
      const items = await res.json();
      return Array.isArray(items) ? items.filter((i) => i.type === "dir").map((i) => i.name) : [];
    }

    function li(href, label, meta, tag) {
      const a = '<a class="mono" href="' + href + '">' + label + "</a>";
      const t = tag ? ' <span class="' + ("tag " + tag.cls).trim() + '">' + tag.text + "</span>" : "";
      const m = meta ? ' <span class="meta">— ' + meta + "</span>" : "";
      return "<li>" + a + t + m + "</li>";
    }

    function esc(s) {
      return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
    }

    async function renderBranches() {
      const el = document.getElementById("branches");
      const names = await listDirs("branch");
      if (names === null) {
        el.innerHTML = li("./branch/main/", "main", "history + latest");
        return;
      }
      if (names.length === 0) {
        el.innerHTML = '<li class="meta">None published yet.</li>';
        return;
      }
      // main first, then the rest alphabetically.
      names.sort((a, b) => (a === "main" ? -1 : b === "main" ? 1 : a.localeCompare(b)));
      el.innerHTML = names
        .map((n) => li("./branch/" + n + "/", n, n === "main" ? "history + latest" : null))
        .join("");
    }

    async function renderPrs() {
      const el = document.getElementById("prs");
      const note = document.getElementById("prs-note");
      const names = await listDirs("pr");
      if (names === null) {
        el.innerHTML = '<li class="meta">Couldn\\'t reach the GitHub API (rate limit or offline). Try a direct link like <code>./pr/pr-123/</code>.</li>';
        return;
      }
      if (names.length === 0) {
        el.innerHTML = '<li class="meta">No open PR previews right now.</li>';
        return;
      }
      // Annotate each pr-<N> with its title/state when the PR lookup succeeds.
      const nums = names
        .map((n) => ({ name: n, num: Number((n.match(/^pr-(\\d+)$/) || [])[1]) }))
        .filter((p) => Number.isFinite(p.num))
        .sort((a, b) => b.num - a.num);
      const meta = await Promise.all(
        nums.map(async (p) => {
          try {
            const res = await api("/pulls/" + p.num);
            if (!res.ok) return null;
            const pr = await res.json();
            return { title: pr.title, state: pr.state, draft: pr.draft };
          } catch {
            return null;
          }
        }),
      );
      el.innerHTML = nums
        .map((p, i) => {
          const m = meta[i];
          const label = "pr-" + p.num;
          const title = m ? esc(m.title) : null;
          const tag = m && m.state !== "open" ? { cls: "closed", text: m.state } : m && m.draft ? { cls: "", text: "draft" } : null;
          return li("./pr/" + p.name + "/", label, title, tag);
        })
        .join("");
      note.textContent = "Previews are latest-only and removed when the PR closes.";
    }

    renderBranches();
    renderPrs();
  </script>
</body>
</html>
`;
}
