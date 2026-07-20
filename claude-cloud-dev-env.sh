# shellcheck shell=bash
# Bootstrap the mise toolchain in a claude cloud sandbox. Source it (don't
# execute it) from the repo root so the env and PATH land in your shell:
#   source claude-cloud-dev-env.sh

# Resolve versions from each tool's own host, not mise's aggregator (blocked here).
# (Not MISE_CHECK_VERSION — that's read as a tool-version pin and invents a "check" tool.)
export MISE_USE_VERSIONS_HOST=false

# Install mise from npm; the mise.run installer is blocked, npm is allowlisted.
if ! command -v mise >/dev/null 2>&1; then
  npm install -g mise
fi

mise trust >/dev/null   # mise won't read an untrusted config
mise install            # node + pnpm (pnpm via npm backend; aqua/GitHub is blocked)
eval "$(mise env)"      # put the tool shims on PATH for this shell

echo "claude-cloud-dev-env: ready. Run 'mise tasks' to list tasks."
