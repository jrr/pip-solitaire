// Frame capture: drive a scene in a headless browser and write out what it
// looked like, frame by frame, plus a contact sheet of the run.
//
// This exists because "does the animation look right?" is the one question the
// rest of the toolchain can't answer. `mise run test` is jsdom, so it has no
// motion at all; `mise run browsertest` can *measure* an animation but only
// reports numbers; `mise run screenshots` shoots one still per scene. None of
// them shows a trajectory. This does — and the PNGs it writes are readable by a
// human and by an agent (both can look at an image), which is what makes a
// judgement about *feel* possible at all.
//
//   mise run capture -- "?scene=freecell&state=finish"
//   mise run capture -- "?scene=freecell&seed=1" --steps 180 --every 4 --hz 120
//   mise run capture -- "?scene=freecell&state=midgame" --real --reduced-motion
//
// ## The clock
//
// By default the run does NOT use wall-clock time. It installs a fake clock
// before any app code loads and advances it in fixed increments, so a capture is
// reproducible: the same URL and the same flags give the same frames, on a busy
// CI runner as on a quiet laptop. That matters for anything seeded — a physics
// effect that claims "this seed replays exactly" can be *checked* rather than
// asserted — and it's the only way to shoot a refresh rate the host doesn't
// have (`--hz 120`) or a frame long enough to exercise dt clamping
// (`--hz 2`).
//
// Two clocks have to move together for that to hold:
//
//   - `requestAnimationFrame` + `performance.now()`, which is what canvas
//     animation loops run on. Faked outright: callbacks queue up and only run
//     when the stepper says so.
//   - Web Animations (`element.animate`), which is what the deal and finish
//     sweeps use. Those run on the compositor's own clock, which a page script
//     can't fake — so they're paused and their `currentTime` is scrubbed in
//     lockstep with the fake clock instead. Scrubbing past the end still fires
//     `onfinish`, so sweep-completion logic behaves normally.
//
// `Date.now` is deliberately left real: nothing in the app animates off it, and
// faking it breaks Vite's client. If that ever changes, fake it here rather than
// working around it at the call site.
//
// `--real` opts out of all of the above and captures against wall-clock time.
// Use it to sanity-check that the fake clock isn't lying — a real-time capture
// and a fake-clock capture of the same scene should look the same.
import { startPreview, launchChromium, assertBundled, webAppRoot } from "../lib/preview-app.mjs"
import fs from "node:fs"
import path from "node:path"

const DEFAULTS = {
  steps: 120,
  every: 6,
  hz: 60,
  width: 900,
  height: 640,
  dpr: 2,
  wait: ".stacking-card",
  settle: 0,
  cols: 4,
  out: path.join(webAppRoot, "capture"),
}

function parseArgs(argv) {
  const opts = { ...DEFAULTS, real: false, reducedMotion: false, query: null }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === "--real") opts.real = true
    else if (a === "--reduced-motion") opts.reducedMotion = true
    else if (a.startsWith("--")) {
      const key = a.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase())
      if (!(key in opts)) throw new Error(`unknown flag ${a}`)
      const value = argv[++i]
      if (value === undefined) throw new Error(`${a} needs a value`)
      opts[key] = typeof DEFAULTS[key] === "number" ? Number(value) : value
    } else if (opts.query === null) opts.query = a
    else throw new Error(`unexpected argument ${a}`)
  }
  if (opts.query === null) {
    throw new Error(
      'a scene query is required, e.g. mise run capture -- "?scene=freecell&state=finish"',
    )
  }
  // Tolerate both `?scene=...` and `scene=...`, since the leading `?` is easy to
  // lose to shell quoting.
  if (!opts.query.startsWith("?") && !opts.query.startsWith("/")) opts.query = `?${opts.query}`
  return opts
}

