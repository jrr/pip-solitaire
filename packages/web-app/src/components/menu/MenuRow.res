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
// **The scene rows were the fifth copy**, and the one outside the menu's own
// components: `SceneSwitcher`'s `.scene-menu__row` was the same box in a third
// stylesheet, with one thing none of the four had — a *selected* highlight for the
// scene currently mounted. #334 merged the box through the `--control-*` tokens;
// the highlight is `selected` below (#335), which is what let those rows become
// `<MenuRow>`s at all. `<MenuDisclosure>` draws its rows, and as of #337 so does the
// main screen's games list — the switcher no longer builds any DOM for the menu.
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

// **A row as data**, for the lists whose rows a *caller* knows and a component draws:
// what the row says, what a tap runs, and whether it's the one currently in effect.
// `<MenuDisclosure>`'s entries are these (#336) and so is the main screen's games list
// (#337) — the same three fields, because they are the same thing seen twice: scenes,
// split across two groups of the menu.
//
// It lives here rather than in either of those, being the data one `<MenuRow>` is
// rendered from; `MenuDisclosure.entry` is an alias, so the name those callers already
// use still means this.
//
// `selected` is optional because a list can have nothing to highlight at all: the
// scene rows always have a current one (a scene is mounted), the debug *state* rows
// are jumps that leave nothing behind, and they simply omit it.
type entry = {
  label: string,
  onSelect: unit => unit,
  selected?: bool,
}

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
  // Defaults to false: this row is the one currently in effect, out of a set of
  // rows that pick between alternatives — the mounted scene among the scene rows.
  //
  // A prop rather than a fourth `trailing`, because it is orthogonal to what sits
  // at the row's right-hand end: a `Switch` row could perfectly well be the
  // selected one, and a variant would make those two states mutually exclusive for
  // no reason. `MenuDisclosure`'s `entry` arrived at the same shape independently
  // (#336) and now hands it straight through.
  selected?: bool,
  onClick: unit => unit,
}

// The row's classes. The kind modifier is always present: `--nav` also carries the
// heavier weight, `--action` carries the disabled styling, and `--switch` pairs
// with `--on` for the track. Naming every kind is also what lets a screen's test
// ask for "the toggles" or "the action row" without matching the other rows.
//
// `--active` is appended to whichever kind the row is, rather than replacing it —
// the highlight is a state the row is *in*, not a kind it is. Exported with a
// labelled argument because `SceneSwitcher` still writes this class list onto a
// button it builds by hand, and there should be one spelling of it (#337 hands
// that DOM here too).
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

// The same absent-rather-than-"false" rule as `checkedFor`, and for the same
// reason: `aria-current` is an enumerated attribute, and every row that isn't the
// current one simply doesn't carry it.
//
// `aria-current` rather than `aria-selected`: these rows are navigation — a tap
// changes what's mounted — not options in a listbox.
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
