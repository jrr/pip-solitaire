// Turning a trace's stack frames back into source.
//
// A frame out of the trace names a position in the bundle — `index-abc123.js`,
// line 4210, column 18 — and a function name. Neither half is enough on its own:
// the bundle renames colliding bindings (two modules with an `advance` give you
// `advance` and `advance$1`), and the file it names is the same file for the
// whole app. The build's sourcemap supplies the other half, so a frame lands on
// `src/scenes/TableScene.res.mjs:1108`.
//
// The consumer is `node:module`'s own `SourceMap`, not a dependency: it is
// exactly the lookup wanted (a position in, a position out) and it ships with
// the runtime.
//
// The **line** is what identifies a call site, not the function name, and the
// line's own text is what's worth printing. A ReScript module compiles to one
// `make` with everything inside it, so the frame that reads a rect mid-drag is
// an anonymous listener inside `make` — a name that would tell you nothing and a
// stack with no better name further out. `let over = zoneAt(wrapper.getBoundingClientRect())`
// tells you what it did.
//
// The position is in the *generated* `.res.mjs`, because that is where the map
// stops: ReScript emits no map of its own from `.res` to `.res.mjs`. Both files
// are on disk, and the generated one is what the source line is read from.

import { SourceMap } from "node:module"
import fs from "node:fs"
import path from "node:path"
import { webAppRoot } from "../lib/preview-app.mjs"

const MAX_SOURCE = 72

/**
 * A resolver over one served build.
 *
 * `base` is the preview origin, and doubles as the test for whether a frame is
 * the app's at all — see `isAppFrame`.
 */
export function frameResolver({ base, outDir }) {
  const maps = new Map()
  const sources = new Map()

  // `null` for a bundle file that carries no map, which is not an error: the
  // frame still resolves, just to the bundle rather than to a module.
  function mapFor(url) {
    if (!maps.has(url)) {
      try {
        const file = path.join(webAppRoot, outDir, new URL(url).pathname)
        const raw = fs.readFileSync(`${file}.map`, "utf8")
        maps.set(url, { map: new SourceMap(JSON.parse(raw)), dir: path.dirname(file) })
      } catch {
        maps.set(url, null)
      }
    }
    return maps.get(url)
  }

  // The generated module, so a call site can quote itself. Missing is fine —
  // a dependency's source needn't be on disk for the position to be useful.
  function lineOf(abs, line) {
    if (!sources.has(abs)) {
      try {
        sources.set(abs, fs.readFileSync(abs, "utf8").split("\n"))
      } catch {
        sources.set(abs, null)
      }
    }
    const text = sources.get(abs)?.[line - 1]?.trim()
    if (!text) return null
    return text.length > MAX_SOURCE ? `${text.slice(0, MAX_SOURCE - 1)}…` : text
  }

  return {
    /**
     * Is this frame the app's own code?
     *
     * The harness measures the board constantly — `readGeometry` reads a rect
     * off every card between drags — and those reads force layout exactly like
     * the app's do. They come from a script Playwright injects, which has no
     * URL to serve from this origin, so an origin test separates the app's
     * forced layout from the cost of watching it. Without it a chunk of the
     * count is the harness's.
     */
    isAppFrame: (frame) => typeof frame?.url === "string" && frame.url.startsWith(base),

    /**
     * `{ site, source }` — where the frame is, and what that line says. `site`
     * is the grouping key, so two frames on one line are one call site.
     */
    resolve(frame) {
      const loaded = mapFor(frame.url)
      // CDP counts lines and columns from zero, and so does `findEntry`.
      const entry = loaded?.map.findEntry(frame.lineNumber, frame.columnNumber)
      if (!entry?.originalSource) {
        const file = path.basename(new URL(frame.url).pathname)
        const name = frame.functionName || "(anonymous)"
        return { site: `${file}:${frame.lineNumber + 1} ${name}`, source: null }
      }
      const abs = path.resolve(loaded.dir, entry.originalSource.replace(/^file:\/\//, ""))
      const line = entry.originalLine + 1
      return {
        site: `${path.relative(webAppRoot, abs)}:${line}`,
        source: lineOf(abs, line),
      }
    },
  }
}
