// The opening board as a still: a game's piles in, one board out that nothing can
// touch — what a game's info screen shows above its numbers before a player has dealt
// it.
//
// It is the table's own markup under the table's own stylesheet (`TableMarkup`,
// `TableScene.css`): the same zones in the same rows, the same slot on an empty pile,
// the same card with the same back at the same tilt. So nothing about how a board
// *looks* is stated here, and a change to a card, a slot or a row on the table is the
// same change here. What this file holds is the one thing the still has that the table
// doesn't: where each card goes without a playfield to measure.
//
// The table measures its stage, picks a scale and publishes pixels (`applyScale`). A
// pure component can't measure, so the still publishes the same footprints
// (`TableLayout.cssVars`) in container-query units instead — `cqw`, hundredths of its
// own width — at the scale that fits the whole board (`TableLayout.boardSize`) into a
// box a hundred of them wide. Every length below is in that unit, so the still fits any
// panel and no DOM is read. The borders and the shadows stay in the unscaled pixels the
// table draws them in, being a card's detail rather than its size; the gap between the
// rows scales, being the board's own proportion (`boxHeight`, `footprints`).
//
// Cards sit *in the zone* rather than on a playfield: each in a `rest` box centred on
// the resting place, which is the box the empty-pile slot is, stepped down the fan by a
// margin. That leaves the zone's flexbox to spread the columns, which is what keeps the
// `space-evenly` arithmetic out of here.
//
// What it leaves to the table: the fan's compression when a pile outgrows the playfield
// (`TableLayout.fanFor`'s `room`, `None` here, so every fan is at its natural step).

%%raw(`import "./BoardPreview.css"`)

let cq = (v: float) => Float.toString(v) ++ "cqw"

// The box the board is drawn in, in the still's own unit: a hundred `cqw` wide by
// definition, and this tall. `~box` is a height a caller is holding the still to, as a
// ratio of its width; without one it is the board's own shape, and the board fills the
// box exactly.
let boxHeight = (~box=?, piles: array<Game.pile>) => {
  let (w, h) = TableLayout.boardSize(piles)
  100. *. box->Option.getOr(h /. w)
}

// The scale at which the board fits that box: the width fit, and the height fit besides
// where the box given is flatter than the board. A still held to no box is its own box,
// and there the width fit is the whole of it — written as its own case rather than as a
// `Math.min` of two expressions that are equal in arithmetic but not to the last bit.
let scaleFor = (~box=?, piles: array<Game.pile>) => {
  let (w, h) = TableLayout.boardSize(piles)
  let widthFit = 100. /. w
  switch box {
  | None => widthFit
  | Some(aspect) => Math.min(widthFit, 100. *. aspect /. h)
  }
}

// The JS→CSS interface, as one declaration string: what `applyScale` publishes on the
// playfield, in the still's unit — and the gap between the rows besides, which the
// table leaves to its stylesheet unscaled and the still scales (`TableLayout.rowGap`).
let footprints = (~scale, ~widestRow) =>
  TableLayout.cssVars(~scale, ~widestRow)
  ->Array.map(((name, value)) => `${name}: ${cq(value)}`)
  ->Array.concat([`gap: ${cq(TableLayout.rowGap *. scale)}`])
  ->Array.join("; ")

// One pile's zone with its cards in it: a squared pile's on one spot, where the tilt
// is what lets the edges beneath the top card show; a fanned pile's stepped down by
// `TableLayout`'s fan, the zone grown to enclose it as the table grows its own. The
// pile's index in the game is half of what its cards' tilt is keyed on.
let pile = (~scale, ~tilt: bool, (index, p): (int, Game.pile)) => {
  let down = p.faceDown
  let fan = TableLayout.fanFor(~count=Array.length(p.cards), ~down, ~room=None, ~scale)
  let (offset, extent) = switch p.stacking {
  | Game.Squared => (_ => 0., 0.)
  | Game.Fanned => (slot => TableLayout.fanOffset(fan, ~down, ~slot), fan.extent)
  }
  let grown =
    extent > 0. ? Some(`height: ${cq(TableLayout.zoneBaseHeight *. scale +. extent)}`) : None
  let cards = p.cards->Array.mapWithIndex((card, slot) => {
    let step = offset(slot)
    TableMarkup.rest(
      ~style=?{step > 0. ? Some(`margin-top: ${cq(step)}`) : None},
      TableMarkup.card(
        ~down=slot < down,
        ~tilt=?{tilt ? Some(TableLayout.cardTilt(~card, ~pile=index, ~slot)) : None},
        card,
      ),
    )
  })
  TableMarkup.zone(
    ~style=?grown,
    <>
      {TableMarkup.slot(p.role)}
      {Html.array(cards)}
    </>,
  )
}

// The whole board. `~label` is what a reader hears in place of the picture — the rows
// under it are hidden from the accessible tree, so the fifty-two cards are not read out
// one by one — and `~tilt` is the Sloppy placement setting, so the still is as square or
// as hand-placed as the table the player has set up.
//
// **`~box` is what holds a screen still under a picture that changes.** The box is
// declared as a ratio and the board is fitted into it, rather than the box being
// whatever the board came to — so a caller with several boards to draw in one place
// (`GameInfo.previewBox`: a family's sizes, a family's packs) hands each of them the
// same one, and the choice redraws the board without moving a line of the screen below
// it. A board smaller than the box keeps its proportions and is centred in it, which is
// also the honest drawing: four columns of five cards are a smaller board, not the same
// board with bigger cards.
let make = (~label: string, ~tilt: bool, ~box=?, piles: array<Game.pile>) => {
  let scale = scaleFor(~box?, piles)
  let rows =
    TableLayout.rows(piles)->Array.map(row =>
      TableMarkup.row(row->Array.map(pile(~scale, ~tilt, ...))->Html.array)
    )
  <div
    className="board-preview"
    role="img"
    ariaLabel={label}
    // A ratio rather than a length: the box is as wide as whatever holds it, and a
    // height in the container unit it publishes to its own children would be reading
    // its own width back.
    style={`aspect-ratio: 100 / ${Float.toString(boxHeight(~box?, piles))}`}
  >
    {TableMarkup.rows(
      ~style=footprints(~scale, ~widestRow=TableLayout.widestRow(piles)),
      ~ariaHidden="true",
      Html.array(rows),
    )}
  </div>
}
