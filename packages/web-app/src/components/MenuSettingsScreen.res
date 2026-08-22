// The menu's **Settings screen** (#191), lifted out of `Menu` into its own pure
// component (#307): the player-facing preferences, the toggles a player can flip
// mid-game. `Menu` puts the About footer under it.
//
// Its content flows from the *top*: the panel grows the space *below* the sections
// (the `.menu-screen` wrapper takes the slack) so the footer still hugs the foot,
// but the settings no longer float in the middle under an empty header. Top to
// bottom:
//   - a header with a **back** button (`onBackToMenu`, returns to the main menu) and
//     the ✕ (`onClose`, still closes the whole menu). Its title doubles as the
//     hidden-options tap target — see `<MenuHeader>` for why that handler is
//     attached here and nowhere else;
//   - the preference toggles (#139), one per row with a one-line description under
//     its label; no section heading — the "Settings" title in the header already
//     names them;
//   - a **Debug** nav row (`onOpenDebug`) that opens the Debug screen — the debug
//     tools moved off Settings entirely onto their own screen so the player
//     preferences stand alone.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).
type props = {
  onClose: unit => unit,
  onBackToMenu: unit => unit,
  onOpenDebug: unit => unit,
  // Counts a tap on this screen's title; every ten flip `revealHidden`
  // (`HiddenOptions`).
  onTapSettingsTitle: unit => unit,
  autoCollect: bool,
  onToggleAutoCollect: unit => unit,
  // "Sloppy placement" (#65) — the slight resting-card tilt, for players who'd
  // rather see cards stacked dead-square.
  cardTilt: bool,
  onToggleCardTilt: unit => unit,
  // "Wiggle Waggle" (#235): not a bool — its `Motion.state` decides both the switch
  // position and the problem-only subtitle (see `<MenuWiggleRow>`).
  wiggle: Motion.state,
  onToggleWiggle: unit => unit,
  // Whether the not-ready-yet settings are showing (`HiddenOptions`). Today that's
  // just the Wiggle Waggle row. A hidden row says nothing about whether its setting
  // is *on*: hiding leaves it running.
  revealHidden: bool,
  // "Display content around notch" (#204) — whether the landscape rail may ride out
  // into the corner wings beside the notch; off clamps every control inside the safe
  // area.
  notchDisplay: bool,
  onToggleNotchDisplay: unit => unit,
}

let make = ({
  onClose,
  onBackToMenu,
  onOpenDebug,
  onTapSettingsTitle,
  autoCollect,
  onToggleAutoCollect,
  cardTilt,
  onToggleCardTilt,
  wiggle,
  onToggleWiggle,
  revealHidden,
  notchDisplay,
  onToggleNotchDisplay,
}) => <>
  <MenuHeader
    title="Settings"
    back={Some({label: "Back to menu", onClick: onBackToMenu})}
    onTitleTap={Some(onTapSettingsTitle)}
    onClose
  />
  <div className="menu-screen">
    <div className="menu-section" attrs={[("aria-label", "Settings")]}>
      <MenuToggleRow
        label="Auto-collect"
        desc="Send cards to the foundations for you as soon as they're ready."
        on=autoCollect
        onToggle=onToggleAutoCollect
      />
      <MenuToggleRow
        label="Sloppy placement"
        desc="Cards don't line up perfectly."
        on=cardTilt
        onToggle=onToggleCardTilt
      />
      {
        // "Wiggle Waggle" (#235) sits below "Sloppy placement" but is *not* nested
        // under it — the two are independent settings. It's hidden until the Settings
        // title has been tapped ten times (`HiddenOptions`) — not ready to be found by
        // a player yet, but reachable on a test device. Ten more taps hide the row
        // again *without* stopping the shake, so an absent row here doesn't mean the
        // board is sitting still.
        revealHidden ? <MenuWiggleRow state=wiggle onToggle=onToggleWiggle /> : Html.array([])
      }
      <MenuToggleRow
        label="Display content around notch"
        desc="Let the controls reach into the corners beside the camera notch."
        on=notchDisplay
        onToggle=onToggleNotchDisplay
      />
    </div>
    <nav className="menu-section" attrs={[("aria-label", "More")]}>
      <MenuNavRow label="Debug" onClick=onOpenDebug />
    </nav>
  </div>
</>
