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

  // Auto-move to foundation (#122): the `home` verb sends a card to the foundation
  // that will take it, and refuses one no foundation is ready for.
  test("home collects several eligible cards to their foundations in a row", () => {
    // The send-home scenario parks each suit's next foundation card — a Three, atop
    // an Ace–Two foundation — in a free cell, so a run of `home` commands collects
    // them all home.
    let transcript = Repl.run([
      "deal freecell sendhome",
      "home 3S",
      "home 3H",
      "home 3D",
      "home 3C",
    ])
    // Each Three lands on its foundation (the squared foundations show their top).
    expect(has(transcript, `3♠`))->toBe(true)
    expect(has(transcript, `3♥`))->toBe(true)
    expect(has(transcript, `3♦`))->toBe(true)
    expect(has(transcript, `3♣`))->toBe(true)
  })

  test("home refuses a card no foundation is ready for", () => {
    // In the send-home scenario the foundations sit at the Two, so a King has no
    // home — it's reported, not moved.
    let transcript = Repl.run(["deal freecell sendhome", "home KS"])
    expect(has(transcript, "No foundation is ready for KS"))->toBe(true)
  })

  test("home guides the user before a game is dealt", () => {
    expect(has(Repl.run(["home AS"]), "Deal a game first"))->toBe(true)
  })

  // Safe auto-collect (#125): after an accepted move the driver sweeps every *safe*
  // card home when the option is on (its default), and does exactly nothing when
  // it's off — the flag-gated no-op path.
  // The send-home scenario sits every foundation at the Two with each suit's Three
  // parked in a free cell — the foundations are 4,5,6,7 (Spades, Hearts, Diamonds,
  // Clubs). Its scrambled cascades keep it far from drainable, so the finish
  // suppression (#132) doesn't apply here and auto-collect's own behaviour shows
  // cleanly. (The suppression itself is covered by the `finish` tests below.)
  describe("auto-collect", () => {
    test(
      "on by default: playing one Three home sweeps the other safe Threes after it",
      () => {
        // Playing 3S home leaves the other Threes safe (both opposite-colour
        // foundations are at the Two), so auto-collect sends them home too — the
        // whole row of Threes homes off a single command.
        let (dealt, _) = Repl.step(~options=Options.default, None, "deal freecell sendhome")
        let (afterMove, _) = Repl.step(~options=Options.default, dealt, "home 3S")
        switch afterMove {
        | Some(s) =>
          // 3H was never commanded, yet it's off the free cell and home on the
          // hearts foundation (pile 5) — wherever the sweep settles above it.
          switch GameState.locationOf(Repl.present(s), {suit: Hearts, rank: Three}) {
          | Some(GameState.InPile(5, _)) => expect(true)->toBe(true)
          | _ => expect(true)->toBe(false)
          }
        | None => expect(true)->toBe(false)
        }
      },
    )

    test(
      "off: the same move collects nothing extra",
      () => {
        // With the flag off the reducer's result stands untouched: 3S is home, the
        // other Threes still resting in their cells — an exact no-op path.
        let off = {Options.autoCollect: false}
        let (dealt, _) = Repl.step(~options=off, None, "deal freecell sendhome")
        let (afterMove, _) = Repl.step(~options=off, dealt, "home 3S")
        switch afterMove {
        | Some(s) =>
          // The hearts foundation still stands at its dealt Two; 3H is still parked
          // in a free cell (piles 0–3), untouched.
          expect(GameState.topOf(Repl.present(s), 5))->toEqual(Some({suit: Hearts, rank: Two}))
          switch GameState.locationOf(Repl.present(s), {suit: Hearts, rank: Three}) {
          | Some(GameState.InPile(i, _)) => expect(i >= 0 && i <= 3)->toBe(true) // a free cell
          | _ => expect(true)->toBe(false)
          }
        | None => expect(true)->toBe(false)
        }
      },
    )
  })

  // The end-game finish sweep (#132): the `finish` verb sweeps a drainable board
  // home to a win, reports when the board isn't yet drainable, and — the scope
  // decision — safe auto-collect steps aside once the board is finishable so the
  // sweep owns the end-game.
  describe("finish", () => {
    test(
      "sweeps a drainable board home to a win",
      () => {
        // The finish scenario is the trapped ♠6-over-♥3 tail: drainable by
        // foundation moves alone, so `finish` completes it in one gesture.
        let transcript = Repl.run(["deal freecell finish", "finish"])
        expect(has(transcript, "You win!"))->toBe(true)
      },
    )

    test(
      "reports when the board isn't drainable yet",
      () => {
        // A fresh FreeCell deal needs plenty of tableau play first — nothing to
        // finish.
        let transcript = Repl.run(["deal freecell", "finish"])
        expect(has(transcript, "Not finishable yet"))->toBe(true)
        expect(has(transcript, "You win!"))->toBe(false)
      },
    )

    test(
      "guides the user before a game is dealt",
      () => {
        expect(has(Repl.run(["finish"]), "Deal a game first"))->toBe(true)
      },
    )

    test(
      "safe auto-collect steps aside once the board is finishable (#125 scope)",
      () => {
        // On the finishable tail, `afterMove` must not auto-collect — even with the
        // option on (its default) — leaving the board for the `finish` sweep.
        let game = Game.freecell
        let state = Scenario.freecellFinish(game)
        let after = Repl.afterMove(~game, ~options=Options.default, state)
        expect(after)->toEqual(state)

        // Contrast: on a *non*-finishable board with a safe card, `afterMove` still
        // collects it — showing the finish guard, not a disabled option, is what
        // held the sweep back above. A lone Ace atop the first cascade, foundations
        // empty, is safe and homeable but nowhere near a win.
        let lone = {
          GameState.piles: game.piles->Array.mapWithIndex(
            (_, i) => i == 8 ? [{suit: Spades, rank: Ace}] : [],
          ),
          loose: [],
        }
        let collected = Repl.afterMove(~game, ~options=Options.default, lone)
        expect(collected == lone)->toBe(false)
      },
    )
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

// Undo/redo over the GameState history (#85): the CLI loop steps back and forth
// over the states an accepted move records. Folds a command script through
// `Repl.step`, inspecting the session's `present` state rather than the ASCII art
// so the assertions pin the actual card positions.
describe("Repl undo/redo", () => {
  // Fold a script of commands into the resulting session (the state assertions
  // read positions off `Repl.present`).
  let runToSession = (cmds: array<string>): option<Repl.session> =>
    cmds->Array.reduce(None, (acc, cmd) => {
      let (next, _) = Repl.step(~options=Options.default, acc, cmd)
      next
    })

  let locationOf = (s: option<Repl.session>, card) =>
    s->Option.flatMap(s => GameState.locationOf(Repl.present(s), card))

  test("apply → undo returns the prior state exactly, and redo replays it", () => {
    let as_ = {suit: Spades, rank: Ace}
    // Deal stacking (the run is dealt loose) and found pile 0 with the Ace.
    let afterMove = runToSession(["deal stacking", "move AS 0"])
    expect(locationOf(afterMove, as_))->toEqual(Some(GameState.InPile(0, 0)))
    // Undo puts the Ace back exactly where it rested before the move — loose.
    let (undone, _) = Repl.step(~options=Options.default, afterMove, "undo")
    expect(locationOf(undone, as_))->toEqual(Some(GameState.Loose))
    // Redo replays the move, landing the Ace back on pile 0.
    let (redone, _) = Repl.step(~options=Options.default, undone, "redo")
    expect(locationOf(redone, as_))->toEqual(Some(GameState.InPile(0, 0)))
  })

  test("undo past the start of a game is a no-op", () => {
    let dealt = runToSession(["deal stacking"])
    let (undone, text) = Repl.step(~options=Options.default, dealt, "undo")
    expect(has(text, "Nothing to undo"))->toBe(true)
    // The opening deal is unchanged — the Ace is still loose.
    expect(locationOf(undone, {suit: Spades, rank: Ace}))->toEqual(Some(GameState.Loose))
  })

  test("a fresh move after an undo clears the redo future", () => {
    // Move the Ace onto pile 0, undo it, then make a *different* move (onto pile 1).
    let branched = runToSession(["deal stacking", "move AS 0", "undo", "move AS 1"])
    expect(locationOf(branched, {suit: Spades, rank: Ace}))->toEqual(Some(GameState.InPile(1, 0)))
    // The undone move is gone — there's nothing to redo onto the abandoned branch.
    let (_, text) = Repl.step(~options=Options.default, branched, "redo")
    expect(has(text, "Nothing to redo"))->toBe(true)
  })

  test("undo steps back out of a win (works even from victory)", () => {
    // Win the foundations demo by stacking the whole Hearts run home, exactly as
    // the win test above does.
    let heartsRun =
      ["AH", "2H", "3H", "4H", "5H", "6H", "7H", "8H", "9H", "TH", "JH", "QH", "KH"]->Array.map(
        c => `move ${c} 0`,
      )
    let won = runToSession(Array.concat(["deal foundations"], heartsRun))
    switch won {
    | Some(s) => expect(GameState.hasWon(s.game, Repl.present(s)))->toBe(true)
    | None => expect(true)->toBe(false)
    }
    // Undo from the won position: the game is no longer won, and the win line is
    // gone from the restored board — the victory is just another undoable state.
    let (undone, text) = Repl.step(~options=Options.default, won, "undo")
    expect(has(text, "You win"))->toBe(false)
    switch undone {
    | Some(s) => expect(GameState.hasWon(s.game, Repl.present(s)))->toBe(false)
    | None => expect(true)->toBe(false)
    }
  })
})
