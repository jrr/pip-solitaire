// The "Wiggle Waggle" row: the shake-to-jostle switch.
//
// It's a component rather than a `<MenuToggleRow>` call because the row's whole
// shape is decided by `Motion.state` rather than by a bool plus a fixed line of
// copy — and the description is the sharpest edge of that. Two things want the one
// subtitle line, so they're ranked rather than concatenated:
//
//   - a **problem** (`Motion.subtitle`): blocked, no sensor, or an insecure origin.
//     It wins whenever there is one, because it's the only place a snap-back to off
//     can explain itself — without it the switch reads as a dropped tap.
//   - otherwise the **teaser**, which explains nothing on purpose. The other
//     settings say what they do; finding out what this one does is the point, so the
//     line asks the question rather than answering it.
//
// The switch reads on only while actually listening (`Motion.isOn`); a `Blocked`
// state snaps it back to off but keeps its problem subtitle.
//
// Whether the row shows at all is the *caller's* business — it's hidden until the
// Settings title has been tapped ten times (`HiddenOptions`), which
// `<MenuSettingsScreen>` decides.
type props = {
  state: Motion.state,
  // Asks for motion permission on the flip; see `<MenuSettingsScreen>`'s `askMotion`
  // for why that has to happen under the real click.
  onToggle: unit => unit,
}

// The line under the title when nothing is wrong: an invitation, not an explanation.
let teaser = "What might this do?"

let make = ({state, onToggle}) =>
  <MenuRow
    label="Wiggle Waggle"
    desc={Motion.subtitle(state)->Option.getOr(teaser)}
    trailing={MenuRow.Switch(Motion.isOn(state))}
    onClick=onToggle
  />
