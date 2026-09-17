import { defineConfig } from "vitest/config"

// ReScript compiles in-source to `.res.mjs` (see rescript.json). Tests live in
// `*_test.res` files, so run the compiled `*_test.res.mjs` output — this doesn't
// match Vitest's default `.test.`/`.spec.` glob, so we set an explicit include.
//
// `vite` is a devDependency of this package even though nothing here builds with
// it: Vitest declares it as a required peer, and core is the one package with no
// bundler of its own to satisfy that. Removing it as unused breaks `mise run test`.
export default defineConfig({
  test: {
    include: ["src/**/*_test.res.mjs"],
  },
})
