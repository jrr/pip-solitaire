# Animation timing

Four things in this app move cards across the board: the opening deal, the
end-game finish sweep, a move played from the debug console, and a move played by
the solver during autoplay. All four are the *same* animation — a staggered
flight, one card at a time, from wherever the card was to wherever it now
belongs — and all four are timed by the same two numbers.

This page derives the model once and puts the four tunings beside each other. The
knobs themselves live in `web-app/src/scenes/TableScene.res`; that's what you
edit.

## The two knobs

Every flight is described by a pair:

| | | |
|---|---|---|
| **C** | `…MaxInFlight` | how many cards may be moving at once |
| **P** | `…PerCardMs` | how long the sequence spends *per card* |

Everything else — the interval between launches, how fast a card travels, when
the last one lands — is derived from those two and the card count `n`.

Pacing by time-per-card rather than by a fixed total is the deliberate part: the
total `T = P·n` scales with the count, so a two-card `moverun` doesn't stretch
across a whole deck's worth of time and a small demo board stays snappy.

## The derivation

With `C` clamped to at most `n`, and `T = P·n`:

```
start interval between successive cards   Δ = T / (n − 1 + C)
per-card flight time                      t = C·Δ
card i's start delay                      i·Δ
```

The distance a card travels is fixed by where it started and where it lands, so
`t` *is* its speed.

Both constraints come out exact:

- **At steady state exactly C cards are in the air.** Card `i` is flying over
  `[i·Δ, i·Δ + C·Δ)`, so at any moment inside the sequence, C of them overlap.
- **The last card lands exactly at T.** It launches at `(n−1)·Δ` and flies for
  `C·Δ`, and `(n−1+C)·Δ = T` by construction.

Which gives the two knobs independent, legible meanings:

- **Scaling P** stretches or tightens the whole sequence — `T` moves with it — and
  changes nothing about how the cards overlap.
- **Raising C** leaves `T` alone and redistributes it. Δ shrinks, so cards launch
  in quicker succession; `t = C·Δ` grows, so each individual card takes *longer*
  to travel. Denser, more simultaneous motion; the same sequence length.

The second one is easy to get backwards. Raising C does not speed a card up — it
speeds up the *stream*.

`n = 1` is the degenerate case — no second card, so no interval to speak of. The
single card simply flies for `T`.

The clamp matters: without `C ≤ n`, a three-card sequence under `C = 5` would
give every card a flight longer than the sequence itself, and the last card would
land well after `T`.

## The four tunings

`staggerTiming` is called four times, each with its own pair. They're separate
constants on purpose — each of these can be re-timed without disturbing the other
three.

| | C | P | the job |
|---|---|---|---|
| **deal** | 5 | 67 ms | fifty-two cards thrown from one off-stage stack; the opening flourish, and it can't outstay its welcome |
| **finish sweep** | 5 | 90 ms | fifty-odd cards on their way to a win — a payoff, so a touch more languid than the deal |
| **console move** | 2 | 170 ms | one card, or a short run, that has to be *followable*: you're reading the log to see what the command did |
| **autoplay step** | 3 | 140 ms | the console's knobs, quickened — one of forty moves on the way to a win |

What the pairs work out to in practice:

| | n | Δ | t | total |
|---|---|---|---|---|
| deal, full deck | 52 | 62 ms | 311 ms | 3.5 s |
| deal, `micro` | 16 | 54 ms | 268 ms | 1.1 s |
| finish sweep, full board | 52 | 84 ms | 418 ms | 4.7 s |
| console, one card | 1 | — | 170 ms | 170 ms |
| console, three-card run | 3 | 128 ms | 255 ms | 510 ms |
| autoplay, one card | 1 | — | 140 ms | 140 ms |

The two deal rows are the time-per-card pacing doing its job: a sixteen-card
board opens in a third of the time rather than dawdling through a deck-sized
budget.

The console's `C = 2` is what makes a `moverun` read as cards moving *in order*
rather than as one undifferentiated blob. That's the reason it isn't simply the
sweep's numbers scaled down.

Autoplay is worth a note, because it's the one case where the pair doesn't
describe the whole animation. Autoplay is a *run of moves*, not one move with
many cards in it: each planned move gets its own `staggerTiming` call, and the
next only starts once the previous one's cards have landed. What you watch is the
line being played, in order — not a board that rearranged itself while you
blinked.

## What rides along with a flight

The timing is only half of it. Three other things are pinned to the same `i·Δ`
schedule, and they're why a move goes through this path rather than leaning on
`.stacking-card`'s plain left/top transition:

- **The hold at the origin.** `fill: "backwards"` keeps a card at its starting
  offset through its `delay`, so a whole batch can be launched in one loop and
  each card still waits its staggered turn.
- **The z-hold.** A card keeps its *resting* layer until it launches, then jumps
  to `finishFlightZBase + i` for the flight. The `+ i` is arrival-order stacking —
  in a sweep, King last — and the hold is what stops a departing card sliding
  *under* the fan it hasn't finished leaving.
- **The tilt timing**. The hand-placed angle is keyed on where a card
  rests, so a card re-tilts the moment it's laid out somewhere new. Left alone the
  whole board would swing to its landing angles in unison, in place, before
  anything moved. Each card's tilt transition is pushed out to its own `i·Δ` and
  stretched over `t`, so the rotation rides along with the movement.

All flights share one easing — `cubic-bezier(0.22, 1, 0.36, 1)`, a soft ease-out
with no overshoot. A card landing on a foundation shouldn't bounce.

## When nothing flies

Every one of the four collapses to an instant `reflowAll` under any of:

- the OS asking for reduced motion (`prefers-reduced-motion: reduce`)
- the URL's `?animate=off`
- nothing to move (`n = 0`)

The model is already committed before any of this runs — a flight is a purely
*visual* catch-up over cards that the state says have already moved. So skipping
it is always safe, and undo and persistence stay correct however a sequence is
interrupted.

## Before you retune

1. **Change the pair, not the derivation.** If a sequence feels wrong, it's C or
   P. Reaching past `staggerTiming` for a hand-computed delay means the last card
   no longer lands at `T`, and `onfinish` on the last flight is what raises the
   win overlay.
2. **Don't share a pair between two of the four.** They read as duplicates and
   they aren't; the whole point of four constants is that a console move can be
   slowed to watch a particular deal without touching how the deal opens.
3. **Check the short case, not just the full deck.** A `micro` board, a one-card
   console move and a two-card `moverun` are where the clamp and the `n = 1`
   branch show up.
4. **Retime with the real thing.** `mise run autoplay -- <deal>` plays a deal to
   the win overlay in a browser, which is the only way to see a pacing change.
