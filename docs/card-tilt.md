# Card tilt

A resting card on this board is not quite square. Each one carries a slight
rotation — at most 2.5° either way — so a pile reads as dealt by a person rather
than stamped down by a machine. The player can turn it off; the menu calls it
**Sloppy placement**.

It is a small effect with an intricate middle. The angle is a hash rather than a
random number, it is published as a custom property rather than applied as a
style, and the finish sweep has to take the rotation apart and re-time it card by
card or the whole board twitches before anything moves.

The code is in `web-app/src/scenes/TableScene.res` (`cardTilt`, `applyTilt`,
`setTiltTiming`, `tiltFor`) and `web-app/src/scenes/TableScene.css`
(`.stacking-card .card-art`).

## Deterministic, not random

The angle is a cheap hash of *the card's identity and where it now rests*. Not
`Math.random`, and not a value stashed on the card when it's created. That choice
buys three things at once:

- **Stable across reflows and resizes.** Every resize, every orientation change,
  every drop re-lays the whole board through `reflowAll`. A random angle would be
  re-rolled each time, so a card would twitch to a new angle whenever a neighbour
  moved. A hash of `(card, pile, slot)` returns the same number for a card that
  hasn't gone anywhere.
- **It *does* change when the card is placed somewhere new.** A card that lands
  in a different slot hashes differently, so a drop re-tilts it — which is what a
  fresh placement should look like. An angle fixed at card creation would follow
  the card around the board unchanged, and a pile would look copy-pasted.
- **Reproducible renders.** No entropy anywhere in the pipeline, so the same
  board draws the same angles every time — screenshots included.

## The hash

```rescript
let maxCardTilt = 2.5

let cardTilt = (~card, ~pile, ~slot) => {
  let h = suitOrdinal(card.suit) * 17 + rankOrdinal(card.rank) * 5 + pile * 23 + slot * 11
  let unit = Int.toFloat(Int.mod(h, 100)) /. 100.
  (unit *. 2. -. 1.) *. maxCardTilt
}
```

Four small integers fold into one, `mod 100` spreads them over `[0, 100)`, and
the last line maps that onto `[-maxCardTilt, maxCardTilt)`.

The multipliers are chosen so that things a player sees *side by side* don't land
on the same angle. With a 5° span over 100 buckets, one hash unit is **0.05°**,
so each input moves the angle by:

| input | step | degrees per step |
|---|---|---|
| suit | 17 | 0.85° |
| rank | 5 | 0.25° |
| pile | 23 | 1.15° |
| slot in pile | 11 | 0.55° |

The two that matter most are `pile` and `slot`: adjacent slots in a fan are the
cards most obviously next to each other, and 0.55° apart is visible as a
difference without either card reading as crooked.

Two rules follow, and both are quiet if broken:

- **All four inputs are non-negative**, which is what keeps `Int.mod` positive. A
  negative `h` would fold `unit` below zero and push the angle past
  `−maxCardTilt`.
- **`maxCardTilt` stays small.** It's the whole span, not a variance: raise it
  and cards stop stacking cleanly, because a fanned pile's overlap is computed
  from `TableLayout.fanStep` and assumes cards are very nearly square. See
  [board-geometry.md](board-geometry.md).

## How the angle reaches the screen

`applyTilt` writes the number to a custom property; the stylesheet does the
rotating.

```rescript
style(wrapper)->setProperty("--card-rot", Float.toString(degrees) ++ "deg")
```

```css
.stacking-card .card-art {
  transform: rotate(var(--card-rot, 0deg));
  transform-origin: 50% 50%;
  transition: transform var(--card-rot-dur, 0.18s) ease var(--card-rot-delay, 0s);
}
```

Three things in that pair are load-bearing:

- **The rotation is on the inner `.card-art`, not the `.stacking-card` wrapper.**
  The wrapper's `transform` is already spoken for — the drag lift and every deal
  and flight animation write it. Putting the tilt on the child means the two
  never fight over one property. The property is *set* on the wrapper and
  inherits down, which is why `applyTilt` takes a wrapper.
- **`transform-origin: 50% 50%`.** SVG elements otherwise default to a `0 0`
  origin, and the card would swing about its top-left corner.
- **The transition is a default, not a fixture.** `--card-rot-dur` and
  `--card-rot-delay` are per-card properties with the in-game snap as their
  fallback, so a card that has never heard of them eases into its new angle in
  0.18s, matching the wrapper's left/top snap. The finish sweep overrides them
  for the length of one sweep — see below.

## The preference

The tilt is a stored flag, `pip.cardTilt`, defaulting **on**
(`Preferences.loadCardTilt`). Two things carry it:

