# shellcheck shell=bash
# claude-cloud-dev-env.sh — bootstrap the mise toolchain in a sandboxed
# Claude Code cloud/CI session.
#
#   source claude-cloud-dev-env.sh
#
# In these sandboxes mise isn't preinstalled and outbound egress is
# restricted, so a plain `mise run` trips on two things: mise itself has to be
# installed from a host that's actually reachable, and mise's default
# version-lookup host isn't reachable. This script handles both, then
# activates the toolchain for the current shell.
#
# SOURCE it, don't execute it: the vars it exports and the PATH it sets up must
# land in your *current* shell so every later `mise run …` in the session
# inherits them. Running it in a subshell would throw that away. Run it from
# the repo root (where mise.toml lives).

# Resolve version lists from each tool's own backend host instead of mise's
# aggregator at mise-versions.jdx.dev, which a locked-down egress policy blocks
# (producing noisy retry warnings on every tool resolution). With this off,
# node resolves from nodejs.org and `npm:pnpm` from the npm registry — both
# allowlisted.
#
# NB: do NOT use `MISE_CHECK_VERSION` here. mise reads `MISE_<TOOL>_VERSION` as
# a per-tool version pin, so `MISE_CHECK_VERSION=0` doesn't disable a check —
# it invents a phantom tool named "check" pinned to version 0 and then errors
# with "check not found in mise tool registry".
export MISE_USE_VERSIONS_HOST=false

# (Separately, mise's one-time self-update check GETs mise.jdx.dev/VERSION on
# the first invocation in a fresh container; if that host is blocked you'll see
# a single burst of retry warnings during `mise install` below. It's harmless
# and throttled — it doesn't recur — and mise exposes no documented setting to
# disable it, so we let it be rather than hack its cache.)

# Install mise if it isn't already on PATH. The standard installer
# (curl https://mise.run | sh) needs mise.run, which a restricted proxy often
# denies with a 403. The prebuilt npm package comes from the allowlisted npm
# registry instead — and Node is already present because this is a pnpm repo.
if ! command -v mise >/dev/null 2>&1; then
  echo "claude-cloud-dev-env: installing mise from the npm registry…"
  npm install -g mise
fi

# mise refuses to read an untrusted config; trust this repo so its tasks and
# pinned tools become visible.
mise trust >/dev/null

# Install the pinned toolchain (node + pnpm). pnpm resolves through mise's
# npm-registry backend (see the `npm:pnpm` entry in mise.toml) rather than the
# default aqua backend, which would fetch from GitHub release assets and 403
# in these sandboxes.
mise install

# Put the tool shims (node, pnpm) on PATH for the current shell.
eval "$(mise env)"

echo "claude-cloud-dev-env: ready ($(mise --version)). Run 'mise tasks' to list tasks."
