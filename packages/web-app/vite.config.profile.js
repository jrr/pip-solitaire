import base from "./vite.config.js";

// The build `mise run profile` measures. It differs from the shipped one in
// exactly two settings, and both exist to make a stack frame readable:
//
//   minify: false   a minified frame is `i` or `wb`, and a ranked list of those
//                   names is unreadable. Unminified, the bundle carries the
//                   ReScript binding names — `applyMove`, `autoCollect` — which
//                   is what the profile prints and what you grep the `.res` for.
//   sourcemap       …except that bundling still collides same-named bindings
//                   into `advance$1`, and a name alone doesn't say which module
//                   it came from. The map turns a frame's position into
//                   `src/scenes/TableScene.res.mjs:334`. Both halves are needed.
//
// Nothing else is touched — same plugins, same PWA, same `define`s — so what the
// profile measures stays as close to the shipped bundle as a readable frame
// allows. The cost is a bundle about twice the size, which is why this goes to
// its own `outDir` rather than over `dist/`: `browsertest`, `screenshots` and
// `autoplay` all serve `dist/`, and none of them should be handed this one.
//
// `keepNames` is the option that looks like it belongs here and doesn't: it sets
// each function's `.name` property, which V8's stack traces don't read, so trace
// frames stay minified.
export default {
  ...base,
  build: { ...base.build, minify: false, sourcemap: true, outDir: "dist-profile" },
};
