// The app's single top bar (#109): all the chrome, banished to the top so the
// bottom of the screen — the thumb arc — stays clear for dragging cards. Left to
// right: a **Menu** button (opens the slide-over menu), a **New Game** button
// (re-deals the primary game — its behaviour is the scene's re-deal hook, #108),
// live **Undo** / **Redo** buttons (stepping over the board's `GameState` history,
// #85), and the conditional **Update** control (`<UpdateButton>`, folded in from
// its old fixed top-right corner), pushed to the far right.
//
// Undo/redo are driven by the mounted board: it publishes the actions to the
// chrome and reports how much history it holds, so each button enables exactly
// when there's something to step to (`canUndo`/`canRedo`). Undo is *not* special-
// cased on a win — a victory is just another recorded state, so the button stays
// live and steps the player back out of the win overlay (#85).
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

// The undo glyph, drawn rather than typed. A Unicode arrow (e.g. `↶`, U+21B6)
// isn't in Libre Franklin, so each platform substitutes its own fallback font
// for that one character and the icon looks different everywhere. Drawing it as
// an inline SVG — the same way cards and the app icon are drawn — makes it
// render identically on every browser. `fill: currentColor` so it inherits the
// button's text colour (and the dimmed `:disabled` opacity) for free. The redo
// glyph is the same arrow mirrored (`scale(-1,1)` about the 24-wide viewBox), so
// the pair reads as a matched set.
let undoPath = "M12.5 8c-2.65 0-5.05.99-6.9 2.6L2 7v9h9l-3.62-3.62c1.39-1.16 3.16-1.88 5.12-1.88 3.54 0 6.55 2.31 7.6 5.5l2.37-.78C21.08 11.03 17.15 8 12.5 8z"

let undoIcon =
  <svg
    className="top-bar__icon"
    attrs={[("viewBox", "0 0 24 24"), ("aria-hidden", "true"), ("focusable", "false")]}
  >
    <path attrs={[("d", undoPath), ("fill", "currentColor")]} />
  </svg>

let redoIcon =
  <svg
    className="top-bar__icon"
    attrs={[("viewBox", "0 0 24 24"), ("aria-hidden", "true"), ("focusable", "false")]}
  >
    <path
      attrs={[
        ("d", undoPath),
        ("fill", "currentColor"),
        ("transform", "scale(-1,1) translate(-24,0)"),
      ]}
    />
  </svg>

// A base attribute list plus the `disabled`/`aria-disabled` pair only when the
// action isn't available — a disabled <button> ignores clicks, so the handler can
// stay wired unconditionally.
let controlAttrs = (~enabled: bool, base: array<(string, string)>): array<(string, string)> =>
  enabled ? base : Array.concat(base, [("disabled", ""), ("aria-disabled", "true")])

let make = ({onMenu, onNewGame, onUndo, onRedo, canUndo, canRedo, updateVisible, onReload}) =>
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
      className="top-bar__button"
      onClick={_ => onUndo()}
      attrs={controlAttrs(
        ~enabled=canUndo,
        [("type", "button"), ("title", "Undo"), ("aria-label", "Undo")],
      )}
    >
      {undoIcon}
    </button>
    <button
      className="top-bar__button"
      onClick={_ => onRedo()}
      attrs={controlAttrs(
        ~enabled=canRedo,
        [("type", "button"), ("title", "Redo"), ("aria-label", "Redo")],
      )}
    >
      {redoIcon}
    </button>
    <UpdateButton visible={updateVisible} onReload={onReload} />
  </header>
