// A game in the menu's **Games** list: the row that mounts it, the variant segment on a
// game the list offers more than one of, and an "i" beside it that opens the game's
// info screen.
//
// **They are siblings, never nested.** A button inside a button is invalid markup that
// browsers rewrite, and the tap on the inner one would reach the outer through
// bubbling: tapping "i" would re-deal, or switch game, on its way to the info screen,
// and tapping the variant would do both at once. So the row is a wrapper `<div>` holding
// independent buttons, and none of them knows about the others.
//
// The variant is a **segment of the name button's box**, sharing its edge and its
// highlight (`MenuGameRow.css`): which FreeCell, or which Spiderette pack, is a state of
// the game named beside it — so it belongs inside the thing it is a state of, and reads
// as part of the same control.
//
// The "i" is not, and that is the difference worth keeping: it is the same mark on
// every row, so it stays detached and takes no part in the highlight. It is also **two
// boxes, one visible**: the `<button>` is a 44px target that paints nothing, and the
// `<span>` inside it is the 18px circle a player sees. Sizing a touch target by what it
// has to look like is how you end up with either a clumsy mark or a thumb-sized miss,
// and the two spans here are what let each be judged on its own.

%%raw(`import "./MenuGameRow.css"`)

// The variant of this row's game that the list is offering, and the tap that moves to
// the next one. Present only where there is more than one to move between.
type variant = {
  mark: GameVariant.t,
  onCycle: unit => unit,
}

type props = {
  label: string,
  // Whether this is the game on the table. Required here, unlike `MenuRow`'s optional
  // one: a games list always has a current game.
  selected: bool,
  onSelect: unit => unit,
  variant?: variant,
  // The "i", and what it opens.
  onInfo: unit => unit,
}

// The segment: the name button's box carried on, so it takes the row's own class list
// (`MenuRow.classesFor` — the one spelling of it) and the highlight with it, and the
// stylesheet does the joining.
//
// The label says whose variant and what kind ("Spiderette pack: 2 suits", "FreeCell
// size: Mini"), because a mark alone is a control with no subject. It names the *state*
// rather than the tap: a control that says what it holds is one a player can come back
// to, where "Change pack" is a button you have to press to find out. A word is left to
// speak for itself; pips are not, being anything from "black spade suit" to silence.
let variantSegment = (~label: string, ~selected: bool, variant: variant) =>
  <button
    className={MenuRow.classesFor(~selected, MenuRow.Nothing) ++ " menu-game-row__variant"}
    type_="button"
    ariaLabel={label ++ " " ++ variant.mark.noun ++ ": " ++ variant.mark.name}
    onClick={_ => variant.onCycle()}
  >
    <MenuVariantMark mark={variant.mark} />
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

// The wrapper says nothing about which game is on the table — the highlight is the name
// button's own, and the segment's. `--segmented` is what the stylesheet joins the two
// boxes on, so the class is the presence of the segment and not a second reading of the
// props.
let make = (props: props) =>
  <div
    className={props.variant->Option.isSome
      ? "menu-game-row menu-game-row--segmented"
      : "menu-game-row"}
  >
    <MenuRow label={props.label} selected={props.selected} onClick={props.onSelect} />
    {switch props.variant {
    | Some(variant) => variantSegment(~label=props.label, ~selected=props.selected, variant)
    | None => Html.empty
    }}
    {infoButton(~label=props.label, props.onInfo)}
  </div>
