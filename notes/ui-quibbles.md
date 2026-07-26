# UI quibbles — play-testing notes

Scratch list of minor UI issues noticed while play-testing, to be rolled up into
a single GitHub issue later. Delete this file once that issue is filed.

## 1. Double-tapping to light up valid moves also triggers an auto-move

Observed: double-tapping a card to see its valid destinations lights them up
*and* sends cards home. It shouldn't do the latter.

Cause is the taps themselves, not the double-tap branch. A tap runs through the
same press/release path as a drag, so it dispatches the lawful identity `Move`
(the no-op from #215); `endDrag` takes the reducer's `Ok` and calls
`autoCollectIfEnabled()` (`packages/web-app/src/TableScene.res:1451`) before ever
comparing against `before`. The `GameState.equal` guard two lines down only gates
`recordHistory`, not the collection. So each half of the double-tap sweeps the
board without the player having moved anything.

Worth noting the send-home path is *not* implicated: `doubleTap`
(line 1413) only reaches `flashMoveTargets` when the card has no `Foundation`
move, so a card that lit up is one `sendHome` would never have played. And
`sendHome` itself (line 1330) only dispatches when a real foundation move
exists.

Wanted: auto-collect should follow a move that actually changed the board — gate
`autoCollectIfEnabled()` on the dispatched move changing state, so a no-op drop
(or a tap) sweeps nothing.

## 2. Opening deal has no visible source stack

The deal's shared launch point is invisible: `animateDeal`
(`packages/web-app/src/TableScene.res:1609`) flies every card from
`originY = pr.height +. ch` — a full card height *below* the stage's bottom edge —
and nothing is drawn there, so cards appear out of empty space rather than
visibly leaving a stack.

Wanted:

- A source stack visible at the centre bottom of the screen, so you can see
  cards leaving it. If vertical space is tight it may hang off the bottom edge,
  with only the stack's top edge showing — it just has to be visible enough to
  read as the pile the cards come from.
- Correct ordering: cards should pop off the *top* of that stack. The deal order
  is `dealSequence` (line 1579) — round-robin by slot across the piles, loose
  cards last — so the stack has to be built such that the next card to fly is
  the one on top, and it visibly shrinks as the deal proceeds.
