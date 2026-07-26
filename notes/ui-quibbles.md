# UI quibbles — play-testing notes

Scratch list of minor UI issues noticed while play-testing, to be rolled up into
a single GitHub issue later. Delete this file once that issue is filed.

## 1. Double-tap does double duty: hint *and* auto-move

Double-tapping a card to "light up" its valid moves also plays the card when a
foundation will take it. The gesture is overloaded: `doubleTap`
(`packages/web-app/src/TableScene.res:1413`) branches on the card's valid moves —
a `Foundation` move calls `sendHome()` (#122), and only when there is no
foundation move does it fall through to `flashMoveTargets` (#197). So the same
gesture is informational for some cards and a committed move for others, and
there's no way to just *ask* what a playable card can do.

Wanted: double-tap shouldn't trigger the auto-move. (Open question for the
write-up: should send-home move to a different gesture/affordance, or drop
entirely in favour of drag + the existing Finish button?)

See also #2 — an auto-collect firing on the taps themselves may be part of what
this looks like in play.

## 2. Auto-collect fires on no-op drops, not just real moves

Auto-collect should only follow a move that actually changed the board. Today it
follows *any* accepted drop, including the lawful identity re-drop (#215):
`endDrag` adopts the reducer's `Ok` result and calls `autoCollectIfEnabled()`
(`packages/web-app/src/TableScene.res:1451`) before it ever compares against
`before` — the `GameState.equal` guard two lines down only gates
`recordHistory`, not the collection.

Because a plain tap goes through the same press/release path, it dispatches an
identity `Move`, gets `Ok`, and sweeps the board. So tapping a card — including
each half of a double-tap — can send cards home without the player having moved
anything.

Wanted: gate `autoCollectIfEnabled()` on the dispatched move actually changing
state, so a no-op drop (or a tap) sweeps nothing. `sendHome` (line 1330) is
fine as-is: it only dispatches when a real foundation move exists.
