#!/usr/bin/env bash
# SessionStart hook: provision the mise toolchain before Claude starts working.
#
# Without this, every cloud session opens with no `mise` on PATH, and the agent
# either rediscovers `claude-cloud-dev-env.sh` from CLAUDE.md or — worse —
# quietly reaches for the pre-installed system node instead of the pinned one.
# Running the bootstrap here means `mise run <task>` works in a plain shell from
# the first command, with nothing sourced (mise resolves a task's pinned tools
# itself; see the bootstrap script's header).
#
# Cloud only: a local checkout already has whatever the developer installed, and
# `CLAUDE_CODE_REMOTE` is only ever "true" on a session VM.
#
# This must never block a session, so every path exits 0. A failure prints the
# manual fix instead of stopping work.
set -u

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

if bash claude-cloud-dev-env.sh >/dev/null 2>&1; then
  echo "Toolchain ready: run repo tasks with 'mise run <task>' ('mise tasks' lists them). No sourcing needed."
else
  echo "Toolchain bootstrap failed. Run 'source claude-cloud-dev-env.sh' by hand and report the error." >&2
fi

exit 0
