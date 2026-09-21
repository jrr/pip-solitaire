// An action row, lifted out of `Menu` into its own pure component: the same
// box and label/description stack as `<MenuToggleRow>`, but it *does* something
// once rather than flipping a setting, so it carries no switch — a `<MenuRow>` with
// nothing at its right-hand end.
//
// `enabled` drives the real `disabled` attribute — a disabled button emits no
// click at all — and the muted styling that goes with it (`.menu-row--action`,
// the one kind of row that is ever disabled).
//
// A row with something to report afterwards — where a link went, what the solver
// found — folds that line into `desc` rather than rendering one of its own, so saying
// it doesn't change the row's height and shove everything below it down the panel. The
// Debug screen's Share and Autoplay rows are both that shape: see `<MenuDebugScreen>`.
type props = {
  label: string,
  desc: string,
  enabled: bool,
  onClick: unit => unit,
}

let make = ({label, desc, enabled, onClick}) => <MenuRow label desc enabled onClick />
