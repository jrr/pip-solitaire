# CLAUDE.md

Guidance for Claude (and other agents) working in this repository.

## What this repo is

A pnpm workspace monorepo. Tooling (Node, pnpm, and future compilers) is
pinned and managed by [mise](https://mise.jdx.dev). The target language and
framework is [ReScript](https://rescript-lang.org).

- `packages/*` — workspace packages.
- `mise.toml` — pinned tools (`[tools]`) and the task interface (`[tasks.*]`).
- `.github/workflows/` — CI, plus the `@claude` implementer and review agents.

## The task interface

**Do your work through mise tasks, not ad-hoc shell commands.** The tasks in
`mise.toml` are the supported set of operations for both developers and agents.

```
mise tasks          # list available tasks
mise run <task>     # run one (install, build, test, format, start, rescript, ci)
mise run format     # format all ReScript source in place
mise run ci         # install → build → test → format-check, exactly what CI runs
```

Tasks wrap the underlying tools (`pnpm`, and framework CLIs like `rescript`),
so running `mise run build` is how you invoke those tools — you don't call them
directly.

### Passing arguments / passthrough tasks

mise forwards anything after `--` to a task's command, and that whole
invocation is still covered by the `Bash(mise run:*)` allowlist. So a single
**passthrough task** can expose a tool's *entire* CLI surface without widening
the Bash allowlist at all. The `rescript` task does this for the ReScript
compiler:

```
mise run rescript -- core build -w     # rescript build -w, in packages/core
mise run rescript -- core format -all  # rescript format -all, in packages/core
```

Prefer this over asking for raw `pnpm`/`npx` access: to reach a new subcommand
of a tool you already have a passthrough for, just pass it after `--`.

### When `mise` isn't installed (sandboxed agents)

This project uses mise as a command runner, but if you're in a claude cloud
sandbox you probably can't install it the normal way. Instead, source
`claude-cloud-dev-env.sh` from the repo root:

```
source claude-cloud-dev-env.sh
```

It installs `mise`, trusts the repo, installs the pinned tools, and activates
them for the current shell — after which `mise tasks` / `mise run ci` work as
normal. This only fixes the current session; wiring it into the environment's
setup script is a human decision, so flag it rather than assuming it.

## Permissions (for CI agents)

The `@claude` GitHub agent runs under a deliberately **tight** allowlist (see
`--allowedTools` in `.github/workflows/claude.yml`):

- Bash is limited to `mise run`, `mise tasks`, `mise install`, and
  `gh pr create`.
- Web access is limited to specific toolchain-docs domains
  (`rescript-lang.org`, `pnpm.io`, `mise.jdx.dev`) via domain-scoped
  `WebFetch`. There is no open web or `WebSearch`.

This is intentional. When you need a capability you don't have, **widen the
interface, not the allowlist**:

- **Need a new operation** (format, codegen, scaffold, lint, …)? Add a
  `mise` task for it and call it via `mise run`. Prefer this over requesting
  raw `pnpm`/`npx`/shell access. To expose a tool's *whole* CLI in one task,
  make it a passthrough (see “Passing arguments” above).
- **Need docs from another domain**? Add a specific
  `WebFetch(domain:<host>)` entry to the workflow — not blanket `WebFetch`.
- **Need something you genuinely can't express as a task or grant yourself?**
  Say so in your PR/comment so a human can decide, and proceed as best you can
  (following the framework's documented conventions) in the meantime.

Keep the review workflow (`claude-code-review.yml`) and the implementer
workflow (`claude.yml`) consistent with this model.

## Pull request lifecycle

When resolving an issue, once the requirements are clearly met and the test
suite is green (`mise run ci`), **open a pull request** rather than reporting
back on the issue. Don't wait to be asked a second time.

- Push your branch and open the PR with `gh pr create`, linking the issue it
  closes.
- Move any remaining discussion, follow-ups, or review to the PR — the issue
  thread is done once the PR exists.
- If the requirements are genuinely ambiguous or CI can't be made green, say so
  on the issue instead of opening a PR, and explain what's blocking.

## Playing the game

The app can be played by an agent, in a real browser, with pointer drags —
`mise run autoplay -- <deal>` plays a deal to the win overlay. Use it to see a
change in the actual game rather than only in tests. Driving the board by hand
(one move, a particular position, a reproduction) is documented as a skill in
`.claude/skills/play-in-browser/`; the harness itself is
`packages/web-app/scripts/autoplay/`.

The thinking behind it lives in `core` — `Position.res` (a FreeCell board packed
for search) and `Solver.res` (the search itself). `mise run solve -- <deal>` runs
that alone, with no browser: seconds instead of a minute, so it's what you
measure a solver change with before playing one for real.

## Formatting

Code is formatted by ReScript's own formatter. **Run `mise run format` before
committing** so your changes match the canonical style. CI enforces this: the
`ci` task runs `format-check`, which fails if any file would be reformatted, so
an unformatted file will turn the build red.

Developers get format-on-save automatically via the workspace settings in
`.vscode/` (install the recommended ReScript extension when VS Code prompts).

## Rendering

The web app's UI is ReScript JSX compiled in **preserve mode** onto **Preact**:
the compiler emits real JSX into the `.res.mjs` output and the bundler lowers it
(see `packages/web-app/src/runtime/Html.res`, which holds the bindings and the reasoning).
Two consequences worth knowing before you touch the build:

- **The same three esbuild settings live in three places** — `vite.config.js`
  twice (the build's transform and the dev server's dependency scanner take
  different paths, and the scanner keys its loader on `.js` even for `.mjs`
  files) and `vitest.config.js` once. Nothing checks that they agree, so
  `mise run dev-smoke` boots the dev server and fails if it complains.
- **Node can't `import` the compiled output directly** where it carries JSX. A
  build script that needs a ReScript module goes through
  `scripts/lib/load-jsx-module.mjs`, which lowers it with esbuild first.

Attributes are typed props on `Html.elementProps`, not a generic string map:
adding an attribute the app has never used means adding a field there.

## Where things live

`src/` is filed by **who owns the DOM**, which is the distinction the code
actually enforces. Module names are flat regardless of nesting (`namespace: true`
with `subdirs: true`), so a directory is a filing decision, not a namespace — and
a file can be moved without touching a single import.

```
src/
  Main.res         the entry point; `index.html` links this path, so it stays put
  runtime/         Html, StaticRender, and the DOM bindings (WebDom, TestDom)
  components/      pure `props => vnode`; `menu/` holds the slide-over's own
  scenes/          the imperative layer: Scene, SceneSwitcher, the board, the demos
  cards/           pure producers of card vnodes and bitmaps; the app icon too
  platform/        no DOM — storage, navigator, permissions, document-root attrs
  debug/           dev chrome that owns live DOM (console, log, overlays)
  styles/  fonts/  the foundations no component owns
```

**`components/` has an entry condition**, and it is load-bearing: everything in
there is reachable from `Html.create`, which renders once and throws its host
away, so those modules must stay pure — no hooks, ever (see the note in
`runtime/Html.res`). `debug/DebugConsole.res` is the near miss: it renders a
component shell but owns module-level live DOM, so it is filed by what it owns
rather than by its shape.

Two paths are coupled and will not follow a move on their own: `index.html`
names `./src/Main.res.mjs` and `./src/styles/index.css`, and
`scripts/generate/icons.mjs` names `src/cards/IconArt.res.mjs`.

## Styling

CSS is **one file per component**, next to the component that renders it —
`src/components/TopBar.css` beside `TopBar.res`, `src/scenes/TableScene.css` beside
`TableScene.res` — and **each component imports its own sheet**, with a one-line
`%%raw` at the top of the module:

```rescript
%%raw(`import "./TopBar.css"`)
```

A rule goes in the file for the thing it styles. The foundations no component
owns (faces, reset, app shell, the landscape rail) live in `src/styles/` and are
imported by `src/styles/index.css`, which `index.html` links.

**The cascade is ordered by `@layer`, not by source order.** A component-imported
sheet has no fixed position in the bundle, so `src/styles/index.css` declares the
order once — `foundations, components, scenes, overrides` — and every sheet wraps
its rules in one of those four. Three rules follow, and `src/styles/index.css`
explains each at length:

- **Every sheet must declare a layer.** An unlayered rule beats every layered one
  regardless of specificity, so there is no such thing as adding "just one"
  unlayered file.
- **A later layer beats an earlier one even when it is less specific.** A rule
  that reaches out of its own component to restyle another (the landscape rail;
  the debug console's dock, which narrows the board) goes in `overrides`.
- **Within a layer, ties still break on source order** — now the module graph's,
  which runs dependency-first. Nothing relies on such a tie; don't add one.

Adding a rule needs no thought. Adding a *file* means wrapping it in the layer it
belongs to and importing it from its component.

Font `url()`s are root-relative (`/fonts/…`) so Vite resolves them from
`public/` — a document-relative `./fonts/…` breaks once the stylesheet is
emitted into `assets/`. See the note in `src/styles/fonts.css`.

CSS is not covered by `mise run format`, and unit tests never evaluate it: the
gate for a styling change is `mise run browsertest` plus a look at
`mise run screenshots`.

## Conventions

- Prefer a framework's own CLI (invoked through a mise task) over hand-writing
  files it would generate.
- Keep code formatted — run `mise run format` (or rely on format-on-save)
  before committing; CI's `format-check` rejects unformatted code.
- Consult the latest official docs (allowed domains above) rather than relying
  on memory for framework specifics.
- The leaf packages (`cli`, `web-app`) set `"namespace": true` in their
  `rescript.json`, so their modules live under `Cli`/`WebApp` and can't collide
  with `core`'s. `core` stays un-namespaced, which is why dependents still say
  `Card`, `Reducer`, `Render` rather than `Core.Card` (#299). A leaf module that
  shares a name with a `core` one shadows it *within that leaf only* — legal, but
  still worth avoiding.
- Leave the `hello` / `hello-cli` example packages in place for now; they exist
  to exercise CI and the agents.
