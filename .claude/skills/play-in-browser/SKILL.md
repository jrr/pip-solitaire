---
name: play-in-browser
description: Play pip's FreeCell in a real browser — drive the built web app with pointer drags to play a deal end to end, try a move by hand, reproduce a board position, or see how the game actually behaves. Use when asked to play the game, to check something in the running app rather than in tests, to reproduce a bug by playing, or to capture what a real game looks like.
---

# Playing the game in a browser

The web app is playable by an agent. Every move is a real pointer drag on the
rendered board — no reaching into game state, no calling `core` directly — so
whatever you observe this way is evidence about the app a player uses.

The machinery is in three parts. Two of them live in
`packages/web-app/scripts/autoplay/`; the third is in `core`:

| part | where | what it does |
| --- | --- | --- |
| eyes | `autoplay/read-board.mjs` | reads the board off the DOM: zone boxes, card `aria-label`s, `settle()`, and the `Position` it all adds up to |
| brain | `core`'s `Position` + `Solver` | the rules, and a solver that plans to a finishable board — in core, not here (#290) |
| hands | `autoplay/autoplay.mjs` | `playGame()` and `dragMove()` — a planned move as a real drag, then look again |

The brain used to be a JavaScript mirror of core's rules kept beside the other
two. It isn't any more: there is one set of rules, in ReScript, and the harness
imports them like any other consumer. `mise run solve -- <deal>` runs that brain
with no browser attached — seconds instead of a minute — which is the faster way
to answer anything about *planning* rather than about the app.

## Just play a game

```
mise run autoplay                    # deal 1
mise run autoplay -- 24680           # a particular deal
mise run autoplay -- 1-25            # a range, to soak the harness
mise run autoplay -- --headed 24680  # watch it play (a human at a desktop)
mise run autoplay -- --shots out 42  # write deal / mid-game / win screenshots
```

It prints the play-by-play and a summary line per deal, and exits non-zero if any
deal fails to reach the win overlay. `browser-tests/autoplay.spec.mjs` runs the
same harness on a fixed deal as a test.

## Play by hand (the interactive case)

For anything that isn't "play a whole game" — trying one move, checking a
highlight, reproducing a position — write a throwaway script in your scratchpad
and run it with `node` from `packages/web-app`. The pieces are exported for this:

Import everything by **absolute path**, core included: a script outside the repo
has no `node_modules` above it, so the bare `core/...` specifier that
`read-board.mjs` uses won't resolve from your scratchpad.

```js
import { startPreview, launchChromium } from "/abs/path/packages/web-app/scripts/lib/preview-app.mjs"
import { look, dragMove } from "/abs/path/packages/web-app/scripts/autoplay/autoplay.mjs"
import { settle, cardId } from "/abs/path/packages/web-app/scripts/autoplay/read-board.mjs"
import * as Position from "/abs/path/packages/core/src/Position.res.mjs"
import * as Solver from "/abs/path/packages/core/src/Solver.res.mjs"

const { base, close } = await startPreview()          // serves the built dist/
const browser = await launchChromium()
const page = await browser.newPage({ baseURL: base, viewport: { width: 900, height: 1100 } })

await page.goto("/?game=freecell&seed=24680&animate=off")
await settle(page)

let view = await look(page)                            // { geom, piles, cards, codes, state }
console.log(view.codes.slice(8))                       // the eight cascades, bottom-first

// `view.state` is a `Position` — the packed board core plans with.
const moves = Position.legalMoves(view.state)
console.log(moves.map(Position.describeMove))          // what's playable right now

// Play the first move on offer (on an opening board, usually an Ace going home).
// `dragMove` takes a *step* — which card to grab, what that grab should raise,
// where it lands — and `Solver.stepFor` makes one from any move.
await dragMove(page, view, Solver.stepFor(view.state, moves[0]))  // settles before returning
view = await look(page)                                // always re-read after a drag

// Or aim at one card. `legalMoves` only lists *movable* cards — the top of a pile
// or the head of a run — so a buried card simply isn't in the list, and `find`
// gives you `undefined` rather than a move that would bounce.
const move = Position.legalMoves(view.state).find((m) => m.card === cardId("QS"))
if (move) await dragMove(page, view, Solver.stepFor(view.state, move))

await page.screenshot({ path: "/tmp/board.png" })
await browser.close(); await close()
```

