// The dot's words for each report, which are all a tester reading the corner has to go on.
open Vitest

describe("ThinkingDot", () => {
  test("a dead worker and a Solve in flight each read as themselves, not as waiting", () => {
    let waiting = ThinkingDot.caption(Thinker.Idle)
    let died = Thinker.Died({why: "raised an error"})
    expect(ThinkingDot.caption(died))->toBe("worker died · reload")
    expect(ThinkingDot.caption(Thinker.Asked))->toBe("solving · asked")
    expect(ThinkingDot.look(died) == ThinkingDot.look(Thinker.Idle))->toBe(false)
    expect(ThinkingDot.look(Thinker.Asked) == ThinkingDot.look(Thinker.Idle))->toBe(false)
    expect(waiting)->toBe("waiting")
  })

  test("a dead worker's line says why, and that only a reload brings thinking back", () => {
    expect(ThinkingDot.sentence(Thinker.Died({why: "raised an error"})))->toEqual(
      Some(
        "think ahead: off until a reload — the solver's worker raised an error and was given up on",
      ),
    )
  })
})
