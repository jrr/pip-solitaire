// The Settings screen's update-check control (#112), lifted out of `Menu` into its
// own pure component so its states can be exercised in isolation (#201). It's the
// adaptive refresh button whose `label` and `onClick` adapt to whether a service
// worker is registered (see Refresh/Main).
//
// It used to be its own **Updates** section with a heading of its own; the button
// now lives folded into the **About** footer beside the version line (the update
// check and the build info belong together), so this component is just the button
// in its column wrapper — `AboutFooter` supplies the surrounding "About" heading.
//
// **The size story (#201).** This control used to carry a transient status line
// *under* the button ("Checking…", "Up to date") that appeared and disappeared,
// growing and shrinking it — a visible reflow of everything below. The status line
// is gone: while a check is in flight the button itself shows a spinner and reads
// **"Checking…"** (`busy`), all on the button's own line, so it changes nothing
// about the height. With no line to come and go, the control is a single button in
// every state — trivially size-stable. `RefreshControl_test` pins that: its rows
// are the same whether or not a check is running.
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
  <MenuSection label="Updates" modifier="menu-refresh">
    <button
      className="menu-button"
      onClick={_ => onClick()}
      type_="button"
      ariaBusy={busy ? "true" : "false"}
    >
      // The spinner sits inside the button, on the button's own text line, so
      // showing it never changes the button's — or the section's — height. Purely
      // decorative; `aria-busy` above voices the state.
      {busy ? <span className="menu-refresh__spinner" ariaHidden="true" /> : Html.array([])}
      {Html.string(busy ? "Checking…" : label)}
    </button>
  </MenuSection>
