open Vitest
open Card

// The session layer: the thing wrapped around `Reducer.reduce` that both front
// ends now share — which game is in play, the history to undo over, the tally and the
// clock beside it, the post-move auto-collect, and running a `Command.t` against all of
// it.
//
// What's pinned here is the part that *wasn't* shared before, and so had nowhere to be
// tested: that a session counts its own moves, times its own win, and hands a caller
// enough to draw the result. The command-by-command behaviour of the board verbs
// themselves is exercised through the CLI's transcripts (`Cli_test`), which is where it
// has always been and where it reads as a session rather than as a call.

// A clock that ticks a second per reading, so a test can say what a game *took* without
// depending on how fast it ran. `dealt` reads it once, so the first move lands at 1s.
let ticker = () => {
  let now = ref(0.)
  () => {
    now := now.contents +. 1000.
    now.contents
  }
}

// A clock stopped at zero: for the tests that don't care what time it is, but still
// have to hand one over.
let stopped = () => 0.

let freecell = Game.freecell

let open_ = (~clock=stopped, ~options=Options.default, state) =>
  Session.open_(~clock, ~options, ~seed=freecell.seed, freecell, state)

let fresh = (~clock=stopped, ~options=Options.default, ()) =>
  open_(~clock, ~options, GameState.initial(freecell))

// A board that `finish` alone can drain to a win.
let almostWon = (~clock=stopped, ()) => open_(~clock, Scenario.freecellAlmostWon(freecell))

// The deepest card of the first cascade: buried under its whole column, so nothing can
// lift it.
let buried = (s: Session.t): card =>
  switch GameState.cardsInPile(Session.present(s), 8)->Array.get(0) {
  | Some(card) => card
  | None => {suit: Spades, rank: Ace} // unreachable: an opening cascade is never empty
  }

// A board with a card ready for its foundation, and that card — the `sendhome` position
// the CLI's own transcripts play.
let threeOfSpades: card = {suit: Spades, rank: Three}

let sentHome = () =>
  Session.step(
    ~clock=stopped,
    open_(Scenario.freecellSendHome(freecell)),
    Command.Home({card: threeOfSpades}),
  )

describe("Session tallies", () => {
  test("a fresh session has played nothing", () => {
    let s = fresh()
    expect(s.stats)->toEqual(Stats.zero)
    expect(Session.canUndo(s))->toBe(false)
  })

  test("an accepted move counts as one move and one undoable step", () => {
    let (s, outcome) = sentHome()
    // The card the command named comes back, so a caller with an animation to run knows
    // what travelled — and anything auto-collect swept up behind it rides along.
    switch outcome.change {
    | Session.Settled({moved}) => expect(moved)->toEqual([threeOfSpades])
    | _ => expect("a settled move")->toBe("something else")
    }
    expect(s.stats.moves)->toBe(1)
    expect(Session.canUndo(s))->toBe(true)
  })

  test("a rejected move counts nothing and records no step", () => {
    let s = fresh()
    let (after, outcome) = Session.step(
      ~clock=stopped,
      s,
      // The card at the *foot* of a cascade has the whole column resting on it, so the
      // reducer refuses to lift it however welcoming the destination.
      Command.Dispatch(Reducer.Move({card: buried(s), to: Reducer.ToPile(0)})),
    )
    switch outcome.change {
    | Session.Rejected(_) => ()
    | _ => expect("a rejection")->toBe("something else")
    }
    expect(after.stats)->toEqual(Stats.zero)
    expect(Session.canUndo(after))->toBe(false)
  })

  test("an undo counts as an undo and never takes the move back", () => {
    let (played, _) = sentHome()
    let (undone, _) = Session.undo(~clock=stopped, played)
    expect(undone.stats.moves)->toBe(1) // the move was still made
    expect(undone.stats.undos)->toBe(1)
    // …and a redo puts it back on the board, so it counts as a move again — the rule
    // that stops undo-then-redo being a way to play for free.
    let (redone, _) = Session.redo(~clock=stopped, undone)
    expect(redone.stats.moves)->toBe(2)
    expect(redone.stats.undos)->toBe(1)
  })

  test("a lawful no-op is neither counted nor recorded", () => {
    // A `MoveColumn` from a column to itself reduces to `Ok` with the board untouched.
    let (s, outcome) = Session.step(
      ~clock=stopped,
      fresh(),
      Command.Dispatch(Reducer.MoveColumn({from: 8, to: 8})),
    )
    expect(s.stats)->toEqual(Stats.zero)
    expect(Session.canUndo(s))->toBe(false)
    // Accepted, though — so a caller redraws. Nothing moved, so nothing flies.
    switch outcome.change {
    | Session.Settled({moved, collected}) =>
      expect(Array.length(moved))->toBe(0)
      expect(Array.length(collected))->toBe(0)
    | _ => expect("a settled no-op")->toBe("something else")
    }
  })
})

