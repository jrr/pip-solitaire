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

// The renderer itself is `core`'s now (see `Render_test` there) — it draws the board the
// web console prints as well as the one this driver does. What's left to check here is
// the driver's *use* of it: that a session's boards come out in colour, since this end of
// it is going to a terminal.
describe("Render, from the driver", () => {
  test("a printed board is coloured for the terminal", () =>
    // The escape byte, by value — the same one `Render` builds its SGR codes from.
    expect(has(Repl.run(["deal freecell"]), String.fromCharCode(27)))->toBe(true)
  )
})

// The reducer driver end to end: a scripted sequence of commands folded through
// the pure interpreter, including a rejected move — the loop covered without a
// terminal (#84's "done when").
describe("Repl.run", () => {
  test("deals, makes a legal move, rejects an illegal one, and prints the board", () => {
    let transcript = Repl.run(["deal stacking", "move AS 0", "move 3C 0", "move 2H 0", "print"]) // Ace of Spades founds the empty tableau pile — legal // black Three onto black Ace: same colour — rejected // red Two onto black Ace: opposite colour, next rank — legal
    // The commands are echoed behind a prompt…
    expect(has(transcript, "pip> move AS 0"))->toBe(true)
    // …the illegal move is rejected, with a reason…
    expect(has(transcript, "Rejected: 3C can't stack there."))->toBe(true)
    // …and the final board shows both legally-placed cards.
    expect(has(transcript, `A♠`))->toBe(true)
    expect(has(transcript, `2♥`))->toBe(true)
  })

  // The three ways to say *where* (#the shared `Command.where`), through the driver.
  // What matters isn't that each is understood — `Command_test` covers the words — but
  // that they all end in the same dispatch: a board played by label, by card, or by
  // index has to be the same board, or the shorthands are a second game.
  describe("a move's destination, said three ways", () => {
    // The supermove scenario is a known board: an ordered 9♠-to-5♠ run on the first
    // cascade, four empty free cells, and an empty last column.
    let deal = "deal freecell supermove"
    // The board a transcript ends on: its last three sections — title, top row, bottom
    // row — with the echoed command lines (which differ by construction) left behind.
    let ending = lines => {
      let sections = Repl.run(lines)->String.split("\n\n")
      sections->Array.slice(~start=Array.length(sections) - 3, ~end=Array.length(sections))
    }

    test(
      "a slot label plays the move its pile index plays",
      () => {
        // T8 is the empty last column — pile 15 on this board.
        expect(ending([deal, "moverun 9S 8H 7S 6H 5S T8"]))->toEqual(
          ending([deal, "moverun 9S 8H 7S 6H 5S 15"]),
        )
        // C1 is the first free cell — pile 0.
        expect(ending([deal, "move 5S C1"]))->toEqual(ending([deal, "move 5S 0"]))
      },
    )

    test(
      "naming the card to land on plays the move its pile index plays",
      () => {
        // Park the Five in a cell, then bring it back by naming the card it goes on
        // rather than the column it lives in.
        expect(ending([deal, "move 5S C1", "move 5S 6H"]))->toEqual(
          ending([deal, "move 5S C1", "move 5S 8"]),
        )
      },
    )

    test(
      "mv and m are the same verb",
      () => {
        expect(ending([deal, "mv 5S C1"]))->toEqual(ending([deal, "move 5S C1"]))
        expect(ending([deal, "m 5S C1"]))->toEqual(ending([deal, "move 5S C1"]))
      },
    )

    // A destination the board can't read is reported like any other refusal — the
    // session survives it, and the reason names the board rather than the grammar.
    test(
      "a destination this board hasn't got is reported, not played",
      () => {
        expect(has(Repl.run([deal, "mv 5S T9"]), "No such tableau column: T9"))->toBe(true)
        expect(has(Repl.run([deal, "mv 5S 3D"]), "buried"))->toBe(true)
        expect(has(Repl.run([deal, "mv 5S KH"]), "buried"))->toBe(true)
      },
    )

    // The board-shaped destinations answer the same "deal a game first" the rest of the
    // board verbs do, rather than complaining about a board that isn't there.
    test(
      "they guide the user before a game is dealt",
      () => expect(has(Repl.run(["mv 5S T1"]), "Deal a game first"))->toBe(true),
    )
  })

  // And the same for a move's *source*, which used to be a card and nothing else. What
  // matters here is the same thing: naming the place a card is showing has to end in the
  // move naming the card would have made, or a shorthand is a second game.
  describe("a move's source, said two ways", () => {
    let deal = "deal freecell supermove"
    let ending = lines => {
      let sections = Repl.run(lines)->String.split("\n\n")
      sections->Array.slice(~start=Array.length(sections) - 3, ~end=Array.length(sections))
    }

    test(
      "the slot a card is showing in plays the move naming the card plays",
      () => {
        // Park the Five in the first cell, then send it home from the cell — once by
        // name, once by the label printed over it.
        expect(ending([deal, "move 5S C1", "move C1 T8"]))->toEqual(
          ending([deal, "move 5S C1", "move 5S T8"]),
        )
        // T1 is the first cascade — pile 8 — and the Five is showing on it to start.
        expect(ending([deal, "move T1 C1"]))->toEqual(ending([deal, "move 5S C1"]))
        expect(ending([deal, "move 8 C1"]))->toEqual(ending([deal, "move 5S C1"]))
      },
    )

    test(
      "the column a run is showing in supermoves the run naming every card supermoves",
      () =>
        // The scenario's whole point: a ready-to-lift 9♠→5♠ run on T1 and an empty T8.
        expect(ending([deal, "moverun T1 T8"]))->toEqual(
          ending([deal, "moverun 9S 8H 7S 6H 5S T8"]),
        ),
    )

    test(
      "an empty place is reported by name, not played",
      () => expect(has(Repl.run([deal, "move C1 T8"]), "C1 is empty."))->toBe(true),
    )
  })

  // Naming a card is how a typed move picks one up, and a name reaches anywhere on the
  // board — including under the cards resting on top of it. The reducer is what stops
  // the reach at what a hand could lift; these check the terminal says so, since typing
  // is the only way to ask for a move the view's drag never offers.
  describe("a move only lifts what a hand could", () => {
    // The supermove scenario again: 9♠-8♥-7♠-6♥-5♠ on T1, only the 5♠ showing, and T8
    // an empty column that would take any of them.
    let deal = "deal freecell supermove"
    // The board a transcript ends on, so a refused move can be shown to have left the
    // position exactly as it found it.
    let ending = lines => {
      let sections = Repl.run(Array.concat(lines, ["print"]))->String.split("\n\n")
      sections->Array.slice(~start=Array.length(sections) - 3, ~end=Array.length(sections))
    }

    test(
      "a buried card is refused rather than pulled out from under its pile",
      () => {
        expect(has(Repl.run([deal, "m 9S T8"]), "9S is buried"))->toBe(true)
        // And the board is the one it was: the 9♠ still at the bottom of its run.
        expect(ending([deal, "m 9S T8"]))->toEqual(ending([deal]))
      },
    )

    test(
      "a run that isn't showing at the top of its pile is refused too",
      () => {
        // 9♠-8♥ is a genuine run, but the 7♠-6♥-5♠ resting on it means no hand could
        // take hold of just those two.
        expect(
          has(Repl.run([deal, "moverun 9S 8H T8"]), "aren't lying together at the top of one pile"),
        )->toBe(true)
        expect(ending([deal, "moverun 9S 8H T8"]))->toEqual(ending([deal]))
        // The run that *is* showing — the whole tail — still moves as one.
        expect(has(Repl.run([deal, "moverun 9S 8H 7S 6H 5S T8"]), "Rejected"))->toBe(false)
      },
    )
  })

  // The verb table's prefix rule (`Command.resolveVerb`), through the driver: a
  // shorthand has to run the very command it abbreviates, and an ambiguous one has to
  // refuse rather than pick.
  describe("verbs, abbreviated", () => {
    // The boards either transcript ends on, since the echoed command lines differ by
    // construction — `pip> p` is not `pip> print`, and that's the only difference there
    // should be.
    let ending = lines => {
      let sections = Repl.run(lines)->String.split("\n\n")
      sections->Array.slice(~start=Array.length(sections) - 3, ~end=Array.length(sections))
    }

    test(
      "an unambiguous prefix runs the verb it abbreviates",
      () => {
        expect(ending(["deal freecell supermove", "p"]))->toEqual(
          ending(["deal freecell supermove", "print"]),
        )
        expect(ending(["deal freecell supermove", "move 5S C1", "u"]))->toEqual(
          ending(["deal freecell supermove", "move 5S C1", "undo"]),
        )
      },
    )

    test(
      "a prefix that fits two verbs says which two",
      () => {
        let transcript = Repl.run(["deal freecell", "r"])
        expect(has(transcript, "redo"))->toBe(true)
        expect(has(transcript, "redeal"))->toBe(true)
      },
    )
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
        let off = {...Options.default, Options.autoCollect: false}
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

  // Autoplay (#291): the `autoplay` verb hands the board to `core`'s solver, plays
  // the line it finds a move at a time, and lets this driver's own `finish` sweep the
  // rest home — so a solvable deal ends on the very win line a hand-played game does.
  describe("autoplay", () => {
    testWithin(
      "plays a real deal all the way to the win, a step at a time",
      () => {
        let transcript = Repl.run(["deal freecell", "autoplay"])
        // The reply says how long the line was, how long it took to find, and what the
        // search spent finding it — the timing is a real measurement, so what's pinned
        // here is the sentence's shape rather than any of its numbers.
        expect(has(transcript, "-move solution found in"))->toBe(true)
        expect(has(transcript, "moves tried"))->toBe(true)
        expect(has(transcript, "You win!"))->toBe(true)
        // Each planned move is committed as its own undoable step — the reason the
        // states go in one at a time rather than as one jump. A game the solver played
        // is as long as it looks, and undo walks back through it rather than
        // teleporting past the lot.
        let stepped = Repl.run(["deal freecell", "autoplay", "undo", "undo", "undo"])
        expect(has(stepped, "Nothing to undo."))->toBe(false)
      },
      ~timeout=120_000,
    )

    test(
      "says so when there was nothing left to think about",
      () => {
        // Already finishable: the solver plans no moves at all, and the sweep this
        // driver hands over to does the rest. A `Played` with no steps reads as a sentence rather
        // than as silence, since the board alone doesn't say which of the two happened.
        let transcript = Repl.run(["deal freecell finish", "autoplay"])
        expect(has(transcript, "nothing left to think about"))->toBe(true)
        expect(has(transcript, "You win!"))->toBe(true)
      },
    )

    test(
      "refuses a board it doesn't know how to play",
      () => {
        // The card-table demo isn't FreeCell, so there's no position to pack it into.
        let transcript = Repl.run(["deal stacking", "autoplay"])
        expect(has(transcript, "only plays FreeCell"))->toBe(true)
      },
    )

    test(
      "guides the user before a game is dealt",
      () => {
        expect(has(Repl.run(["autoplay"]), "Deal a game first"))->toBe(true)
      },
    )
  })

  // Column reorder (#159): the `movecol` verb reorders two cascades in one undoable
  // step when the house-rule option is on, does nothing when it's off, and rejects a
  // non-cascade or out-of-range target — mirroring the `finish`/`home` verb style.
  describe("movecol", () => {
    // FreeCell's cascades are pile indices 8–15; the cells/foundations sit at 0–7.
    let dealt = () => {
      let (s, _) = Repl.step(~options=Options.default, None, "deal freecell")
      s
    }

    test(
      "reorders two cascades (insert-and-shift), recorded as one undo step",
      () => {
        let start = dealt()
        // Capture the two columns the reorder will touch before moving them.
        let (col8, col9) = switch start {
        | Some(s) => (
            GameState.cardsInPile(Repl.present(s), 8),
            GameState.cardsInPile(Repl.present(s), 9),
          )
        | None => ([], [])
        }
        let (moved, _) = Repl.step(~options=Options.default, start, "movecol 8 15")
        switch moved {
        | Some(s) =>
          // Cascade 8 slid to 15; the one that followed it (9) slid into 8.
          expect(GameState.cardsInPile(Repl.present(s), 15))->toEqual(col8)
          expect(GameState.cardsInPile(Repl.present(s), 8))->toEqual(col9)
          // One clean undo step: undo restores the original order exactly.
          let (undone, _) = Repl.step(~options=Options.default, moved, "undo")
          switch undone {
          | Some(u) => expect(GameState.cardsInPile(Repl.present(u), 8))->toEqual(col8)
          | None => expect(true)->toBe(false)
          }
        | None => expect(true)->toBe(false)
        }
      },
    )

    test(
      "is an exact no-op when the option is off",
      () => {
        let off = {...Options.default, Options.allowColumnReorder: false}
        let (start, _) = Repl.step(~options=off, None, "deal freecell")
        let col8 = switch start {
        | Some(s) => GameState.cardsInPile(Repl.present(s), 8)
        | None => []
        }
        let (after, text) = Repl.step(~options=off, start, "movecol 8 15")
        // The board is untouched and the driver says the rule is off — nothing moved.
        expect(has(text, "off"))->toBe(true)
        switch after {
        | Some(s) => expect(GameState.cardsInPile(Repl.present(s), 8))->toEqual(col8)
        | None => expect(true)->toBe(false)
        }
      },
    )

    test(
      "rejects a non-cascade target and an out-of-range index",
      () => {
        // Pile 4 is a foundation (cells 0–3, foundations 4–7), so it isn't a column.
        let notColumn = Repl.run(["deal freecell", "movecol 8 4"])
        expect(has(notColumn, "isn't a cascade column"))->toBe(true)
        let outOfRange = Repl.run(["deal freecell", "movecol 8 99"])
        expect(has(outOfRange, "no such pile"))->toBe(true)
      },
    )

    test(
      "guides the user before a game is dealt",
      () => {
        expect(has(Repl.run(["movecol 8 15"]), "Deal a game first"))->toBe(true)
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
    expect(has(transcript, "pip> deal stacking"))->toBe(true)
    expect(has(transcript, "pip> print"))->toBe(true)
  })

  // The `deal` family, now read by `core`'s shared resolver so a terminal and the web
  // console agree on what the argument means.
  test("deals by number, and the same number twice is the same board", () => {
    let board = Repl.run(["deal 12345"])
    expect(has(board, "FreeCell"))->toBe(true)
    expect(Repl.run(["deal 12345"]))->toBe(board)
    // A *different* number is a different board — the number is really the deal.
    expect(Repl.run(["deal 24680"]) == board)->toBe(false)
  })

  // `new` invents a deal number, and inventing is the driver's job — so the interpreter
  // takes a `~newSeed` and its default is deterministic (`Cli.res` passes a random one).
  // That makes the three ways of asking for the canonical board provably the same board.
  // Compared board-only: the echoed command line differs by construction.
  test("a fresh deal, a numbered one and a named one agree on deal #1", () => {
    let board = t => t->String.split("\n\n")->Array.sliceToEnd(~start=1)->Array.join("\n\n")
    let fresh = board(Repl.run(["new"]))
    expect(fresh)->toBe(board(Repl.run([`deal ${Game.freecellSeed->Int.toString}`])))
    expect(fresh)->toBe(board(Repl.run(["deal freecell"])))
  })

  // The named positions (`Scenario`) reach the board through the shared resolver too —
  // the same vocabulary the browser's `?state=` opens. What each *position* does is
  // covered by the scenario tests above (`sendhome`, `finish`); this is the wiring.
  test("a named position deals a different board from the plain deal", () => {
    let posed = Repl.run(["deal freecell almost-won"])
    expect(has(posed, "FreeCell"))->toBe(true)
    expect(posed == Repl.run(["deal freecell"]))->toBe(false)
  })

  // A mistyped deal used to drop the session — the most destructive thing you could
  // enter. It now says what it couldn't read and leaves the game alone.
  test("a deal it can't read keeps the game already in play", () => {
    let transcript = Repl.run(["deal stacking", "deal nope", "print"])
    expect(has(transcript, "Unknown game: nope"))->toBe(true)
    // The board is still there to print — no "Deal a game first".
    expect(has(transcript, "Deal a game first"))->toBe(false)
    expect(has(transcript, "Stacking"))->toBe(true)
  })

  // `quit` ends the transcript where it appears, the way `exit` ends a shell script.
  test("quit ends the transcript and leaves the rest of the script unread", () => {
    let transcript = Repl.run(["deal stacking", "quit", "games", "print"])
    // The quit itself is echoed — a transcript should say why it stopped…
    expect(has(transcript, "pip> quit"))->toBe(true)
    // …and nothing after it ran or echoed.
    expect(has(transcript, "pip> games"))->toBe(false)
    expect(has(transcript, "pip> print"))->toBe(false)
  })
})

// `redeal`/`restart`: the web menu's Restart button as a verb (#156), and held to the
// same contract — replay the deal on the table from its opening layout, with a clean
// history, and from a posed position go to the game's *real* deal rather than the pose
// (see `TableScene`'s `publishRestart`).
describe("Repl redeal", () => {
  let runToSession = (cmds: array<string>): option<Repl.session> =>
    cmds->Array.reduce(None, (acc, cmd) => {
      let (next, _) = Repl.step(~options=Options.default, acc, cmd)
      next
    })

  test("puts the cards back and leaves nothing to undo", () => {
    let as_ = {suit: Spades, rank: Ace}
    let played = runToSession(["deal stacking", "move AS 0"])
    expect(played->Option.flatMap(s => GameState.locationOf(Repl.present(s), as_)))->toEqual(
      Some(GameState.InPile(0, 0)),
    )
    let (restarted, _) = Repl.step(~options=Options.default, played, "redeal")
    // Back where the deal put it…
    expect(restarted->Option.flatMap(s => GameState.locationOf(Repl.present(s), as_)))->toEqual(
      Some(GameState.Loose),
    )
    // …and the history starts here: a restart isn't an undo you can step back through.
    let (_, text) = Repl.step(~options=Options.default, restarted, "undo")
    expect(has(text, "Nothing to undo"))->toBe(true)
  })

  test("replays the same deal, not a new one", () => {
    let dealt = Repl.run(["deal 12345"])
    // The board after a restart is the board the number deals — byte for byte.
    expect(
      Repl.run(["deal 12345", "move AS 0", "redeal"])->String.endsWith(
        dealt->String.split("pip> deal 12345\n\n")->Array.getUnsafe(1),
      ),
    )->toBe(true)
  })

  test("from a posed position it restarts to the game's real deal", () => {
    // `almost-won` poses a board one move from victory; the real deal #1 is not that.
    let posed = runToSession(["deal freecell almost-won"])
    let (restarted, _) = Repl.step(~options=Options.default, posed, "redeal")
    switch (posed, restarted) {
    | (Some(before), Some(after)) =>
      expect(GameState.equal(Repl.present(before), Repl.present(after)))->toBe(false)
      // It's the opening layout of the very game that was on the table.
      expect(GameState.equal(Repl.present(after), GameState.initial(before.game)))->toBe(true)
    | _ => expect("no session")->toBe("session")
    }
  })

  test("there's nothing to replay before a game is dealt", () =>
    expect(has(Repl.run(["redeal"]), "Deal a game first"))->toBe(true)
  )
})

// The deal number on the board. It's the one fact you need to open the same board again
// — and it means the same thing in both front ends — so the board says it rather than
// making you remember what you typed.
describe("Render deal number", () => {
  test("a numbered deal, and the canonical board, name themselves", () => {
    expect(has(Repl.run(["deal 12345"]), "deal #12345"))->toBe(true)
    expect(has(Repl.run(["deal freecell"]), "deal #1"))->toBe(true)
  })

  // The rule the web app follows before offering a Share (#264): a posed position names
  // only the deal it's been *proved* to descend from, and stays quiet otherwise.
  test("a posed position names only a deal it descends from", () => {
    expect(has(Repl.run(["deal freecell almost-won"]), "deal #264"))->toBe(true)
    expect(has(Repl.run(["deal freecell midgame"]), "deal #"))->toBe(false)
  })

  test("a game with no seed behind it names none", () =>
    expect(has(Repl.run(["deal stacking"]), "deal #"))->toBe(false)
  )

  test("a redeal keeps naming the board it replays", () =>
    expect(has(Repl.run(["deal 777", "move AS 0", "redeal"]), "deal #777"))->toBe(true)
  )
})

// The driver's flags, typed (`set`). They're the *loop's* state rather than the
// interpreter's — a `~options` passed per call couldn't outlive the call that changed it
// — so these drive the state the way a real loop does, carrying both halves forward.
describe("Repl set", () => {
  let drive = (cmds: array<string>): (option<Repl.session>, Options.t) => {
    let session = ref(None)
    let flags = ref(Options.default)
    cmds->Array.forEach(line =>
      switch Repl.consider(~options=flags.contents, session.contents, line) {
      | Repl.Ran({session: next, options: flags', _}) =>
        session := next
        flags := flags'
      | Repl.Skipped | Repl.Cleared | Repl.Ended => ()
      }
    )
    (session.contents, flags.contents)
  }

  test("a set sticks, and leaves the other flags alone", () => {
    let (_, flags) = drive(["set autocollect off"])
    expect(flags.autoCollect)->toBe(false)
    expect(flags.allowColumnReorder)->toBe(true)
  })

  // The point of the verb: not that the value reads back, but that the *next move*
  // behaves differently. With auto-collect on, playing one Three home sweeps the other
  // safe Threes after it (the auto-collect tests above); switched off by hand, they stay.
  test("and the very next move honours it", () => {
    let (session, _) = drive(["deal freecell sendhome", "set autocollect off", "home 3S"])
    switch session->Option.flatMap(
      s => GameState.locationOf(Repl.present(s), {suit: Hearts, rank: Three}),
    ) {
    // The free cells are piles 0–3; the hearts foundation is 5. Still in its cell.
    | Some(GameState.InPile(pile, _)) => expect(pile < 4)->toBe(true)
    | _ => expect("nowhere")->toBe("in a free cell")
    }
  })

  // The house rule (#159) had no control anywhere before this — not a switch in the web
  // menu, not a flag on the CLI. Typing it off is now the only way to reach that branch.
  test("reorder off gates the reducer, and back on ungates it", () => {
    let off = Repl.run(["deal freecell", "set reorder off", "movecol 8 9"])
    expect(has(off, "Column reordering is off"))->toBe(true)
    let on = Repl.run(["deal freecell", "set reorder off", "set reorder on", "movecol 8 9"])
    expect(has(on, "Column reordering is off"))->toBe(false)
  })

  test("a bare set shows both flags", () => {
    let shown = Repl.run(["set"])
    expect(has(shown, "autocollect  on"))->toBe(true)
    expect(has(shown, "reorder      on"))->toBe(true)
  })

  // A malformed `set` is about the driver, not the board, so it answers with what it
  // couldn't read — not "deal a game first", which is what every other usage failure
  // rightly says when nothing has been dealt.
  test("a malformed set answers about the setting, dealt or not", () => {
    expect(has(Repl.run(["set frob on"]), `Not a setting: "frob"`))->toBe(true)
    expect(has(Repl.run(["set reorder nope"]), `Not on or off: "nope"`))->toBe(true)
    expect(has(Repl.run(["set autocollect"]), "Usage: set"))->toBe(true)
    expect(has(Repl.run(["set frob on"]), "Deal a game first"))->toBe(false)
  })
})

// The per-line decision both shapes of `cli play` share (a live prompt and the batch
// fold above). Everything that decides anything lives here, on the pure side, which is
// what keeps the interactive loop — untestable without a pty — down to plumbing.
describe("Repl.consider", () => {
  let consider = line => Repl.consider(~options=Options.default, None, line)

  test("a blank line and a `#` comment are skipped, unparsed", () => {
    expect(consider(""))->toEqual(Repl.Skipped)
    expect(consider("   "))->toEqual(Repl.Skipped)
    expect(consider("# a note"))->toEqual(Repl.Skipped)
    expect(consider("   # an indented note"))->toEqual(Repl.Skipped)
  })

  test("quit and exit end the session", () => {
    expect(consider("quit"))->toEqual(Repl.Ended)
    expect(consider("exit"))->toEqual(Repl.Ended)
  })

  // `clear` is the screen's business, and only one of the two shapes has a screen: a live
  // prompt wipes the terminal, a transcript echoes the line and prints nothing.
  test("clear is handed to the loop rather than answered here", () => {
    expect(consider("clear"))->toEqual(Repl.Cleared)
    let transcript = Repl.run(["deal stacking", "clear", "print"])
    expect(has(transcript, "pip> clear"))->toBe(true)
    expect(has(transcript, "Stacking"))->toBe(true)
  })

  test("anything else runs, carrying the session and the text to show", () =>
    switch consider("games") {
    | Repl.Ran({output}) => expect(has(output, "freecell"))->toBe(true)
    | Repl.Skipped | Repl.Ended => expect(true)->toBe(false)
    }
  )
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

  test("a no-op move records no undoable step (#215)", () => {
    let as_ = {suit: Spades, rank: Ace}
    // Found pile 0 with the Ace (one real step), then re-drop it onto pile 0 — a
    // lawful no-op that must not push a second state onto the undo stack.
    let session = runToSession(["deal stacking", "move AS 0", "move AS 0"])
    expect(locationOf(session, as_))->toEqual(Some(GameState.InPile(0, 0)))
    // A single undo returns to the opening deal (the Ace loose): the no-op left
    // only the *one* founding move on the stack, not two.
    let (undone, _) = Repl.step(~options=Options.default, session, "undo")
    expect(locationOf(undone, as_))->toEqual(Some(GameState.Loose))
    let (_, text) = Repl.step(~options=Options.default, undone, "undo")
    expect(has(text, "Nothing to undo"))->toBe(true)
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
