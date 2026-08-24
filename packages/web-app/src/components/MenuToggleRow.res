// A settings toggle row (#139), lifted out of `Menu` into its own pure component
// (#307): the label with a one-line description under it on the left, a switch
// track on the right.
//
// It's the menu's most-used row and the plainest use of `<MenuRow>`: a `Switch`
// trailing, whose state comes straight from a bool. `MenuRow` is what makes it a
// real `<button role="switch">` with `aria-checked` — the class only slides the
// knob; the role and the ARIA state are what a screen reader reads.
//
// The rows beside it are the same box with a different right-hand end:
// `<MenuActionRow>` has none (it *does* something once rather than holding a
// state), `<MenuNavRow>` has a chevron, and `<MenuWiggleRow>` has a switch but
// derives its whole shape from `Motion.state` rather than from a bool. All four
// now hand that shape to `<MenuRow>` instead of drawing it themselves.
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
  <MenuRow label desc trailing={MenuRow.Switch(on)} onClick=onToggle />
