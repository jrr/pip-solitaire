# repo scripts

Node scripts behind mise tasks that are **about the repository**, not about one
package. Everything else is package-scoped and lives in `packages/*/scripts/`
(`packages/web-app/scripts/README.md` has that set); a script only belongs here
if filing it under a package would make it look like it measured or built only
that package.

Run them through the task, never with `node` directly — the tasks are the
supported interface (see the repo-root `CLAUDE.md`).

## Script → task → output

| script | task | output |
| --- | --- | --- |
| `comment-census.mjs` | `mise run comment-census` | stdout — comment lines per language and per file, at a commit. `-- --json` for the same data machine-readably, `-- --rev <ref>` for any commit, `-- --help` for the counting rules |

`comment-census` reads `git ls-tree`, not the working tree, so a built
`packages/*/lib/` or `packages/cli/dist/` can't be counted as a second copy of
the sources. It gates nothing — `build-test.yml` prints it after `mise run ci`
and moves on. Why it exists, and the three commits that pin its definition, are
in the script's header.
