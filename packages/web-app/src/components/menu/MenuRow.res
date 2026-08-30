// **Every row in the menu comes through here**: a full-width `<button>` with a label,
// an optional line explaining it, and something optional on the right.
//
// `<MenuToggleRow>`, `<MenuActionRow>`, `<MenuNavRow>` and `<MenuWiggleRow>` differ in
// exactly one thing — what sits at that right-hand end — so they are thin wrappers,
// each with its own file and tests, which is where the reasoning about a variant
// belongs. The scene rows and the games list come through here too, drawn from `entry`.

%%raw(`import "./MenuRow.css"`)

// What sits at the right-hand end, which is also what *kind* of row this is. `Switch`
// makes the row a real `role="switch"` with `aria-checked`, a `<button>` having no
// checkedness of its own for assistive tech to read; `Chevron` is `aria-hidden`, being
// a direction rather than a word where the label is already the accessible name.
type trailing =
  | Switch(bool)
  | Chevron
  | Nothing

// **A row as data**, for the lists whose rows a *caller* knows and a component draws.
// It lives here rather than in either caller, being what a `<MenuRow>` renders from;
// `MenuDisclosure.entry` is an alias, so the name those callers use still means this.
//
// `selected` is optional because a list can have nothing to highlight at all: the
// scene rows always have a current one, while the debug state rows are jumps that
// leave nothing behind.
type entry = {
  label: string,
  onSelect: unit => unit,
  selected?: bool,
}

type props = {
  label: string,
  // Optional because one row deliberately has none: `<MenuWiggleRow>` shows a line
  // only to report a problem.
  desc?: string,
  trailing?: trailing,
  // Drives the *real* `disabled` attribute, so a disabled row emits no click at all
  // and the handler guard below is belt and braces.
  enabled?: bool,
  // A prop rather than a fourth `trailing`, because it is orthogonal to what sits at
  // the row's right-hand end: a `Switch` row could perfectly well be the selected one,
  // and a variant would make those two states mutually exclusive for no reason.
  selected?: bool,
  onClick: unit => unit,
}

// The kind modifier is always present, which is also what lets a screen's test ask for
// "the toggles" or "the action row" without matching the other rows. `--active` is
// *appended* to it rather than replacing it — the highlight is a state the row is in,
// not a kind it is.
//
// Exported with a labelled argument because `SceneSwitcher` writes this class list
// onto a button it builds by hand, and there should be one spelling of it.
let classesFor = (~selected=false, trailing) => {
  let kind = switch trailing {
  | Switch(true) => "menu-row menu-row--switch menu-row--on"
  | Switch(false) => "menu-row menu-row--switch"
  | Chevron => "menu-row menu-row--nav"
  | Nothing => "menu-row menu-row--action"
  }
  selected ? kind ++ " menu-row--active" : kind
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

// The same absent-rather-than-"false" rule as `checkedFor`. `aria-current` rather than
// `aria-selected`, because these rows are navigation — a tap changes what's mounted —
// not options in a listbox.
let currentFor = selected => selected ? Some("true") : None

let make = (props: props) => {
  let trailing = props.trailing->Option.getOr(Nothing)
  let enabled = props.enabled->Option.getOr(true)
  let selected = props.selected->Option.getOr(false)

  <button
    className={classesFor(~selected, trailing)}
    type_="button"
    disabled={!enabled}
    role=?{roleFor(trailing)}
    ariaChecked=?{checkedFor(trailing)}
    ariaCurrent=?{currentFor(selected)}
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
