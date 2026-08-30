# Board geometry

The whole card table is one number wide. A stage is measured, a **scale** is
chosen, and every pixel the board draws — the card, the empty-pile slot, the
highlight frame, the fan step, the width the columns are allowed to spread to —
is a design constant multiplied by that scale. Cards, zones and fans therefore
shrink together, and however many piles a game declares still land on a phone.

This page derives the constants and the two fits that pick the scale. The
constants themselves live in `web-app/src/scenes/TableLayout.res`; that's what
you edit.

## The seam

Three files, and the split between them is the load-bearing part:

| | owns |
|---|---|
| `TableLayout.res` | the arithmetic — footprints, the fits, the hit-test. **No DOM at all**: functions of rects and counts. |
| `TableScene.res` | the measuring and the publishing — `getBoundingClientRect`, `getComputedStyle`, `style.left/top`, `setProperty`. |
| `TableScene.css` | the consuming — every footprint arrives as a custom property; the stylesheet derives nothing. |

The reason `TableLayout` has no DOM is that it can then be tested without one.
`TableLayout_test` covers both fits, the clamp at both ends, the dock refusal and
the hit-test in plain vitest; before the split, asking "does a short screen shrink
the cards?" meant opening a browser. `ConsoleDock_test` reaches here too, rather
than pulling a 2,600-line jsdom-dependent module in for one subtraction.

A new *derivation* belongs in `TableLayout`. A new *measurement* does not.

## The design footprints, at scale 1

| | value | |
|---|---|---|
| `cardW` | 80 | the card's design width |
| `cardH` | 112 | `cardW × CardArt.aspect` |
| `cardRadius` | 8 | `cardW × CardArt.cornerRatio` |
| `fanStep` | 26 | how far a Fanned card steps off the one beneath it |
| `zoneInset` | 4 | the gap between the resting card and its highlight frame |
| `zoneWidth` | 88 | `cardW + 2·zoneInset` |
| `zoneBaseHeight` | 120 | `cardH + 2·zoneInset` |
| `zoneRadius` | 12 | `cardRadius + zoneInset` |
| `maxColumnGap` | 20 | `0.25 × cardW` |

Only the four in the left-hand column are literals. Everything else is derived,
and that's deliberate: the 5:7 proportion and the 10%-of-width corner belong to
the card *art*, so `cardH` and `cardRadius` read them off `CardArt` (a 120×168
design box with `rx=12`) rather than restating them. A second literal is a second
thing to keep in step, and the way it fails is quiet — a slot that no longer
traces the card, corners that are almost concentric.

The same argument is why the stylesheet gets values rather than ratios. It used
to re-derive the slot's height as `calc(var(--card-w) * 1.4)` and its corner as
`* 0.1`; those are the same facts written a third time.

### The zone is `card + 2·inset`

```
┌─────────────────────────────┐ ← .drop-zone      zoneWidth      = cardW + 2·inset
│  ┌───────────────────────┐  │                   zoneBaseHeight = cardH + 2·inset
│  │                       │  │                   zoneRadius     = cardRadius + inset
│  │   .drop-zone__slot    │  │
│  │   cardW × cardH,      │  │ ← a resting card covers the slot
│  │   cardRadius corners  │  │   pixel-for-pixel, so the dashed
│  │                       │  │   cue shows only on empty piles
│  └───────────────────────┘  │
└─────────────────────────────┘
  ↕ zoneInset — the same on all four sides
```

Sizing the box as `card + 2·inset` on *both* axes is what makes the highlight
frame sit an equal distance outside the resting card all the way round. (The old
hand-picked 88×124 left a 4px side gap and a 6px top gap.) And because the frame
is a uniform inset outside the slot, its radius has to be the slot's *plus* that
inset for the two rounded corners to share a centre — otherwise the gap widens or
pinches round the bends.

`browser-tests/geometry.spec.mjs` measures all of this off a real engine, at three
viewports chosen so a different term of the clamp binds in each.

## Choosing the scale

`scaleFor` is two fits and a clamp:

```
width fit    fillFraction · avail / widestRow / cardW
height fit   (availH − vFixed) / (rowsCount · zoneBaseHeight + fanExtent)

scale = clamp(minScale, maxScale, min(width fit, height fit))
```

| | value | |
|---|---|---|
| `minScale` | 0.4 | the floor — a crowded, narrow screen keeps cards legible |
| `maxScale` | 1.35 | the ceiling — a wide screen doesn't blow them up without bound |
| `fillFraction` | 0.9 | the share of the stage width the row of cards fills |

**The width fit** puts `fillFraction × avail` of card across the busiest row. The
remaining 10% is not slack — it *is* the gaps: `.drop-row` is `space-evenly`, so
the leftover width becomes equal margins before, between and after the columns.
Push `fillFraction` toward 1 and the columns butt together card-to-card with
nothing for `space-evenly` to spread.