// Installed with `addInitScript`, so it lands before the app's own bundle runs
// and no animation can start on the real clock behind our back.
function installFakeClock() {
  let now = 0
  let queue = []
  const owned = new WeakSet()

  const realRaf = globalThis.requestAnimationFrame.bind(globalThis)
  globalThis.requestAnimationFrame = (cb) => queue.push(cb) || queue.length
  globalThis.cancelAnimationFrame = (id) => {
    // Ids are 1-based positions into the pending queue; a cancelled callback is
    // blanked rather than spliced out so the other ids stay valid.
    if (queue[id - 1]) queue[id - 1] = null
  }
  performance.now = () => now

  // Take ownership of a Web Animation: pause it and pin it to the fake clock.
  //
  // Doing this at *creation* rather than at the next step is what makes a
  // capture reproducible. An animation that starts between two steps would
  // otherwise keep running on the compositor's real clock for however long the
  // step's round trip took — a millisecond or two of wall-clock leaking into
  // every flight, different on every run. The deal and finish sweeps create
  // animations continuously, so that leak is the whole difference between a
  // capture that replays identically and one that doesn't.
  const own = (anim) => {
    if (!anim || owned.has(anim)) return anim
    owned.add(anim)
    anim.pause()
    try {
      anim.currentTime = now
    } catch {
      // A finished or cancelled animation rejects the write; nothing to do.
    }
    return anim
  }

  const realAnimate = Element.prototype.animate
  Element.prototype.animate = function (...args) {
    return own(realAnimate.apply(this, args))
  }

  globalThis.__capture = {
    // Advance the fake clock by `ms` and run everything that was waiting on it.
    step(ms) {
      now += ms
      // `animate` is owned at birth above; this sweep catches the rest — CSS
      // transitions and keyframe animations, which the engine starts on its own.
      for (const anim of document.getAnimations()) {
        own(anim)
        try {
          anim.currentTime = now
        } catch {
          // Finished or cancelled; nothing to do.
        }
      }
      // Snapshot and clear before running: a callback that re-arms itself (every
      // animation loop does) must land in the *next* step, not this one.
      const due = queue
      queue = []
      for (const cb of due) if (cb) cb(now)
    },
    // Let the real rAF through once, so a paint can happen between steps.
    paint: () => new Promise((res) => realRaf(() => res())),
    pending: () => queue.length,
    now: () => now,
  }
}

