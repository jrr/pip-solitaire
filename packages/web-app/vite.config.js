import { defineConfig } from "vite"

// Vite bundles the ReScript-compiled ESM (`.res.mjs`) in this package into a
// static site under `dist/`. ReScript compiles first (`mise run build`), then
// Vite bundles — see the `bundle` task in `mise.toml`.
//
// `base: "./"` makes every emitted asset URL relative, so the built site works
// unchanged when GitHub Pages serves it from a project subpath
// (https://<user>.github.io/<repo>/) rather than a domain root.
export default defineConfig({
  base: "./",
})
