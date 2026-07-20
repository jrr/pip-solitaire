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

Every task runs through `mise`, so a sandbox where `mise` isn't on `PATH`
leaves you unable to run *anything* — `mise tasks`, `mise run ci`, and the rest
all fail with `command not found`.

**Bootstrap the toolchain in one step by sourcing the setup script from the
repo root:**

```
source claude-cloud-dev-env.sh
```

It installs `mise`, trusts this repo's `mise.toml`, installs the pinned tools,
and activates them for the current shell. `source` it rather than executing it,
so the environment it sets up lands in your shell and every later `mise run …`
inherits it. After it finishes, `mise tasks` / `mise run ci` work as normal.

Why the script does what it does (all to stay inside a restricted egress
policy — see the file's comments for detail):

- It installs `mise` from the **npm registry** (`npm install -g mise`), not the
  `curl https://mise.run | sh` installer. `mise.run` is often denied (proxy
  `403`); the npm registry is allowlisted, and Node is already present since
  this is a pnpm repo. Don't route around a policy denial — use the source
  that's already allowed. (Also avoid `cargo install mise` — slow from-source
  build — and `cargo binstall`, which pulls from GitHub release assets a
  restricted proxy often blocks.)
- It exports `MISE_USE_VERSIONS_HOST=false` so mise resolves tool versions from
  each backend's own host (nodejs.org, the npm registry) instead of its
  aggregator at `mise-versions.jdx.dev`, which a locked-down policy blocks —
  otherwise every tool resolution emits noisy retry warnings. Note this is
  **not** `MISE_CHECK_VERSION`: mise reads `MISE_<TOOL>_VERSION` as a per-tool
  version pin, so `MISE_CHECK_VERSION=0` invents a phantom tool called "check"
  and errors with "check not found in mise tool registry" — don't use it.

Sourcing only fixes the *current* session; a fresh sandbox starts without
`mise` again. For a durable fix, wire `source claude-cloud-dev-env.sh` into the
environment's setup script (or grant a network policy that permits `mise.run`)
— that's a human decision, so flag it in your PR/comment rather than assuming
it.

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

## Formatting

Code is formatted by ReScript's own formatter. **Run `mise run format` before
committing** so your changes match the canonical style. CI enforces this: the
`ci` task runs `format-check`, which fails if any file would be reformatted, so
an unformatted file will turn the build red.

Developers get format-on-save automatically via the workspace settings in
`.vscode/` (install the recommended ReScript extension when VS Code prompts).

## Conventions

- Prefer a framework's own CLI (invoked through a mise task) over hand-writing
  files it would generate.
- Keep code formatted — run `mise run format` (or rely on format-on-save)
  before committing; CI's `format-check` rejects unformatted code.
- Consult the latest official docs (allowed domains above) rather than relying
  on memory for framework specifics.
- Leave the `hello` / `hello-cli` example packages in place for now; they exist
  to exercise CI and the agents.