describe("Session clock", () => {
  test("a game that isn't won has no time to report", () => {
    expect(Timing.summary(fresh().timing))->toEqual(None)
  })

  test("winning stamps the clock, and the time covers the whole game", () => {
    // One clock for the whole game: dealt at 1s, and the winning `finish` stamps at 2s.
    let clock = ticker()
    let (won, _) = Session.step(~clock, almostWon(~clock, ()), Command.Finish)
    expect(Session.hasWon(won))->toBe(true)
    expect(Timing.summary(won.timing))->toEqual(Some("0:01"))
  })

  test("stepping back out of a victory un-stamps it, and winning again stamps afresh", () => {
    let clock = ticker()
    let (won, _) = Session.step(~clock, almostWon(~clock, ()), Command.Finish)
    let (stepped, _) = Session.undo(~clock, won)
    expect(Session.hasWon(stepped))->toBe(false)
    expect(Timing.summary(stepped.timing))->toEqual(None)
    let (again, _) = Session.redo(~clock, stepped)
    expect(Session.hasWon(again))->toBe(true)
    // Dealt at 1s, won again at 3s: the detour is inside the time, the same way undoing
    // never gives a move back.
    expect(Timing.summary(again.timing))->toEqual(Some("0:02"))
  })

  test("a resumed victory keeps the moment it was won", () => {
    let clock = ticker()
    let (won, _) = Session.step(~clock, almostWon(~clock, ()), Command.Finish)
    let reopened = Session.restore(
      ~seed=freecell.seed,
      ~options=Options.default,
      freecell,
      Session.save(won),
    )
    expect(Timing.summary(reopened.timing))->toEqual(Timing.summary(won.timing))
  })
})

