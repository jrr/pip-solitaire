// Teach Preact the `attrs` escape hatch (SPIKE — see Html.res).
//
// The app writes generic attributes as pairs — `attrs={[("viewBox", …), ("d", …)]}`
// — because the old hand-rolled runtime applied them with `setAttribute`. Preact
// has no such prop: it would set an attribute literally named "attrs". This hook
// runs on every vnode Preact creates (the DOM renderer and
// `preact-render-to-string` share the same `options` object) and expands the
// pairs into real props before anything diffs or serializes them.
//
// This exists so the runtime swap could be evaluated without touching ~40 call
// sites. A real migration deletes it and moves those call sites onto typed props
// (`JsxDOM.domProps` ships a `viewBox`, `d`, `role`, `ariaLabel`, … surface with
// `@rescript/runtime`), which is strictly better: the attribute names get
// checked, and nothing has to run per vnode.
import { options } from "preact";

// Attributes the app writes as a bare presence flag — `("disabled", "")` — the
// way `setAttribute` takes them. Preact reads props, and an empty string is
// falsy there, so it would *remove* the attribute instead of setting it. These
// are the ones the app actually uses; the pair-list is a stringly-typed API and
// this is one of the seams that shows (a typed `disabled?: bool` prop has no
// such ambiguity).
const PRESENCE_ATTRS = new Set([
  "disabled",
  "hidden",
  "checked",
  "selected",
  "readonly",
  "required",
  "open",
]);

let installed = false;

export function install() {
  if (installed) return;
  installed = true;

  const previous = options.vnode;
  options.vnode = (vnode) => {
    const props = vnode.props;
    const attrs = props && props.attrs;
    if (attrs) {
      delete props.attrs;
      for (const [name, value] of attrs) {
        props[name] = value === "" && PRESENCE_ATTRS.has(name) ? true : value;
      }
    }
    if (previous) previous(vnode);
  };
}
