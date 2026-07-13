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
mise run <task>     # run one (install, build, test, start, rescript, ci)
mise run ci         # install → build → test, exactly what CI runs
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

## Conventions

- Prefer a framework's own CLI (invoked through a mise task) over hand-writing
  files it would generate.
- Consult the latest official docs (allowed domains above) rather than relying
  on memory for framework specifics.
- **Verify versions; don't go on knowledge.** Your training data lags reality,
  so a version you "remember" as latest or as beta may be neither. Before
  pinning or recommending a version of any tool, package, or framework, check
  an authoritative live source (the project's official docs/blog on an allowed
  domain, or the CLI/registry itself via a mise task) and cite what you found.
  This especially applies to "is X stable yet?" judgments — e.g. ReScript 12
  went stable on 2025-11-25, so treat "v12 is still beta" as a memory to
  double-check, not a fact. If you genuinely can't reach a source to confirm,
  say so explicitly rather than asserting a version from memory.
- Leave the `hello` / `hello-cli` example packages in place for now; they exist
  to exercise CI and the agents.
