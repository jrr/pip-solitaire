// Import a compiled ReScript module that carries JSX: esbuild bundles it, lowers
// the JSX onto Preact, and the result is imported from memory. Nothing is written
// to disk.
//
// **A Node script that imports compiled ReScript goes through here, not around
// it.** Why bare Node can't do it directly, and what that costs, is
// docs/rendering.md § Node can't import the compiled output.
import { build } from "esbuild";

export async function loadJsxModule(entryPath) {
  const result = await build({
    entryPoints: [entryPath],
    bundle: true,
    write: false,
    format: "esm",
    platform: "node",
    // `.res.mjs` isn't a JSX extension, so say so explicitly — the same three
    // settings the app build uses. The CSS drop is because a component imports its
    // own stylesheet and there is no document here to apply it to.
    loader: { ".mjs": "jsx", ".css": "empty" },
    jsx: "automatic",
    jsxImportSource: "preact",
  });
  const code = result.outputFiles[0].text;
  return import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`);
}
