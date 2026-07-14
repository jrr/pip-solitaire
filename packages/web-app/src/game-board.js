// The <game-board> custom element.
//
// This file is now just the *shell*: the `class extends HTMLElement` lifecycle
// that ReScript can't express (no class syntax) plus registration. Everything
// that used to be hand-written DOM here — the `innerHTML` string, `querySelector`,
// the click listener, the transform decoding — moved into Board.res, which
// renders the inside as ReScript JSX on the Html runtime (see Board.res).
//
// This shell is fully generic about the boundary in *both* directions — it
// knows no event names, command shapes, or payloads. Board.res owns all of that
// (see OutwardEvents / InwardEvents); the shell only moves opaque values across:
//   inward   — `send(command)` forwards an InwardEvents command straight to the
//              component's dispatch (the conduit `mount` returns).
//   outward  — Board.res emits its CustomEvents off the host itself.

import { mount } from "./Board.res.mjs";

class GameBoard extends HTMLElement {
  connectedCallback() {
    // `mount` paints into the shadow root, fires outward events off the host
    // (this), and returns the inward conduit: a function that forwards commands
    // to the component's dispatch. Flush anything queued before we upgraded.
    this._send = mount(this.attachShadow({ mode: "open" }), this);
    this._pending?.forEach((command) => this._send(command));
    this._pending = null;
  }

  // inward: forward a command untouched. Custom elements can be handed messages
  // before `connectedCallback` runs, so buffer until the conduit exists.
  send(command) {
    if (this._send) this._send(command);
    else (this._pending ??= []).push(command);
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
