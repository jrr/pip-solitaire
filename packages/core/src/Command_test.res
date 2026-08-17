// Tests for the shared command parser (`Command.res`, #273).
//
// The parser is the seam two front ends meet at — the CLI's reducer driver and the
// web app's debug console — so what's locked in here is the *grammar itself*, once,
// rather than twice over in each front end's own tests. `packages/cli/examples/*.txt`
// and `Cli_test` still exercise the interpreter end to end; these are the unit tests
// underneath them, and the only tests the browser console has.
//
// Two properties matter most:
//
//   - a move-shaped line parses all the way to the `Reducer.action` a *pointer drop*
//     would dispatch, so a typed move and a dragged one are literally the same move;
//   - malformed input never fails — it comes back as `Usage` (a known verb) or
//     `Unknown` (no such verb), carrying the prose to show and, for `Usage`, the verb
//     it choked on, which is what lets an interpreter answer "deal a game first"
//     ahead of "that's not a card".

open Vitest
open Card

let ace = (suit): card => {suit, rank: Ace}

describe("Command.parse", () => {
  describe("moves parse to the action a drag would dispatch", () => {
    test(
      "move <card> <pile>",
      () =>
        expect(Command.parse("move AS 0"))->toEqual(
          Command.Dispatch(Reducer.Move({card: ace(Spades), to: Reducer.ToPile(0)})),
        ),
    )

    test(
      "the verb and the card are case-insensitive",
      () =>
        expect(Command.parse("MoVe as 12"))->toEqual(
          Command.Dispatch(Reducer.Move({card: ace(Spades), to: Reducer.ToPile(12)})),
        ),
    )

    test(
      "extra whitespace is nothing",
      () =>
        expect(Command.parse("   move    AS   0  "))->toEqual(
          Command.Dispatch(Reducer.Move({card: ace(Spades), to: Reducer.ToPile(0)})),
        ),
    )

    test(
      "move <card> table is the loose drop",
      () =>
        expect(Command.parse("move AS table"))->toEqual(
          Command.Dispatch(Reducer.Move({card: ace(Spades), to: Reducer.ToTable})),
        ),
    )

    test(
      "moverun takes its cards bottom-first, the target last",
      () =>
        expect(Command.parse("moverun 8H 7S 5"))->toEqual(
          Command.Dispatch(
            Reducer.MoveRun({
              cards: [{suit: Hearts, rank: Eight}, {suit: Spades, rank: Seven}],
              to: Reducer.ToPile(5),
            }),
          ),
        ),
    )

    test(
      "movecol takes two pile indices",
      () =>
        expect(Command.parse("movecol 8 15"))->toEqual(
          Command.Dispatch(Reducer.MoveColumn({from: 8, to: 15})),
        ),
    )

    // `home` deliberately stops at the card: which foundation will take it is a
    // question about the board, so the interpreter resolves it (see the module note).
    test(
      "home names a card and no destination",
      () => expect(Command.parse("home AS"))->toEqual(Command.Home({card: ace(Spades)})),
    )
  })

  describe("the session verbs", () => {
    test("a blank line is blank", () => expect(Command.parse("   "))->toEqual(Command.Blank))
    test("undo", () => expect(Command.parse("undo"))->toEqual(Command.Undo))
    test("redo", () => expect(Command.parse("redo"))->toEqual(Command.Redo))
    test("finish", () => expect(Command.parse("finish"))->toEqual(Command.Finish))
    test("help", () => expect(Command.parse("help"))->toEqual(Command.Help))
    test("clear", () => expect(Command.parse("clear"))->toEqual(Command.Clear))
    // Shared vocabulary even though only the CLI can act on it, exactly as `clear` is
    // shared even though only the panel can.
    test(
      "quit, and exit as its alias",
      () => {
        expect(Command.parse("quit"))->toEqual(Command.Quit)
        expect(Command.parse("exit"))->toEqual(Command.Quit)
      },
    )
    test(
      "print, and its aliases",
      () => {
        expect(Command.parse("print"))->toEqual(Command.Print)
        expect(Command.parse("board"))->toEqual(Command.Print)
        expect(Command.parse("show"))->toEqual(Command.Print)
      },
    )

    // What the argument *means* is the interpreter's call — a game id in the CLI, a
    // deal number in the browser console — so the parser hands the token over
    // untouched, and hands over `None` for the bare verb rather than complaining.
    test(
      "deal carries its argument through uninterpreted",
      () => {
        expect(Command.parse("deal freecell"))->toEqual(
          Command.Deal({game: Some("freecell"), scenario: None}),
        )
        expect(Command.parse("deal freecell midgame"))->toEqual(
          Command.Deal({game: Some("freecell"), scenario: Some("midgame")}),
        )
        expect(Command.parse("deal 12345"))->toEqual(
          Command.Deal({game: Some("12345"), scenario: None}),
        )
      },
    )

    test(
      "new is deal with nothing to deal",
      () => expect(Command.parse("new"))->toEqual(Command.Deal({game: None, scenario: None})),
    )
  })

  describe("malformed input answers rather than failing", () => {
    test(
      "an unknown verb names itself",
      () => expect(Command.parse("frobnicate AS"))->toEqual(Command.Unknown({verb: "frobnicate"})),
    )

    // Arity before content: `move AS` is missing a target, and saying so is more use
    // than complaining about the target that isn't there.
    test(
      "a verb with too few arguments asks for the usage line",
      () =>
        switch Command.parse("move AS") {
        | Command.Usage({verb, message}) =>
          expect(verb)->toBe("move")
          expect(message->String.startsWith("Usage: move"))->toBe(true)
        | _ => expect("not a usage")->toBe("usage")
        },
    )

    test(
      "a token that isn't a card is reported as such",
      () =>
        switch Command.parse("move XX 0") {
        | Command.Usage({verb, message}) =>
          expect(verb)->toBe("move")
          expect(message)->toBe(`Not a card: "XX" (try AS, TH, KD).`)
        | _ => expect("not a usage")->toBe("usage")
        },
    )

    test(
      "a token that isn't a pile is reported as such",
      () =>
        switch Command.parse("move AS nowhere") {
        | Command.Usage({message}) =>
          expect(message)->toBe(`Not a pile: "nowhere" (an index, or "table").`)
        | _ => expect("not a usage")->toBe("usage")
        },
    )

    test(
      "a moverun with a bad card in the run is refused whole",
      () =>
        switch Command.parse("moverun 8H XX 5") {
        | Command.Usage({verb, message}) =>
          expect(verb)->toBe("moverun")
          expect(message)->toBe(`Not all of those are cards (try AS, TH, KD).`)
        | _ => expect("not a usage")->toBe("usage")
        },
    )

    test(
      "a one-token moverun can't tell a card from a target",
      () =>
        switch Command.parse("moverun 8H") {
        | Command.Usage({verb, message}) =>
          expect(verb)->toBe("moverun")
          expect(message->String.startsWith("Usage: moverun"))->toBe(true)
        | _ => expect("not a usage")->toBe("usage")
        },
    )

    test(
      "movecol wants two indices",
      () =>
        switch Command.parse("movecol 8 nowhere") {
        | Command.Usage({verb, message}) =>
          expect(verb)->toBe("movecol")
          expect(message)->toBe(`Not a pile index (try two indices, e.g. movecol 8 15).`)
        | _ => expect("not a usage")->toBe("usage")
        },
    )

    // The verb rides along on every `Usage` precisely so a front end can decide what
    // to say *about the verb* before it says anything about the arguments.
    test(
      "a usage failure still names the verb it choked on",
      () =>
        switch Command.parse("home nonsense") {
        | Command.Usage({verb}) => expect(verb)->toBe("home")
        | _ => expect("not a usage")->toBe("usage")
        },
    )
  })
})

