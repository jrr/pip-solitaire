// The opening-board still, read back through the DOM: which cards it draws, in which
// zones, and what it writes for the stylesheet to lay them out by. The lengths are
// checked against `TableLayout`'s own arithmetic rather than against literals, because
// the claim is that the still and the table agree, not that either is at any number.
// That the markup is then *drawn* as the table draws it is the stylesheet's, and
// `browser-tests/game-info.spec.mjs` measures it.
open Vitest
open TestDom

let draw = (~tilt=false, ~box=?, piles: array<Game.pile>) =>
  Html.create(BoardPreview.make(~label="a board", ~tilt, ~box?, piles))

let cq = BoardPreview.cq
let styleOf = el => el->attrOr("style")

describe("BoardPreview", () => {
  test("is one image for a reader, with the table's markup hidden under it", () => {
    let still = draw(Game.freecell.piles)
    expect(still->attrOr("role"))->toBe("img")
    expect(still->attrOr("aria-label"))->toBe("a board")
    expect(still->find(".drop-rows")->Option.getOrThrow->attrOr("aria-hidden"))->toBe("true")
  })

  test("draws every card FreeCell deals, and a slot in its role in every zone", () => {
    // The zone, its slot and the card are the table's own elements — the same class
    // names `TableMarkup` gives the table — so the same rules draw them.
    let still = draw(Game.freecell.piles)
    expect(still->findAll(".drop-zone")->Array.length)->toBe(16)
    expect(still->findAll(".drop-zone > .drop-zone__slot")->Array.length)->toBe(16)
    expect(still->findAll(".drop-zone__slot--cell")->Array.length)->toBe(4)
    expect(still->findAll(".drop-zone__slot--foundation")->Array.length)->toBe(4)
    expect(still->findAll(".drop-zone__slot--tableau")->Array.length)->toBe(8)
    expect(still->findAll(".stacking-card")->Array.length)->toBe(52)
    expect(still->findAll(".stacking-card > .card-art")->Array.length)->toBe(52)
    expect(still->findAll(".stacking-card > .card-back")->Array.length)->toBe(52)
    expect(still->findAll(".stacking-card--down")->Array.length)->toBe(0)
  })

  test("splits the rows as the table does, and seats each card in its own zone", () => {
    // Cells and foundations across the top, cascades below; each card in a rest box
    // in its pile's zone, so flexbox spreads the columns and no arithmetic here does.
    let rows = draw(Game.freecell.piles)->findAll(".drop-row")
    expect(rows->Array.length)->toBe(2)
    let top = rows->Array.getUnsafe(0)
    expect(top->findAll(".drop-zone")->Array.length)->toBe(8)
    expect(top->findAll(".stacking-card")->Array.length)->toBe(0)
    let bottom = rows->Array.getUnsafe(1)
    expect(bottom->findAll(".drop-zone")->Array.length)->toBe(8)
    expect(bottom->findAll(".drop-zone > .drop-zone__rest > .stacking-card")->Array.length)->toBe(
      52,
    )
    // A board of one kind is one row.
    let cascades = Game.freecell.piles->Array.filter(p => p.role == Game.Cascade)
    expect(draw(cascades)->findAll(".drop-row")->Array.length)->toBe(1)
  })

  test("publishes the table's footprints in hundredths of its own width", () => {
    // What `applyScale` writes on the playfield in pixels, written on the rows in
    // `cqw`, at the scale that makes the widest row's capped width the whole box.
    let piles = Game.freecell.piles
    let scale = 100. /. TableLayout.rowsMaxWidth(~widestRow=8)
    let style = draw(piles)->find(".drop-rows")->Option.getOrThrow->styleOf
    TableLayout.cssVars(~scale, ~widestRow=8)->Array.forEach(
      ((name, value)) => expect(style->String.includes(`${name}: ${cq(value)}`))->toBe(true),
    )
    expect(style->String.includes("--rows-max-w: 100cqw"))->toBe(true)
    // The gap between the rows goes with them, where the table leaves it to the
    // stylesheet at a stage's unscaled sixteen pixels: a still is a scaled picture of a
    // board, the space between its rows included.
    expect(style->String.includes(`gap: ${cq(TableLayout.rowGap *. scale)}`))->toBe(true)
  })

  test("is drawn in a box of the board's own shape, where it is held to none", () => {
    // The still declares its box as a ratio and fits the board into it, rather than
    // coming out whatever height the board ran to — which is what a caller with more
    // than one board to draw in one place can hold to (`~box`, below).
    let (w, h) = TableLayout.boardSize(Game.freecell.piles)
    expect(
      draw(Game.freecell.piles)
      ->styleOf
      ->String.includes(`aspect-ratio: 100 / ${Float.toString(100. *. h /. w)}`),
    )->toBe(true)
  })

  test("fits a board into the box it is held to, and leaves the slack across", () => {
    // What keeps the info screen still under a picker: every board of a family is drawn
    // in the flattest one's box (`GameInfo.previewBox`), so the numbers, the picker and
    // the link below never move. Micro is the taller-shaped board, so the box's height
    // is what fits it and it is drawn narrower than the mat — centred in the room left
    // over by `--rows-max-w`, not blown up to the mat's width.
    let box = GameInfo.previewBoxFor(Game.freecell)
    let shapeOf = piles => draw(~box, piles)->styleOf
    expect(shapeOf(Game.micro.piles))->toBe(shapeOf(Game.freecell.piles))

    let spread = piles => {
      let (w, _) = TableLayout.boardSize(piles)
      w *. BoardPreview.scaleFor(~box, piles)
    }
    expect(
      BoardPreview.scaleFor(~box, Game.micro.piles) < BoardPreview.scaleFor(Game.micro.piles),
    )->toBe(true)
    expect(spread(Game.micro.piles) < 90.)->toBe(true)
    // …while the board the box was cut for still fills it across.
    expect(Math.round(spread(Game.freecell.piles)))->toBe(100.)
  })

  // The lengths a zone writes, read off the markup rather than the DOM: jsdom's style
  // parser doesn't know `cqw` and drops a declaration in it, where a browser doesn't.
  // `StaticRender` writes the same props the DOM renderer sets.
  let zoneMarkup = (piles, ~role) => {
    let scale = BoardPreview.scaleFor(piles)
    let index = piles->Array.findIndex(p => p.role == role)
    (
      scale,
      StaticRender.toString(
        BoardPreview.pile(~scale, ~tilt=false, (index, piles->Array.getUnsafe(index))),
      ),
    )
  }
  let stepped = (markup, step) => markup->String.includes(`style="margin-top: ${cq(step)}"`)

  test("steps a fan at the layout's own steps, and grows the zone to hold it", () => {
    // FreeCell's first column: seven cards face up, each `fanStep` (scaled) below the
    // last, and the zone as tall as the base box plus the fan — the table's own two
    // expressions, in the still's unit.
    let piles = Game.freecell.piles
    let (scale, markup) = zoneMarkup(piles, ~role=Game.Cascade)
    expect(markup->String.split("drop-zone__rest")->Array.length)->toBe(1 + 8)
    expect(
      markup->String.includes(`<div class="drop-zone__rest"><div class="stacking-card"`),
    )->toBe(true)
    expect(stepped(markup, TableLayout.fanStep *. scale))->toBe(true)
    expect(stepped(markup, 6. *. TableLayout.fanStep *. scale))->toBe(true)
    expect(stepped(markup, 7. *. TableLayout.fanStep *. scale))->toBe(false)
    let fan = TableLayout.fanFor(~count=7, ~down=0, ~room=None, ~scale)
    expect(
      markup->String.startsWith(
        `<div class="drop-zone" style="height: ${cq(
            TableLayout.zoneBaseHeight *. scale +. fan.extent,
          )}">`,
      ),
    )->toBe(true)
  })

  test("turns a face-down card over, keeps a squared pile on one spot", () => {
    // Spiderette: seven columns of one to seven with only the top card face up — 21
    // backs — and a stock of 24 face down on the one spot, as the table has them; the
    // tilt is what shows a squared stack's edges. A back steps by the tighter step.
    let piles = Game.spiderette.piles
    let still = draw(piles)
    expect(still->findAll(".stacking-card")->Array.length)->toBe(52)
    expect(still->findAll(".stacking-card--down")->Array.length)->toBe(21 + 24)
    let (_, stock) = zoneMarkup(piles, ~role=Game.Stock)
    expect(stock->String.startsWith(`<div class="drop-zone"><div class="drop-zone__slot`))->toBe(
      true,
    )
    expect(stock->String.includes("margin-top"))->toBe(false)
    expect(stock->String.split("stacking-card stacking-card--down")->Array.length)->toBe(1 + 24)
    let (scale, column) = zoneMarkup(piles, ~role=Game.Cascade)
    expect(column->String.includes("stacking-card--down"))->toBe(false)
    let last = piles->Array.filter(p => p.role == Game.Cascade)->Array.length - 1
    let index = piles->Array.findIndex(p => p.role == Game.Cascade) + last
    let deepest = StaticRender.toString(
      BoardPreview.pile(~scale, ~tilt=false, (index, piles->Array.getUnsafe(index))),
    )
    expect(deepest->String.split("stacking-card stacking-card--down")->Array.length)->toBe(1 + 6)
    expect(stepped(deepest, TableLayout.fanDownStep *. scale))->toBe(true)
    expect(stepped(deepest, 6. *. TableLayout.fanDownStep *. scale))->toBe(true)
  })

  test("tilts each card by the table's own hash, keyed on the card and where it rests", () => {
    // The property the table's `applyTilt` writes, written up front: FreeCell's first
    // cascade is pile 8 of the sixteen, and its bottom card turns by the hash for that
    // place. Square when the setting is off — no property, and the stylesheet's 0deg.
    let piles = Game.freecell.piles
    let first = piles->Array.findIndex(p => p.role == Game.Cascade)
    let card = (piles->Array.getUnsafe(first)).cards->Array.getUnsafe(0)
    let degrees = TableLayout.cardTilt(~card, ~pile=first, ~slot=0)
    let bottom =
      draw(~tilt=true, piles)
      ->findAll(".drop-row")
      ->Array.getUnsafe(1)
      ->find(".stacking-card")
      ->Option.getOrThrow
    expect(bottom->styleOf->String.includes(`--card-rot: ${Float.toString(degrees)}deg`))->toBe(
      true,
    )
    expect(draw(piles)->findAll(".stacking-card[style]")->Array.length)->toBe(0)
  })
})
