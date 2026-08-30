// The "Wiggle Waggle" row: the shake-to-jostle switch.
//
// Unlike the plain `<MenuToggleRow>`, its label is title-cased and it deliberately
// carries *no* description — the other settings explain themselves; finding out
// what this one does is the point. That's why it's a component rather than a
// `<MenuToggleRow>` call: the row's whole shape is decided by `Motion.state`
// rather than by a bool plus a fixed line of copy.
//
// The subtitle line under the title appears *only* to report a problem
// (`Motion.subtitle`): blocked, no sensor, or an insecure origin. A healthy switch
// — off or listening — shows just the title and the switch, so `desc` is simply
// absent in those states and `<MenuRow>` renders no description element at all.
// The switch reads on only while actually listening (`Motion.isOn`); a `Blocked`
// state snaps it back to off but keeps its subtitle.
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

let make = ({state, onToggle}) =>
  <MenuRow
    label="Wiggle Waggle"
    desc=?{Motion.subtitle(state)}
    trailing={MenuRow.Switch(Motion.isOn(state))}
    onClick=onToggle
  />
