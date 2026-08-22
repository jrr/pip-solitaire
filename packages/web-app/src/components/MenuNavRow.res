// A nav row that opens a deeper menu screen, lifted out of `Menu` into its own
// pure component (#307). Styled like a toggle row but with a ›-chevron on the
// right in place of a switch, marking it as "goes somewhere" rather than "flips
// here" — the Settings screen's **Debug** entry is the one of these today (#191).
//
// The chevron is `aria-hidden`: it's a direction, not a word, and the row's own
// label is the accessible name.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).
type props = {
  label: string,
  onClick: unit => unit,
}

let make = ({label, onClick}) =>
  <button className="menu-nav-row" onClick={_ => onClick()} attrs={[("type", "button")]}>
    <span className="menu-nav-row__label"> {Html.string(label)} </span>
    <span className="menu-nav-row__chevron" attrs={[("aria-hidden", "true")]}>
      {Html.string("›")}
    </span>
  </button>
