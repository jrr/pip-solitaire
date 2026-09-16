// The menu: a slide-over overlay opened from the top bar's Menu button,
// holding everything that isn't day-to-day play.
//
// **This file is the pane, and only the pane.** It owns the overlay, the backdrop, the
// panel, and which of the five screens is showing — nothing that is inside one of them.
// Every screen is a component of its own under `components/` — `<MenuMainScreen>`,
// `<MenuSettingsScreen>`, `<MenuDebugScreen>`, `<MenuGameInfoScreen>`,
// `<MenuAboutScreen>`, and the rows they're built from (`<MenuHeader>`, `<MenuRow>` and
// its four variants, `<MenuGameRow>`, `<MenuGameButton>`) — each with its own props
// record and its own test. What each screen holds, and why, is documented in its own
// file.
//
// **The props are a screen apiece, not a field apiece**. Each screen's props
// record *is* the field: `Menu` hands `settings` to `<MenuSettingsScreen>` whole and
// never looks inside it, which is why adding a setting doesn't touch this file at all.
// Don't flatten a screen's fields up to here — it would put every setting in the app
// through this record and its destructure, saying nothing the screen hasn't already
// specified. The trade is that `Main` names the screens' types rather than only this
// one's: this isn't the single boundary between the chrome model and the menu, it's the
// pane that arranges three of them.
//
// The pane has **five screens**, on two levels. One tap below the **main menu** sit
// **Settings**, **About** and the **game info** screen reached from the "i" beside a
// game's row; one tap below Settings sits **Debug**, which is the only screen about the
// build's tools rather than about the app. Which one shows is chosen by the `screen`
// variant, and reopening the menu always lands on the main screen (the chrome resets
// `screen` to `Main` when it closes/opens the menu).
//
// **Every screen fills the pane.** There is no band the pane keeps outside them and
// draws under whichever is showing: what a screen holds is the screen's, top to bottom,
// so a change to one is a change to one file. `switch` below is the whole of the
// arrangement.
//
// A screen is placed by calling its `make` with the record it was handed, which is
// exactly what `<MenuSettingsScreen …/>` lowers to — the JSX form builds the record
// from attributes, and here the record already exists. Layout lives in Menu.css.

%%raw(`import "./Menu.css"`)

// Which of the pane's five screens is showing. Reopening the menu resets this to `Main`
// (see the chrome model), so a visit to Settings/About/Debug/a game's info never lingers
// into the next open.
//
// **`GameInfo` carries its subject**, which none of the others needs to: the info
// screen is *about* a game, down to the title in its header, so "which screen" and
// "which game" are one answer. It is plain data (`GameInfo.t` is strings and ints, no
// closures), which is what keeps this variant comparable with `!=` where the chrome
// model holds it — the reason the other three screens' props are *not* folded in here.
type screen =
  | Main
  | Settings
  | Debug
  | About
  | GameInfo(GameInfo.t)

type props = {
  open_: bool,
  screen: screen,
  // The backdrop's tap. The ✕ in each screen's header closes the menu too, and is
  // that screen's own `onClose` — the two are wired to the same thunk by `Main`.
  onClose: unit => unit,
  // One record per screen, passed through untouched. The pane chooses which to place;
  // what's in them is between `Main` and the screen.
  //
  // All three are built on every render even though one is placed — the same three
  // records' worth of fields the flat props built before, just grouped, so it costs
  // what it always did. Folding the props into the `screen` variant would build only
  // the one, but `screen` is also a *model* field (`Main`'s `menuScreen`, compared
  // with `!=` in `update`), and a variant carrying closures can't be compared.
  main: MenuMainScreen.props,
  settings: MenuSettingsScreen.props,
  debug: MenuDebugScreen.props,
  about: MenuAboutScreen.props,
  // The fourth screen's record, as a *function* of the game it is about — the one
  // field that can't be a ready-made record, since the game arrives in `screen` and
  // there is no game at all while the other three show. Everything else about it is
  // the same bargain as the three above: what's in the record is between `Main` and
  // the screen, and the pane only places it.
  gameInfo: GameInfo.t => MenuGameInfoScreen.props,
}

let make = ({open_, screen, onClose, main, settings, debug, about, gameInfo}) =>
  <div id="menu-overlay" hidden={!open_}>
    <div className="menu-overlay__backdrop" onClick={_ => onClose()} />
    <aside className="menu-panel" ariaLabel="Menu">
      {switch screen {
      | Main => MenuMainScreen.make(main)
      | Settings => MenuSettingsScreen.make(settings)
      | Debug => MenuDebugScreen.make(debug)
      | About => MenuAboutScreen.make(about)
      | GameInfo(info) => MenuGameInfoScreen.make(gameInfo(info))
      }}
    </aside>
  </div>
