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
// The three designs it restates — the back (`CardArt.back`), an empty pile's slot in
// each of its roles (`slot`), and the card's shadow (`defs`) — are drawn by the table in
// CSS, which an SVG cannot share; each is kept in step with its stylesheet rule by hand.
//
// What it leaves to the table: the fan's compression when a pile outgrows the playfield
// (`TableLayout.fanFor`'s `room`, given `None` here, so every fan is drawn at its natural
// step).

let n = Float.toString

// The two rows, as the table splits them: a cascade lands on the bottom row and every
// other pile on the top — but only when the board has both kinds. One kind alone is one
// row.
// A pile keeps its index in the game, which is half of what its cards' tilt is keyed
// on — the same index the table hands `cardTilt` as `~pile`.
type placed = (int, Game.pile)

let rows = (piles: array<Game.pile>): array<array<placed>> => {
  let indexed = piles->Array.mapWithIndex((p, i) => (i, p))
  let cascades = indexed->Array.filter(((_, p)) => p.role == Game.Cascade)
  let others = indexed->Array.filter(((_, p)) => p.role != Game.Cascade)
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

// An empty pile's slot, in the pile's role: the same three registers `.drop-zone__slot`
// paints on the table, restated as SVG. A foundation is a dark well with the four suits
// in it, a free cell a lighter plate with a card outlined at under half size, an empty
// column the bare dashed ghost, and the stock the plate with nothing in it. The colours
// and the proportions — the mark at 0.26 of the card's width, the outline at 0.46 of it
// — are the stylesheet's, and a change to either is a change to both.
let slotBox = (~x, ~y, ~fill, ~stroke, ~dashed=false, ()) =>
  <rect
    className="board-art__slot-box"
    x={n(x)}
    y={n(y)}
    width={n(TableLayout.cardW)}
    height={n(TableLayout.cardH)}
    rx={n(TableLayout.cardRadius)}
    fill={fill}
    stroke={stroke}
    strokeWidth="1"
    strokeDasharray=?{dashed ? Some("4 3") : None}
  />

let slotInk = "rgba(148,163,184,"

// The suits' quartet, two to a line, set in the pips' own face at the baseline
// `CardArt` states for it (see `centerGlyphBaseline` there for why a baseline and not
// `dominant-baseline`).
let foundationMark = (~cx, ~cy) => {
  let size = TableLayout.cardW *. 0.26
  let half = size *. 1.05 /. 2.
  let line = (~at, glyphs) =>
    <text
      x={n(cx)}
      y={n(at +. size *. 0.31)}
      textAnchor="middle"
      fontSize={n(size)}
      fontFamily="Pip Suits"
      fill={slotInk ++ "0.6)"}
    >
      {Html.string(glyphs)}
    </text>
  let s = Deck.suitSymbol
  <>
    {line(~at=cy -. half, s(Deck.Spades) ++ " " ++ s(Deck.Hearts))}
    {line(~at=cy +. half, s(Deck.Diamonds) ++ " " ++ s(Deck.Clubs))}
  </>
}

let slot = (~x, ~y, role: Game.role) => {
  let cx = x +. TableLayout.cardW /. 2.
  let cy = y +. TableLayout.cardH /. 2.
  switch role {
  | Game.Foundation =>
    <g className="board-art__slot board-art__slot--foundation">
      {slotBox(~x, ~y, ~fill="rgba(2,6,23,0.42)", ~stroke="#3b4a63", ())}
      // The well's inset shadow, as a shade falling from its top edge.
      <rect
        x={n(x)}
        y={n(y)}
        width={n(TableLayout.cardW)}
        height={n(TableLayout.cardH)}
        rx={n(TableLayout.cardRadius)}
        fill="url(#board-art-well)"
      />
      {foundationMark(~cx, ~cy)}
    </g>
  | Game.FreeCell =>
    let w = TableLayout.cardW *. 0.46
    let h = TableLayout.cardH *. 0.46
    <g className="board-art__slot board-art__slot--cell">
      {slotBox(~x, ~y, ~fill={slotInk ++ "0.11)"}, ~stroke={slotInk ++ "0.45)"}, ())}
      <rect
        x={n(cx -. w /. 2.)}
        y={n(cy -. h /. 2.)}
        width={n(w)}
        height={n(h)}
        rx={n(TableLayout.cardRadius *. 0.5)}
        fill="none"
        stroke={slotInk ++ "0.42)"}
        strokeWidth="1"
      />
    </g>
  | Game.Stock =>
    <g className="board-art__slot board-art__slot--stock">
      {slotBox(~x, ~y, ~fill={slotInk ++ "0.06)"}, ~stroke={slotInk ++ "0.3)"}, ())}
    </g>
  | Game.Cascade =>
    <g className="board-art__slot board-art__slot--tableau">
      {slotBox(~x, ~y, ~fill="none", ~stroke="#334155", ~dashed=true, ())}
    </g>
  }
}

// One card at a position: the real face, or the back for one lying face down, in a
// nested `<svg>` scaled from the card's design box to the board's card width. The
// tilt, where it is on, is a rotate about the card's centre on a group around it — a
// nested `<svg>` takes no `transform` of its own in SVG 1.1.
let placedCard = (~x, ~y, ~down: bool, ~tilt: option<float>, card: Deck.card) => {
  let art =
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
  switch tilt {
  | Some(degrees) =>
    let cx = x +. TableLayout.cardW /. 2.
    let cy = y +. TableLayout.cardH /. 2.
    <g className="board-art__tilt" transform={`rotate(${n(degrees)} ${n(cx)} ${n(cy)})`}> {art} </g>
  | None => art
  }
}

// One pile, its zone's top-left corner given. Every card is drawn, as on the table: a
// squared pile's lie on one spot, where the tilt is what lets the edges beneath the top
// card show; a fanned pile's step down by `TableLayout`'s fan.
let pile = (~x, ~y, ~tilt: bool, (index, p): placed): Html.vnode => {
  let cardX = x +. TableLayout.zoneInset
  let cardY = y +. TableLayout.zoneInset
  let count = Array.length(p.cards)
  if count == 0 {
    slot(~x=cardX, ~y=cardY, p.role)
  } else {
    let offset = switch p.stacking {
    | Game.Squared => _ => 0.
    | Game.Fanned =>
      let fan = TableLayout.fanFor(~count, ~down=p.faceDown, ~room=None, ~scale=1.)
      slot => TableLayout.fanOffset(fan, ~down=p.faceDown, ~slot)
    }
    p.cards
    ->Array.mapWithIndex((card, slot) =>
      placedCard(
        ~x=cardX,
        ~y=cardY +. offset(slot),
        ~down=slot < p.faceDown,
        ~tilt=tilt ? Some(TableLayout.cardTilt(~card, ~pile=index, ~slot)) : None,
        card,
      )
    )
    ->Html.array
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
    <linearGradient id="board-art-well" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stopColor="rgba(0,0,0,0.5)" />
      <stop offset="0.08" stopColor="rgba(0,0,0,0)" />
    </linearGradient>
    {CardArt.backDefs()}
  </defs>

// The whole board. `~label` is what a reader hears in place of the picture; `~tilt` is
// the Sloppy placement setting, so the picture is as square or as hand-placed as the
// table the player has set up.
let svg = (~label: string, ~tilt: bool, piles: array<Game.pile>) => {
  let width = widthFor(piles)
  // Each row's zones, spread `space-evenly` across the width; each row's top, the
  // rows stacked with the table's gap between them.
  let (drawn, height) = rows(piles)->Array.reduce(([], 0.), ((acc, top), row) => {
    let gap = TableLayout.spreadGap(~width, ~count=Array.length(row))
    let zones = row->Array.mapWithIndex(((_, p) as placed, i) => {
      let x = gap +. Int.toFloat(i) *. (TableLayout.zoneWidth +. gap)
      (pile(~x, ~y=top, ~tilt, placed), top +. reach(p))
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
