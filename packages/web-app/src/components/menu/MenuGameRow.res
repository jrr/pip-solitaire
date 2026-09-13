// A game in the menu's **Games** list: the row that mounts it, and — behind the
// feature flag — an "i" beside it that opens the game's info screen.
//
// **The two are siblings, never nested.** A button inside a button is invalid markup
// that browsers rewrite, and the tap on the inner one would reach the outer through
// bubbling: tapping "i" would re-deal, or switch game, on its way to the info screen.
// So the pair is a wrapper `<div>` holding two independent buttons, and neither knows
// about the other.
//
// The "i" is **two boxes, one visible**: the `<button>` is a 44px target that paints
// nothing, and the `<span>` inside it is the 18px circle a player sees. Sizing a
// touch target by what it has to look like is how you end up with either a clumsy
// mark or a thumb-sized miss, and the two spans here are what let each be judged on
// its own (`MenuGameRow.css`).
//
// `onInfo` absent is the flag off (see `MenuSettingsScreen`'s "Game info"), and then
// this renders *exactly* what the list rendered before the "i" existed — a bare
// `<MenuRow>`, no wrapper — so nothing about the plain row's layout depends on the
// flag being on.

%%raw(`import "./MenuGameRow.css"`)

type props = {
  label: string,
  // Whether this is the game on the table. Required here, unlike `MenuRow`'s optional
  // one: a games list always has a current game.
  selected: bool,
  onSelect: unit => unit,
  // The "i", and what it opens. `None` leaves the row a plain full-width button —
  // which is the flag off.
  onInfo?: unit => unit,
}

let make = (props: props) => {
  let row = <MenuRow label={props.label} selected={props.selected} onClick={props.onSelect} />
  switch props.onInfo {
  | None => row
  // The wrapper says nothing about which game is on the table: the highlight is the
  // name button's own, and the "i" beside it is the same mark on every row.
  | Some(onInfo) =>
    <div className="menu-game-row">
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
