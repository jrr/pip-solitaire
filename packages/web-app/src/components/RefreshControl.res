// The Settings screen's **Updates** section (#112), lifted out of `Menu` into its
// own pure component so its states can be exercised in isolation (#201). It's the
// adaptive refresh button whose `label` and `onClick` adapt to whether a service
// worker is registered (see Refresh/Main).
//
// **The size story (#201).** This section used to carry a transient status line
// *under* the button ("Checking…", "Up to date") that appeared and disappeared,
// growing and shrinking the section — a visible reflow of everything below it. The
// status line is gone: while a check is in flight the button itself shows a
// spinner and reads **"Checking…"** (`busy`), all on the button's own line, so it
// changes nothing about the section's height. With no line to come and go, the
// section is heading + button in every state — trivially size-stable.
// `RefreshControl_test` pins that: the section's rows are the same whether or not
// a check is running.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand). The whole section is optional at the *call* site
// — `Menu` shows it only once a worker state is known.
type props = {
  label: string,
  // An update check / refresh is in flight — spin the on-button indicator and swap
  // the label to "Checking…". There's no separate result text: an update that's
  // found surfaces as the About footer's Update button, and the spinner simply
  // stops otherwise.
  busy: bool,
  onClick: unit => unit,
}

let make = ({label, busy, onClick}) =>
  <div className="menu-section" attrs={[("aria-label", "Updates")]}>
    <h2 className="menu-section__heading"> {Html.string("Updates")} </h2>
    <button
      className="menu-button"
      onClick={_ => onClick()}
      attrs={[("type", "button"), ("aria-busy", busy ? "true" : "false")]}
    >
      // The spinner sits inside the button, on the button's own text line, so
      // showing it never changes the button's — or the section's — height. Purely
      // decorative; `aria-busy` above voices the state.
      {busy
        ? <span className="menu-refresh__spinner" attrs={[("aria-hidden", "true")]} />
        : Html.array([])}
      {Html.string(busy ? "Checking…" : label)}
    </button>
  </div>
