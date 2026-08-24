// The "Wiggle Waggle" row (#235), lifted out of `Menu` into its own pure component
// (#307): the shake-to-jostle switch.
//
// Unlike the plain `<MenuToggleRow>`, its label is title-cased and it deliberately
// carries *no* description — the other settings explain themselves; finding out
// what this one does is the point. That's why it's a component rather than a
// `<MenuToggleRow>` call: the row's whole shape is decided by `Motion.state`
// rather than by a bool plus a fixed line of copy.
//
// The subtitle line under the title appears *only* to report a problem
// (`Motion.subtitle`): blocked, no sensor, or an insecure origin. A healthy switch
// — off or listening — shows just the title and the switch, so the row renders no
// `menu-toggle__desc` at all in those states. The switch reads on only while
// actually listening; a `Blocked` state snaps it back to off but keeps its
// subtitle.
//
// Whether the row shows at all is the *caller's* business — it's hidden until the
// Settings title has been tapped ten times (`HiddenOptions`), which
// `<MenuSettingsScreen>` decides.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).
type props = {
  state: Motion.state,
  // Asks for motion permission on the flip; see `Main`'s handler for why that has
  // to happen under the real click.
  onToggle: unit => unit,
}

let make = ({state, onToggle}) => {
  let on = Motion.isOn(state)
  <button
    className={on ? "menu-toggle menu-toggle--on" : "menu-toggle"}
    onClick={_ => onToggle()}
    type_="button"
    role="switch"
    ariaChecked={on ? "true" : "false"}
  >
    <span className="menu-toggle__text">
      <span className="menu-toggle__label"> {Html.string("Wiggle Waggle")} </span>
      {switch Motion.subtitle(state) {
      | Some(line) => <span className="menu-toggle__desc"> {Html.string(line)} </span>
      | None => Html.array([])
      }}
    </span>
    <span className="menu-toggle__switch" />
  </button>
}
