# The victory cascade

The Windows 3.1 payoff: when a game is won, the foundations empty one card at a
time and the deck bounces its way off the table, leaving a trail behind it.

Three modules, in `web-app/src/scenes/`:

| | |
|---|---|
| `Cascade.res` | the motion. A run is a value and `step` is the only thing that moves it — no canvas, no DOM, no clock |
| `CascadePlayer.res` | the surface. Backing store, sprite sheet, frame loop, what a resize costs |
| `CascadeScene.res` | the `?scene=cascade` demo: the chrome, and every number on a slider |

The split is what keeps the demo from being the animation. `TableScene` attaches
to `CascadePlayer` too, and the only thing the demo has that the board doesn't is
controls. A second copy of the player's mechanics is how the two would drift — a
store sized at one ratio here and a sheet built at another there draws perfectly
good cards, softer by the ratio between them, with nothing anywhere saying so.

This page is the model. The code keeps the numbers.

## Units

**The physics is in card-widths and seconds.** A card is 1 wide and
`CardArt.aspect` tall, the stage is however many cards across it happens to be,
and a speed is card-widths per second. Pixels never enter `Cascade`, because a
pixel is the one unit that changes meaning between a 40px card on a phone and a
140px one on a desktop: a gravity in px/s² is a slow drift on the small board
and a plummet on the large one, and the same numbers have to read the same on
both.

Pixels enter twice, both in the player: `Cascade.arenaOf` divides the measured
CSS box by the card size on the way in, and `draw` multiplies by it on the way
out.

**Metres are for people.** A card-width is a length as soon as you say which
card — `CardArt.widthMetres`, 2.5in, the poker size the 120×168 design box is a
picture of — so `Cascade.toMetric` lets a gravity be read in m/s² and compared
to a g. That conversion lives at the edge a person meets (the sliders, the
status line) and never inside `step`, for the same reason pixels don't.

The three units, for one desktop stage: 1056×560 CSS px = 11.7×6.2 card-widths
= 0.75×0.4 m.

## The motion

### Integration

`v += g·dt; p += v·dt`, and **`dt` is clamped inside `step`** rather than
trusted. A frame's `dt` is whatever the browser felt like giving: 8ms at 120Hz,
16 at 60, and *seconds* when a tab comes back from the background. Unclamped,
that last one moves a card the length of the stage in one step, through the
floor and past every bounce it should have taken. Clamped (`maxStep`, 50ms), a
returning tab resumes where it left off and the run loses the time — which is
the right thing to lose.

**A surface is caught by position, not by reflecting the overshoot.** A bounce
sets `y` to the floor (or `x` to the wall) and negates the speed across it, so no
step size can tunnel a card through however fast it is going.

### A table with a budget

**A card is caught a fixed number of times and then it isn't.** Each card draws
its own `numBounces ± numBouncesVariance` at launch, spends one per landing and
one per wall, and once it has none left the table simply stops catching *that*
card: it goes on through whichever surface it meets next and off the stage.
Without a budget the floor is forever and the last of a card's energy goes into a
Zeno tail of hops too small to see — which reads as a card stuck to the table
while the rest of the deck goes past it.

**One budget for the floor and the sides**, because it is the only way out of a
box with walls on it. The card that runs out mid-stage drops through the floor,
the card that runs out at a wall carries on through it, and there is no
combination of knobs that leaves a card with a way to spend energy and no way to
leave. At the defaults a card takes about two walls and two landings on a desktop
stage, which makes the count the knob that decides how long the deck ricochets
around rather than one that only shapes the tail of a run.

**A contact spends a bounce only if it sends the card back.** A floor with no
give — bounciness at zero, which the slider reaches — is not bouncing the card,
it is holding it, and a card that spent a bounce per frame lying there would be
through the table in a tenth of a second. So the card rests where it landed with
its budget intact, which is what a dead floor has always looked like.

