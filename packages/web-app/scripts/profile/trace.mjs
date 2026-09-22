// Recording a Chrome trace of the main thread, and reading it back.
//
// `disabled-by-default-devtools.timeline.stack` is the load-bearing entry in
// the category list below: without it a forced style or layout recalc records
// with no JS stack, and `forcedStyleAndLayout` has nothing to name. Don't drop
// it to slim the trace.
//
// What the numbers mean, and what they can't tell you, is `docs/profiling.md`.

/** Categories: the timeline, its detail, and the stacks that name a call site. */
const CATEGORIES = [
  "devtools.timeline",
  "disabled-by-default-devtools.timeline",
  "disabled-by-default-devtools.timeline.stack",
]

/**
 * Start recording, and hand back the `stop` that ends it and returns the events.
 *
 * Two calls rather than one wrapping a body, because what is worth measuring
 * starts partway into the run: the board has to be loaded and settled first, and
 * a page load under throttling is seconds of startup work that would outweigh
 * every drag after it. `playGame`'s `onReady` is where the first call goes.
 */
export async function startRecording(cdp) {
  const events = []
  const onData = (e) => events.push(...e.value)
  cdp.on("Tracing.dataCollected", onData)
  const complete = new Promise((resolve) => cdp.once("Tracing.tracingComplete", resolve))

  await cdp.send("Tracing.start", {
    transferMode: "ReportEvents",
    traceConfig: { includedCategories: CATEGORIES },
  })

  return {
    // The events arrive after `Tracing.end` resolves, in batches, and are only
    // all in once `tracingComplete` fires — so the wait is on that, not on the
    // command that asked for the end.
    async stop() {
      await cdp.send("Tracing.end")
      await complete
      cdp.off("Tracing.dataCollected", onData)
      return events
    },
  }
}

/**
 * The renderer thread that drew the board.
 *
 * A trace holds several processes — other renderers, the GPU, the service
 * worker — and each names its threads in `thread_name` metadata. Several can
 * call themselves `CrRendererMain`, so the name only narrows it; the one that
 * ran the most task time is the page.
 */
export function mainThread(events) {
  const named = events.filter((e) => e.ph === "M" && e.name === "thread_name")
  const candidates = named
    .filter((e) => e.args?.name === "CrRendererMain")
    .map((e) => ({ pid: e.pid, tid: e.tid }))
  let best = null
  for (const c of candidates) {
    const work = events
      .filter((e) => e.pid === c.pid && e.tid === c.tid && e.name === "RunTask")
      .reduce((sum, e) => sum + (e.dur ?? 0), 0)
    if (!best || work > best.work) best = { ...c, work }
  }
  return best
}

/** That thread's completed (`ph: "X"`) events, in the order they started. */
export function timeline(events, thread) {
  if (!thread) return []
  return events
    .filter((e) => e.ph === "X" && e.pid === thread.pid && e.tid === thread.tid)
    .sort((a, b) => a.ts - b.ts || (b.dur ?? 0) - (a.dur ?? 0))
}

/**
 * What to rank an event under.
 *
 * `EventDispatch` is split by the event it dispatched, because that is the
 * distinction being looked for: a drag's cost is `pointermove` against
 * `pointerup`, and one `EventDispatch` row holding both answers nothing.
 */
const label = (e) =>
  e.name === "EventDispatch" && e.args?.data?.type
    ? `${e.name} (${e.args.data.type})`
    : e.name

/**
 * Time per event name, both ways round.
 *
 * `total` double-counts by design — a `RunTask` contains the dispatch inside it,
 * which contains the recalc inside that — so it answers "how much time was under
 * this" and nothing else. `self` subtracts what nested inside, and says where the
 * thread actually sat.
 */
export function byName(events) {
  const self = new Map()
  const total = new Map()
  const count = new Map()
  // Complete events on one thread nest properly, so a stack is enough: each
  // event debits its duration from whatever is still open beneath it, and a
  // frame's remaining `own` is its self time once nothing can debit it further.
  // Clamped at zero because a trace can hold a pair that overlaps by a
  // microsecond without nesting, and a negative time in the report reads as a
  // bug in the report.
  const stack = []
  const retire = (f) => self.set(f.name, (self.get(f.name) ?? 0) + Math.max(0, f.own))
  for (const e of events) {
    const dur = e.dur ?? 0
    const name = label(e)
    while (stack.length && stack.at(-1).end <= e.ts) retire(stack.pop())
    if (stack.length) stack.at(-1).own -= dur
    stack.push({ end: e.ts + dur, own: dur, name })
    total.set(name, (total.get(name) ?? 0) + dur)
    count.set(name, (count.get(name) ?? 0) + 1)
  }
  while (stack.length) retire(stack.pop())
  return { self, total, count }
}

/** Tasks long enough to have been felt: a dropped frame's worth or more. */
export function longTasks(events, thresholdMs = 50) {
  return events
    .filter((e) => e.name === "RunTask" && (e.dur ?? 0) >= thresholdMs * 1000)
    .sort((a, b) => b.dur - a.dur)
}

/**
 * Style and layout recalcs that JS forced, grouped by the app call site that
 * forced them and ranked by how often.
 *
 * A recalc the renderer scheduled for itself carries no JS stack; one that a
 * script provoked by reading geometry mid-frame does. The innermost frame that
 * belongs to the app is the call site to report — inside it there is only the
 * DOM property that did the forcing, and outside it the framework that called
 * the app.
 */
export function forcedStyleAndLayout(events, { isAppFrame, resolve }) {
  const sites = new Map()
  let forced = 0
  let foreign = 0
  for (const e of events) {
    if (e.name !== "UpdateLayoutTree" && e.name !== "Layout") continue
    const stack = e.args?.beginData?.stackTrace ?? e.args?.data?.stackTrace
    if (!stack?.length) continue
    forced++
    const frame = stack.find(isAppFrame)
    if (!frame) {
      foreign++
      continue
    }
    const { site, source } = resolve(frame)
    const at = sites.get(site) ?? { site, source, count: 0, us: 0 }
    at.count++
    at.us += e.dur ?? 0
    sites.set(site, at)
  }
  return { forced, foreign, sites: [...sites.values()].sort((a, b) => b.count - a.count) }
}
