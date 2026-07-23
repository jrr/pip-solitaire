// The app's single top bar (#109): all the chrome, banished to the top so the
// bottom of the screen — the thumb arc — stays clear for dragging cards. Two
// controls: a **Menu** button (opens the slide-over menu) and a live **Undo**
// button (stepping back over the board's `GameState` history, #85). The **New
// Game** control no longer lives here (#156): it moved into the menu, alongside a
// new **Restart** that re-deals the same seed. The **Update** control left even
// earlier (#165): it moved into the menu's About footer, and its availability is
// signalled instead by a small green pip on the **Menu** button — the ☰ badge
// that keeps the now-hidden update call-to-action discoverable.
//
// In portrait the two sit side by side across the top; in the landscape rail
// (#179 follow-up) they split to opposite ends — Menu at the top, Undo at the
// bottom — so that with the rail on a cutout edge both controls land in the
// corner "wings" and stay clear of the centered camera band (#180). The **Redo**
// button was removed (a single undo is enough for this game); redo lives on only
// in `core`'s history for the CLI.
//
// Undo is driven by the mounted board: it publishes the action to the chrome and
// reports whether there's anything to step back to, so the button enables exactly
// when history holds a prior state (`canUndo`). Undo is *not* special-cased on a
// win — a victory is just another recorded state, so the button stays live and
// steps the player back out of the win overlay (#85).
//
// A component is just a `props => vnode` function; the JSX transform lowers
// `<TopBar .../>` to `Html.jsx(TopBar.make, props)` and fills this record from the
// attributes. See `VersionBadge` for why the record is spelled out by hand rather
// than derived by the `@jsx.component` sugar. Layout lives in the stylesheet in
// index.html; here we build only structure and behaviour.
type props = {
  onMenu: unit => unit,
  onUndo: unit => unit,
  canUndo: bool,
  updateVisible: bool,
}

// The undo glyph, drawn rather than typed. A Unicode arrow (e.g. `↶`, U+21B6)
// isn't in Libre Franklin, so each platform substitutes its own fallback font
// for that one character and the icon looks different everywhere. Drawing it as
// an inline SVG — the same way cards and the app icon are drawn — makes it
// render identically on every browser. `fill: currentColor` so it inherits the
// button's text colour (and the dimmed `:disabled` opacity) for free.
let undoPath = "M12.5 8c-2.65 0-5.05.99-6.9 2.6L2 7v9h9l-3.62-3.62c1.39-1.16 3.16-1.88 5.12-1.88 3.54 0 6.55 2.31 7.6 5.5l2.37-.78C21.08 11.03 17.15 8 12.5 8z"

let undoIcon =
  <svg
    className="top-bar__icon"
    attrs={[("viewBox", "0 0 24 24"), ("aria-hidden", "true"), ("focusable", "false")]}
  >
    <path attrs={[("d", undoPath), ("fill", "currentColor")]} />
  </svg>

// A base attribute list plus the `disabled`/`aria-disabled` pair only when the
// action isn't available — a disabled <button> ignores clicks, so the handler can
// stay wired unconditionally.
let controlAttrs = (~enabled: bool, base: array<(string, string)>): array<(string, string)> =>
  enabled ? base : Array.concat(base, [("disabled", ""), ("aria-disabled", "true")])

let make = ({onMenu, onUndo, canUndo, updateVisible}) =>
  <header id="top-bar">
    <button
      className="top-bar__button top-bar__button--menu"
      onClick={_ => onMenu()}
      attrs={[
        ("type", "button"),
        // Fold the pending-update signal into the button's accessible name so the
        // pip isn't a silent, visual-only cue (#165).
        ("aria-label", updateVisible ? "Open menu — update available" : "Open menu"),
        ("title", "Menu"),
      ]}
    >
      {Html.string("☰")}
      // The update pip: a small green presence dot on the Menu button when a new
      // version is waiting (#165). Purely decorative — the state it marks is voiced
      // by the button's `aria-label` above — so it's `aria-hidden`.
      {updateVisible
        ? <span className="top-bar__pip" attrs={[("aria-hidden", "true")]} />
        : Html.array([])}
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
  </header>
