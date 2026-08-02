# shellcheck shell=bash
# Bootstrap the mise toolchain in a claude cloud sandbox.
#
# Two ways in, and which you want depends on whether you need the tools on your
# own PATH or only need `mise run` to work:
#
#   source claude-cloud-dev-env.sh    # also puts node/pnpm on this shell's PATH
#   bash claude-cloud-dev-env.sh      # just provisions; `mise run <task>` works after
#
# The second form is what the SessionStart hook in .claude/settings.json uses, so
# a cloud session arrives with the toolchain already provisioned and every
# `mise run <task>` works in a plain shell with nothing sourced. That works
# because mise resolves a task's pinned tools itself when it runs the task — the
# `mise env` line below is only needed to call `node`/`pnpm` *directly*.
#
# Everything here is idempotent, so re-running it is cheap.

# Resolve versions from each tool's own host, not mise's aggregator (blocked here).
# (Not MISE_CHECK_VERSION — that's read as a tool-version pin and invents a "check" tool.)
export MISE_USE_VERSIONS_HOST=false

# Install mise from npm; the mise.run installer is blocked, npm is allowlisted.
if ! command -v mise >/dev/null 2>&1; then
  npm install -g mise
fi

mise trust >/dev/null   # mise won't read an untrusted config
mise install            # node + pnpm (pnpm via npm backend; aqua/GitHub is blocked)

# Only meaningful when sourced — an executed script can't change its caller's
# PATH, and doesn't need to (see the header).
eval "$(mise env)"

echo "claude-cloud-dev-env: ready. Run 'mise tasks' to list tasks."
