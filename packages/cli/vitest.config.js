import { defineConfig } from "vitest/config"

// ReScript compiles in-source to `.res.mjs` (see rescript.json). Tests live in
// `*_test.res` files, so run the compiled `*_test.res.mjs` output — this doesn't
// match Vitest's default `.test.`/`.spec.` glob, so we set an explicit include.
export default defineConfig({
  test: {
    include: ["src/**/*_test.res.mjs"],
  },
})
