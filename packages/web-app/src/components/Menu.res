// The menu (#109): a slide-over overlay opened from the top bar's Menu button,
// holding everything that isn't day-to-day play.
//
// **This file is the pane, not its contents (#307).** It owns the overlay, the
// backdrop, the panel, which of the three screens is showing, and the About footer
// that sits under all of them. Everything inside a screen is a component of its own
// under `components/` — `<MenuMainScreen>`, `<MenuSettingsScreen>`,
// `<MenuDebugScreen>`, and the rows they're built from (`<MenuHeader>`,
// `<MenuToggleRow>`, `<MenuActionRow>`, `<MenuNavRow>`, `<MenuGameButton>`,
// `<MenuWiggleRow>`) — each with its own props record and its own test, the shape
// `<AboutFooter>` established when it was lifted out of here for the same reason
// (#201). What each screen holds, and why, is documented in its own file.
//
// **The props record is one field per screen, not one field per thing on it
// (#308).** It used to be flat — 37 fields, every one of them re-declared from the
// screen below and re-declared again from `Main`'s model above, so a seventh switch
// meant editing four files and this one paid six lines for it without ever reading
// the value. It now carries each child's *own* props record whole and hands it
// straight over, which is the same move #300 made on the board boundary: pass the
// record, don't re-spell its fields. Adding anything to a screen is now that
// screen's business and `Main`'s, and this file doesn't change at all.
//
// What's left here is genuinely the pane's: whether it's open, which screen shows,
// the backdrop's close, and the one decision it makes about the footer (below).
//
// The pane has **three screens** (#191): the **main menu**, a dedicated **Settings**
// screen, and a **Debug** screen nested one level below Settings — which one shows
// is chosen by the `screen` variant. The **About** footer (version line + update
// controls) stays put across all three — only the content above it swaps. Reopening
// the menu always lands on the main screen (the chrome resets `screen` to `Main` when
// it closes/opens the menu).
//
// The **About** footer is the build/version line and, when a service-worker update is
// waiting, the green **Update** button (#165). The adaptive **update-check** button
// (#112) folds into that footer too: it used to be its own "Updates" section above
// About; the build info and the update check belong together, so `Menu` hands the
// footer a `refresh` vnode (a `<RefreshControl>` when a worker state is known, an
// empty node otherwise) and the footer tucks it under the version row. Both
// `<AboutFooter>` and `<RefreshControl>` are their own pure components, lifted out so
// their size-across-state can be pinned in isolation (#201) — see those files for the
// "don't wiggle" story.
//
// It's a pure `props => vnode` in the `VersionBadge` mold (see VersionBadge for why
// the record is spelled out by hand). Open/closed and which-screen are chrome model
// state passed in as `open_`/`screen`; a click on the backdrop or the close button
// calls `onClose`. Layout lives in Menu.css.

// Which of the pane's three screens is showing (#191). Reopening the menu
// resets this to `Main` (see the chrome model), so a visit to Settings/Debug never
// lingers into the next open.
type screen =
  | Main
  | Settings
  | Debug

// The adaptive refresh control folded into the About footer (#112): one button whose
// `label` and click behaviour adapt to whether a service worker is registered
// ("Refresh" force-reloads a cache-only install; "Check for updates" checks a
// real install without applying — see Refresh/Main). `busy` spins the on-button
// indicator while a check/refresh is in flight (#201). The whole control is a
// `props` option: `None` (still detecting, or `serviceWorker` unsupported) hides it.
type refreshButton = {
  label: string,
  busy: bool,
  onClick: unit => unit,
}

// What the About footer needs from the app. It's `AboutFooter.props` minus the
// `refresh` slot and plus the button that fills it, because *whether* there's a
// refresh button to show is the one thing about that footer this pane decides (it
// depends on which screen is up — see `make`). Everything else it just carries.
type about = {
  version: string,
  buildTime: string,
  updateVisible: bool,
  onReload: unit => unit,
  refreshButton: option<refreshButton>,
}

type props = {
  open_: bool,
  screen: screen,
  // The backdrop and, through each screen's own props, the ✕ in its header.
  onClose: unit => unit,
  // One field per screen, carried whole and handed straight to the component that
  // owns it. `settings` is two fields wide because that screen holds its own state
  // (#308); the other two are still flat records built by `Main`.
  main: MenuMainScreen.props,
  settings: MenuSettingsScreen.props,
  debug: MenuDebugScreen.props,
  about: about,
}

let make = ({open_, screen, onClose, main, settings, debug, about}) => {
  // The update-check button folded into the About footer: shown on the Settings and
  // Debug screens once a service-worker state has been detected, and never on the
  // main menu — which is where the detection is kicked off (see `Main`).
  let refresh = switch (screen, about.refreshButton) {
  | (Main, _) | (_, None) => Html.array([])
  | (_, Some({label, busy, onClick})) => <RefreshControl label busy onClick />
  }

  // The screen itself. `Html.jsx(C.make, props)` is exactly what `<C … />` lowers to
  // (see Html.res); it's written that way rather than as JSX because JSX *builds* the
  // props record out of attributes, and these records already exist — the whole point
  // of carrying them whole is not to take them apart again on the way through.
  let content = switch screen {
  | Main => Html.jsx(MenuMainScreen.make, main)
  | Settings => Html.jsx(MenuSettingsScreen.make, settings)
  | Debug => Html.jsx(MenuDebugScreen.make, debug)
  }

  <div id="menu-overlay" hidden={!open_}>
    <div className="menu-overlay__backdrop" onClick={_ => onClose()} />
    <aside className="menu-panel" attrs={[("aria-label", "Menu")]}>
      {content}
      <AboutFooter
        version={about.version}
        buildTime={about.buildTime}
        updateVisible={about.updateVisible}
        onReload={about.onReload}
        refresh
      />
    </aside>
  </div>
}