- `~tiltEnabled` is a **ref**, not a value: the board reads `.contents` live
  wherever it lays a card out, so flipping the switch takes hold on the next
  relayout without rebuilding the scene. Same trick as `~options`.
- `controls.relayout` is its companion — a thunk that re-lays every resting card,
  so a flip re-tilts (or squares) the board *in place*, immediately, rather than
  only on the next move.

Turning it off doesn't take a different code path. `tiltFor` returns a
dead-square `0.`, the same property is written with the same transition, and
every card eases back to true. Nothing else about the layout changes.

## The sweep problem

This is the part worth reading before touching anything.

The tilt is keyed on **where a card rests**. The finish sweep begins by
calling `reflowAll`, which lays every card onto its foundation slot *at once* —
and therefore re-tilts every card at once — while the flight animations hold each
card visually at its source until its staggered turn comes.

Left alone, that is a boardful of cards all swinging to their landing angles, in
unison, in place, before a single card has moved. Small, but wrong in a
way that's hard to un-see: the board twitches, then plays.

The fix is to give each card's *rotation* the same schedule as its *flight*:

```rescript
cards->Array.forEachWithIndex((c, i) =>
  setTiltTiming(c.wrapper, ~delay=Int.toFloat(i) *. delta, ~duration=flight)
)
```

`--card-rot-delay` is the card's own launch delay and `--card-rot-dur` is its
flight time, so the rotation rides along with the movement: a tilt at the source,
a tilt at the destination, and the turn between them happening while the card is
in the air. `delta` and `flight` are the same pair the flights use — see
[animation-timing.md](animation-timing.md) for where they come from.

Two ordering constraints hang off this:

- **The timings must be set before `reflowAll`**, because `reflowAll` is what
  applies the new angle. Set them after and the transition has already started on
  the stylesheet's default.
- **The loop index must match the flight loop's**, or a card's rotation and its
  flight start at different times.

With the hand-placed look off, both angles are 0°, so nothing rotates either way
and the deferral is a no-op.

### Why the deal doesn't do this

`animateDeal` flies cards in on the same staggered schedule but sets no tilt
timing, and doesn't need to: its cards are being laid out for the first time.
There is no prior resting angle for the board to visibly swing away from — each
card eases from square to its angle on the way up, which is what a deal looks
like anyway.

### Clearing again

The properties are borrowed for the length of one sweep, so `clearTiltTimings`
drops them (via `removeProperty`, falling back to the stylesheet's snap) at every
place a sweep can end:

| where | why |
|---|---|
| the sweep's own `onFinish` | every card has landed at its final angle; the settling reflow re-applies the same angles, so this drops nothing |
| `adoptHistoryPresent` | an undo cutting a sweep short would otherwise deliver the restored position's angles on the dead sweep's schedule |
| the start of an autoplay | any flight in the air belongs to the position the line starts from, and its timings with it |

Miss one and the symptom is delayed: the next ordinary drop re-tilts on a stale
sweep's delay instead of snapping, seconds after the sweep everyone has forgotten
about.

## What checks it

`browser-tests/finish-tilt.spec.mjs`, and it has to be a browser test: jsdom has
no layout, no CSS transitions and no resolved transform matrices, so `mise run
test` cannot see an angle at all. It reads the *rendered* angle off the resolved
transform matrix rather than `--card-rot`, because mid-transition the property
already holds the destination value while the matrix is what the player sees.

Three checks, on the `?state=finish` board:

1. tilt on — 90ms into the sweep, at most a couple of cards have turned (the ones
   already launched), not the whole board. This is the regression the whole
   mechanism exists to prevent.
2. tilt on — cards end the sweep tilted, at their foundation angles.
3. tilt off — every card is dead square throughout, source and destination.

Run it with `mise run browsertest`. The screenshots (`mise run screenshots`) are
the other half: the tilt is deterministic precisely so they don't churn.

## Before you change the tilt

1. **Changing a multiplier or `maxCardTilt` changes every screenshot.** That's
   expected, not a failure — but check a fanned pile, which is where cards are
   closest together.
2. **Keep the hash's inputs non-negative** and keep them to identity plus resting
   place. An input that isn't stable while a card sits still reintroduces the
   twitch on every resize.
3. **Anything that ends a flight must call `clearTiltTimings`.** New cancel path,
   new call.
4. **Set tilt timings before `reflowAll`, not after.**
5. **Don't move the rotation onto `.stacking-card`.** It will fight the drag and
   flight transforms.
6. **`mise run browsertest` is the gate**, not `mise run test`.