`Solver.planSteps(view.state)` gives a whole plan of those steps to a finishable
board — that's what `playGame()` plays. Every card in a move is a small int; use
`Position.code(id)` to print one and `cardId("QS")` to name one.

`mise run bundle` first — `startPreview` serves `dist/`, and `assertBundled()`
will tell you if it's stale. (The `autoplay` task carries that `depends`; a
hand-run script doesn't.)

## Driving the app into a position

Query parameters, all documented in `src/platform/AppUrl.res`:

- `?game=freecell` — open a game by id (`freecell`, `mini`, `micro`).
- `?scene=gallery` — mount a non-game scene (`gallery`, `raster`, `motion`).
- `?seed=N` — open deal N of whichever game is mounted. Deterministic: the same N
  always deals the same board.
- `?animate=off` — skip the opening fly-in, so the board is at its resting
  positions as soon as the cards exist. **Use this**, or your first grab races
  the deal.
- `?state=<name>` — a named scenario from `core`'s `Scenario`: `midgame`,
  `almost-won`, `supermove`, `sendhome`, `finish`. Much faster than playing into
  a position when you only need to be *in* one.

## What you need to know about the board

- **Sixteen `.drop-zone`s in board order**: 0–3 free cells, 4–7 foundations, 8–15
  cascades (`Game.freecellDeal`'s pile order).
- **Cards are positioned siblings, not children of their zones.** A card belongs
  to the lowest zone above it in its column — that's how `assignPiles` tells a
  cascade card from one in the cell overhead.
- **Card identity comes from the art's `aria-label`** ("ace of spades",
  `Deck.cardName`).
- **Only a card that heads a legal run is draggable.** Grabbing one lifts the
  whole run below it — that's how a supermove is played, as one gesture.

## Four things that will bite you

1. **Grab the sliver, not the centre.** A buried card in a fan shows only the
   band above the next card (33px of a 142px card at desktop size). Press its
   centre and you press the card on top of it, and lift the wrong span.
2. **The drop is decided by the card's rect, not the pointer.** `zoneAt`
   hit-tests the grabbed card: centre x inside the zone's x-span, rect
   overlapping vertically. The card tracks the pointer by its grab offset, so
   subtract that offset from the target — otherwise a card grabbed by its sliver
   lands a row high, on a free cell instead of the cascade beneath it.
3. **A squared pile has no readable position — ask the accessible tree.**
   Foundations stack every card at identical coordinates, so DOM order there is
   z-order, not pile order (one really does come back as `3H AH 4H 2H`). Since
   #267 reflow leaves only the visible card of a squared pile in the accessible
   tree, so the announced card *is* the top: `foundationTop` reads that, and
   checks it against the pile's contents. Cascades are `Fanned` and *are*
   readable by position.
4. **The board moves on its own after a move.** Safe auto-collect
   (`Reducer.autoCollect`, on by `Options.default`) sends cards home after every
   accepted move — until `canFinish` flips true, at which point it stands aside
   and a **Finish** button appears that plays the rest home. So always `settle()`
   and re-read; never assume the board is just your move applied.

## House rules to keep

- **Believe the screen.** Read the board back after every drag and compare it to
  what you expected. If they differ, re-read and re-plan; don't push on with a
  stale picture.
- **Don't reach into game state to make something work.** The value of playing
  this way is that it can't lie about the app. If a move can't be made by
  dragging, that's a finding, not an obstacle to route around.
- **If the app disagrees with `core`, that's a finding about the app.** There's
  no mirror to fix any more — the harness plans with core's own rules, so a
  board that doesn't match what core predicted means the running app did
  something its own rules don't. `autoplay.spec.mjs` asserts the two never
  disagree over a whole game, so a drift shows up there. (The rules themselves
  are held against `Reducer` by `core`'s `Position_test`, which needs no
  browser.)
