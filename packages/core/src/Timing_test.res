open Vitest

// The game clock (#302). Two stamps and a subtraction, so what's worth pinning isn't
// the arithmetic but the three decisions around it: a win is stamped *once* (or a
// resumed victory would re-time itself on every reload), stepping back out of a
// victory un-stamps it, and a pair of stamps that can't be a real game reports
// nothing rather than nonsense.
describe("Timing", () => {
  let noon = 1_700_000_000_000.

  test("a game nobody timed has nothing to report", () => {
    expect(Timing.unknown)->toEqual({Timing.dealtAt: None, wonAt: None})
    expect(Timing.elapsed(Timing.unknown))->toEqual(None)
    expect(Timing.summary(Timing.unknown))->toEqual(None)
  })

  test("a game still being played has no time yet", () => {
    // The deal is stamped the moment the board is built, but a game only *takes* a
    // length once it's over — until then there's no second stamp to subtract.
    expect(Timing.elapsed(Timing.dealt(~at=noon)))->toEqual(None)
  })

  test("winning stamps the far end, and the time is the gap between them", () => {
    let t = Timing.dealt(~at=noon)->Timing.won(~at=noon +. 247_000.)
    expect(Timing.elapsed(t))->toEqual(Some(247_000.))
    expect(Timing.summary(t))->toEqual(Some("4:07"))
  })

  test("a win is stamped once and stays stamped", () => {
    // The property the resumed victory (#177) depends on: reopening a won board raises
    // its overlay again, and if that re-stamped, "how long the game took" would drift
    // into "how long ago you played it" — growing every time you came back to it.
    let won = Timing.dealt(~at=noon)->Timing.won(~at=noon +. 60_000.)
    let reopened = won->Timing.won(~at=noon +. 86_400_000.)
    expect(reopened)->toEqual(won)
    expect(Timing.summary(reopened))->toEqual(Some("1:00"))
  })

  test("stepping back out of a victory un-stamps it, and winning again re-times", () => {
    // Undo out of a win (#85): the board isn't won, so it has no won-at. Playing on and
    // winning again times the *whole* game, detour included — the same stance the tally
    // takes, where undoing never gives a move back.
    let t = Timing.dealt(~at=noon)->Timing.won(~at=noon +. 60_000.)->Timing.unwon
    expect(Timing.elapsed(t))->toEqual(None)
    expect(Timing.elapsed(t->Timing.won(~at=noon +. 90_000.)))->toEqual(Some(90_000.))
  })

  test("a win that reads as earlier than the deal reports nothing", () => {
    // Not a game that took negative time: two stamps from two different clocks, which
    // is what a `?state=` link shared between devices can carry. "-3:07" would be
    // worse than saying nothing.
    let crossed: Timing.t = {dealtAt: Some(noon), wonAt: Some(noon -. 1000.)}
    expect(Timing.elapsed(crossed))->toEqual(None)
    expect(Timing.summary(crossed))->toEqual(None)
  })

  // How a duration reads: minutes and seconds, hours only once there are any, and
  // seconds floored the way a stopwatch shows them.
  describe("the label", () => {
    test(
      "reads as a clock, zero-padded below the leading field",
      () => {
        expect(Timing.label(0.))->toBe("0:00")
        expect(Timing.label(7_000.))->toBe("0:07")
        expect(Timing.label(70_000.))->toBe("1:10")
        expect(Timing.label(247_000.))->toBe("4:07")
        expect(Timing.label(599_000.))->toBe("9:59")
        expect(Timing.label(3_600_000.))->toBe("1:00:00")
        expect(Timing.label(3_753_000.))->toBe("1:02:33")
      },
    )

    test(
      "floors the seconds rather than rounding them up",
      () => {
        // A game 3.9 seconds old has not been going for four seconds, and a game one
        // millisecond short of the minute hasn't turned it.
        expect(Timing.label(3_900.))->toBe("0:03")
        expect(Timing.label(59_999.))->toBe("0:59")
      },
    )
  })
})
