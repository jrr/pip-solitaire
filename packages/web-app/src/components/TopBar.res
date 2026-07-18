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

let make = ({onMenu, onNewGame, updateVisible, onReload}) =>
  <header id="top-bar">
    <button
      className="top-bar__button"
      onClick={_ => onMenu()}
      attrs={[("type", "button"), ("aria-label", "Open menu")]}
    >
      {Html.string("☰ Menu")}
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
      {Html.string("↶ Undo")}
    </button>
    <UpdateButton visible={updateVisible} onReload={onReload} />
  </header>
