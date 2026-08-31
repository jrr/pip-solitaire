// A "game" action button — Random, Enter Seed, Restart, Share Seed — lifted out of
// `Menu` into its own pure component. A word and nothing else: what the deal in
// question *is* rides on the section heading above the pair (`MenuSection`'s
// `headingValue`), so all four buttons are the same size and shape whatever board is
// on the table.
//
// `enabled` drives the real `disabled` attribute — a disabled button emits no
// click at all, so the handler guard is belt and braces — and the muted styling
// that goes with it. Only Share Seed is ever disabled; the others are no-ops on
// a scene without a game rather than unavailable, which is the behaviour they've
// always had. It is spelled out at every call site rather than defaulted, since a
// props record has no defaults to give.

%%raw(`import "./MenuGameButton.css"`)

type props = {
  label: string,
  enabled: bool,
  onClick: unit => unit,
}

let make = ({label, enabled, onClick}) =>
  <button
    className="menu-button"
    onClick={_ =>
      if enabled {
        onClick()
      }}
    type_="button"
    disabled={!enabled}
  >
    {Html.string(label)}
  </button>
