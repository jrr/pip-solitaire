// The <game-board> custom element.
//
// This file is now just the *shell*: the `class extends HTMLElement` lifecycle
// that ReScript can't express (no class syntax) plus registration. Everything
// that used to be hand-written DOM here — the `innerHTML` string, `querySelector`,
// the click listener, the transform decoding — moved into Board.res, which
// renders the inside as ReScript JSX on the Html runtime (see Board.res).
//
// The custom-element contract is unchanged (*attributes in, events out*), but
// this shell is now fully generic about it: it knows no event names or payload
// shapes. Board.res defines and fires its own events (see `Html.emit` /
// `cardPoked`); all we do is hand it the host element to fire them from.
//   inward   — the observed `spin="cw" | "ccw"` attribute; CSS in Board.res
//              reacts, so changing direction still needs no JavaScript.
//   outward  — Board.res emits `card-poked` off the host itself.

import { mount } from "./Board.res.mjs";

class GameBoard extends HTMLElement {
  connectedCallback() {
    // Hand the ReScript view the shadow root to paint into and the host element
    // to fire events from. That's the whole boundary — no per-event glue here.
    mount(this.attachShadow({ mode: "open" }), this);
  }
}

// Registration is exposed as an explicit call rather than a bare import side
// effect, so Main can guarantee the element is defined before it creates one.
// Idempotent: safe if called more than once (e.g. under HMR).
export function register() {
  if (!customElements.get("game-board")) {
    customElements.define("game-board", GameBoard);
  }
}
