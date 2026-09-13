// A game in the menu's **Games** list: the row that mounts it, the pack segment on a
// game that has more than one pack, and — behind the feature flag — an "i" beside it
// that opens the game's info screen.
//
// **They are siblings, never nested.** A button inside a button is invalid markup that
// browsers rewrite, and the tap on the inner one would reach the outer through
// bubbling: tapping "i" would re-deal, or switch game, on its way to the info screen,
// and tapping the pack would do both at once. So the row is a wrapper `<div>` holding
// independent buttons, and none of them knows about the others.
//
// The pack is a **segment of the name button's box**, sharing its edge and its
// highlight (`MenuGameRow.css`): it is a state of the game on the row — which pack you
// play Spiderette with — so it belongs inside the thing it is a state of, and reads as
// part of the same control.
//
// The "i" is not, and that is the difference worth keeping: it is the same mark on
// every row, so it stays detached and takes no part in the highlight. It is also **two
// boxes, one visible**: the `<button>` is a 44px target that paints nothing, and the
// `<span>` inside it is the 18px circle a player sees. Sizing a touch target by what it
// has to look like is how you end up with either a clumsy mark or a thumb-sized miss,
// and the two spans here are what let each be judged on its own.
//
// `onInfo` absent is the flag off (see `MenuSettingsScreen`'s "Game info"), and a game
// with one pack has no `pack`; with neither this renders *exactly* what the list
// rendered before either existed — a bare `<MenuRow>`, no wrapper — so nothing about
// the plain row's layout depends on a feature being on.

%%raw(`import "./MenuGameRow.css"`)

// The pack this row's game is played with, and the tap that moves it to the next one
// (`Game.nextInFamily`). Present only on a game that has more than one.
type pack = {
  mark: GamePack.t,
  onCycle: unit => unit,
}

type props = {
  label: string,
  // Whether this is the game on the table. Required here, unlike `MenuRow`'s optional
  // one: a games list always has a current game.
  selected: bool,
  onSelect: unit => unit,
  pack?: pack,
  // The "i", and what it opens. `None` leaves the row without one — which is the flag
  // off.
  onInfo?: unit => unit,
}

// The segment: the name button's box carried on, so it takes the row's own class list
// (`MenuRow.classesFor` — the one spelling of it) and the highlight with it, and the
// stylesheet does the joining.
//
// The label says whose pack, because "2 suits" alone is a control with no subject, and
// it names the *state* rather than the tap: a control that says what it holds is one a
// player can come back to, where "Change pack" is a button you have to press to find
// out. The pips are left to the eye — read aloud they are anything from "black spade
// suit" to silence.
let packSegment = (~label: string, ~selected: bool, pack: pack) =>
  <button
    className={MenuRow.classesFor(~selected, MenuRow.Nothing) ++ " menu-game-row__pack"}
    type_="button"
    ariaLabel={label ++ " pack: " ++ pack.mark.name}
    onClick={_ => pack.onCycle()}
  >
    <span className="menu-game-row__suits"> {Html.string(pack.mark.suits)} </span>
    {switch pack.mark.copies {
    | Some(copies) => <span className="menu-game-row__copies"> {Html.string(copies)} </span>
    | None => Html.empty
    }}
  </button>

// The label says which game, because "Info" alone is four identical buttons to anyone
// reading the menu through their names. The glyph itself is `aria-hidden` — a letter
// standing in for a word the accessible name already carries.
let infoButton = (~label: string, onInfo: unit => unit) =>
  <button
    className="menu-game-row__info"
    type_="button"
    ariaLabel={"About " ++ label}
    onClick={_ => onInfo()}
  >
    <span className="menu-game-row__badge" ariaHidden="true"> {Html.string("i")} </span>
  </button>

let make = (props: props) => {
  let row = <MenuRow label={props.label} selected={props.selected} onClick={props.onSelect} />
  switch (props.pack, props.onInfo) {
  // Nothing beside the name: no wrapper either. The wrapper is what lays a pair out, so
  // a row that kept one would be reserving space beside itself for nothing.
  | (None, None) => row
  | (pack, onInfo) =>
    // The wrapper says nothing about which game is on the table — the highlight is the
    // name button's own, and the pack segment's. `--packed` is what the stylesheet
    // joins the two boxes on, so the class is the presence of the segment and not a
    // second reading of the props.
    <div className={pack->Option.isSome ? "menu-game-row menu-game-row--packed" : "menu-game-row"}>
      {row}
      {switch pack {
      | Some(pack) => packSegment(~label=props.label, ~selected=props.selected, pack)
      | None => Html.empty
      }}
      {switch onInfo {
      | Some(onInfo) => infoButton(~label=props.label, onInfo)
      | None => Html.empty
      }}
    </div>
  }
}
