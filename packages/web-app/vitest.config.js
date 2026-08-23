import { defineConfig } from "vitest/config"

// ReScript compiles in-source to `.res.mjs` (see rescript.json). Tests live in
// `*_test.res` files, so run the compiled `*_test.res.mjs` output — this doesn't
// match Vitest's default `.test.`/`.spec.` glob, so we set an explicit include.
//
// The runtime under test (Html) drives the real DOM, so these tests need a DOM:
// the `jsdom` environment provides `document`, `createElementNS`, namespaces and
// attribute reflection.
export default defineConfig({
  // The compiled output carries JSX under `"preserve": true` (see rescript.json
  // and vite.config.js); the test run needs the same lowering the app build gets.
  esbuild: {
    include: [/\.res\.mjs$/, /\.[jt]sx?$/],
    loader: "jsx",
    jsx: "automatic",
    jsxImportSource: "preact",
  },
  test: {
    environment: "jsdom",
    include: ["src/**/*_test.res.mjs"],
  },
})
