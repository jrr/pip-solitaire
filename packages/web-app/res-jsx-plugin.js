// Lower the JSX that ReScript leaves in its compiled output onto Preact, for
// every Vite pipeline that reads that output: the app build, the dev server and
// the unit-test run all import this one plugin.
//
// It exists because `.res.mjs` is not a JSX extension and Vite's own transform
// infers the language from the extension alone — `oxc.jsx` says what JSX becomes
// but nothing in that option says a `.mjs` file may contain any. `lang` is the
// knob that does, and `transformWithOxc` is where Vite exposes it.
//
// docs/rendering.md § The JSX settings, in three places is the rest of the story.
import { transformWithOxc } from "vite";

const resModuleRE = /\.res\.mjs$/;

export const resJsxPlugin = {
  name: "pip-res-jsx",
  // Ahead of Vite's own transform, so that by the time anything else parses the
  // module the JSX is already gone. That's what lets the `.res.mjs` files travel
  // through the bundler untouched by any of the extension-keyed machinery.
  enforce: "pre",
  async transform(code, id) {
    if (!resModuleRE.test(id)) return null;
    const { code: transformed, map } = await transformWithOxc(code, id, {
      lang: "jsx",
      jsx: { runtime: "automatic", importSource: "preact" },
    });
    return { code: transformed, map };
  },
};
