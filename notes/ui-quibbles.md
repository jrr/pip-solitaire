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
