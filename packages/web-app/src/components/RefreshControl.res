// The Settings screen's update-check control: the adaptive refresh button whose `label`
// and `onClick` adapt to whether a service worker is registered (see Refresh/Main). One
// button and nothing around it — the About footer stands it beside the About button and
// names the pair (`AboutFooter`), so a band of its own here would be a box inside a box.
//
// **This control must stay size-stable in every state.** It sits inside the
// About footer, which reflows the menu around it if its height changes — so
// progress goes *inside the button* (a spinner on its own line of text, and the label
// swapped to "Checking…") rather than into a status line beneath it. Don't add an
// element that comes and goes beside the button: one button, whatever the state.
// `RefreshControl_test` pins that.
//
// The whole control is optional at the *call* site — `Main` builds it only once a
// worker state is known.
//
// `menu-refresh` beside the button class is what the button is *addressed* by — the
// spinner's own class is under it, and `browser-tests/menu-refresh.spec.mjs` finds the
// control with it. The label is no good for that: it reads "Refresh" or "Check for
// updates" depending on what this install turned out to be.
%%raw(`import "./RefreshControl.css"`)

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
  <button
    className="menu-button menu-refresh"
    onClick={_ => onClick()}
    type_="button"
    ariaBusy={busy ? "true" : "false"}
  >
    // Inside the button, on its own text line — see the size rule above. Purely
    // decorative; `aria-busy` above voices the state.
    {busy ? <span className="menu-refresh__spinner" ariaHidden="true" /> : Html.empty}
    {Html.string(busy ? "Checking…" : label)}
  </button>
