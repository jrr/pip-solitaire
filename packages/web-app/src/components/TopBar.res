// The app's single top bar: all the chrome, banished to the top so the
// bottom of the screen — the thumb arc — stays clear for dragging cards. Two
// controls: a **Menu** button (opens the slide-over menu) and a live **Undo**
// button (stepping back over the board's `GameState` history). Those two are all
// of it: **New Game** and **Restart** live in the menu, and so does the
// **Update** control, in the About footer — its availability is signalled up
// here only by a small green pip on the **Menu** button, the ☰ badge that keeps an
// otherwise hidden call-to-action discoverable.
//
// In portrait the two sit side by side across the top; in the landscape rail
// they split to opposite ends — Menu at the top, Undo at the
// bottom — so that with the rail on a cutout edge both controls land in the
// corner "wings" and stay clear of the centered camera band. The **Redo**
// button was removed (a single undo is enough for this game); redo lives on only
// in `core`'s history for the CLI.
//
// A third, **Hint**, is a beta feature: a press asks the solver for a line from the board
// on the table and shows its next move (`TableScene`'s `hint`), and a toast says what it
// found (`HintToast`). It comes last in the row, so Beta features adding it never moves
// Undo; the landscape rail puts it between the two instead, keeping both in their corners.
//
// Undo is driven by the mounted board: it publishes the action to the chrome and
// reports whether there's anything to step back to, so the button enables exactly
// when history holds a prior state (`canUndo`). Undo is *not* special-cased on a
// win — a victory is just another recorded state, so the button stays live and
// steps the player back out of the win overlay.
//
// A component is just a `props => vnode` function; the JSX transform lowers
// `<TopBar .../>` to `Html.jsx(TopBar.make, props)` and fills this record from the
// attributes. See `VersionBadge` for why the record is spelled out by hand rather
// than derived by the `@jsx.component` sugar. Layout lives in the stylesheet in
// TopBar.css; here we build only structure and behaviour.

%%raw(`import "./TopBar.css"`)

type props = {
  onMenu: unit => unit,
  onUndo: unit => unit,
  canUndo: bool,
  updateVisible: bool,
  // `None` with Beta features off, and then there is no button at all.
  onHint: option<unit => unit>,
}

// The undo glyph, drawn rather than typed. A Unicode arrow (e.g. `↶`, U+21B6)
// isn't in Libre Franklin, so each platform substitutes its own fallback font
// for that one character and the icon looks different everywhere. Drawing it as
// an inline SVG — the same way cards and the app icon are drawn — makes it
// render identically on every browser. `fill: currentColor` so it inherits the
// button's text colour (and the dimmed `:disabled` opacity) for free.
let undoPath = "M12.5 8c-2.65 0-5.05.99-6.9 2.6L2 7v9h9l-3.62-3.62c1.39-1.16 3.16-1.88 5.12-1.88 3.54 0 6.55 2.31 7.6 5.5l2.37-.78C21.08 11.03 17.15 8 12.5 8z"

let undoIcon =
  <svg className="top-bar__icon" viewBox="0 0 24 24" ariaHidden="true" focusable="false">
    <path d={undoPath} fill="currentColor" />
  </svg>

// A lightbulb, drawn for the same reason as the undo glyph.
let hintPath = "M9 21c0 .55.45 1 1 1h4c.55 0 1-.45 1-1v-1H9v1zm3-19C8.14 2 5 5.14 5 9c0 2.38 1.19 4.47 3 5.74V17c0 .55.45 1 1 1h6c.55 0 1-.45 1-1v-2.26c1.81-1.27 3-3.36 3-5.74 0-3.86-3.14-7-7-7z"

let hintIcon =
  <svg className="top-bar__icon" viewBox="0 0 24 24" ariaHidden="true" focusable="false">
    <path d={hintPath} fill="currentColor" />
  </svg>

let make = ({onMenu, onUndo, canUndo, updateVisible, onHint}) =>
  <header id="top-bar">
    <button
      className="top-bar__button top-bar__button--menu"
      onClick={_ => onMenu()}
      type_="button"
      // Fold the pending-update signal into the button's accessible name so the
      // pip isn't a silent, visual-only cue.
      ariaLabel={updateVisible ? "Open menu — update available" : "Open menu"}
      title="Menu"
    >
      {Html.string("☰")}
      // The update pip: a small green presence dot on the Menu button when a new
      // version is waiting. Purely decorative — the state it marks is voiced
      // by the button's `aria-label` above — so it's `aria-hidden`.
      {updateVisible ? <span className="top-bar__pip" ariaHidden="true" /> : Html.empty}
    </button>
    <button
      className="top-bar__button top-bar__button--undo"
      onClick={_ => onUndo()}
      type_="button"
      title="Undo"
      ariaLabel="Undo"
      // A disabled <button> ignores clicks, so the handler stays wired
      // unconditionally; `aria-disabled` mirrors the state for assistive tech,
      // and is absent rather than "false" when the action is available.
      disabled={!canUndo}
      ariaDisabled=?{canUndo ? None : Some("true")}
    >
      {undoIcon}
    </button>
    {switch onHint {
    | Some(onHint) =>
      <button
        className="top-bar__button top-bar__button--hint"
        onClick={_ => onHint()}
        type_="button"
        title="Hint"
        ariaLabel="Hint"
      >
        {hintIcon}
      </button>
    | None => Html.empty
    }}
  </header>
