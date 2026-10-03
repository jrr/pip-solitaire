// What `Thinker` reports once its worker has been given up on. jsdom has no `Worker`, so
// the worker here is a stand-in that can only be terminated, which is all `abandon` asks
// of one; and nothing is ever armed, so each report below is the only one its call makes.
open Vitest

let stub: Thinker.worker = %raw(`({ terminate() {} })`)

describe("Thinker, once its worker is given up on", () => {
  let heard = []
  Thinker.reports := (report => heard->Array.push(report))
  let last = () => heard->Array.last
  let game = Game.freecellDeal(~seed=1)
  let opening = GameState.initial(game)

  test("says so at once, with why, rather than leaving the last think's report up", () => {
    Thinker.follow(~game, ~state=opening)
    expect(last())->toEqual(Some(Thinker.Idle))
    Thinker.abandon(stub, ~why="said nothing for 10 s")
    expect(last())->toEqual(Some(Thinker.Died({why: "said nothing for 10 s"})))
  })

  test("says it again on every board after, where it would otherwise be waiting", () => {
    let moved =
      Position.ofGameState(~game, opening)
      ->Option.flatMap(position => Position.legalMoves(position)->Array.get(0))
      ->Option.flatMap(move => Position.toAction(~game, opening, move))
      ->Option.flatMap(
        action =>
          switch Reducer.reduce(~game, opening, action) {
          | Ok(state) => Some(state)
          | Error(_) => None
          },
      )
      ->Option.getOrThrow
    Thinker.follow(~game, ~state=moved)
    expect(last())->toEqual(Some(Thinker.Died({why: "said nothing for 10 s"})))
    Thinker.leave()
    expect(last())->toEqual(Some(Thinker.Died({why: "said nothing for 10 s"})))
  })
})
