// An action row, lifted out of `Menu` into its own pure component: the same
// box and label/description stack as `<MenuToggleRow>`, but it *does* something
// once rather than flipping a setting, so it carries no switch — a `<MenuRow>` with
// nothing at its right-hand end.
//
// `enabled` drives the real `disabled` attribute — a disabled button emits no
// click at all — and the muted styling that goes with it (`.menu-row--action`,
// the one kind of row that is ever disabled).
//
// The Debug screen's "Share game state" is the only one of these today. Its
// caller folds the transient "where the link went" status into `desc` rather than
// rendering a line of its own, so reporting the outcome doesn't change the row's
// height: see `<MenuDebugScreen>`.
type props = {
  label: string,
  desc: string,
  enabled: bool,
  onClick: unit => unit,
}

let make = ({label, desc, enabled, onClick}) => <MenuRow label desc enabled onClick />
