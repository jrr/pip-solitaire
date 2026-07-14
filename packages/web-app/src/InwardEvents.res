// The single source of truth for messages the outside sends *inward*, into the
// component. Unlike outward events (DOM CustomEvents), these travel through the
// element's generic `send` conduit — a plain method that forwards straight to
// the component's Elm `dispatch` (see game-board.js). Because the element never
// inspects a command, this type is the whole contract: the caller (Main.res)
// and the component (Board.res) both reference it, so they can't drift.
//
// Adding an inward message = adding a constructor here. Constructors can carry
// structured payloads (unlike a string attribute) — that's the point.

type command = Flip // toggle the card's spin direction
