# Card compositing

Fifty-two cards sit on the table at once, each a live `<svg>` moved by writing
`style.left`/`style.top`. That is a lot of moving parts for a low-end machine, and
two lines in `TableScene.css` decide almost the whole cost of it:

```css
.stacking-card { transform: translateZ(0); }        /* a layer per card */
.stacking-card .card-art { box-shadow: …; }         /* not filter: drop-shadow() */
```

Both look like details. Both are worth about a quarter of the frame budget on a
slow device, in opposite directions, and the pull between them is why neither is
obvious from the other's side. This page is the measurement.

## Why every card gets its own layer

A card moved by `left`/`top` with nothing promoted repaints itself *and*
everything it uncovers. In a cascade the cards overlap by design, so the card in
hand is dragging its damage rectangle across a fan of other cards — each of which
is SVG text, the most expensive thing on the board to raster.

Promoted, the card is a texture the compositor slides around, and the fan
underneath it is never touched.

The tempting middle road — promote only the card in hand, and leave the resting
fifty-one alone — is *worse than either*, and worth knowing why: the cards that
repaint are not the one moving, they're the ones it slides over. Promoting the
mover doesn't spare them; only promoting *them* does.

| during a 250-move drag | raster |
|---|---|
| every card promoted (what we do) | 0.7 s |
| only the dragged card promoted | 2.5 s |
| nothing promoted | 9.4 s |

The layers themselves are cheap to hold — a card is roughly 100×140 device px on
a 1366×768 Chromebook, so the whole deck is about 3 MB of texture.

## Why the shadow is a `box-shadow`

`filter: drop-shadow()` reads the *alpha* of what it's applied to. A layer with a
filter therefore needs a render surface of its own to be filtered into, and every
frame in which anything on the board moves, the compositor re-composites all
fifty-two of them.

The cost doesn't show up on the main thread at all, which is what makes it hard to
find: JS is fine, layout is fine, and the profiler's flame chart is mostly idle.
It lands on the viz compositor — a GPU-process thread, and on a tile-based mobile
GPU (the Mali-G72 in an MT8183 Chromebook, say) render-surface switches are the
thing it is worst at.

The card is an opaque rounded rectangle, so a `box-shadow` tracing `--card-radius`
draws the same picture with no surface at all. Measured on the built site under 6×
CPU throttling, at 1366×768:

| | opening deal | drag |
|---|---|---|
| | dropped frames · viz | ms/move · viz |
| `filter: drop-shadow()` | 33 · 1967 ms | 25.9 · 5097 ms |
| `box-shadow` | 8 · 311 ms | 19.3 · 243 ms |

Twenty times less compositor work during a drag, and the opening deal stops
dropping frames.

The shadow hangs on the inner `.card-art` rather than on the `.stacking-card`
wrapper for a second reason, unrelated to speed: the hand-placed tilt
(`docs/card-tilt.md`) rotates the art, so a shadow there leans with the card
instead of sitting square behind it.

## If you're chasing a frame rate here

Measure the **viz compositor thread**, not just the renderer. The two findings
above are both invisible from the main thread — a trace that only shows
`RunTask`, `Layout` and `FunctionCall` will tell you the board is idle while the
device drops half its frames.

Chrome's CPU throttling (`Emulation.setCPUThrottlingRate`) does not throttle the
GPU, so it *understates* anything in this file on real hardware rather than
overstating it.
