open Vitest
open Card

// A substring check, so the box-drawn boards can be asserted by the glyphs they
// contain without pinning every space of the ASCII art (which the layout tests
// in `core` don't, and which would be brittle here).
let has = (s: string, sub: string): bool => s->String.includes(sub)

// The compact card identity (#84): the text the driver names a card by.
describe("CardText", () => {
  test("parses the canonical two-character identities", () => {
    expect(CardText.parse("AS"))->toEqual(Some({suit: Spades, rank: Ace}))
    expect(CardText.parse("KD"))->toEqual(Some({suit: Diamonds, rank: King}))
    expect(CardText.parse("TH"))->toEqual(Some({suit: Hearts, rank: Ten}))
  })

  test("is case-insensitive and accepts the two-digit ten", () => {
    expect(CardText.parse("th"))->toEqual(Some({suit: Hearts, rank: Ten}))
    expect(CardText.parse("10h"))->toEqual(Some({suit: Hearts, rank: Ten}))
    expect(CardText.parse(" 7c "))->toEqual(Some({suit: Clubs, rank: Seven}))
  })

  test("rejects nonsense, a lone rank, and a bad suit", () => {
    expect(CardText.parse("ZZ"))->toEqual(None)
    expect(CardText.parse("A"))->toEqual(None)
    expect(CardText.parse("1X"))->toEqual(None)
  })

  test("format is the inverse of parse", () => {
    expect(CardText.format({suit: Spades, rank: Ace}))->toBe("AS")
    expect(CardText.format({suit: Hearts, rank: Ten}))->toBe("TH")
    expect(CardText.format({suit: Diamonds, rank: King}))->toBe("KD")
  })
})

// The board rendered from a live snapshot, not just the opening deal.
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
})

// The reducer driver end to end: a scripted sequence of commands folded through
// the pure interpreter, including a rejected move — the loop covered without a
// terminal (#84's "done when").
describe("Repl.run", () => {
  test("deals, makes a legal move, rejects an illegal one, and prints the board", () => {
    let transcript = Repl.run(["deal stacking", "move AS 0", "move 3C 0", "move 2H 0", "print"]) // Ace of Spades founds the empty tableau pile — legal // black Three onto black Ace: same colour — rejected // red Two onto black Ace: opposite colour, next rank — legal
    // The commands are echoed behind a prompt…
    expect(has(transcript, "sleight> move AS 0"))->toBe(true)
    // …the illegal move is rejected, with a reason…
    expect(has(transcript, "Rejected: 3C can't stack there."))->toBe(true)
    // …and the final board shows both legally-placed cards.
    expect(has(transcript, `A♠`))->toBe(true)
    expect(has(transcript, `2♥`))->toBe(true)
  })

  test("a loose drop is rejected when the game confines cards to piles", () => {
    // four-fans opens with cards in its piles and `free: false`.
    let transcript = Repl.run(["deal four-fans", "move 2C table"])
    expect(has(transcript, "no loose drops"))->toBe(true)
  })

  test("announces a win once every foundation is complete", () => {
    // The foundations demo deals a whole Hearts Ace→King run loose beside a single
    // foundation; stacking it end-to-end onto pile 0 completes the only foundation
    // and wins (#121).
    let heartsRun =
      ["AH", "2H", "3H", "4H", "5H", "6H", "7H", "8H", "9H", "TH", "JH", "QH", "KH"]->Array.map(
        c => `move ${c} 0`,
      )
    let transcript = Repl.run(Array.concat(["deal foundations"], heartsRun))
    expect(has(transcript, "You win"))->toBe(true)
    // …and the win isn't declared before the run is finished.
    let almost = Repl.run(
      Array.concat(["deal foundations"], heartsRun->Array.slice(~start=0, ~end=12)),
    )
    expect(has(almost, "You win"))->toBe(false)
  })

  test("guides the user before a game is dealt and on unknown input", () => {
    expect(has(Repl.run(["move AS 0"]), "Deal a game first"))->toBe(true)
    expect(has(Repl.run(["frobnicate"]), "Unknown command"))->toBe(true)
    expect(has(Repl.run(["deal nope"]), "Unknown game"))->toBe(true)
  })

  test("reports out-of-range piles and cards that aren't in play", () => {
    expect(has(Repl.run(["deal stacking", "move AS 99"]), "no such pile"))->toBe(true)
    // The King of Diamonds isn't dealt anywhere in the stacking demo.
    expect(has(Repl.run(["deal stacking", "move KD 0"]), "isn't in play"))->toBe(true)
  })

  // `#` comments let the piped example scripts (packages/cli/examples/) document
  // themselves: a comment is neither echoed nor run.
  test("skips `#` comment lines entirely — not echoed, not run", () => {
    let transcript = Repl.run(["# deal a game", "deal stacking", "  # indented note", "print"])
    // The comments are absent from the transcript…
    expect(has(transcript, "deal a game"))->toBe(false)
    expect(has(transcript, "indented note"))->toBe(false)
    // …while the real commands still run and echo.
    expect(has(transcript, "sleight> deal stacking"))->toBe(true)
    expect(has(transcript, "sleight> print"))->toBe(true)
  })
})
