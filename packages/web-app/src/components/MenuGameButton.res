// A "game" action button — New, Restart, Share Seed — lifted out of `Menu` into
// its own pure component (#307).
//
// `enabled` drives the real `disabled` attribute — a disabled button emits no
// click at all, so the handler guard is belt and braces — and the muted styling
// that goes with it. Only Share Seed is ever disabled; the other two are no-ops on
// a scene without a game rather than unavailable, which is the behaviour they've
// always had.
//
// `value` is a number the button carries *as data* rather than prose — the seed
// Share Seed would hand out. It's set in the mono stack a step dimmer than the
// label (see `.menu-button__value`), which is the label/value split the About
// footer's build string already uses: the word says what the button does, the
// digits say what it would act on. It stays inside the button rather than becoming
// an `aria-label`, so the accessible name is the visible text — the trailing space
// after the label is what keeps the two from running together when a screen reader
// concatenates them.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand). `value` and `enabled` are spelled out at every
// call site rather than defaulted, since a props record has no defaults to give.
type props = {
  label: string,
  value: option<string>,
  enabled: bool,
  onClick: unit => unit,
}

let make = ({label, value, enabled, onClick}) =>
  <button
    className="menu-button"
    onClick={_ =>
      if enabled {
        onClick()
      }}
    type_="button"
    disabled={!enabled}
  >
    {Html.string(value->Option.isSome ? label ++ " " : label)}
    {switch value {
    | Some(value) => <span className="menu-button__value"> {Html.string(value)} </span>
    | None => Html.array([])
    }}
  </button>
