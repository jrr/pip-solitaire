// Minimal ReScript bindings to the parts of Vitest we use, kept local (as in the
// `core` package) so the test setup has no dependency beyond `vitest` itself.
// Extend as more matchers are needed.

type assertion<'a>

@module("vitest") external test: (string, unit => unit) => unit = "test"
// The same `test`, for a body that has to await something — Vitest waits on a
// returned promise. A separate binding rather than a variant of the one above
// because ReScript won't let one external have two return shapes.
@module("vitest") external testAsync: (string, unit => promise<unit>) => unit = "test"
@module("vitest") external describe: (string, unit => unit) => unit = "describe"
@module("vitest") external expect: 'a => assertion<'a> = "expect"

@send external toBe: (assertion<'a>, 'a) => unit = "toBe"
@send external toEqual: (assertion<'a>, 'a) => unit = "toEqual"
