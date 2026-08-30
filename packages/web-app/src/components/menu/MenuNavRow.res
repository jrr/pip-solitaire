// A nav row that opens a deeper menu screen, lifted out of `Menu` into its own
// pure component. The same box as the other rows but with a ›-chevron on
// the right in place of a switch, marking it as "goes somewhere" rather than
// "flips here" — the Settings screen's **Debug** entry is the one of these today.
//
// The chevron and the heavier weight that goes with it both come from `<MenuRow>`'s
// `Chevron` trailing, which is also what makes the chevron `aria-hidden`: it's a
// direction, not a word, and the row's own label is the accessible name.
type props = {
  label: string,
  onClick: unit => unit,
}

let make = ({label, onClick}) => <MenuRow label trailing=MenuRow.Chevron onClick />
