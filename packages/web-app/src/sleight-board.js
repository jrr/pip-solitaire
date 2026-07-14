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
//              its `detail` carrying the card's current rotation `{ angle }` in
//              degrees. The rotation is applied by the CSS animation, so there's
//              nothing to read on the JS side except the *computed* transform —
//              which is exactly what we sample at click time (see below).
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
    const card = root.querySelector(".card");
    card.addEventListener("click", () => {
      // outward: tell whoever's listening which way the card is pointed right
      // now. The animation lives entirely in CSS, so we sample the *computed*
      // transform and decode its 2-D matrix — `matrix(a, b, c, d, …)`, where
      // the rotation is atan2(b, a). `none` (no transform yet) reads as 0°.
      const t = getComputedStyle(card).transform;
      const m = t.match(/matrix\(([^)]+)\)/);
      let angle = 0;
      if (m) {
        const [a, b] = m[1].split(",").map(Number);
        angle = (Math.atan2(b, a) * 180) / Math.PI;
      }
      this.dispatchEvent(
        new CustomEvent("card-poked", {
          detail: { angle },
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
