import { defineConfig } from "vitest/config"
import { resJsxPlugin } from "./res-jsx-plugin.js"

// ReScript compiles in-source to `.res.mjs` (see rescript.json). Tests live in
// `*_test.res` files, so run the compiled `*_test.res.mjs` output — this doesn't
// match Vitest's default `.test.`/`.spec.` glob, so we set an explicit include.
//
// The runtime under test (Html) drives the real DOM, so these tests need a DOM:
// the `jsdom` environment provides `document`, `createElementNS`, namespaces and
// attribute reflection.
export default defineConfig({
  // The compiled output carries JSX under `"preserve": true` (see rescript.json),
  // so the test run needs the same lowering the app build gets — the same plugin,
  // for that reason. See docs/rendering.md.
  plugins: [resJsxPlugin],
  test: {
    environment: "jsdom",
    include: ["src/**/*_test.res.mjs"],
  },
})
