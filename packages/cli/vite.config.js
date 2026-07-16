import { defineConfig } from "vite";

// Bundle the CLI into a single self-contained Node script so it can be run
// with `node dist/cli.js` without needing the workspace symlinks at runtime.
// `build.ssr` targets Node (no browser polyfills, no code-splitting), and
// `ssr.noExternal` inlines the workspace `core` module and the ReScript runtime
// rather than leaving them as bare imports Node couldn't resolve from `dist/`
// (the runtime lives in pnpm's store, not hoisted next to the built script).
export default defineConfig({
  build: {
    ssr: "src/Cli.res.mjs",
    target: "node20",
    outDir: "dist",
    rollupOptions: {
      output: { entryFileNames: "cli.js" },
    },
  },
  ssr: {
    noExternal: ["core", "@rescript/runtime"],
  },
});
