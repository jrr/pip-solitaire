// A board as a picture: a game's piles in, one inline `<svg>` vnode out — the opening
// board a game's info screen shows before a player has dealt it.
//
// It is composed the way the app icon is (`IconArt`), not the way the table is
// (`TableScene`): every card is the real `CardArt` face or back nested at a position,
// so the preview cannot drift from the cards the game draws, and the positions come
// from `TableLayout`'s design constants at scale 1 — the same footprints, fan steps and
// row spread the board lays out with — so it cannot drift from where the table puts
// them either. No DOM is measured. The drawing has a `viewBox` and the stylesheet gives
// it a width, which is what lets a pure component render it and any panel size it.
//
// What it leaves to the table: the hand-placed tilt (`docs/card-tilt.md`), the fan's
// compression when a pile outgrows the playfield (`TableLayout.fanFor`'s `room`, given
// `None` here, so every fan is drawn at its natural step), and the slot's role cue.

let n = Float.toString

// The two rows, as the table splits them: a cascade lands on the bottom row and every
// other pile on the top — but only when the board has both kinds. One kind alone is one
// row.
let rows = (piles: array<Game.pile>): array<array<Game.pile>> => {
  let cascades = piles->Array.filter(p => p.role == Game.Cascade)
  let others = piles->Array.filter(p => p.role != Game.Cascade)
  switch (Array.length(others), Array.length(cascades)) {
  | (0, _) => [cascades]
  | (_, 0) => [others]
  | _ => [others, cascades]
  }
}

// The design width: the widest row at the spread the board caps itself at
// (`TableLayout.rowsMaxWidth`), so the columns sit as they do on a wide table.
let widthFor = (piles: array<Game.pile>) =>
  TableLayout.rowsMaxWidth(
    ~widestRow=rows(piles)->Array.reduce(0, (w, row) => Math.Int.max(w, Array.length(row))),
  )

// The card-sized dashed outline an empty pile shows, traced off the same box a resting
// card fills.
let slot = (~x, ~y) =>
  <rect
    className="board-art__slot"
    x={n(x)}
    y={n(y)}
    width={n(TableLayout.cardW)}
    height={n(TableLayout.cardH)}
    rx={n(TableLayout.cardRadius)}
    fill="none"
    stroke="#334155"
    strokeWidth="1"
    strokeDasharray="4 3"
  />

// One card at a position: the real face, or the back for one lying face down, in a
// nested `<svg>` scaled from the card's design box to the board's card width.
let placedCard = (~x, ~y, ~down: bool, card: Deck.card) =>
  <svg
    className={down ? "board-art__card board-art__back" : "board-art__card"}
    x={n(x)}
    y={n(y)}
    width={n(TableLayout.cardW)}
    height={n(TableLayout.cardH)}
    viewBox={CardArt.viewBox}
    filter="url(#board-art-shadow)"
  >
    {down ? CardArt.back() : CardArt.body(card)}
  </svg>

// One pile, its zone's top-left corner given. A squared pile shows its top card alone,
// as the table does; a fanned one shows every card stepped down by `TableLayout`'s fan.
let pile = (~x, ~y, p: Game.pile): Html.vnode => {
  let cardX = x +. TableLayout.zoneInset
  let cardY = y +. TableLayout.zoneInset
  let count = Array.length(p.cards)
  if count == 0 {
    slot(~x=cardX, ~y=cardY)
  } else {
    switch p.stacking {
    | Game.Squared =>
      let top = count - 1
      p.cards
      ->Array.get(top)
      ->Option.mapOr(Html.empty, card =>
        placedCard(~x=cardX, ~y=cardY, ~down=top < p.faceDown, card)
      )
    | Game.Fanned =>
      let fan = TableLayout.fanFor(~count, ~down=p.faceDown, ~room=None, ~scale=1.)
      p.cards
      ->Array.mapWithIndex((card, slot) =>
        placedCard(
          ~x=cardX,
          ~y=cardY +. TableLayout.fanOffset(fan, ~down=p.faceDown, ~slot),
          ~down=slot < p.faceDown,
          card,
        )
      )
      ->Html.array
    }
  }
}

// How far a pile reaches below its zone's top: the base box, plus the fan's extent.
let reach = (p: Game.pile) =>
  switch p.stacking {
  | Game.Squared => TableLayout.zoneBaseHeight
  | Game.Fanned =>
    TableLayout.zoneBaseHeight +.
    TableLayout.fanFor(~count=Array.length(p.cards), ~down=p.faceDown, ~room=None, ~scale=1.).extent
  }

// The shadow every card carries, one filter shared by reference: the board's
// `box-shadow` on `.card-art` restated as a drop — tight, small and soft, enough to draw
// a covering card's edge against the face beneath it.
let defs = () =>
  <defs>
    <filter id="board-art-shadow" x="-10%" y="-10%" width="120%" height="125%">
      <feDropShadow dx="0" dy="1" stdDeviation="1" floodColor="#0f172a" floodOpacity="0.5" />
    </filter>
    {CardArt.backDefs()}
  </defs>

// The whole board. `~label` is what a reader hears in place of the picture.
let svg = (~label: string, piles: array<Game.pile>) => {
  let width = widthFor(piles)
  // Each row's zones, spread `space-evenly` across the width; each row's top, the
  // rows stacked with the table's gap between them.
  let (drawn, height) = rows(piles)->Array.reduce(([], 0.), ((acc, top), row) => {
    let gap = TableLayout.spreadGap(~width, ~count=Array.length(row))
    let zones = row->Array.mapWithIndex((p, i) => {
      let x = gap +. Int.toFloat(i) *. (TableLayout.zoneWidth +. gap)
      (pile(~x, ~y=top, p), top +. reach(p))
    })
    let bottom = zones->Array.reduce(top, (b, (_, r)) => Math.max(b, r))
    (acc->Array.concat(zones->Array.map(((v, _)) => v)), bottom +. TableLayout.rowGap)
  })
  let height = height -. TableLayout.rowGap
  <svg className="board-art" viewBox={`0 0 ${n(width)} ${n(height)}`} role="img" ariaLabel={label}>
    {defs()}
    {Html.array(drawn)}
  </svg>
}
