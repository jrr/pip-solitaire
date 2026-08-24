// The menu (#109): a slide-over overlay opened from the top bar's Menu button,
// holding everything that isn't day-to-day play.
//
// **This file is the pane, and only the pane (#307/#308).** It owns the overlay, the
// backdrop, the panel, which of the three screens is showing, and the fact that the
// About footer sits under all of them. Everything inside a screen is a component of
// its own under `components/` — `<MenuMainScreen>`, `<MenuSettingsScreen>`,
// `<MenuDebugScreen>`, and the rows they're built from (`<MenuHeader>`, `<MenuRow>`
// and its four variants, `<MenuGameButton>`) — each with its own props record and its
// own test, the shape `<AboutFooter>` established when it was lifted out of here for
// the same reason (#201). What each screen holds, and why, is documented in its own
// file.
//
// **The props are a screen apiece, not a field apiece.** This record used to be flat:
// 37 fields, one per thing any screen wanted, destructured by name here and fanned
// back out to whichever screen it belonged to. That made this file mention every
// setting in the app — a seventh toggle meant declaring it in `Main`'s model, again
// on `Menu.props`, again on the destructure, again on the `<MenuSettingsScreen>` call
// and again on that screen's own props. Four declarations for one switch, and the
// middle two said nothing: they were this file repeating what the screen had already
// specified (#308).
//
// So each screen's props record *is* the field now. `Menu` hands `settings` to
// `<MenuSettingsScreen>` whole and never looks inside it, which is why adding a
// setting no longer touches this file at all. The trade is that `Main` names the
// screens' types rather than only this one's — this stopped being the single boundary
// between the chrome model and the menu, and became the pane that arranges three
// boundaries. That's the honest description of what it was already doing.
//
// The pane has **three screens** (#191): the **main menu**, a dedicated **Settings**
// screen, and a **Debug** screen nested one level below Settings — which one shows
// is chosen by the `screen` variant. The **About** footer (version line + update
// controls) stays put across all three — only the content above it swaps. Reopening
// the menu always lands on the main screen (the chrome resets `screen` to `Main` when
// it closes/opens the menu).
//
// A screen is placed by calling its `make` with the record it was handed, which is
// exactly what `<MenuSettingsScreen …/>` lowers to — the JSX form builds the record
// from attributes, and here the record already exists. Layout lives in Menu.css.

// Which of the pane's three screens is showing (#191). Reopening the menu
// resets this to `Main` (see the chrome model), so a visit to Settings/Debug never
// lingers into the next open.
type screen =
  | Main
  | Settings
  | Debug

type props = {
  open_: bool,
  screen: screen,
  // The backdrop's tap. The ✕ in each screen's header closes the menu too, and is
  // that screen's own `onClose` — the two are wired to the same thunk by `Main`.
  onClose: unit => unit,
  // One record per screen, passed through untouched. The pane chooses which of the
  // three to place; what's in them is between `Main` and the screen.
  //
  // All three are built on every render even though one is placed — the same three
  // records' worth of fields the flat props built before, just grouped, so it costs
  // what it always did. Folding the props into the `screen` variant would build only
  // the one, but `screen` is also a *model* field (`Main`'s `menuScreen`, compared
  // with `!=` in `update`), and a variant carrying closures can't be compared.
  main: MenuMainScreen.props,
  settings: MenuSettingsScreen.props,
  debug: MenuDebugScreen.props,
  // The About footer, under every screen. Its `refresh` slot — the adaptive
  // update-check button (#112), or an empty node — is filled in by `Main`, which is
  // where both halves of that decision live: whether a service-worker state has been
  // detected yet, and which screen is showing (it never appears on the main menu).
  about: AboutFooter.props,
}

let make = ({open_, screen, onClose, main, settings, debug, about}) =>
  <div id="menu-overlay" hidden={!open_}>
    <div className="menu-overlay__backdrop" onClick={_ => onClose()} />
    <aside className="menu-panel" ariaLabel="Menu">
      {switch screen {
      | Main => MenuMainScreen.make(main)
      | Settings => MenuSettingsScreen.make(settings)
      | Debug => MenuDebugScreen.make(debug)
      }}
      {AboutFooter.make(about)}
    </aside>
  </div>