describe("Command.parseTarget", () => {
  test("an index is a pile", () =>
    expect(Command.parseTarget("7"))->toEqual(Some(Reducer.ToPile(7)))
  )
  test("table, loose and t all name the table", () => {
    expect(Command.parseTarget("table"))->toEqual(Some(Reducer.ToTable))
    expect(Command.parseTarget("LOOSE"))->toEqual(Some(Reducer.ToTable))
    expect(Command.parseTarget("t"))->toEqual(Some(Reducer.ToTable))
  })
  test("anything else is no target at all", () => expect(Command.parseTarget("qq"))->toEqual(None))
})

describe("Command.describeRejection", () => {
  // A rejection is named by the card that bounced, so someone typing learns which
  // card the reducer refused rather than just that something was refused.
  test("a Move is named by its card", () =>
    expect(
      Command.describeRejection(
        Reducer.Rejected,
        ~action=Reducer.Move({card: ace(Spades), to: Reducer.ToPile(0)}),
      ),
    )->toBe("Rejected: AS can't stack there.")
  )

  test("a MoveRun is named by the bottom card of its run", () =>
    expect(
      Command.describeRejection(
        Reducer.NotARun,
        ~action=Reducer.MoveRun({
          cards: [{suit: Hearts, rank: Eight}, {suit: Spades, rank: Seven}],
          to: Reducer.ToPile(0),
        }),
      ),
    )->toBe("Rejected: those cards aren't an ordered run.")
  )

  // A reorder carries no card, so it's described on its own terms.
  test("a MoveColumn is described without one", () => {
    expect(
      Command.describeRejection(Reducer.NotAColumn, ~action=Reducer.MoveColumn({from: 8, to: 4})),
    )->toBe("Rejected: that pile isn't a cascade column.")
    expect(
      Command.describeRejection(Reducer.NoSuchPile, ~action=Reducer.MoveColumn({from: 8, to: 99})),
    )->toBe("Rejected: no such pile.")
  })
})

describe("Command.renderHelp", () => {
  // The listing is composed per front end out of shared rows, so the one thing worth
  // pinning is that they come out as one aligned table rather than two ragged ones.
  test("descriptions line up in a single column", () => {
    let lines = Command.renderHelp([("a", "first"), ("longer verb", "second")])->String.split("\n")
    let column = line =>
      line->String.indexOf("first") >= 0
        ? line->String.indexOf("first")
        : line->String.indexOf("second")
    expect(lines->Array.map(column))->toEqual([15, 15])
  })

  test("every shared board verb is listed", () => {
    let listed = Command.boardHelp->Array.map(((verb, _)) => verb)->Array.join(" ")
    ["move", "moverun", "home", "movecol", "finish", "undo", "redo"]->Array.forEach(
      verb => expect(listed->String.includes(verb))->toBe(true),
    )
  })
})
