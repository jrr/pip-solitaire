// What `Thinker` remembers of an answer: the line from the board on the table, which a
// Hint shows without asking again. jsdom has no `Worker`, so every question here is
// answered on the spot (`Thinker.here`), which is the same answer kept the same way.
open Vitest

describe("Thinker's known line", () => {
  // A deal the solver answers in milliseconds.
  let game = Game.freecellDeal(~seed=24680)
  let opening = GameState.initial(game)

  let line = () => {
    Thinker.follow(~game, ~state=opening)
    let found = ref(None)
    Thinker.think(~game, ~state=opening, ~patience=None, ~onAnswer=answer => found := Some(answer))
    switch found.contents {
    | Some(Solver.Played({steps})) => steps
    | _ => throw(Failure("no line for the deal"))
    }
  }

  test("nothing is known from a board nobody has asked about", () => {
    Thinker.follow(~game, ~state=opening)
    expect(Thinker.known(~game, ~state=opening))->toEqual(None)
  })

  test("an answer about the board on the table is known from it afterwards", () => {
    let steps = line()
    expect(Thinker.known(~game, ~state=opening)->Option.map(Array.length))->toEqual(
      Some(Array.length(steps)),
    )
  })

  test("a move along the line keeps the rest of it; a move off it forgets it", () => {
    let steps = line()
    let first = steps->Array.getUnsafe(0)
    Thinker.follow(~game, ~state=first.state)
    expect(Thinker.known(~game, ~state=first.state)->Option.map(Array.length))->toEqual(
      Some(Array.length(steps) - 1),
    )

    // Back to the opening is not the next step of what is left, so nothing is known.
    Thinker.follow(~game, ~state=opening)
    expect(Thinker.known(~game, ~state=opening))->toEqual(None)
  })

  test("a board that left the table takes its line with it", () => {
    line()->ignore
    Thinker.leave()
    expect(Thinker.known(~game, ~state=opening))->toEqual(None)
  })
})
