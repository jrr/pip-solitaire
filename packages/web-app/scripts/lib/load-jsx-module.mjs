// Import a compiled ReScript module that carries JSX: bundle it through esbuild,
// lower the JSX onto Preact, and import the result from memory. Nothing is written
// to disk. Why bare Node can't do it directly is docs/rendering.md § Node can't
// import the compiled output.
//
// **A Node script that imports compiled ReScript goes through here, not around
// it.**
import { build } from "esbuild";

export async function loadJsxModule(entryPath) {
  const result = await build({
    entryPoints: [entryPath],
    bundle: true,
    write: false,
    format: "esm",
    platform: "node",
    // `.res.mjs` isn't a JSX extension, so say so explicitly — same three
    // settings the app build uses (see vite.config.js). A component also imports
    // its own stylesheet (see the `%%raw` line at the top of CardArt.res, which
    // IconArt pulls in); there's no document here to apply it to, so drop it.
    loader: { ".mjs": "jsx", ".css": "empty" },
    jsx: "automatic",
    jsxImportSource: "preact",
  });
  const code = result.outputFiles[0].text;
  return import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`);
}
