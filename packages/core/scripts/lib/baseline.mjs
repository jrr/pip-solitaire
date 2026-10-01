// Another commit's solver, compiled where Node can import it beside this one.
//
// Compiled ReScript sits beside its source as `.res.mjs` and imports
// `@rescript/runtime` by bare name, which Node resolves by walking up to a
// `node_modules`. A copy outside the workspace finds none, so the copy goes under
// `packages/core/.baseline/<sha>/`, whose walk reaches core's own. It is built by
// core's own compiler, from the commit's `src/` and `rescript.json` alone, and
// kept: a second run against the same commit only imports it.

import { execFileSync } from "node:child_process"
import { existsSync, mkdirSync, readdirSync, rmSync, unlinkSync } from "node:fs"
import { dirname, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const core = resolve(dirname(fileURLToPath(import.meta.url)), "../..")
const git = (...args) => execFileSync("git", args, { cwd: core, encoding: "utf8" }).trim()

// What "main's build" means for a branch: where the branch left it, so a solver change
// merged to main since isn't charged to this one. A shallow clone may not reach that
// far back, and then the tip is the best there is — said, not hidden.
export function resolveBase(ref) {
  const tip = git("rev-parse", "--verify", `${ref}^{commit}`)
  try {
    return { sha: git("merge-base", "HEAD", tip), said: `the merge base with ${ref}` }
  } catch {
    return { sha: tip, said: `${ref}'s tip (no merge base in this clone)` }
  }
}

export function buildBaseline(sha) {
  const dir = join(core, ".baseline", sha.slice(0, 12))
  const src = join(dir, "src")
  if (existsSync(join(src, "Solver.res.mjs"))) return src
  rmSync(dir, { recursive: true, force: true })
  mkdirSync(dir, { recursive: true })
  execFileSync("sh", ["-c", `git archive ${sha} src rescript.json | tar -x -C "${dir}"`], { cwd: core })
  // The tests import vitest, which the copy has no reason to resolve.
  for (const file of readdirSync(src)) if (file.endsWith("_test.res")) unlinkSync(join(src, file))
  execFileSync(join(core, "node_modules/.bin/rescript"), ["build"], { cwd: dir, stdio: "inherit" })
  return src
}