const capture = async (opts) => {
  assertBundled("capture")
  fs.rmSync(opts.out, { recursive: true, force: true })
  fs.mkdirSync(opts.out, { recursive: true })

  const { base, close } = await startPreview()
  const browser = await launchChromium()
  const page = await browser.newPage({
    viewport: { width: opts.width, height: opts.height },
    deviceScaleFactor: opts.dpr,
    reducedMotion: opts.reducedMotion ? "reduce" : "no-preference",
  })

  if (!opts.real) await page.addInitScript(installFakeClock)

  const target = `${base}/${opts.query}`
  await page.goto(target, { waitUntil: "load" })
  if (opts.wait) await page.waitForSelector(opts.wait, { timeout: 15_000 })
  await page.evaluate(() => document.fonts.ready)
  if (opts.settle) await page.waitForTimeout(opts.settle)

  const stepMs = 1000 / opts.hz
  const shots = []

  // Burn one frame before capturing. The app's first painted frame is the only
  // one whose raster isn't reproducible — a card already in flight at page load
  // lands a few pixels differently depending on when the first compositor commit
  // happens. Stepping once and letting a real frame through puts frame 0 on the
  // same footing as every frame after it, which is what makes a whole run
  // byte-identical to the run beside it.
  if (!opts.real) {
    await page.evaluate((ms) => globalThis.__capture.step(ms), 0)
    await page.evaluate(() => globalThis.__capture.paint())
  }

  for (let i = 0; i < opts.steps; i++) {
    if (opts.real) await page.waitForTimeout(stepMs)
    else await page.evaluate((ms) => globalThis.__capture.step(ms), stepMs)

    if (i % opts.every !== 0) continue
    const name = `frame-${String(i).padStart(4, "0")}.png`
    await page.screenshot({ path: path.join(opts.out, name) })
    shots.push({ name, frame: i, ms: +(i * stepMs).toFixed(1) })
  }

  // The contact sheet: every shot on one page, labelled with the frame number
  // and the simulated time it was taken at. This is the artifact worth looking
  // at — a single image that shows the whole trajectory.
  const sheet = await browser.newPage({ viewport: { width: 1400, height: 900 } })
  const cells = shots
    .map((s) => {
      const data = fs.readFileSync(path.join(opts.out, s.name)).toString("base64")
      return `<figure>
        <img src="data:image/png;base64,${data}" alt="frame ${s.frame}">
        <figcaption>#${s.frame} · ${s.ms}ms</figcaption>
      </figure>`
    })
    .join("")
  await sheet.setContent(`<body>
    <h1>${opts.query}</h1>
    <p>${shots.length} of ${opts.steps} frames · ${opts.real ? "wall clock" : `fake clock, ${opts.hz}Hz`}
       · ${opts.width}×${opts.height} @${opts.dpr}x${opts.reducedMotion ? " · reduced motion" : ""}</p>
    <div class="grid">${cells}</div>
    <style>
      body { margin: 0; padding: 14px; background: #0f172a; color: #e2e8f0;
             font: 13px/1.4 ui-sans-serif, system-ui, sans-serif; }
      h1 { font-size: 15px; margin: 0 0 2px; color: #86efac; font-family: ui-monospace, monospace; }
      p { margin: 0 0 12px; color: #94a3b8; }
      .grid { display: grid; grid-template-columns: repeat(${opts.cols}, 1fr); gap: 6px; }
      figure { margin: 0; }
      img { width: 100%; display: block; border: 1px solid #334155; }
      figcaption { padding: 3px 1px; color: #94a3b8; font-family: ui-monospace, monospace; }
    </style>
  </body>`)
  const sheetPath = path.join(opts.out, "sheet.png")
  await sheet.screenshot({ path: sheetPath, fullPage: true })

  await browser.close()
  await close()
  return { sheetPath, shots }
}

const USAGE = `usage: mise run capture -- "?scene=<id>&…" [flags]

  --steps N          frames to advance            (${DEFAULTS.steps})
  --every N          screenshot every Nth frame   (${DEFAULTS.every})
  --hz N             simulated refresh rate       (${DEFAULTS.hz})
  --real             use wall-clock time instead of the fake clock
  --reduced-motion   emulate prefers-reduced-motion: reduce
  --width/--height N viewport size                (${DEFAULTS.width}×${DEFAULTS.height})
  --dpr N            device pixel ratio           (${DEFAULTS.dpr})
  --wait SELECTOR    await this before capturing  (${DEFAULTS.wait})
  --settle MS        wall-clock pause before the first step (${DEFAULTS.settle})
  --cols N           contact sheet columns        (${DEFAULTS.cols})
  --out DIR          output directory             (packages/web-app/capture)`

// A bad flag or a missing scene is a usage mistake, not a crash. Print what's
// wrong and how to spell it instead of a stack trace — the readers here are a
// developer at a terminal and an agent parsing the output, and neither is served
// by twenty frames of node internals.
const rel = (p) => path.relative(process.cwd(), p)
try {
  const opts = parseArgs(process.argv.slice(2))
  const { sheetPath, shots } = await capture(opts)
  console.log(`captured ${shots.length} frames -> ${rel(opts.out)}/`)
  console.log(`contact sheet -> ${rel(sheetPath)}`)
} catch (err) {
  console.error(`capture: ${err.message}\n\n${USAGE}`)
  process.exit(1)
}
// Playwright keeps the preview server's socket alive briefly; nothing left to do.
process.exit(0)
