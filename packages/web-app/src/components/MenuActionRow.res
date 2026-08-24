// An action row, lifted out of `Menu` into its own pure component (#307): the same
// box and label/description stack as `<MenuToggleRow>`, but it *does* something
// once rather than flipping a setting, so it carries no switch and stays a plain
// `<button>`.
//
// `enabled` drives the real `disabled` attribute — a disabled button emits no
// click at all, so the handler guard below is belt and braces — and the muted
// styling that goes with it.
//
// The Debug screen's "Share game state" is the only one of these today. Its
// caller folds the transient "where the link went" status into `desc` rather than
// rendering a line of its own, so reporting the outcome doesn't change the row's
// height: see `<MenuDebugScreen>`.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).
type props = {
  label: string,
  desc: string,
  enabled: bool,
  onClick: unit => unit,
}

let make = ({label, desc, enabled, onClick}) =>
  <button
    className="menu-action-row"
    onClick={_ =>
      if enabled {
        onClick()
      }}
    type_="button"
    disabled={!enabled}
  >
    <span className="menu-toggle__text">
      <span className="menu-toggle__label"> {Html.string(label)} </span>
      <span className="menu-toggle__desc"> {Html.string(desc)} </span>
    </span>
  </button>
