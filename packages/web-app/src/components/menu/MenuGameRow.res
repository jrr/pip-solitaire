// A game in the menu's **Games** list: the row that mounts it, and — behind the
// feature flag — an "i" segment beside it that opens the game's info screen.
//
// **The two are siblings, never nested.** A button inside a button is invalid markup
// that browsers rewrite, and the tap on the inner one would reach the outer through
// bubbling: tapping "i" would re-deal, or switch game, on its way to the info screen.
// So the segmented control is a wrapper `<div>` holding two independent buttons, and
// neither knows about the other.
//
// `onInfo` absent is the flag off (see `MenuSettingsScreen`'s "Game info"), and then
// this renders *exactly* what the list rendered before the segment existed — a bare
// `<MenuRow>`, no wrapper — so nothing about the plain row's layout depends on the
// flag being on.

%%raw(`import "./MenuGameRow.css"`)

type props = {
  label: string,
  // Whether this is the game on the table. Required here, unlike `MenuRow`'s optional
  // one: a games list always has a current game, and the highlight spans both segments.
  selected: bool,
  onSelect: unit => unit,
  // The "i" segment, and what it opens. `None` leaves the row a plain full-width
  // button — which is the flag off.
  onInfo?: unit => unit,
}

let make = (props: props) => {
  let row = <MenuRow label={props.label} selected={props.selected} onClick={props.onSelect} />
  switch props.onInfo {
  | None => row
  | Some(onInfo) =>
    <div className={props.selected ? "menu-game-row menu-game-row--active" : "menu-game-row"}>
      {row}
      // The label says which game, because "Info" alone is four identical buttons to
      // anyone reading the menu through their names. The glyph itself is `aria-hidden`
      // — a letter standing in for a word the accessible name already carries.
      <button
        className="menu-game-row__info"
        type_="button"
        ariaLabel={"About " ++ props.label}
        onClick={_ => onInfo()}
      >
        <span className="menu-game-row__badge" ariaHidden="true"> {Html.string("i")} </span>
      </button>
    </div>
  }
}
