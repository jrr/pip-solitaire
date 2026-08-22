// A settings toggle row (#139), lifted out of `Menu` into its own pure component
// (#307) alongside the other rows the menu is built from: the label with a
// one-line description under it on the left, a switch track on the right.
//
// It's a `<button role="switch">` — the `Html` runtime only wires clicks, so the
// switch is a plain button, not a checkbox — and toggling `--on` slides the knob
// and greens the track. `aria-checked` is what actually voices the state; the
// class is only how it looks.
//
// This is the menu's most-used row, and the two rows beside it are deliberate
// variations on it rather than separate designs: `<MenuActionRow>` keeps the box
// and the label/description stack but drops the switch (it *does* something once
// rather than holding a state), and `<MenuWiggleRow>` keeps the switch but
// supplies its own label/subtitle rules. Both borrow this file's
// `.menu-toggle__text` stack — see MenuToggleRow.css.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).
type props = {
  label: string,
  // The one-line explanation under the label. Every plain toggle carries one —
  // the row that deliberately has none is `<MenuWiggleRow>`, which is why it's a
  // component of its own rather than a `desc=""` call here.
  desc: string,
  on: bool,
  onToggle: unit => unit,
}

let make = ({label, desc, on, onToggle}) =>
  <button
    className={on ? "menu-toggle menu-toggle--on" : "menu-toggle"}
    onClick={_ => onToggle()}
    attrs={[("type", "button"), ("role", "switch"), ("aria-checked", on ? "true" : "false")]}
  >
    <span className="menu-toggle__text">
      <span className="menu-toggle__label"> {Html.string(label)} </span>
      <span className="menu-toggle__desc"> {Html.string(desc)} </span>
    </span>
    <span className="menu-toggle__switch" />
  </button>