**A wall with no give is not a wall: it lets the card past.** The floor can hold
a card it cannot rebound, because gravity is what put the card there and what
keeps it there. A wall holding one would be holding it *for good* — resting on a
floor that has refused to drop it, with no sideways speed left to carry it
anywhere — and a cascade whose last card never leaves is a run that never ends.
So at zero bounciness a card slides straight out over the side, and a table with
no give in it anywhere still empties.

### Launching

One card per `launchMs`, the first on the very first step — waiting an interval
for it reads as the scene not having started. The remainder is carried, so a
launch rate faster than the frame rate still comes out right.

Cards take the stage's seats in turn. `Cascade.foundationOrder` deals in the
same round-robin, so with four of each, every card falls from the pile it sat
on: a won game gives up four complete A→K foundations, King first, one pile at a
time, and the aces go last. The seed picks which suit ended on which foundation,
because that is the only thing a finished game varies.

### Which way a card is thrown

A fair coin, from every seat. The seat's room each way is not in it: the card
thrown at the wall beside it meets that wall a card-width later and comes back,
so half of an outer seat's deck going into the near wall is the ricochet the
walls are for rather than a card leaving with nothing to show. A seat's side is
still drawn from the run's own chain, so it stays one of the four draws a launch
takes and a seed replays a throw exactly.

### A value and a ±

