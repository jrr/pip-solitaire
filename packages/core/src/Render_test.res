// The text renderer, now that it's `core`'s: one board drawing served to a terminal and
// to the web app's debug console (#273). It moved here from `packages/cli` when the
// console's `print` stopped answering "the board is on screen" and started showing one.
//
// The property that matters most is the one the move introduced: **colour is a caller's
// choice**, because ANSI escapes are a terminal's alphabet and a browser panel would show
// them as garbage. Stripping the colour off a coloured board has to give back exactly the
// plain one — same glyphs, same alignment — or the two front ends aren't drawing the same
// board.

open Vitest
open Card

let has = (s: string, sub: string): bool => s->String.includes(sub)

// The escape byte the SGR codes are built from (`Render.esc`), by value, so this file
// needs no literal control character either.
let esc = String.fromCharCode(27)
let ansi = /\[[0-9;]*m/g
let stripColor = s => s->String.replaceAll(esc, "")->String.replaceRegExp(ansi, "")

describe("Render.stateBoard", () => {
  test("shows a card after the reducer has moved it onto a pile", () => {
    let game = Game.stacking
    let state = GameState.initial(game)
    // Found pile 0 with the Ace of Spades via the reducer.
    let moved = switch Reducer.reduce(
      ~game,
      state,
      Move({card: {suit: Spades, rank: Ace}, to: ToPile(0)}),
    ) {
    | Ok(next) => next
    | Error(_) => state
    }
    let board = Render.stateBoard(~game, moved)
    expect(has(board, game.name))->toBe(true)
    expect(has(board, `A♠`))->toBe(true)
  })

  // The title names the deal when the caller knows one — the fact you need to open the
  // same board again, in either front end.
  test("the title names the deal the caller supplies, and nothing when it doesn't", () => {
    let game = Game.freecell
    let state = GameState.initial(game)
    expect(has(Render.stateBoard(~game, ~deal=12345, state), "deal #12345"))->toBe(true)
    expect(has(Render.stateBoard(~game, state), "deal #"))->toBe(false)
  })
})

describe("Render colour", () => {
  let game = Game.freecell
  let state = GameState.initial(game)

  // Plain by default: `core` doesn't assume its output is going to a terminal. The web
  // console renders exactly this.
  test("carries no escape codes unless asked", () =>
    expect(has(Render.stateBoard(~game, state), esc))->toBe(false)
  )

  test("paints the red suits when asked", () => {
    let colored = Render.stateBoard(~game, ~color=true, state)
    expect(has(colored, esc))->toBe(true)
    // The red suits are wrapped; the black ones are left alone.
    expect(has(colored, `${esc}[31m`))->toBe(true)
  })

  // The invariant behind serving both front ends from one renderer: colour is *only*
  // colour. Strip it and you have the plain board, character for character — which is
  // also why the columns line up either way (`visibleWidth` measures without it).
  test("stripping the colour gives back the plain board exactly", () => {
    expect(stripColor(Render.stateBoard(~game, ~color=true, state)))->toBe(
      Render.stateBoard(~game, state),
    )
    expect(stripColor(Render.board(~color=true, game)))->toBe(Render.board(game))
  })

  // A board with a red card in a fanned pile exercises the peeking face lines too, not
  // just the full cards a squared pile shows.
  test("holds for a fanned pile of many cards", () => {
    let fanned = Game.stacking
    expect(stripColor(Render.board(~color=true, fanned)))->toBe(Render.board(fanned))
  })
})

// The board's *shape*: two role-grouped rows, each column headed by the name a typed
// move can address it by. Both are how the drawing tells you how to play it — a label
// that doesn't line up over its column, or one the parser wouldn't take, is worse than
// no label at all (the parser end is checked in `Command_test`).
describe("Render layout", () => {
  let game = Game.freecell
  let state = GameState.initial(game)
  let board = Render.stateBoard(~game, state)
  let sections = board->String.split("\n\n")

  // Sixteen columns in one row is wider than a terminal, and the two halves aren't the
  // same kind of thing: the free cells and foundations sit above the tableau, the way
  // the web table lays them out (#94).
  test("a FreeCell board is drawn in two rows, cells and foundations above", () => {
    // Title, top row, bottom row — no loose cards on a FreeCell board.
    expect(Array.length(sections))->toBe(3)
    let top = sections->Array.getUnsafe(1)
    let bottom = sections->Array.getUnsafe(2)
    expect(has(top, "C1"))->toBe(true)
    expect(has(top, "F4"))->toBe(true)
    expect(has(top, "T1"))->toBe(false)
    expect(has(bottom, "T1"))->toBe(true)
    expect(has(bottom, "T8"))->toBe(true)
    // The dealt cards are all in the cascades, so the top row holds only empty slots.
    expect(has(bottom, `♠`) || has(bottom, `♥`))->toBe(true)
  })

  // A board carrying only one of the two groups keeps its single row, laid out exactly
  // as it always was.
  test("a board with one group of piles keeps its single row", () => {
    let demo = Game.stacking
    let rows = Render.stateBoard(~game=demo, GameState.initial(demo))->String.split("\n\n")
    // Title, the one pile row, and the loose cards dealt beneath it.
    expect(Array.length(rows))->toBe(3)
    expect(has(rows->Array.getUnsafe(1), "T1"))->toBe(true)
    expect(has(rows->Array.getUnsafe(1), "T2"))->toBe(true)
  })

  // Every column is headed by the name that slot answers to, and every name is there
  // exactly once — the labels and the piles are the same set.
  test("every pile is headed by its slot name", () =>
    Slot.labels(~game)->Array.forEach(
      label => {
        let heading = board->String.split("\n")->Array.filter(line => has(line, label))
        expect(Array.length(heading))->toBe(1)
      },
    )
  )

  // The headings are padded to the column width rather than merely centred, which is
  // what keeps the cards beneath them aligned: every line of a row measures the same.
  test("a heading line is exactly as wide as the row it heads", () =>
    sections
    ->Array.slice(~start=1, ~end=Array.length(sections))
    ->Array.forEach(
      section => {
        let lines = section->String.split("\n")
        let width = Render.visibleWidth(lines->Array.getUnsafe(0))
        lines->Array.forEach(line => expect(Render.visibleWidth(line))->toBe(width))
      },
    )
  )

  // The label a board prints and the pile it's printed over are one fact (`Slot`), so
  // a player reading `T3` off the screen addresses the third cascade — pile 10 here.
  test("the printed labels are the ones the model answers to", () => {
    expect(Slot.labelAt(~game, 0))->toEqual(Some("C1"))
    expect(Slot.labelAt(~game, 7))->toEqual(Some("F4"))
    expect(Slot.labelAt(~game, 10))->toEqual(Some("T3"))
    expect(Slot.indexOf(~game, ~role=Game.Cascade, ~ordinal=3))->toEqual(Some(10))
  })
})
