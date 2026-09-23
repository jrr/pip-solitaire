# Profiling a frame

`mise run profile` plays the opening drags of a deal against a build of the real
site, under CPU throttling, with a Chrome trace running, and prints where the
main thread's time went.

```
mise run profile -- 24680               # a deal
mise run profile -- --throttle 4 24680  # a less punishing device
mise run profile -- --moves 20 24680    # a longer sample
mise run profile -- --game simplesimon 3
mise run profile -- --headed 24680      # watch it drag
```

It stands to a main-thread change the way `mise run solve` stands to a solver
change: the thing you run before deciding what to move off the thread, and again
after, to find out whether it helped. The driving half is `autoplay`'s — the
same pointer drags on the same bundled site — so what it measures is the app
being played, not a benchmark written to look like it.

This page carries what the numbers mean, what they can't tell you, and the
record to compare against. The code keeps the mechanics:
`packages/web-app/scripts/profile/`.

## What it measures

**The drags, not the load.** The board is loaded and settled at full speed;
throttling and the trace both start on a board at rest, from `playGame`'s
`onReady`. A page load under 6× throttling is seconds of startup work that would
outweigh every drag after it and answer a question nobody asked.

**The renderer's main thread, and only it.** `Emulation.setCPUThrottlingRate`
slows the renderer and leaves the GPU alone, so anything compositor-side is
understated here rather than overstated. The compositor is measured by hand in
[card-compositing.md](card-compositing.md), and folding the two together is a
separate job from this one.

**One deal.** `autoplay` takes lists and ranges; this takes a single number, on
purpose. Averaging several boards hides the thing the tool is for — that *this*
deal's opening drags cost what they cost.

## Reading the output

### Events, ranked by total

`total` is inclusive and double-counts by design: a `RunTask` contains the
dispatch inside it, which contains the recalc inside that. It answers "how much
time was under this", which is what a gesture's cost is — an `EventDispatch
(pointerup)` is half a second of work in its callees and almost nothing in
itself.

`self` subtracts what nested inside, and is the column that says where the
thread actually sat. A row with a large `total` and a tiny `self` is a name for
a phase; a row where the two are close did the work itself.

### Long tasks

`RunTask` over 50ms — a dropped frame's worth or more. A count and a total,
because on a throttled device the count is what a player feels as stutter.

### Forced style and layout

The ranking to read first, and the reason the tool exists.

A style or layout recalc that the renderer scheduled for itself is ordinary. One
that JS forced — by reading geometry after writing to the DOM in the same frame
— is charged to whatever function happened to be running, which is why **a flame
chart actively misleads here**: the cost shows up as the app's own function being
slow rather than as layout. The trace tells the two apart, and this ranking is
the forced ones, grouped by the app call site that forced them.

Ranked by count rather than by time, because count is what a fix changes. The
times move by a few percent between runs; the counts don't move at all.

## The two traps

**`disabled-by-default-devtools.timeline.stack` is not optional.** Without that
one category in the trace config, a forced recalc records with no JS stack, and
the profile can say that time went to layout but not what asked for it. That
single category is the difference between "some function is slow" and a call
site.

**The harness forces layout too.** `readGeometry` reads a rect off every card on
the board between drags, which forces layout exactly the way the app's own reads
do. Those frames come from a script Playwright injects, which has no URL on the
preview origin, so the profile keeps only frames served from that origin. Skip
the filter and a chunk of the count is the cost of watching, not the cost of
playing. The summary line prints both numbers, so the filter can be checked
rather than trusted.

## The build it measures

The shipped bundle is minified and carries no sourcemap, so its stack frames are
`i` and `wb` and a ranked list of them is unreadable. `mise run profile` builds
its own (`mise run bundle-profile`, into `packages/web-app/dist-profile`) with
two settings changed, and `packages/web-app/vite.config.profile.js` says which
and why neither alone is enough.

Everything else about that build is the shipped configuration, so the numbers
carry — but they are the numbers for an unminified bundle. Compare a profile to
another profile, never to a measurement taken against `dist/`.

### How precise a call site is

A frame resolves through the sourcemap to a position in the **generated**
`.res.mjs`, because that is where the map stops: ReScript emits no map of its
own from `.res` to `.res.mjs`. The line's own text is printed under it, which is
what makes it readable — a ReScript module compiles to one `make` with
everything inside it, so a function name would say `make` or nothing at all.

Attribution is to the innermost frame that belongs to the app, and it is good to
about a statement, not to a character. Chrome samples these stacks, V8 inlines
small callees into their callers, and a native builtin between two app frames
(`zones.forEach`, say) can shorten the stack to one frame. So read a call site
as *this loop, in this module* — and then read the surrounding ten lines rather
than only the line printed.

## The record

FreeCell deal 24680, 12 drags, 6× throttle, on a 2026 cloud container. Numbers
to compare a change against, not to aim at — a different machine will put
different absolutes here, and the ratios are what carry.

| | |
| --- | --- |
| main thread in tasks | ~7.9s over ~13.5s of trace |
| long tasks (≥50ms) | 6–9, ~450–650ms in total |
| `EventDispatch (pointermove)` | ~600ms total, 108 dispatches |
| `EventDispatch (pointerup)` | ~520ms total, 12 dispatches |
| style/layout forced from app code | **259** recalcs, ~600ms |
| …of which `TableScene.res.mjs:1108` | **192**, the drag's hover highlight |

The drag's hover highlight is three quarters of the forced layout in the
profile: the pointermove handler writes `drop-zone--over` and
`drop-zone--invalid` across every zone, and then the next pointermove reads a
rect back. Fixing it is not this tool's job, and hasn't been done.

**The counts are the stable part.** Two runs on an unchanged tree give the same
259 and the same 192; event counts land within a percent or two, and times
within five to eight. That is the comparison this is built for — a change that
moves a count moved something real, and a change that only moves a time by five
percent moved nothing you can see from here.

That stability is also why there is **no CI gate on any of this**. A threshold
needs a machine that performs the same twice, and a shared runner isn't one.

## The harness options it added

`playGame` grew two options for this, both opt-in and both no-ops for a caller
that doesn't pass them: `onReady`, which runs once on a settled opening board
before anything is planned or dragged, and `maxMoves`, which stops after that
many drags and reports `stopped: true`. The drag loop itself is the one in
`scripts/autoplay/autoplay.mjs` — a profile plays the game exactly the way
`mise run autoplay` does, or it would be measuring a second harness.