**The height fit** mirrors what reflow actually stacks into the playfield: each
row's base box, plus the deepest fan, above a fixed vertical offset. Solving
`rowsCount·zoneBaseHeight·s + fanExtent·s + vFixed ≤ availH` for `s` gives the cap.
On a tall screen the width target is the smaller of the two, so the height term
changes nothing there.

### Where each term comes from

Only `TableScene` can answer these, which is why `scaleFor` takes them as
arguments:

| | |
|---|---|
| `avail` | the playfield's width, **less the display cutaway**. `.drop-rows` is pinned inside `env(safe-area-inset-left/right)`, so on a landscape phone with a side notch that width was never the board's. Sizing to the raw stage packs the columns together. The nav rail is already excluded — the playfield is laid out beside it, not under it. |
| `availH` | the playfield's height. |
| `vFixed` | the rows' `top`, plus the inter-row `rowGap` on a two-row board — read off the *computed* style, so the stylesheet stays the one place either is written down. |
| `widestRow` | the busiest row's pile count, not a constant eight. |
| `rowsCount` | 1 or 2 (free cells + foundations above, cascades below). |
| `fanExtent` | below. |

### The fan, and `fanHeadroom`

```
fanExtent = hasFanned ? (referenceDepth − 1) · fanStep : 0
referenceDepth = deepest opening pile + fanHeadroom      (fanHeadroom = 5)
```

The extent is the *gaps* between cards, one fewer than the cards themselves. A
board with no Fanned pile grows no fan at all, so its extent is zero and the
height fit is left with only the row boxes to clear.

Two things about `referenceDepth` are worth stating plainly:

- It is **not** the deal's actual depth. Sizing to that would overflow the moment
  a cascade grew by one. Fitting the opening depth *plus* five leaves a pile room
  to take on that many before it reaches the bottom edge.
- It is **captured once**, from the opening deal, and held for the game. Deriving
  it live would resize every card on the table each time a pile grew or shrank.

A pile that grows past the headroom still overflows. This is a comfort margin,
not a guarantee.

### What the numbers work out to

For a FreeCell board — eight cascades, two rows, an opening deal seven deep, so
`referenceDepth = 12`:

```
width  to reach the ceiling   maxScale · (8 · 80 / 0.9)          = 1.35 · 711 = 960 px
height to reach the ceiling   maxScale · (2·120 + 11·26) + 16    = 1.35 · 526 + 16 = 726 px
narrowest stage at the floor  minScale · (8 · 80 / 0.9)          = 0.4 · 711 = 284 px
row width cap                 8 · 88 + 9 · 20                    = 884 px (× scale)
```

Which says something useful about `maxScale`: above 1 the design footprint stops
being the maximum and becomes what it really is — the size the *fits* are
expressed in. Both fits still bind first on a smaller window, so raising the
ceiling only takes effect once there is genuinely room, and a laptop that falls
short settles a little below it rather than clipping. Card faces are inline SVG,
so they resharpen at any size instead of blurring.

### Two clamps and a `None`

The clamp is not a fallback, it's a refusal to go past the ends. But
`scaleFor` returns `option`, and the `None` is the subtle one: a stage with
nothing to divide by — `avail` of 0 before layout, or a board with no piles —
gets **no answer at all**, and the caller keeps the scale it had.

Substituting a number there is the bug this shape exists to prevent. A playfield
measures 0 wide before it is laid out and again mid-resize on some engines, and a
board that snapped to `minScale` for one frame each time would be visible. (With
`widestRow = 0` the division would give `Infinity`, which the clamp would hand
back as `maxScale` perfectly happily.)

## The wide-desktop cap

Below the ceiling, a wider stage means bigger cards. Above it, the cards have
stopped growing and the extra width keeps pouring into the `space-evenly` gaps —
on a wide desktop that leaves the columns marooned in a sea of green.

So the row's width is capped:

```
rowsMaxWidth = widestRow · zoneWidth + (widestRow + 1) · maxColumnGap
```

— the columns plus the point at which each of the `widestRow + 1` gaps has
reached `maxColumnGap`, half a card. `.drop-rows` takes this as a `max-width` and
centres itself with `margin-inline: auto`, so a stage wider than the cap turns its
surplus into equal left/right margins instead of ever-wider gaps and the board
keeps a solitaire-table shape. Below the cap the value exceeds the stage width, so
the `max-width` is slack and the row spreads as before.

The cutaway is deliberately *not* folded in here — it comes off `avail` in the
scale, and `--rows-max-w` stays a pure spreading limit.

## The floor, and the dock refusal

`minStageWidth` is the width fit solved for `minScale` instead of for the scale:

```
minStageWidth(columns) = minScale · columns · cardW / fillFraction
```