Everything a card can differ in is a centre and a spread, drawn once at launch:
`speed ± speedVariance`, `bounciness ± bouncinessVariance`, uniform. Not a low
and a high — that's two numbers to drag to move one thing, and no answer to
which of them is "the speed". `Cascade.scatter` clamps: a negative speed would
be a *direction* (which is the aim's business) and a bounciness over 1 is a card
that gains energy off the floor and never comes down. A spread of zero is 52
identical cards, which is the setting that shows what the spread was doing.

A count is the exception to *uniform*, not to the shape: `numBounces ±
numBouncesVariance` is drawn from the whole numbers in the band, each equally
likely (`Cascade.scatterCount`). Rounding a scattered float instead would hand
the two ends half the weight of every number between them, which at `3 ± 2` is a
seventh of the deck landing on the wrong count.

Bounciness and the bounce budget ride on the `flyer`, not on the knobs, so a card
keeps the character it launched with instead of picking a new one off every
surface it meets.

### Retiring

A card is done when the *whole* of it is past an edge — it would otherwise blink
out with an edge showing. Downwards counts, because that is how a card out of
bounces mid-stage leaves. The run `isDone` when the deck has launched and the
last card has left.

## Determinism

Randomness is `Cards.xorshift` threaded through the run as `rng` (`Math.random`
is banned on pure paths here), so a seed replays a cascade exactly. Each launch
takes four draws in this order — speed, side, bounce, bounce count — and changing
the order or the number of them changes every cascade, which is harmless but
worth knowing before reordering `spawn` or giving a card one more thing of its
own.

A *live* run is not pixel-identical between loads, because the frame clock isn't:
what repeats exactly is the simulation for a given number of steps. That is what
the pose is for.

## The surface

**A card is handed back as it launches** (`~onLaunch`), which is the second half
of the effect on a real board: the foundation under the canvas empties a card at
a time as its sprites take over. It can't ride on `~onChange`, which is a
half-second heartbeat — a node left on the table that long after its copy has
flown off it is a card in two places.

**Nothing is ever cleared.** The trail *is* the effect, and it's why this is a
canvas rather than DOM nodes: per-frame cost tracks the cards in flight, not the
length of the trail behind them. With retained nodes it would be one to two
thousand SVGs by the end of a run.

**One ratio, two consumers.** The backing store is `css × CardRaster.displayPixelRatio()`
and the sprite sheet is built at that same number. `CascadePlayer.spritesStale`
is the check; `build` is what happens when it fails.

**The blit is 1:1 by construction.** `draw` passes the sprite's own device size
converted back to CSS pixels, not the size it asked for, so a card size the
ratio doesn't divide evenly (90px at 1.25×) still copies pixel for pixel.

**Whole pixels.** Under `ctx.scale(ratio, ratio)` a whole CSS pixel is only a
whole device pixel at a whole ratio, and browser zoom reaches 1.5, 2.5, 3.75. Off
the grid every blit is resampled, and what that looks like is not blur: a
sub-pixel scale acts about the centre, so a card's two ends move in opposite
directions and it reads as the ends disagreeing — which sends the natural
diagnosis into the rasterizer instead of the compositor. `Cascade.snapToDevice`
rounds the corner onto the grid before drawing. **Snap the drawing, never the
simulation:** quantising a position feeds back into the next bounce, and a bounce
that depends on the display is a bug you cannot see.

The scene's `whole pixels` toggle turns it off, which is the only way to see what
it buys; `browser-tests/cascade.spec.mjs` measures the same thing as a count of
half-lit edge pixels at `deviceScaleFactor: 1.5`.

**Assigning `canvas.width` wipes the surface**, and a resize forces it. So a live
run *ends* on a resize rather than being rescaled mid-flight, and a still — which
is a pure function of the box, the seed and the options — is simply drawn again.
If the device ratio moved with the resize (a browser zoom is a resize), the sheet
is rebuilt then, while nothing is in the air. That is this module's answer to
#253: never under a card.

## The clock

A fixed simulation step of 1/120s off an accumulator, with at most
`maxCatchUpMs` (100ms) of arrears worked off per frame — a backgrounded tab
comes back owing seconds, and spending that in one frame is thousands of steps
and a locked-up page.

**The trail is stamped on an interval of *simulated* time** (`stampMs`), which is
neither the step nor the frame. Stamping every step paints a solid white sheet
you can't see a card in; stamping every frame makes the picture denser on a
120Hz display than on a 60Hz one, which is the one thing a trail can't be allowed
to depend on. Spacing is speed × interval, so a faster card leaves a sparser
trail — which is what the original does, because it drew one stamp per frame at a
fixed speed.

## The numbers

Tuned by dragging the sliders in the scene until it looked right, then copied
into `Cascade.defaults` and `CascadePlayer.defaults`. The knobs are written in
the unit the sliders read them in, so the panel opens on the numbers that were
chosen.

| knob | default | |
|---|---|---|
| gravity | 4 m/s² | 0.41 g — this is slow motion, deliberately. Earth is `fromMetric(9.81)`, ~154 card-widths/s² |
| bounciness | 0.8 ± 0.15 | the share of its speed a bounce keeps, off the floor and off a wall alike |
| numBounces | 3 ± 2 | contacts — landings and walls together — before the table lets the card through |
| speed | 0.4 ± 0.1 m/s | the sideways throw |
| launchInterval | 750 ms | so a 52-card deck takes ~39s |
| trail | 16 ms | of simulated time between stamps |

Not on a slider: the simulation step (1/120s), `maxStep`
(50ms), `maxCatchUpMs` (100ms), the pose length (16 cards), and the scene's three
card sizes (40/90/140px).

At earth gravity the trail knob has to come down with it — spacing is speed ×
interval, and raising one without the other turns the smear into a scatter.

## The demo scene

`?scene=cascade`, plus:

- `?seed=N` — the same number a board reads as its deal, replayed as a cascade.
- `?cascade=pose` — the still: a fixed number of steps, no clock, so the picture
  is identical on every load. What the screenshot report shoots and what the
  browser suite compares two loads of. It counts in **cards** (16), not seconds,
  so dragging the launch interval doesn't empty it.

Three of the controls are claims rather than feel, put where an eye can check
them: the card size (the motion is in card-widths — it should read the same at
40px and 140px), `whole pixels` (above), and the pose (determinism).

The scene opens on the largest card size its stage has room for, so a phone gets
40px without anyone touching a control. A board gets this free: its cards are
already scaled to its stage.

## Where it's pinned

| | |
|---|---|
| `Cascade_test.res` | the arithmetic: framerate independence, the clamp, the floor, the walls, energy loss, the bounce budget, the aim, the spreads, seeded replay |
| `CascadePlayer_test.res` | the mechanics a jsdom can reach |
| `CascadeScene_test.res` | the chrome: which knobs exist, what they read out |
| `browser-tests/cascade.spec.mjs` | the pixels: the store, the trail, the snap, a seeded pose repeating to the byte, the resize policy |
| `TableScene_test.res` | which wins play one, and that every way out of a run still ends at the panel |
| `browser-tests/win.spec.mjs` | the board's own: real sprites, foundations emptying, a real tap ending it |

## Before you retune

1. **Drag, don't edit.** The scene is the instrument; `Cascade.defaults` is where
   the answer gets written down afterwards.
2. **Watch a whole run, not a still.** The pose is for repeatability, not for
   judging pace — a 39-second cascade is a different thing from any one frame of
   it.
3. **Check both extremes of card size.** A change that only reads at 90px is a
   change tuned in pixels wearing card-widths' clothes.
4. **The launch interval is not `docs/animation-timing.md`'s model.** The four
   board movers time themselves by that page's C/P pair because a flight has a
   destination; a cascading card doesn't, so its interval is a plain interval on
   the clock. See that page's own note.

## On the board

`TableScene` is the second caller, behind the hidden **Victory animation** flag
(off by default). The board's half is which cards fall and from where: the
foundations' own resting spots become the seats, the piles are taken King-first
in the same round-robin `Cascade` seats by — which is what makes a card fall from
the pile it was on — and each `.stacking-card` is hidden as its sprite leaves.

**Only a win as it happens plays one.** A victory restored from storage, and a
redo back into the winning move, raise the panel alone: the cascade is what a
game being won looks like, not what a won position looks like.

**A tap is a peek, not a skip.** It toggles the win panel over the still-falling
cards and nothing else; the run is unaffected either way. That costs the panel its
hit-testing for the length of the run — the scrim goes click-through so the tap
that puts it away can reach the canvas underneath, and only the panel itself keeps
its own events (`.table-board--cascading`). The canvas takes pointer events from
the moment the win lands rather than from the first card, so the peek covers the
~60ms the first sheet takes to build — otherwise a slow build reads as a hang on
the most emotionally loaded screen in the app.

**The panel also comes up on its own, six seconds in** (`winPanelDelayMs` in
`TableScene.res`), so nobody has to tap or wait out the run to be told they won.
It is the same peek — a tap puts it away again and the cards go on falling — but
it eases in over a second and a half where a tap's answer snaps up
(`.win-overlay--gradual`): a panel nobody asked for should read as the
celebration arriving at the message, not as an interruption. The timer is counted
from the win landing, like the tap, and it rides with the run — every way of
ending one clears it, or an undo out of the victory would be followed six seconds
later by a win panel over a board being played again.

Four things end a run, and all four end with the panel up — again, if it was up
at six seconds and tapped away since: the last card leaves, an undo steps out of
the victory, a resize wipes the surface, or the sprite sheet fails to build. Only
the first of those eases the panel in; the others are a win being handed over,
not a finale. That last one is the one worth stating: **a won game is never held
up by its celebration failing to load.**

The whole run is 52 cards at the launch interval, so a victory is a ~40-second
celebration. That is the number the sliders were dragged to; retune it there, not
here.

**The victory takes the board over when the cascade starts, not when the panel
goes up.** An already-won board is still `Reducer.canFinish` — draining it wins it
again — so the Finish button is held off by that flag rather than by the position,
and forty seconds of cascade is forty seconds for it to be wrong in.

## Still open

- A sprite carries no drop shadow (`.stacking-card`'s `filter` is the DOM's), so a
  card in flight is flatter than a resting one.
- There is no ceiling, and nothing needs one: nothing is thrown upwards and a
  bounciness of 1 only returns a card to the height it was dropped from. A card
  given upward speed would want one.
