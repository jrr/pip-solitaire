// The app's single top bar (#109): all the chrome, banished to the top so the
// bottom of the screen — the thumb arc — stays clear for dragging cards. Left to
// right: a **Menu** button (opens the slide-over menu), a **New Game** button
// (re-deals the primary game — its behaviour is the scene's re-deal hook, #108),
// a reserved **Undo** slot (disabled until #85 lands move history in `core`), and
// the conditional **Update** control (`<UpdateButton>`, folded in from its old
// fixed top-right corner), pushed to the far right.
//
// A component is just a `props => vnode` function; the JSX transform lowers
// `<TopBar .../>` to `Html.jsx(TopBar.make, props)` and fills this record from the
// attributes. See `VersionBadge` for why the record is spelled out by hand rather
// than derived by the `@jsx.component` sugar. Layout lives in the stylesheet in
// index.html; here we build only structure and behaviour.
type props = {
  onMenu: unit => unit,
  onNewGame: unit => unit,
  updateVisible: bool,
  onReload: unit => unit,
}

// The undo glyph, drawn rather than typed. A Unicode arrow (e.g. `↶`, U+21B6)
// isn't in Libre Franklin, so each platform substitutes its own fallback font
// for that one character and the icon looks different everywhere. Drawing it as
// an inline SVG — the same way cards and the app icon are drawn — makes it
// render identically on every browser. `fill: currentColor` so it inherits the
// button's text colour (and the dimmed `--reserved` opacity) for free.
let undoIcon =
  <svg
    className="top-bar__icon"
    attrs={[("viewBox", "0 0 24 24"), ("aria-hidden", "true"), ("focusable", "false")]}
  >
    <path
      attrs={[
        (
          "d",
          "M12.5 8c-2.65 0-5.05.99-6.9 2.6L2 7v9h9l-3.62-3.62c1.39-1.16 3.16-1.88 5.12-1.88 3.54 0 6.55 2.31 7.6 5.5l2.37-.78C21.08 11.03 17.15 8 12.5 8z",
        ),
        ("fill", "currentColor"),
      ]}
    />
  </svg>

let make = ({onMenu, onNewGame, updateVisible, onReload}) =>
  <header id="top-bar">
    <button
      className="top-bar__button"
      onClick={_ => onMenu()}
      attrs={[("type", "button"), ("aria-label", "Open menu"), ("title", "Menu")]}
    >
      {Html.string("☰")}
    </button>
    <button className="top-bar__button" onClick={_ => onNewGame()} attrs={[("type", "button")]}>
      {Html.string("New Game")}
    </button>
    <button
      className="top-bar__button top-bar__button--reserved"
      attrs={[
        ("type", "button"),
        ("disabled", ""),
        ("aria-disabled", "true"),
        ("title", "Undo — coming soon"),
        ("aria-label", "Undo — coming soon"),
      ]}
    >
      {undoIcon}
    </button>
    <UpdateButton visible={updateVisible} onReload={onReload} />
  </header>
