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
