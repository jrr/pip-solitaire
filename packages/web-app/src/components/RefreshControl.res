// The Settings screen's update-check control (#112): the adaptive refresh button
// whose `label` and `onClick` adapt to whether a service worker is registered (see
// Refresh/Main). It's an aria-labelled "Updates" band with no heading of its own,
// folded into the **About** footer beside the version line.
//
// **This control must stay size-stable in every state (#201).** It sits inside the
// About footer, which reflows the menu around it if its height changes — so
// progress goes *on the button's own line* (a spinner, and the label swapped to
// "Checking…") rather than into a status line beneath it. Don't add a line that
// comes and goes: one button, one row, in every state. `RefreshControl_test` pins
// the row count.
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
      // Inside the button, on its own text line — see the size rule above. Purely
      // decorative; `aria-busy` above voices the state.
      {busy ? <span className="menu-refresh__spinner" ariaHidden="true" /> : Html.empty}
      {Html.string(busy ? "Checking…" : label)}
    </button>
  </MenuSection>
