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

**Anything repeatable belongs in a mise task.** The tasks in `mise.toml` are the
supported set of operations for both developers and agents: they carry the
`depends` that build or bundle first, they work identically in CI, and they're
the only thing an agent on a tight allowlist can reach.

Ad-hoc `node` for genuine one-offs — a throwaway probe, measuring something
before you know whether it's worth keeping — is fine, and is often how a task
starts life. The rule of thumb: **if you run it twice, make it a task.** What's
not fine is reaching past a task that already exists (`node
packages/web-app/scripts/…` when `mise run screenshots` is right there), because
that skips the `depends` and drifts from what CI does.

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

Cloud sessions run a **SessionStart hook** (`.claude/hooks/session-start.sh`,
wired up in `.claude/settings.json`) that provisions the toolchain before you
start work, so `mise run <task>` should just work in a plain shell from your
first command — nothing to source.

If it didn't run, or you're in some other sandbox without `mise`, do it by hand:

```
source claude-cloud-dev-env.sh   # tools on this shell's PATH too
bash claude-cloud-dev-env.sh     # just provision; `mise run` works after
```

The sourced form additionally puts `node`/`pnpm` on your PATH, which you only
need to call them *directly* — `mise run` resolves a task's pinned tools itself.

## Seeing the app move

`mise run capture` shoots one scene frame by frame and writes a contact sheet:

```
mise run capture -- "?scene=freecell&state=finish"
mise run capture -- "?scene=freecell&seed=1" --steps 180 --hz 120
```

Reach for it when the question is about *motion* — timing, trajectory, whether
an effect reads right — which the other tools can't answer: `test` is jsdom and
has no motion, `browsertest` measures an animation but only reports numbers, and
`screenshots` shoots one still per scene.

It runs on a fake clock by default, so a capture is reproducible frame for frame
and can shoot refresh rates and frame durations the host doesn't have. The
script header (`packages/web-app/scripts/capture/frames.mjs`) documents exactly
which clocks it owns; read it before trusting a capture of something new.

Both the images it writes and the report from `mise run screenshots` are worth
actually looking at — agents can read PNGs, so "does this look right?" is a
question you can answer yourself rather than escalate.

## Permissions (for CI agents)

The `@claude` GitHub agent runs under a deliberately **tight** allowlist (see
`--allowedTools` in `.github/workflows/claude.yml`):

- Bash is limited to `mise run`, `mise tasks`, `mise install`, and
  `gh pr create`. Note this rules out ad-hoc `node`, which an interactive
  session *can* run — so a probe you wrote by hand has to become a task before
  the CI agent can reuse it.
- Web access is limited to specific docs domains via domain-scoped `WebFetch`
  (`rescript-lang.org`, `pnpm.io`, `mise.jdx.dev`, `playwright.dev`,
  `developer.mozilla.org`, `raw.githubusercontent.com`). There is no open web
  or `WebSearch`.

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

### Network in a claude cloud session (different constraint entirely)

The allowlist above is a *tool* allowlist, and it only binds the GitHub agent —
the Actions runner itself has open internet. A **cloud session** is the opposite:
tools are unrestricted, but the VM sits behind an egress policy set on the cloud
environment, not by this repo. On the default **Trusted** level that policy
allows package registries and GitHub and denies everything else, which means
`rescript-lang.org`, `developer.mozilla.org`, `playwright.dev`, `pnpm.io` and
`mise.jdx.dev` all fail with a `403` at CONNECT — the exact domains the workflows
grant.

Two things follow, and the second matters more:

- **Don't diagnose it as a bug.** A 403 from the proxy is a policy denial. It's
  fixed by editing the environment at claude.ai/code (see below), not from here.
- **You can still get the docs.** `raw.githubusercontent.com` is allowed, and
  these projects keep their docs in public repos — MDN's pages are in
  `mdn/content` under `files/en-us/…`, ReScript's site is in
  `rescript-lang/rescript-lang.org`. Read the source rather than guessing from
  memory. `WebSearch` also works, since it runs server-side, but it returns
  snippets rather than pages.

To widen it: open the environment selector at claude.ai/code (the cloud icon
above the message box), edit the environment, set **Network access** to
**Custom**, tick *"Also include default list of common package managers"*, and
add the domains. There's no repo-side setting for this.

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
