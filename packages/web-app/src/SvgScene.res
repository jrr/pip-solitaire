// The SVG scene: proof that the hand-rolled `Html` runtime renders real vector
// graphics, not just HTML. It replaces the old "Coming soon" placeholder and is
// the enabling demo for the card gallery (#36) — cards will be typed vnodes like
// this, never `innerHTML` strings.
//
// Everything here goes through the same runtime and the same Elm-style loop as
// the chrome: the `<svg>` and its children are ordinary JSX vnodes, so they are
// created in the SVG namespace (see Html.create's `inSvg`), carry arbitrary
// geometry via the generic `attrs` map, and — crucially — *diff*. Clicking
// "Cycle color" changes only the accent `fill`; the loop re-renders, the diff
// sees the same tags, and it patches that one attribute in place. No node is
// torn down and rebuilt (which is what would restart a CSS/WAAPI animation).

type model = {hue: int}

type msg = Cycle

let update = (msg, model) =>
  switch msg {
  | Cycle => ({hue: mod(model.hue + 40, 360)}, Html.noEffect)
  }

let view = (model, dispatch) => {
  // An `hsl()` string is a perfectly good SVG `fill`; the only dynamic attribute
  // in the whole tree, so a click patches exactly one node.
  let accent = `hsl(${Int.toString(model.hue)} 70% 55%)`
  <>
    <svg
      className="svg-card"
      attrs={[
        ("viewBox", "0 0 120 168"),
        ("width", "120"),
        ("height", "168"),
        ("role", "img"),
        ("aria-label", "A generated SVG card"),
      ]}
    >
      <rect
        attrs={[
          ("x", "1"),
          ("y", "1"),
          ("width", "118"),
          ("height", "166"),
          ("rx", "12"),
          ("ry", "12"),
          ("fill", "#0b1220"),
          ("stroke", "#334155"),
          ("stroke-width", "2"),
        ]}
      />
      <path
        attrs={[
          ("d", "M60 40 L88 84 L60 128 L32 84 Z"),
          ("fill", accent),
          ("stroke", "#f8fafc"),
          ("stroke-width", "2"),
          ("stroke-linejoin", "round"),
        ]}
      />
      <circle attrs={[("cx", "60"), ("cy", "84"), ("r", "10"), ("fill", "#0b1220")]} />
      <text
        attrs={[
          ("x", "60"),
          ("y", "156"),
          ("text-anchor", "middle"),
          ("font-size", "12"),
          ("font-family", "Libre Franklin, sans-serif"),
          ("fill", "#94a3b8"),
        ]}
      >
        {Html.string(`hue ${Int.toString(model.hue)}°`)}
      </text>
    </svg>
    <button className="svg-demo-button" onClick={_ => dispatch(Cycle)}>
      {Html.string("Cycle color")}
    </button>
  </>
}

let make = (): Scene.t => {
  id: "svg",
  label: "SVG",
  mount: container => {
    // A self-contained Elm loop rooted at the scene container. The switcher
    // clears the container when another scene is picked, dropping this subtree
    // wholesale, so there's no extra teardown to do.
    Html.mount(~root=container, ~init={hue: 210}, ~update, ~view)->ignore
    () => ()
  },
}
