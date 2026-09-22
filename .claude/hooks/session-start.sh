#!/bin/bash
# Bring a Claude Code on the web container up to the point where `mise run …`
# works, so a session can use the task interface (CLAUDE.md § The task
# interface) without a human pasting the bootstrap in first.
#
# The bootstrap itself is not duplicated here: `claude-cloud-dev-env.sh` at the
# repo root is the one copy, sourced below, and is still what you run by hand in
# a shell it hasn't reached. This file is only the two things a hook can do that
# sourcing in one shell can't — run it before the session starts, and publish the
# resulting PATH to every later shell via $CLAUDE_ENV_FILE.
#
# Local machines are left alone (they have their own mise); this is web-only.
set -euo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")}"

# shellcheck source=../../claude-cloud-dev-env.sh
source ./claude-cloud-dev-env.sh

# node_modules is the slow half, and the container image is cached once this
# hook finishes — so installing here is what a later `mise run test` doesn't pay.
mise run install

# `mise env` would bake a whole PATH snapshot into the session; the shim
# directory is a fixed path that dispatches to the pinned versions instead, so
# a bare `node`/`pnpm` resolves in every later shell. `mise run` needs none of
# this — it resolves tools itself — which is why the tasks work either way.
mise reshim
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo 'export PATH="$HOME/.local/share/mise/shims:$PATH"' >> "$CLAUDE_ENV_FILE"
fi
