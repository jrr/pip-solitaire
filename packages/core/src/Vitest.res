// Minimal ReScript bindings to the parts of Vitest we use. Kept local rather
// than pulling in a third-party binding package so the test setup has no
// dependencies beyond `vitest` itself. Extend as more matchers are needed.
//
// If maintaining these bindings by hand becomes too burdensome, we could switch
// to https://github.com/cometkim/rescript-vitest instead.
//
// **The copy worth extending.** `cli` and `web-app` both depend on `core`, so both
// reach these bindings from here; add what you need here rather than starting a second
// `Vitest.res` in a dependent. A preference, not a prohibition — but only because
// `"namespace": true` on both leaf packages confines a duplicate to the package that
// defines it. Drop that namespacing and module names are global across the build graph
// again, so a second `Vitest` displaces this one inside `core`'s *own* build; the
// failure surfaces only when a `core` test happens to need rebuilding
// mid-dependency-build, so such a duplicate can build for months before it breaks.

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

// Float equality with slack, for arithmetic where the exact bits aren't the claim:
// a fit solved one way and stated another agree to the precision anyone can see, not
// necessarily to the last mantissa bit. Vitest's default is two decimal places, which
// is a pixel fraction — where the claim needs to be tighter than that, `toBeCloseToWithin`
// takes the digit count instead. (One external can't have two arities, hence two names.)
@send external toBeCloseTo: (assertion<float>, float) => unit = "toBeCloseTo"
@send external toBeCloseToWithin: (assertion<float>, float, int) => unit = "toBeCloseTo"
