// The **variant picker** on a game's info screen: every board of that game's family laid
// out at once — the Spiderette packs, the FreeCell sizes — with the one the screen is
// about marked, and a tap on any other moving the screen to it.
//
// It shows the same boards the Games list's segment offers beside a game's name
// (`MenuGameRow`), and wears the same mark (`MenuVariantMark`), but it is a way of
// *reading* about them, not of choosing one: the segment is what picks the family's
// board and what swaps the table, and a walk through this control changes neither
// (`Main`). A row has room for one mark, so the segment *cycles*; a screen about a game
// has room for all three, so here they are laid out and pointed at.
//
// The buttons are `.menu-row`s — `MenuRow.classesFor`, the one spelling of that class
// list — so the box and the highlight arrive with them, and what this file adds is the
// joining of them into a single control (MenuVariantPicker.css).

%%raw(`import "./MenuVariantPicker.css"`)

// One board on offer: its mark, whether it is the one the screen is about, and the tap
// that moves the screen to it.
type choice = {
  mark: GameVariant.t,
  selected: bool,
  onChoose: unit => unit,
}

type props = {
  // Whose variants these are, for each button's accessible name — "Spiderette pack: 2
  // suits", the sentence the Games list's segment already says. A mark alone is a
  // control with no subject, and here there are three of them in a row.
  game: string,
  // …and the word for what they vary in, which is also what heads the group: "pack",
  // "size". Taken off the family rather than written down here, the same way the mark is
  // (`GameVariant.nounFor`).
  noun: string,
  choices: array<choice>,
}

let make = ({game, choices}) =>
  <div className="menu-variant-picker">
    {choices
    ->Array.map(choice =>
      <button
        className={MenuRow.classesFor(
          ~selected=choice.selected,
          MenuRow.Nothing,
        ) ++ " menu-variant-picker__choice"}
        type_="button"
        // The state, not the tap: "Spiderette pack: 2 suits" is a control a player can
        // come back to, where "Choose 2 suits" is one that only says what pressing it
        // would do. `aria-current` on the chosen one is what says which of the three is
        // in effect — the same mark the Games list's rows wear, and absent rather than
        // "false" on the others.
        ariaLabel={game ++ " " ++ choice.mark.noun ++ ": " ++ choice.mark.name}
        ariaCurrent=?{MenuRow.currentFor(choice.selected)}
        onClick={_ => choice.onChoose()}
        key={choice.mark.name}
      >
        <MenuVariantMark mark={choice.mark} />
      </button>
    )
    ->Html.array}
  </div>
