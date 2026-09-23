// "Share game state": the Debug screen's link to the board, on a panel raised over
// everything — as a QR code, as the text of the link, and as a button that copies it.
//
// **A modal rather than a row's description.** A QR code is only any use large enough
// to scan, and the slide-over has no room for one; raised over the screen instead, it
// wears the seed dialog's shape (`SeedDialog`), so the two panels the menu raises read
// as one kind of thing.
//
// **The link arrives already encoded.** `Main` compresses the board when the Debug
// screen opens, so what's here is a string: the dialog can go up on the tap itself,
// and Copy reaches the clipboard with the click's transient activation intact (see
// `ShareLink.deliver`).
//
// **The status line stands in for the hint** rather than appearing under it, the same
// substitution the menu's rows make, so reporting where the link went doesn't grow the
// panel and shift the code a phone is pointed at.

%%raw(`import "./ShareDialog.css"`)

type props = {
  url: string,
  // Where the last Copy went; `None` shows the hint in its place.
  status: option<string>,
  onCopy: unit => unit,
  // Close and the dim behind the panel, which are the same answer. The menu is still
  // up underneath, so this lands back on the Debug screen.
  onClose: unit => unit,
}

let title = "Share game state"
let hint = "Scan to open this exact game on another device, undo history and all."
let tooLong = "This game's link is too long for a QR code — copy it instead."

let make = ({url, status, onCopy, onClose}) => {
  let qr = QrCode.matrix(url)
  <div id="share-dialog" role="dialog" ariaModal="true" ariaLabel=title>
    <div className="share-dialog__backdrop" onClick={_ => onClose()} />
    <div className="share-dialog__panel">
      <p className="share-dialog__title"> {Html.string(title)} </p>
      {switch qr {
      | Some(matrix) =>
        <div className="share-dialog__qr">
          <QrCode matrix label="QR code for the game's link" />
        </div>
      | None => Html.empty
      }}
      <p className="share-dialog__hint" ariaLive="polite">
        {Html.string(
          switch (status, qr) {
          | (Some(status), _) => status
          | (None, Some(_)) => hint
          | (None, None) => tooLong
          },
        )}
      </p>
      // The link itself, for a desktop reader who'd rather select it than scan it.
      <p className="share-dialog__url"> {Html.string(url)} </p>
      // Copy is the primary and sits on the right, where the seed dialog puts Deal.
      <div className="share-dialog__actions">
        <button
          className="share-dialog__button share-dialog__button--close"
          type_="button"
          onClick={_ => onClose()}
        >
          {Html.string("Close")}
        </button>
        <button className="share-dialog__button" type_="button" onClick={_ => onCopy()}>
          {Html.string("Copy link")}
        </button>
      </div>
    </div>
  </div>
}
