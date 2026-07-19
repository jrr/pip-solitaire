// The app's single top bar (#109): all the chrome, banished to the top so the
// bottom of the screen — the thumb arc — stays clear for dragging cards. Left to
// right: a **Menu** button (opens the slide-over menu), a **New Game** button
// (re-deals the primary game — its behaviour is the scene's re-deal hook, #108),
// **Undo** and **Redo** buttons (step through the board's move history, #85 —
// each disabled when there's nothing to step to), and the conditional **Update**
// control (`<UpdateButton>`, folded in from its old fixed top-right corner),
// pushed to the far right.
//
// A component is just a `props => vnode` function; the JSX transform lowers
// `<TopBar .../>` to `Html.jsx(TopBar.make, props)` and fills this record from the
// attributes. See `VersionBadge` for why the record is spelled out by hand rather
// than derived by the `@jsx.component` sugar. Layout lives in the stylesheet in
// index.html; here we build only structure and behaviour.
type props = {
  onMenu: unit => unit,
  onNewGame: unit => unit,
  onUndo: unit => unit,
  onRedo: unit => unit,
  canUndo: bool,
  canRedo: bool,
  updateVisible: bool,
  onReload: unit => unit,
}

// A history button's attributes: greyed out and non-interactive (`disabled`) when
// there's nothing to step to, so the control mirrors the board's history exactly.
let historyAttrs = (~enabled: bool, ~label: string) =>
  enabled
    ? [("type", "button"), ("aria-label", label)]
    : [("type", "button"), ("disabled", ""), ("aria-disabled", "true"), ("aria-label", label)]

let make = ({onMenu, onNewGame, onUndo, onRedo, canUndo, canRedo, updateVisible, onReload}) =>
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
      className="top-bar__button"
      onClick={_ => onUndo()}
      attrs={historyAttrs(~enabled=canUndo, ~label="Undo")}
    >
      {Html.string("↶ Undo")}
    </button>
    <button
      className="top-bar__button"
      onClick={_ => onRedo()}
      attrs={historyAttrs(~enabled=canRedo, ~label="Redo")}
    >
      {Html.string("↷ Redo")}
    </button>
    <UpdateButton visible={updateVisible} onReload={onReload} />
  </header>
