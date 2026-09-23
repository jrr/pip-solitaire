// "Share game state": the Debug screen's link to the board, on a panel raised over
// everything — as a QR code, and as a button that copies it.
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
// **The code and Copy can be different links.** The code has a ceiling (`QrCode`) that a
// long game's history outgrows, so `Main` hands over a link cut down to fit it
// (`ShareLink.linksFor`), and a note under the hint says what the cut cost. Copy always
// carries the whole game, and is `Main`'s: a clipboard has no ceiling to fit.
//
// **The status line stands in for the hint** rather than appearing under it, the same
// substitution the menu's rows make, so reporting where the link went doesn't grow the
// panel and shift the code a phone is pointed at.

%%raw(`import "./ShareDialog.css"`)

type props = {
  // What the code says, when anything fits in one: the whole game, or the game with its
  // history trimmed.
  scan: option<ShareLink.trimmed>,
  // Where the last Copy went; `None` shows the hint in its place.
  status: option<string>,
  onCopy: unit => unit,
  // Close and the dim behind the panel, which are the same answer. The menu is still
  // up underneath, so this lands back on the Debug screen.
  onClose: unit => unit,
}

let title = "Share game state"
let hint = "Scan to open this game on another device."
let tooLong = "This game's link is too long for a QR code — copy it instead."

// Said only when the code had to leave history out. A line of its own rather than part
// of the hint, so a Copy's status taking the hint's place doesn't take this with it.
// Counted in states, the present included, so the total is every board the save holds.
let truncated = ({kept, total}: ShareLink.trimmed): string =>
  `QR code discarded history. (${Int.toString(kept + 1)}/${Int.toString(total + 1)} states kept)`

let make = ({scan, status, onCopy, onClose}) => {
  let qr = scan->Option.flatMap(({url}) => QrCode.matrix(url))
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
      {switch (qr, scan) {
      | (Some(_), Some(trimmed)) if trimmed.kept < trimmed.total =>
        <p className="share-dialog__truncated"> {Html.string(truncated(trimmed))} </p>
      | _ => Html.empty
      }}
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