describe("Session house rules", () => {
  test("column reordering off refuses before the reducer sees it", () => {
    let off = Options.apply(Options.default, ~setting=Options.ColumnReorder, ~on=false)
    let (s, outcome) = Session.step(
      ~clock=stopped,
      fresh(~options=off, ()),
      Command.Dispatch(Reducer.MoveColumn({from: 8, to: 9})),
    )
    switch outcome.change {
    | Session.Blocked({reason}) => expect(reason)->toBe(Session.columnReorderOff)
    | _ => expect("blocked")->toBe("something else")
    }
    expect(Session.canUndo(s))->toBe(false)
  })

  test("auto-collect off leaves the reducer's result exactly as it came", () => {
    let off = Options.apply(Options.default, ~setting=Options.AutoCollect, ~on=false)
    let state = Scenario.freecellSendHome(freecell)
    let (settled, swept) = Session.settle(~game=freecell, ~options=off, state)
    expect(GameState.equal(settled, state))->toBe(true)
    expect(Array.length(swept))->toBe(0)
  })

  test("safe auto-collect steps aside once the board is finishable", () => {
    // On the finishable tail, settling must not auto-collect — even with the option on
    // (its default) — leaving the board for the `finish` sweep to own.
    let state = Scenario.freecellFinish(freecell)
    let (settled, swept) = Session.settle(~game=freecell, ~options=Options.default, state)
    expect(settled)->toEqual(state)
    expect(Array.length(swept))->toBe(0)

    // Contrast: on a *non*-finishable board with a safe card, settling still collects it
    // — showing the finish guard, not a disabled option, is what held the sweep back
    // above. A lone Ace atop the first cascade, foundations empty, is safe and homeable
    // but nowhere near a win.
    let lone = {
      GameState.piles: freecell.piles->Array.mapWithIndex(
        (_, i) => i == 8 ? [{suit: Spades, rank: Ace}] : [],
      ),
      loose: [],
    }
    let (collected, sent) = Session.settle(~game=freecell, ~options=Options.default, lone)
    expect(GameState.equal(collected, lone))->toBe(false)
    expect(sent)->toEqual([{suit: Spades, rank: Ace}])
  })

  test("a restart is the same board under the same rules", () => {
    let off = Options.apply(Options.default, ~setting=Options.AutoCollect, ~on=false)
    let (again, outcome) = Session.redeal(~clock=stopped, fresh(~options=off, ()))
    expect(outcome.change)->toEqual(Session.Dealt)
    // Restarting a game isn't changing the rules you're playing it under.
    expect(again.options)->toEqual(off)
    expect(Session.canUndo(again))->toBe(false)
    expect(GameState.equal(Session.present(again), GameState.initial(freecell)))->toBe(true)
  })
})

describe("Session autoplay", () => {
  test("the trail carries a whole session per move, so a caller can stop anywhere", () => {
    // The point of the trail: a front end that animates each move adopts these one at a
    // time and simply stops adopting when the player interrupts. What it stops on has to
    // be a real session — a real position, with a real history and a real tally behind
    // it — rather than something to be unwound.
    let (played, outcome) = Session.step(
      ~clock=stopped,
      open_(Scenario.freecellFinish(freecell)),
      Command.Autoplay,
    )
    switch outcome.change {
    | Session.Played({trail, swept}) =>
      // This board is already finishable, so the solver plans nothing and the sweep is
      // the whole of it.
      expect(Array.length(trail))->toBe(0)
      expect(Array.length(swept) > 0)->toBe(true)
    | _ => expect("a played line")->toBe("something else")
    }
    expect(Session.hasWon(played))->toBe(true)
    // The reach is counted once, however many moves it played.
    expect(played.stats.autoplays)->toBe(1)
    expect(Stats.usedAutoplay(played.stats))->toBe(true)
  })

  testWithin(
    "each step in the trail is one further undoable move",
    () => {
      let (played, outcome) = Session.step(~clock=stopped, fresh(), Command.Autoplay)
      switch outcome.change {
      | Session.Played({trail}) =>
        expect(Array.length(trail) > 0)->toBe(true)
        // Every entry's session is one step deeper than the last, so undo walks back
        // through the solver's line a move at a time rather than teleporting past it.
        trail->Array.forEachWithIndex((step: Session.played, i) =>
          expect(History.steps(step.session.history))->toBe(i + 1)
        )
      | _ => expect("a played line")->toBe("something else")
      }
      expect(Session.hasWon(played))->toBe(true)
    },
    ~timeout=120_000,
  )
})

describe("Session save envelope", () => {
  test("a save round-trips the history, the tally and the clock", () => {
    let (played, _) = sentHome()
    let reopened = Session.restore(
      ~seed=freecell.seed,
      ~options=Options.default,
      freecell,
      Session.save(played),
    )
    expect(reopened.stats)->toEqual(played.stats)
    expect(reopened.timing)->toEqual(played.timing)
    expect(GameState.equal(Session.present(reopened), Session.present(played)))->toBe(true)
  })
})
