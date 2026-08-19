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

    // The two destinations a *board* has to read stop short of an action, for the same
    // reason `home` does: "which pile is showing the Three of Clubs" isn't a property
    // of the line. What the parser locks in is that the words were understood.
    test(
      "a card destination parses to the card to land on",
      () =>
        expect(Command.parse("move 2H 3C"))->toEqual(
          Command.MoveTo({
            from: Command.Cards([{suit: Hearts, rank: Two}]),
            where: Command.Onto({suit: Clubs, rank: Three}),
          }),
        ),
    )

    test(
      "a slot label parses to its role and 1-based ordinal",
      () => {
        expect(Command.parse("move AS T3"))->toEqual(
          Command.MoveTo({
            from: Command.Cards([ace(Spades)]),
            where: Command.Slot({role: Game.Cascade, ordinal: 3}),
          }),
        )
        expect(Command.parse("move AS c1"))->toEqual(
          Command.MoveTo({
            from: Command.Cards([ace(Spades)]),
            where: Command.Slot({role: Game.FreeCell, ordinal: 1}),
          }),
        )
        expect(Command.parse("move AS F4"))->toEqual(
          Command.MoveTo({
            from: Command.Cards([ace(Spades)]),
            where: Command.Slot({role: Game.Foundation, ordinal: 4}),
          }),
        )
      },
    )

    // The collision the label scheme is shaped around: a card is rank-then-suit, so
    // `3C` is the Three of Clubs and can never be read as the third free cell — the
    // label for that is `C3`, letter first.
    test(
      "a card destination is never mistaken for a slot label",
      () =>
        expect(Command.parse("move AS 3C"))->toEqual(
          Command.MoveTo({
            from: Command.Cards([ace(Spades)]),
            where: Command.Onto({suit: Clubs, rank: Three}),
          }),
        ),
    )

    // `Int.fromString` is `parseInt` underneath, which reads "4D" as 4. That was merely
    // untidy while a number was the only thing a destination could be; with cards in the
    // same position it would aim a move at pile 4 instead of at the Four of Diamonds.
    test(
      "a numeric destination is all digits or it isn't a pile index",
      () => {
        expect(Command.parse("move AS 4D"))->toEqual(
          Command.MoveTo({
            from: Command.Cards([ace(Spades)]),
            where: Command.Onto({suit: Diamonds, rank: Four}),
          }),
        )
        switch Command.parse("move AS 12abc") {
        | Command.Usage({verb}) => expect(verb)->toBe("move")
        | _ => expect(true)->toBe(false)
        }
      },
    )

    test(
      "mv and m are the same verb, still complaining as move",
      () => {
        let asMove = Command.Dispatch(Reducer.Move({card: ace(Spades), to: Reducer.ToPile(0)}))
        expect(Command.parse("mv AS 0"))->toEqual(asMove)
        expect(Command.parse("m AS 0"))->toEqual(asMove)
        expect(Command.parse("MV AS 0"))->toEqual(asMove)
        // The shorthand doesn't grow messages of its own: an interpreter keys the
        // "deal a game first" hint off the verb, and there's still only one.
        switch Command.parse("m ZZ 0") {
        | Command.Usage({verb}) => expect(verb)->toBe("move")
        | _ => expect(true)->toBe(false)
        }
      },
    )

    test(
      "a run takes the same three destinations",
      () =>
        expect(Command.parse("moverun 8H 7S T3"))->toEqual(
          Command.MoveTo({
            from: Command.Cards([{suit: Hearts, rank: Eight}, {suit: Spades, rank: Seven}]),
            where: Command.Slot({role: Game.Cascade, ordinal: 3}),
          }),
        ),
    )

    // The source half, which used to be a card and nothing else. Like the two
    // board-shaped destinations it stops short of an action: "what is showing in C1"
    // is not a property of the line.
    test(
      "a slot names what to move, not just where to move it",
      () => {
        expect(Command.parse("move C1 F1"))->toEqual(
          Command.MoveTo({
            from: Command.Top(Command.InSlot({role: Game.FreeCell, ordinal: 1})),
            where: Command.Slot({role: Game.Foundation, ordinal: 1}),
          }),
        )
        // A pile index says the same thing the absolute way, exactly as it does on the
        // destination side.
        expect(Command.parse("move 11 F1"))->toEqual(
          Command.MoveTo({
            from: Command.Top(Command.AtPile(11)),
            where: Command.Slot({role: Game.Foundation, ordinal: 1}),
          }),
        )
      },
    )

    // The same collision the destination grammar is shaped around, from the other end:
    // `TC` is the Ten of Clubs and `C1` is the first free cell, and neither can be read
    // as the other.
    test(
      "a card source is never mistaken for a slot label",
      () =>
        expect(Command.parse("move TC 0"))->toEqual(
          Command.Dispatch(Reducer.Move({card: {suit: Clubs, rank: Ten}, to: Reducer.ToPile(0)})),
        ),
    )

    // A run named by the place it's showing in: one token where the cards would be
    // several, which is the whole point — nobody wants to type five card names for the
    // run they can see.
    test(
      "moverun takes the column a run is showing in",
      () => {
        expect(Command.parse("moverun T6 T2"))->toEqual(
          Command.MoveTo({
            from: Command.Run(Command.InSlot({role: Game.Cascade, ordinal: 6})),
            where: Command.Slot({role: Game.Cascade, ordinal: 2}),
          }),
        )
        // Two places name two runs and no move, so it asks rather than guessing which.
        switch Command.parse("moverun T6 T7 T2") {
        | Command.Usage({verb}) => expect(verb)->toBe("moverun")
        | _ => expect("not a usage")->toBe("usage")
        }
      },
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
    // No arguments: what autoplay does is decided entirely by the board it's typed at
    // (#291), so there's nothing about the line left to read.
    test(
      "autoplay, down to a bare a",
      () => {
        expect(Command.parse("autoplay"))->toEqual(Command.Autoplay)
        expect(Command.parse("a"))->toEqual(Command.Autoplay)
      },
    )
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

    test(
      "redeal, and restart as its alias",
      () => {
        expect(Command.parse("redeal"))->toEqual(Command.Redeal)
        expect(Command.parse("restart"))->toEqual(Command.Redeal)
      },
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

    // A source that's none of the three things a source can be. It lists them for the
    // reason the destination complaint below does: a refusal that only says "no" sends
    // the reader to the source code.
    test(
      "a token that names nothing to move is reported as such, listing what does",
      () =>
        switch Command.parse("move XX 0") {
        | Command.Usage({verb, message}) =>
          expect(verb)->toBe("move")
          expect(message->String.includes(`"XX"`))->toBe(true)
          expect(message->String.includes("AS"))->toBe(true)
          expect(message->String.includes("T3"))->toBe(true)
          expect(message->String.includes("pile index"))->toBe(true)
        | _ => expect("not a usage")->toBe("usage")
        },
    )

    // A destination that's none of the four things a destination can be. The complaint
    // lists them, because a refusal that only says "no" sends the reader to the source.
    test(
      "a token that names no place to move to is reported as such, listing what does",
      () =>
        switch Command.parse("move AS nowhere") {
        | Command.Usage({message}) =>
          expect(message->String.includes(`"nowhere"`))->toBe(true)
          expect(message->String.includes("pile index"))->toBe(true)
          expect(message->String.includes("T3"))->toBe(true)
          expect(message->String.includes("9S"))->toBe(true)
          expect(message->String.includes(`"table"`))->toBe(true)
        | _ => expect("not a usage")->toBe("usage")
        },
    )

    test(
      "a moverun with a bad card in the run is refused whole",
      () =>
        switch Command.parse("moverun 8H XX 5") {
        | Command.Usage({verb, message}) =>
          expect(verb)->toBe("moverun")
          expect(message->String.startsWith("Not all of those are cards"))->toBe(true)
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

// One reading of a `deal` argument for both front ends (the CLI's session and the web
// console's board): the resolver is what stopped `deal 12345` meaning a board in the
// browser and an unknown game in the terminal.
describe("Command.resolveDeal", () => {
  let resolve = (~game=?, ~scenario=?, ()) => Command.resolveDeal(~game, ~scenario)

  test("no argument asks for something fresh", () => expect(resolve())->toEqual(Command.Fresh))

  test("an all-digits argument is a deal number", () => {
    expect(resolve(~game="12345", ()))->toEqual(Command.Numbered({seed: 12345}))
    expect(resolve(~game="1", ()))->toEqual(Command.Numbered({seed: 1}))
  })

  // `Int.fromString` would read this as 12 and open a board nobody asked for, so the
  // resolver insists on the whole token being digits.
  test("a number with something stuck to it is not a deal number", () =>
    expect(resolve(~game="12abc", ()))->toEqual(Command.NoSuchGame({id: "12abc"}))
  )

  test("a game id names that game, at its opening layout", () =>
    switch resolve(~game="stacking", ()) {
    | Command.Named({game, position: None}) => expect(game.id)->toBe("stacking")
    | _ => expect("not a named game")->toBe("named game")
    }
  )

  test("a second token names one of that game's positions", () =>
    switch resolve(~game="freecell", ~scenario="midgame", ()) {
    | Command.Named({game, position: Some(position)}) =>
      expect(game.id)->toBe("freecell")
      expect(position.name)->toBe("midgame")
      // A layout assembled rather than played to, so it points at no deal (`Scenario`).
      expect(position.seed)->toEqual(None)
    | _ => expect("not a posed game")->toBe("posed game")
    }
  )

  // The whole `Scenario.named` comes through rather than just the state it builds, so a
  // caller can also read the deal a posed board descends from — which is what the web
  // app's Share buttons need after a `deal freecell almost-won`.
  test("a position that descends from a deal carries its number", () =>
    switch resolve(~game="freecell", ~scenario="almost-won", ()) {
    | Command.Named({position: Some(position)}) => expect(position.seed)->toEqual(Some(264))
    | _ => expect("not a posed game")->toBe("posed game")
    }
  )

  test("a game we don't have, and a position that game doesn't have", () => {
    expect(resolve(~game="nope", ()))->toEqual(Command.NoSuchGame({id: "nope"}))
    switch resolve(~game="freecell", ~scenario="nonesuch", ()) {
    | Command.NoSuchScenario({game, name}) =>
      expect(game.id)->toBe("freecell")
      expect(name)->toBe("nonesuch")
    | _ => expect("not a missing position")->toBe("missing position")
    }
  })

  // Each refusal ends with what *would* have worked.
  test("the refusals list the way out", () => {
    expect(Command.describeNoSuchGame("nope")->String.includes("freecell"))->toBe(true)
    expect(
      Command.describeNoSuchScenario(~game=Game.freecell, ~name="nonesuch")->String.includes(
        "midgame",
      ),
    )->toBe(true)
  })
})

// The driver's flags, addressed by name (`Options.setting`). The settings are a closed
// set `core` knows, so the parser hands over a typed one rather than a string each front
// end re-checks.
describe("Command.parse — set", () => {
  test("a bare set asks to see them", () => expect(Command.parse("set"))->toEqual(Command.Settings))

  test("set <setting> on|off names a typed setting and a value", () => {
    expect(Command.parse("set autocollect off"))->toEqual(
      Command.Set({setting: Options.AutoCollect, on: false}),
    )
    expect(Command.parse("set reorder on"))->toEqual(
      Command.Set({setting: Options.ColumnReorder, on: true}),
    )
  })

  // Generous about spelling on both halves: a flag refused over `true` vs `on` teaches
  // nothing, and the settings answer to the names they're known by elsewhere.
  test("the aliases people will actually type", () => {
    expect(Command.parse("SET Auto-Collect TRUE"))->toEqual(
      Command.Set({setting: Options.AutoCollect, on: true}),
    )
    expect(Command.parse("set movecol no"))->toEqual(
      Command.Set({setting: Options.ColumnReorder, on: false}),
    )
  })

  test("a setting we don't have, and a value that isn't on or off", () => {
    switch Command.parse("set frobnicate on") {
    | Command.Usage({verb, message}) =>
      expect(verb)->toBe("set")
      expect(message)->toBe(`Not a setting: "frobnicate" (autocollect, reorder).`)
    | _ => expect("not a usage")->toBe("usage")
    }
    switch Command.parse("set autocollect maybe") {
    | Command.Usage({message}) => expect(message)->toBe(`Not on or off: "maybe".`)
    | _ => expect("not a usage")->toBe("usage")
    }
  })

  // Arity before content, as everywhere else in this grammar.
  test("a setting with no value asks for the usage line", () =>
    switch Command.parse("set autocollect") {
    | Command.Usage({verb, message}) =>
      expect(verb)->toBe("set")
      expect(message->String.startsWith("Usage: set"))->toBe(true)
    | _ => expect("not a usage")->toBe("usage")
    }
  )

  test("the listing shows every flag and its value", () => {
    let shown = Command.describeSettings(Options.default)
    expect(shown->String.includes("autocollect  on"))->toBe(true)
    expect(shown->String.includes("reorder      on"))->toBe(true)
    expect(
      Command.describeSettings(
        Options.apply(Options.default, ~setting=Options.AutoCollect, ~on=false),
      )->String.includes("autocollect  off"),
    )->toBe(true)
  })
})

describe("Options", () => {
  test("apply changes one flag and leaves the other", () => {
    let off = Options.apply(Options.default, ~setting=Options.ColumnReorder, ~on=false)
    expect(off.allowColumnReorder)->toBe(false)
    expect(off.autoCollect)->toBe(Options.default.autoCollect)
  })

  test("read is apply's inverse, for both settings", () =>
    Options.all->Array.forEach(
      setting => {
        expect(Options.read(Options.apply(Options.default, ~setting, ~on=false), setting))->toBe(
          false,
        )
        expect(Options.read(Options.apply(Options.default, ~setting, ~on=true), setting))->toBe(
          true,
        )
      },
    )
  )

  test("every setting parses back from the name it's listed under", () =>
    Options.all->Array.forEach(
      setting => expect(Options.parse(Options.name(setting)))->toEqual(Some(setting)),
    )
  )
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
    ["move", "moverun", "home", "movecol", "finish", "autoplay", "undo", "redo"]->Array.forEach(
      verb => expect(listed->String.includes(verb))->toBe(true),
    )
  })
})

// --- Verbs, and how little of one you have to type -----------------------------
// The table and its prefix rule (`Command.resolveVerb`). What's being pinned down is
// less the shorthands than the two rules that keep them trustworthy: a whole word is
// never shadowed by a longer verb, and a prefix that fits two verbs is refused by name
// rather than resolved to whichever the table happens to list first.
describe("Command.parse, abbreviated", () => {
  test("an unambiguous prefix is the verb", () => {
    expect(Command.parse("p"))->toEqual(Command.Print)
    expect(Command.parse("u"))->toEqual(Command.Undo)
    expect(Command.parse("f"))->toEqual(Command.Finish)
    expect(Command.parse("de 12345"))->toEqual(Command.Deal({game: Some("12345"), scenario: None}))
  })

  test("a whole word wins over any prefix of a longer one", () => {
    // `set` is a verb *and* the start of nothing else; `redo` and `redeal` are each
    // other's neighbours, and typing either in full says which.
    expect(Command.parse("set"))->toEqual(Command.Settings)
    expect(Command.parse("redo"))->toEqual(Command.Redo)
    expect(Command.parse("redeal"))->toEqual(Command.Redeal)
  })

  test("a prefix that fits two verbs is refused by name", () => {
    switch Command.parse("h") {
    | Command.Ambiguous({verb, matches}) =>
      expect(verb)->toBe("h")
      expect(matches)->toEqual(["help", "home"])
    | _ => expect("not ambiguous")->toBe("ambiguous")
    }
    // …and the refusal says both, so the next keystroke is obvious.
    switch Command.parse("r") {
    | Command.Ambiguous({verb, matches}) =>
      let message = Command.describeAmbiguous(~verb, ~matches)
      expect(message->String.includes("redo"))->toBe(true)
      expect(message->String.includes("redeal"))->toBe(true)
    | _ => expect("not ambiguous")->toBe("ambiguous")
    }
  })

  test("the pinned aliases still win, and fill the gaps the canonical names leave", () => {
    // `m` fits three verbs and is pinned to one of them.
    expect(Command.parse("m AS 0"))->toEqual(
      Command.Dispatch(Reducer.Move({card: ace(Spades), to: Reducer.ToPile(0)})),
    )
    // `s` is `set` because a canonical name outranks the `show` alias…
    expect(Command.parse("s"))->toEqual(Command.Settings)
    // …while `n` is free for `new`, which nothing canonical claims.
    expect(Command.parse("n"))->toEqual(Command.Deal({game: None, scenario: None}))
  })

  test("a prefix of nothing is still an unknown verb", () =>
    expect(Command.parse("zz"))->toEqual(Command.Unknown({verb: "zz"}))
  )
})

// --- Resolving a destination against a board ----------------------------------
// The other half of the two board-shaped destinations: `parse` read the words, and
// `resolveWhere` reads the board they were said about. It lives in `core` so a
// terminal and the browser console pick the same pile from the same words.
describe("Command.resolveWhere", () => {
  let game = Game.freecell
  let state = GameState.initial(game)

  // `Game.freecell` is deal #1: four free cells, four foundations, then the eight
  // dealt cascades — so `T1` is pile 8 and `C1` is pile 0.
  test("a slot label resolves to the pile index that role's ordinal names", () => {
    expect(
      Command.resolveWhere(~game, state, Command.Slot({role: Game.Cascade, ordinal: 1})),
    )->toEqual(Ok(Reducer.ToPile(8)))
    expect(
      Command.resolveWhere(~game, state, Command.Slot({role: Game.FreeCell, ordinal: 1})),
    )->toEqual(Ok(Reducer.ToPile(0)))
    expect(
      Command.resolveWhere(~game, state, Command.Slot({role: Game.Foundation, ordinal: 4})),
    )->toEqual(Ok(Reducer.ToPile(7)))
  })

  // The label the board prints and the label the parser takes are the same string —
  // the property `Slot` exists to hold, checked here against a real board.
  test("every label the board prints resolves to the pile it was printed over", () =>
    game.piles->Array.forEachWithIndex(
      (_, i) =>
        switch Slot.labelAt(~game, i) {
        | None => expect(true)->toBe(false)
        | Some(label) =>
          switch Command.parseWhere(label) {
          | Some(where) =>
            expect(Command.resolveWhere(~game, state, where))->toEqual(Ok(Reducer.ToPile(i)))
          | None => expect(true)->toBe(false)
          }
        },
    )
  )

  test("an ordinal past the board's slots is refused, saying what it has", () =>
    switch Command.resolveWhere(~game, state, Command.Slot({role: Game.Cascade, ordinal: 9})) {
    | Ok(_) => expect(true)->toBe(false)
    | Error(message) =>
      expect(message->String.includes("T9"))->toBe(true)
      expect(message->String.includes("T1–T8"))->toBe(true)
    }
  )

  test("a board with none of a role says so rather than counting to zero", () =>
    switch Command.resolveWhere(
      ~game=Game.stacking,
      GameState.initial(Game.stacking),
      Command.Slot({role: Game.FreeCell, ordinal: 1}),
    ) {
    | Ok(_) => expect(true)->toBe(false)
    | Error(message) => expect(message->String.includes("no free cells"))->toBe(true)
    }
  )

  // The point of the card destination: name what you can see, not the index you'd
  // have to count out. Deal #1's cascades each show their last dealt card.
  test("a card destination resolves to the pile showing it", () => {
    let top = i =>
      switch GameState.topOf(state, i) {
      | Some(card) => card
      | None => {suit: Spades, rank: Ace}
      }
    expect(Command.resolveWhere(~game, state, Command.Onto(top(8))))->toEqual(Ok(Reducer.ToPile(8)))
    expect(Command.resolveWhere(~game, state, Command.Onto(top(15))))->toEqual(
      Ok(Reducer.ToPile(15)),
    )
  })

  // A buried card is refused rather than resolved to its pile: landing "on" it would
  // really land on whatever covers it — a different move from the one that was typed,
  // and one the rules might happily accept.
  test("a buried card is refused, not read as its pile", () => {
    let buried = GameState.cardsInPile(state, 8)->Array.getUnsafe(0)
    switch Command.resolveWhere(~game, state, Command.Onto(buried)) {
    | Ok(_) => expect(true)->toBe(false)
    | Error(message) => expect(message->String.includes("buried"))->toBe(true)
    }
  })

  // An empty foundation shows nothing, so no card names it — that's what the labels
  // are for, and what the refusal should send the reader to.
  test("a card that isn't showing anywhere is refused", () => {
    // Every card is dealt into a cascade on a fresh FreeCell board, so this asks about
    // a card that exists but is covered — the "isn't in play" arm needs a board that
    // doesn't hold it at all.
    let missing = GameState.initial(Game.freeCells)
    switch Command.resolveWhere(
      ~game=Game.freeCells,
      missing,
      Command.Onto({suit: Hearts, rank: Two}),
    ) {
    | Ok(_) => expect(true)->toBe(false)
    | Error(message) => expect(message->String.includes("isn't in play"))->toBe(true)
    }
  })

  // The guard that lets the rule stay simple ("the pile showing that card"): if a board
  // ever *could* show one card twice, the move is refused rather than sent to whichever
  // pile happened to be first. A standard deck can't produce this, so the state is built
  // by hand — the rule is about the model, not about FreeCell.
  test("a card showing on more than one pile is ambiguous, and says which", () => {
    let twice = {suit: Clubs, rank: Three}
    let doubled: GameState.t = {
      piles: Game.freeCells.piles->Array.mapWithIndex((_, i) => i < 2 ? [twice] : []),
      loose: [],
    }
    switch Command.resolveWhere(~game=Game.freeCells, doubled, Command.Onto(twice)) {
    | Ok(_) => expect(true)->toBe(false)
    | Error(message) =>
      expect(message->String.includes("Ambiguous"))->toBe(true)
      // …and it points at the two, by the names the board prints over them.
      expect(message->String.includes("C1, C2"))->toBe(true)
    }
  })

  // The one destination that needs no board still passes through unchanged, so a
  // resolved move and an index-typed one are the same dispatch.
  test("an index or the table passes straight through", () => {
    expect(Command.resolveWhere(~game, state, Command.At(Reducer.ToPile(3))))->toEqual(
      Ok(Reducer.ToPile(3)),
    )
    expect(Command.resolveWhere(~game, state, Command.At(Reducer.ToTable)))->toEqual(
      Ok(Reducer.ToTable),
    )
  })

  // One card is a `Move`, several are the supermove — the same actions the index-typed
  // commands parse to, which is what makes a resolved destination not a second kind of
  // move.
  test("the resolved action is the ordinary Move / MoveRun", () => {
    let eight: card = {suit: Hearts, rank: Eight}
    let seven: card = {suit: Spades, rank: Seven}
    expect(Command.moveAction(~cards=[eight], ~to=Reducer.ToPile(9)))->toEqual(
      Reducer.Move({card: eight, to: Reducer.ToPile(9)}),
    )
    expect(Command.moveAction(~cards=[eight, seven], ~to=Reducer.ToPile(9)))->toEqual(
      Reducer.MoveRun({cards: [eight, seven], to: Reducer.ToPile(9)}),
    )
  })
})

// --- Resolving a source against a board ----------------------------------------
// The other half of the same job (`Command.resolveFrom`): the words named a *place*,
// and only the board knows which card is lying there. Shared for the same reason the
// destination reader is — `move C1 F1` has to lift the same card in a terminal and in
// the panel.
describe("Command.resolveFrom", () => {
  let game = Game.freecell
  let state = GameState.initial(game)
  // Deal #1's layout: four free cells, four foundations, then the eight cascades — so
  // `T1` is pile 8 and `C1` is pile 0.
  let firstCascade = 8

  let topOfFirstCascade = switch GameState.topOf(state, firstCascade) {
  | Some(card) => card
  | None => ace(Spades) // unreachable: a freshly dealt cascade is never empty
  }

  test("cards named outright are handed straight back", () =>
    expect(Command.resolveFrom(~game, state, Command.Cards([ace(Spades)])))->toEqual(
      Ok([ace(Spades)]),
    )
  )

  test("a slot lifts the card showing there", () => {
    expect(
      Command.resolveFrom(
        ~game,
        state,
        Command.Top(Command.InSlot({role: Game.Cascade, ordinal: 1})),
      ),
    )->toEqual(Ok([topOfFirstCascade]))
    // The same pile, said the absolute way.
    expect(Command.resolveFrom(~game, state, Command.Top(Command.AtPile(firstCascade))))->toEqual(
      Ok([topOfFirstCascade]),
    )
  })

  // A place with nothing in it is a refusal rather than an empty move: the player named
  // something they can see, and what they can see is that it's empty.
  test("an empty place says so, by the name the board prints over it", () =>
    switch Command.resolveFrom(
      ~game,
      state,
      Command.Top(Command.InSlot({role: Game.FreeCell, ordinal: 1})),
    ) {
    | Ok(_) => expect("empty cell resolved")->toBe("refused")
    | Error(message) => expect(message)->toBe("C1 is empty.")
    }
  )

  // The refusals a destination gets, from the source side — one reader answers both, so
  // an out-of-range label reads the same whichever end of a move it was said at.
  test("a place this board hasn't got is refused the way a destination is", () => {
    switch Command.resolveFrom(
      ~game,
      state,
      Command.Top(Command.InSlot({role: Game.Cascade, ordinal: 9})),
    ) {
    | Ok(_) => expect("T9 resolved")->toBe("refused")
    | Error(message) => expect(message->String.includes("T1–T8"))->toBe(true)
    }
    switch Command.resolveFrom(~game, state, Command.Top(Command.AtPile(99))) {
    | Ok(_) => expect("pile 99 resolved")->toBe("refused")
    | Error(message) => expect(message->String.includes("No such pile: 99"))->toBe(true)
    }
  })

  // What `moverun T1 T8` means: the run a player would take hold of, not the pile.
  describe("the run showing in a column", () => {
    let supermove = switch Scenario.forName(game, "supermove") {
    | Some(s) => s
    | None => state // unreachable: the scenario is listed for freecell
    }
    let run = [
      {suit: Spades, rank: Nine},
      {suit: Hearts, rank: Eight},
      {suit: Spades, rank: Seven},
      {suit: Hearts, rank: Six},
      {suit: Spades, rank: Five},
    ]

    test(
      "a run showing in a column is lifted whole",
      () =>
        expect(
          Command.resolveFrom(
            ~game,
            supermove,
            Command.Run(Command.InSlot({role: Game.Cascade, ordinal: 1})),
          ),
        )->toEqual(Ok(run)),
    )

    // It stops where the run stops rather than taking the pile: a King dropped on top
    // heads a run of one, because nothing outranks it.
    test(
      "it stops at the deepest card that still heads a run",
      () => {
        let capped = Reducer.placeOnPile(supermove, {suit: Spades, rank: King}, firstCascade)
        expect(
          Command.resolveFrom(
            ~game,
            capped,
            Command.Run(Command.InSlot({role: Game.Cascade, ordinal: 1})),
          ),
        )->toEqual(Ok([{suit: Spades, rank: King}]))
      },
    )

    // Length one is a run, so `moverun` off a column holding a single card is the
    // ordinary `Move` — the same collapse `moveAction` makes for a one-card run.
    test(
      "a lone card is a run of one",
      () => {
        let lone = Reducer.placeOnPile(
          {piles: game.piles->Array.map(_ => []), loose: []},
          ace(Spades),
          firstCascade,
        )
        expect(
          Command.resolveFrom(
            ~game,
            lone,
            Command.Run(Command.InSlot({role: Game.Cascade, ordinal: 1})),
          ),
        )->toEqual(Ok([ace(Spades)]))
      },
    )
  })
})

// --- Why a move bounced --------------------------------------------------------
// Two shapes of the same refusal: the phrase alone, for a caller whose line above already
// named the move (the console's two-line rejection), and the standalone sentence a
// terminal prints. The second is built from the first, so they can't drift.
describe("Command.reason", () => {
  test("the phrase has no subject and no full stop", () => {
    expect(Command.reason(Reducer.Rejected))->toBe("can't stack there")
    expect(Command.reason(Reducer.PileFull))->toBe("that pile is full")
    expect(Command.reason(Reducer.RunTooLong))->toBe(
      "that run is longer than the free cells and empty columns allow",
    )
    expect(Command.reason(Reducer.NotASpan))->toBe(
      "those cards aren't lying together at the top of one pile",
    )
  })

  // The sentence a terminal has always printed, unchanged by the split: prefixed, ended,
  // and naming the card in the two cases that read better for it.
  test("the standalone sentence still says what it always said", () => {
    let three: card = {suit: Clubs, rank: Three}
    expect(Command.describeError(Reducer.Rejected, three))->toBe("Rejected: 3C can't stack there.")
    expect(Command.describeError(Reducer.CardNotFound, three))->toBe("Rejected: 3C isn't in play.")
    expect(Command.describeError(Reducer.PileFull, three))->toBe("Rejected: that pile is full.")
    // A card refused for being *buried* is named too, and in the words `resolveWhere`
    // already refuses a buried destination with — one move, one sense of "buried".
    expect(Command.describeError(Reducer.CardBuried, three))->toBe(
      "Rejected: 3C is buried — only the card on top of a pile can be moved.",
    )
  })

  // Every error answers both ways — a phrase that reads as one, and a sentence that ends.
  test("every rejection has both shapes", () =>
    [
      Reducer.Rejected,
      Reducer.PileFull,
      Reducer.LooseNotAllowed,
      Reducer.NoSuchPile,
      Reducer.CardNotFound,
      Reducer.NotARun,
      Reducer.RunTooLong,
      Reducer.NotAColumn,
      Reducer.CardBuried,
      Reducer.NotASpan,
    ]->Array.forEach(
      err => {
        let phrase = Command.reason(err)
        expect(phrase == "")->toBe(false)
        expect(phrase->String.endsWith("."))->toBe(false)
        expect(Command.describeError(err, ace(Spades))->String.startsWith("Rejected: "))->toBe(true)
      },
    )
  )
})
