// Import a compiled ReScript module that carries JSX (see src/Html.res).
//
// Under `"jsx": {"preserve": true}` the compiler emits real JSX into the
// `.res.mjs` output and leaves the lowering to the bundler. That's exactly what
// we want in the app (Vite's esbuild pass does it), but it means bare Node can
// no longer `import` those files — `<svg …>` is a syntax error there, and the
// build scripts that render art without a browser (`generate/icons.mjs`) do
// import them.
//
// So they come through esbuild first: bundle the module, lower its JSX onto
// Preact, and import the result from memory. Nothing is written to disk.
//
// This is a real cost of preserve mode, and worth weighing against the
// alternative: with the *generic* JSX transform (no `preserve`) the output is
// plain function calls that Node runs as-is, and this file wouldn't exist.
import { build } from "esbuild";

export async function loadJsxModule(entryPath) {
  const result = await build({
    entryPoints: [entryPath],
    bundle: true,
    write: false,
    format: "esm",
    platform: "node",
    // `.res.mjs` isn't a JSX extension, so say so explicitly — same three
    // settings the app build uses (see vite.config.js).
    loader: { ".mjs": "jsx" },
    jsx: "automatic",
    jsxImportSource: "preact",
  });
  const code = result.outputFiles[0].text;
  return import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`);
}