That is, the narrowest stage a row of `columns` piles can be laid into with the
cards still clearing the floor. Docking the debug console takes
`ConsoleDock.width` (340px) of stage away from the board, and is *refused* when
what's left falls below this:

```
fitsDock  ⇔  stage − cutaway − inset ≥ minStageWidth(columns)
```

Two things this buys. Neither side names a pixel breakpoint — the refusal is the
layout's own arithmetic, so retuning `minScale` or `cardW` moves it automatically.
And `~columns` is the board's busiest row, so a two-pile demo can give up width a
FreeCell board can't.

It matters that the refusal exists at all: below the floor `scaleFor` *clamps*
rather than clipping, so a docked board would still render — just at cards the
width fit no longer sized, overflowing their row.

**What this test is not:** it's the *width* term only, and says nothing about the
height term that binds on a short screen. A landscape phone is wide enough on
paper to clear it. It just has nothing worth docking beside, and stays out of it
by the console being keyboard-only rather than by being refused here.

## The published footprints

`cssVars` is the whole of the JS→CSS interface — seven numbers, each a design
constant times the live scale:

```
--card-w  --card-h  --card-radius  --zone-w  --zone-h  --zone-radius  --rows-max-w
```

`.stacking-playfield` declares unscaled defaults for the first six so the window
before the first layout isn't blank; `applyScale` overwrites all of them before
the first paint, and every rule below reads them with a bare `var()`.

They cross the seam as **pixels, not strings**. The `px` suffix is CSS's business
and goes on at the DOM edge in `applyScale`, which leaves the proportions between
these numbers checkable without parsing anything back out of a declaration —
`TableLayout_test` asserts the aspect, the uniform inset, the concentric corner
and that doubling the scale doubles every one of them (no fixed term hiding
anywhere).

## Laying out a pile

`reflow` re-derives a zone's whole pile from the model, per card:

- **Centre it in the base box.** Horizontally on the zone; vertically within
  `zoneBaseHeight × scale`, *not* the zone's live height. A fanned zone is grown
  downward (next point), and measuring against that growth would feed back and
  shift the cards on the next reflow.
- **Step Fanned cards down** by `i · fanStep · scale`, so the newest card lands
  lowest and fully exposed. Squared piles don't step at all.
- **Grow the zone to cover the fan**: `zoneBaseHeight · scale + (count − 1) ·
  fanStep · scale`. The outline, the drop highlight *and* the hit-test box all
  follow, so the whole fanned pile is the drop target rather than just the top
  card's footprint.

## The hit-test

`hits` decides whether a dragged card's rect lands in a zone, and it is the
shared primitive for both the live hover highlight and the snap-on-drop decision —
one function, so the highlight can't promise a drop the drop then refuses.

It is **deliberately asymmetric**:

- **Horizontally strict** — the card's *centre* must fall inside the zone, so
  tightly packed columns stay distinguishable.
- **Vertically generous** — any overlap at all counts, so a card need only graze
  a zone's top or bottom edge to land in it.

Both rects are viewport-coordinate, which is what `getBoundingClientRect` hands
back, so nothing is converted before comparing. The conversion to playfield-local
`left`/`top` happens at the end of the snap maths, in `TableScene`.

## What checks this

| | |
|---|---|
| `TableLayout_test.res` | the fits, the clamp, the `None`, `minStageWidth`'s round trip, the published proportions, the hit-test. Arithmetic only — no browser. `mise run test` |
| `browser-tests/geometry.spec.mjs` | the *rendered* relationships at three viewports: slot traces card, 5:7 held, corners concentric, inset uniform. `mise run browsertest` |
| `ConsoleDock_test.res` | the dock refusal from the chrome's side. |

## Before you change a footprint

1. **Change a constant, not a formula.** If the board feels wrong it's almost
   always `cardW`, `maxScale`, `fillFraction` or `fanHeadroom`. Everything else
   is derived from those and from `CardArt`.
2. **Don't restate a proportion.** `cardH` and `cardRadius` come off `CardArt`,
   and the stylesheet gets values rather than ratios, precisely so the card's
   shape is written down once. A `calc(var(--card-w) * 1.4)` is a regression.
3. **Add a footprint to `cssVars`, not to the stylesheet.** Anything the CSS
   needs in scaled pixels is published; anything it derives itself can drift.
4. **Check the short screen, not just the wide one.** The height fit, the fan
   extent and `rowsCount` only show up on a landscape phone.
5. **Retuning `minScale` or `cardW` moves the dock refusal.** They're the same
   arithmetic; `TableLayout_test`'s round-trip test is what notices.
6. **Look at it.** `mise run browsertest` and `mise run screenshots` are the
   gate — jsdom has no layout engine, so a unit test can only check the numbers,
   never where they put a card.
