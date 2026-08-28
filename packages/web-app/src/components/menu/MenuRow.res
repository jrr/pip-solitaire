// The row the menu is built out of: a full-width `<button>` carrying a label —
// and, where it has one, the line explaining it — with something optional on the
// right that says what kind of row it is.
//
// **Four components used to draw this box.** `<MenuToggleRow>`, `<MenuActionRow>`,
// `<MenuNavRow>` and `<MenuWiggleRow>` differed in exactly one thing: what sat at
// the right-hand end (a switch, nothing, a chevron, a switch). Everything else —
// the button, the label/description stack, the full-width flex box — was written
// out four times in ReScript and four times in CSS (`.menu-toggle`,
// `.menu-action-row`, `.menu-nav-row` repeated the same nine declarations). The
// CSS half of that was already half-admitted: the action row borrowed the toggle
// row's `.menu-toggle__text` stack by class, from another file.
//
// It was written four ways because the runtime had no children — a base row with a
// slot in it wasn't expressible. `<MenuSection>` (#307) was the first component to
// take children once Preact landed; this is the second, and the four rows are now
// thin wrappers that each say *why* their variant exists and hand the shape here.
// They keep their own files and their own tests, which is where the reasoning about
// each variant belongs.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).

// This component's stylesheet, in the `components` layer (see src/styles/index.css).
%%raw(`import "./MenuRow.css"`)

// What sits at the right-hand end, which is also what *kind* of row this is:
//
//   - `Switch(on)` — a setting that holds a state. The row is a real
//     `role="switch"` with `aria-checked` (a `<button>` has no checkedness of its
//     own for assistive tech to read), and `--on` slides the knob and greens the
//     track.
//   - `Chevron` — the row goes somewhere: a deeper screen. Set in the heavier
//     weight, and the chevron is `aria-hidden`, since it's a direction rather than
//     a word and the row's label is already its accessible name.
//   - `Nothing` — the row does something once. No state to show, so nothing to put
//     on the right.
type trailing =
  | Switch(bool)
  | Chevron
  | Nothing

type props = {
  label: string,
  // The one-line explanation under the label. Optional because one row
  // deliberately has none: `<MenuWiggleRow>` shows a line only to report a problem.
  desc?: string,
  // Defaults to `Nothing` — a row that acts in place is the plain case.
  trailing?: trailing,
  // Defaults to true. Drives the *real* `disabled` attribute, so a disabled row
  // emits no click at all and the handler guard below is belt and braces.
  enabled?: bool,
  onClick: unit => unit,
}

// The row's classes. The kind modifier is always present: `--nav` also carries the
// heavier weight, `--action` carries the disabled styling, and `--switch` pairs
// with `--on` for the track. Naming every kind is also what lets a screen's test
// ask for "the toggles" or "the action row" without matching the other rows.
let classesFor = trailing =>
  switch trailing {
  | Switch(true) => "menu-row menu-row--switch menu-row--on"
  | Switch(false) => "menu-row menu-row--switch"
  | Chevron => "menu-row menu-row--nav"
  | Nothing => "menu-row menu-row--action"
  }

let roleFor = trailing =>
  switch trailing {
  | Switch(_) => Some("switch")
  | Chevron | Nothing => None
  }

// `aria-checked` is what actually voices a switch's state; the class is only how it
// looks. Absent — not "false" — on a row that holds no state at all.
let checkedFor = trailing =>
  switch trailing {
  | Switch(on) => Some(on ? "true" : "false")
  | Chevron | Nothing => None
  }

let make = (props: props) => {
  let trailing = props.trailing->Option.getOr(Nothing)
  let enabled = props.enabled->Option.getOr(true)

  <button
    className={classesFor(trailing)}
    type_="button"
    disabled={!enabled}
    role=?{roleFor(trailing)}
    ariaChecked=?{checkedFor(trailing)}
    onClick={_ =>
      if enabled {
        props.onClick()
      }}
  >
    <span className="menu-row__text">
      <span className="menu-row__label"> {Html.string(props.label)} </span>
      {switch props.desc {
      | Some(desc) => <span className="menu-row__desc"> {Html.string(desc)} </span>
      | None => Html.empty
      }}
    </span>
    {switch trailing {
    | Switch(_) => <span className="menu-row__switch" />
    | Chevron => <span className="menu-row__chevron" ariaHidden="true"> {Html.string("›")} </span>
    | Nothing => Html.empty
    }}
  </button>
}
