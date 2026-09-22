// One setting with a handful of named states, in the menu: the label and which state it
// is in on one line, the states themselves as a row of chips under it. The other control
// shape a debug group wants beside `<MenuSlider>` — a slider says how much, this says
// which, and the two stack into the same box so a group of both reads as one panel.
//
// The chips are `.menu-row`s (`MenuRow.classesFor`, the one spelling of that class list),
// which is where the box, the highlight and `aria-current` come from — the same trick
// `<MenuVariantPicker>` plays with a family's boards, and for the same reason: a segmented
// control is a row of rows, not a new kind of button.
%%raw(`import "./MenuChoiceRow.css"`)

// One state on offer, and the tap that moves to it. `selected` is the one in effect —
// exactly one, though nothing here enforces that: a control with none marked is a caller
// that hasn't said what it is set to.
type choice = {
  label: string,
  selected: bool,
  onChoose: unit => unit,
}

type props = {
  // What the setting is called, and the `data-choice` a test reaches it by.
  label: string,
  // What the state in effect *means*, where the label can't say it — the same place a
  // slider's readout sits, and left out where the chip's own word is the whole story.
  readout?: string,
  choices: array<choice>,
}

let make = ({label, ?readout, choices}) =>
  <div className="menu-choice" dataChoice=label>
    <div className="menu-choice__head">
      <span className="menu-choice__label"> {Html.string(label)} </span>
      {switch readout {
      | Some(readout) => <span className="menu-choice__readout"> {Html.string(readout)} </span>
      | None => Html.empty
      }}
    </div>
    <div className="menu-choice__chips">
      {choices
      ->Array.map(choice =>
        <button
          className={MenuRow.classesFor(
            ~selected=choice.selected,
            MenuRow.Nothing,
          ) ++ " menu-choice__chip"}
          type_="button"
          ariaCurrent=?{MenuRow.currentFor(choice.selected)}
          onClick={_ => choice.onChoose()}
          key={choice.label}
        >
          {Html.string(choice.label)}
        </button>
      )
      ->Html.array}
    </div>
  </div>
