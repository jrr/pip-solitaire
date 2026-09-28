// "Solve": the Debug screen's answer from the solver, on a panel raised over the menu —
// what it found, and, when that is a line, the offer to play it.
//
// **Found and played are two presses.** The search runs as soon as the row is tapped;
// the board doesn't move until Autoplay is pressed here, so a solve can be asked for just
// to learn whether the board still has a win in it. Close lands back on the Debug screen
// with the board untouched.
//
// It wears the share dialog's shape (`ShareDialog`), so the panels the menu raises read
// as one kind of thing.

%%raw(`import "./SolveDialog.css"`)

type props = {
  // The solver's own sentence: a line's length and what it cost to find, or why there
  // isn't one.
  message: string,
  // Present exactly when there is a line to play.
  onAutoplay: option<unit => unit>,
  // Close and the dim behind the panel, which are the same answer.
  onClose: unit => unit,
}

let title = "Solve"

let make = ({message, onAutoplay, onClose}) =>
  <div id="solve-dialog" role="dialog" ariaModal="true" ariaLabel=title>
    <div className="solve-dialog__backdrop" onClick={_ => onClose()} />
    <div className="solve-dialog__panel">
      <p className="solve-dialog__title"> {Html.string(title)} </p>
      <p className="solve-dialog__message"> {Html.string(message)} </p>
      // Autoplay is the primary and sits on the right, where the share dialog puts Copy.
      <div className="solve-dialog__actions">
        <button
          className="solve-dialog__button solve-dialog__button--close"
          type_="button"
          onClick={_ => onClose()}
        >
          {Html.string("Close")}
        </button>
        {switch onAutoplay {
        | Some(play) =>
          <button className="solve-dialog__button" type_="button" onClick={_ => play()}>
            {Html.string("Autoplay")}
          </button>
        | None => Html.empty
        }}
      </div>
    </div>
  </div>
