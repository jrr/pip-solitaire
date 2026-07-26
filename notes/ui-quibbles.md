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
