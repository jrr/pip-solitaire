// The <sleight-board> custom element — the "inside" of the spike.
//
// Deliberately tiny: it paints a spinning 🃏 into a shadow root and speaks the
// standard custom-element contract of *attributes in, events out*:
//
//   inward   — the observed `spin="cw" | "ccw"` attribute. The element never
//              exposes an imperative "reverse" method; callers just flip the
//              attribute and CSS reacts (see `animation-direction` below), so
//              changing direction needs no JavaScript at all.
//   outward  — a `card-poked` CustomEvent dispatched on click, with
//              `bubbles: true, composed: true` so it escapes the shadow root,
//              its `detail` carrying the card centre `{ x, y }` in viewport
//              coordinates.
//
// It's authored in plain JS on purpose: `class extends HTMLElement` with
// lifecycle callbacks is the one genuinely class-shaped part of the contract,
// and ReScript has no class syntax. Everything *across* the boundary — toggling
// the attribute inward, listening for the event outward — lives in ReScript
// (see Main.res), which is the ergonomics this spike is checking.

const css = `
  :host { display: inline-block; cursor: pointer; }
  .card { font-size: 4rem; animation: spin 2s linear infinite; }
  /* inward: the whole "reverse" behaviour is this one CSS rule reacting to the
     host attribute — no JS branch, no re-render. */
  :host([spin="ccw"]) .card { animation-direction: reverse; }
  @keyframes spin { to { transform: rotate(360deg); } }
`;

class SleightBoard extends HTMLElement {
  connectedCallback() {
    const root = this.attachShadow({ mode: "open" });
    root.innerHTML = `<style>${css}</style><div class="card">🃏</div>`;
    root.querySelector(".card").addEventListener("click", () => {
      const r = this.getBoundingClientRect();
      // outward: tell whoever's listening where the card is right now.
      this.dispatchEvent(
        new CustomEvent("card-poked", {
          detail: { x: r.x + r.width / 2, y: r.y + r.height / 2 },
          bubbles: true,
          composed: true,
        }),
      );
    });
  }
}

// Registration is exposed as an explicit call rather than a bare import side
// effect, so Main can guarantee the element is defined before it creates one.
// Idempotent: safe if called more than once (e.g. under HMR).
export function register() {
  if (!customElements.get("sleight-board")) {
    customElements.define("sleight-board", SleightBoard);
  }
}
