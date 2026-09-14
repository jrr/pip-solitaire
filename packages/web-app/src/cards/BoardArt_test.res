// The opening-board drawing, read back through the DOM: which cards it draws and where
// it puts them. The positions are checked against `TableLayout`'s own arithmetic rather
// than against pixel literals, because the claim is that the drawing and the table
// agree, not that either is at any particular number.
open Vitest
open TestDom

let draw = (~tilt=false, game: Game.t) =>
  Html.create(BoardArt.svg(~label=game.name, ~tilt, game.piles))

let num = (el, name) => el->attrOr(name)->Float.fromString->Option.getOrThrow

// The `x` of every drawn card and slot, in order, so a row's spread can be read off.
let xs = (root, selector) => root->findAll(selector)->Array.map(el => num(el, "x"))

describe("BoardArt", () => {
  test("draws every card FreeCell deals, and a dashed slot for each empty pile", () => {
    let art = draw(Game.freecell)
    expect(art->findAll(".board-art__card")->Array.length)->toBe(52)
    expect(art->findAll(".board-art__back")->Array.length)->toBe(0)
    // Four cells and four foundations, all empty on the opening board.
    expect(art->findAll(".board-art__slot")->Array.length)->toBe(8)
  })

  test("draws an empty slot in its pile's role, as the table does", () => {
    // FreeCell's top row: four cells, a plate with a card outlined inside it, then four
    // foundations, a well with the four suits in it. Which is which is the table's
    // `slotRoleClass`; the shapes are `.drop-zone__slot`'s.
    let art = draw(Game.freecell)
    expect(art->findAll(".board-art__slot--cell")->Array.length)->toBe(4)
    expect(art->findAll(".board-art__slot--foundation")->Array.length)->toBe(4)
    expect(art->findAll(".board-art__slot--cell rect")->Array.length)->toBe(4 * 2)
    expect(art->find(".board-art__slot--foundation")->Option.getOrThrow->text)->toBe(
      "♠ ♥♦ ♣",
    )
    // An empty column is the bare dashed ghost — the only slot that is.
    let piles = Game.freecell.piles->Array.filter(p => p.role == Game.Cascade)
    let column = Html.create(
      BoardArt.svg(~label="empty", ~tilt=false, piles->Array.map(p => {...p, cards: []})),
    )
    expect(
      column
      ->findAll(".board-art__slot--tableau .board-art__slot-box[stroke-dasharray]")
      ->Array.length,
    )->toBe(8)
  })

  test("turns a face-down card over, and draws a squared pile whole", () => {
    // Spiderette: seven columns of one to seven with only the top card face up — 21
    // backs — and a stock of 24 face down, every one of them drawn on the one spot, as
    // the table has them: with the tilt on, that is what shows the stack's edges.
    let art = draw(Game.spiderette)
    expect(art->findAll(".board-art__card")->Array.length)->toBe(52)
    expect(art->findAll(".board-art__back")->Array.length)->toBe(21 + 24)
    expect(art->findAll(".board-art__slot")->Array.length)->toBe(4)
    // The stock sits on the top row, which is drawn first: its backs lead the list.
    let stock = art->findAll(".board-art__back")->Array.slice(~start=0, ~end=24)
    let ys = stock->Array.map(el => num(el, "y"))
    expect(ys->Array.every(y => Some(y) == ys[0]))->toBe(true)
  })

  test("tilts each card by the table's own hash, keyed on the card and where it rests", () => {
    // FreeCell's first cascade, pile 8 of the sixteen (the cells and foundations come
    // first): the card in slot 0 turns by `TableLayout.cardTilt` for that place, about
    // its own centre, and the next slot by its own. Square when the setting is off:
    // no group, no rotate.
    let art = draw(~tilt=true, Game.freecell)
    let first = Game.freecell.piles->Array.findIndex(p => p.role == Game.Cascade)
    let card = (Game.freecell.piles[first]->Option.getOrThrow).cards[0]->Option.getOrThrow
    let degrees = TableLayout.cardTilt(~card, ~pile=first, ~slot=0)
    let turned = art->find(".board-art__tilt")->Option.getOrThrow
    let box = turned->find(".board-art__card")->Option.getOrThrow
    let cx = num(box, "x") +. TableLayout.cardW /. 2.
    let cy = num(box, "y") +. TableLayout.cardH /. 2.
    expect(turned->attrOr("transform"))->toBe(
      `rotate(${Float.toString(degrees)} ${Float.toString(cx)} ${Float.toString(cy)})`,
    )
    expect(draw(Game.freecell)->findAll(".board-art__tilt")->Array.length)->toBe(0)
  })

  test("nests the real card art, so the drawing can't drift from the face the game draws", () => {
    // A card is `CardArt.body` in a nested `<svg>` at the card's own design box, exactly
    // as the app icon composes its fan.
    let card = draw(Game.freecell)->find(".board-art__card")->Option.getOrThrow
    expect(card->attrOr("viewBox"))->toBe(CardArt.viewBox)
    expect(num(card, "width"))->toBe(TableLayout.cardW)
    expect(card->findAll("text")->Array.length)->toBe(3)
  })

  test("is the widest row wide, spread evenly, with the cascades in the row beneath", () => {
    let art = draw(Game.freecell)
    let width = TableLayout.rowsMaxWidth(~widestRow=8)
    expect(art->attrOr("viewBox")->String.startsWith("0 0 " ++ Float.toString(width)))->toBe(true)
    // Eight slots across the top row at the `space-evenly` gap: the first sits one gap
    // in, and each is a zone and a gap further on.
    let gap = TableLayout.spreadGap(~width, ~count=8)
    let slots = xs(art, ".board-art__slot-box")
    expect(slots[0])->toEqual(Some(gap +. TableLayout.zoneInset))
    expect(slots[1])->toEqual(Some(gap +. TableLayout.zoneWidth +. gap +. TableLayout.zoneInset))
    // The first cascade card starts under the top row, a row gap below its base box.
    let first = art->find(".board-art__card")->Option.getOrThrow
    expect(num(first, "y"))->toBe(
      TableLayout.zoneBaseHeight +. TableLayout.rowGap +. TableLayout.zoneInset,
    )
  })

  test("steps a fan at the layout's own steps, tighter under a face-down card", () => {
    // FreeCell's first column: seven cards face up, each `fanStep` below the last.
    let up = draw(Game.freecell)->findAll(".board-art__card")
    expect(num(up[1]->Option.getOrThrow, "y") -. num(up[0]->Option.getOrThrow, "y"))->toBe(
      TableLayout.fanStep,
    )
    // Spiderette's last column: six face down, so the first steps are the down step.
    let cards = draw(Game.spiderette)->findAll(".board-art__card")
    let last = Array.length(cards)
    let seventh = cards->Array.slice(~start=last - 7, ~end=last)
    let y = i => num(seventh[i]->Option.getOrThrow, "y")
    expect(y(1) -. y(0))->toBe(TableLayout.fanDownStep)
    expect(y(6) -. y(5))->toBe(TableLayout.fanDownStep)
  })

  test("a row of one kind alone is one row, spread on its own", () => {
    // Nothing on the board but cascades: no top row, so the first card is at the top.
    let piles = Game.freecell.piles->Array.filter(p => p.role == Game.Cascade)
    let art = Html.create(BoardArt.svg(~label="cascades", ~tilt=false, piles))
    let first = art->find(".board-art__card")->Option.getOrThrow
    expect(num(first, "y"))->toBe(TableLayout.zoneInset)
  })
})
