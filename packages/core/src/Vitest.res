// Minimal ReScript bindings to the parts of Vitest we use. Kept local rather
// than pulling in a third-party binding package so the test setup has no
// dependencies beyond `vitest` itself. Extend as more matchers are needed.
//
// If maintaining these bindings by hand becomes too burdensome, we could switch
// to https://github.com/cometkim/rescript-vitest instead.
//
// **The copy worth extending.** `cli` and `web-app` both depend on `core`, so both
// reach these bindings from here; add what you need here rather than starting a second
// `Vitest.res` in a dependent. That's a preference now, not a prohibition. It used to
// be one: module names are global across a ReScript build graph, so before `cli` and
// `web-app` were namespaced (#299) a second `Vitest` there displaced `core`'s copy in
// `core`'s own build — web-app carried such a duplicate; it built for months and then
// failed the moment a `core` test happened to need rebuilding mid-dependency-build.
// With `"namespace": true` on both leaf packages, a duplicate now shadows this module
// only inside the package that defines it, which is a local decision with a local
// error message rather than a spooky one in `core`.

type assertion<'a>

@module("vitest") external test: (string, unit => unit) => unit = "test"
// The same `test`, for a body that has to await something — Vitest waits on a
// returned promise. A separate binding rather than a variant of the one above
// because ReScript won't let one external have two return shapes.
@module("vitest") external testAsync: (string, unit => promise<unit>) => unit = "test"
// The same `test` again, with Vitest's per-test timeout (milliseconds) instead of
// its 5-second default — for a body that legitimately takes longer, like the
// solver soak in `Solver_test`, which would otherwise flake on a slow machine
// rather than fail for a reason worth reading.
@module("vitest")
external testWithin: (string, unit => unit, ~timeout: int) => unit = "test"
@module("vitest") external describe: (string, unit => unit) => unit = "describe"
@module("vitest") external expect: 'a => assertion<'a> = "expect"

@send external toBe: (assertion<'a>, 'a) => unit = "toBe"
@send external toEqual: (assertion<'a>, 'a) => unit = "toEqual"
