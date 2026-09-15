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
// own width — at the scale that makes the widest row's capped width (`rowsMaxWidth`)
// exactly a hundred of them. Every length below is in that unit, so the still fits any
// panel and no DOM is read. What the table leaves in unscaled pixels — the row gap, the
// borders, the shadows — stays unscaled here too, because it is the same rule.
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

// The scale at which the board is a hundred `cqw` wide.
let scaleFor = (piles: array<Game.pile>) =>
  100. /. TableLayout.rowsMaxWidth(~widestRow=TableLayout.widestRow(piles))

// The JS→CSS interface, as one declaration string: what `applyScale` publishes on the
// playfield, in the still's unit.
let footprints = (~scale, ~widestRow) =>
  TableLayout.cssVars(~scale, ~widestRow)
  ->Array.map(((name, value)) => `${name}: ${cq(value)}`)
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
let make = (~label: string, ~tilt: bool, piles: array<Game.pile>) => {
  let scale = scaleFor(piles)
  let rows =
    TableLayout.rows(piles)->Array.map(row =>
      TableMarkup.row(row->Array.map(pile(~scale, ~tilt, ...))->Html.array)
    )
  <div className="board-preview" role="img" ariaLabel={label}>
    {TableMarkup.rows(
      ~style=footprints(~scale, ~widestRow=TableLayout.widestRow(piles)),
      ~ariaHidden="true",
      Html.array(rows),
    )}
  </div>
}
