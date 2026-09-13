// The mark that says **which board of a family** a control is offering — "♠♥ ×2",
// "Standard". It is drawn in two places: the segment beside a game's name in the Games
// list (`MenuGameRow`) and the picker on that game's info screen
// (`MenuVariantPicker`). A component rather than a few spans apiece, because a pack
// drawn two ways is two things to keep in step — and the pips are the half that would
// drift silently, being a font choice rather than a word (see MenuVariantMark.css).
//
// What a board's mark *is* — which pips, which word — is `GameVariant`'s; this file
// only draws it.

%%raw(`import "./MenuVariantMark.css"`)

type props = {mark: GameVariant.t}

let make = ({mark}) =>
  switch mark.mark {
  | GameVariant.Word(word) => <span className="menu-variant-mark__word"> {Html.string(word)} </span>
  | GameVariant.Pips({suits, copies}) =>
    <>
      <span className="menu-variant-mark__suits"> {Html.string(suits)} </span>
      {switch copies {
      | Some(copies) => <span className="menu-variant-mark__copies"> {Html.string(copies)} </span>
      | None => Html.empty
      }}
    </>
  }
