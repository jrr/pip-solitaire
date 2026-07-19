// The end-game "Finish" button (#132): it appears in the mounted board exactly
// when the position is drainable to a win by foundation moves alone
// (`Reducer.canFinish`), and is absent otherwise. Mounting the real scene into a
// jsdom container and querying for the control proves the conditional wiring end
// to end.
//
// The deferred opening deal (scheduled on the next animation frame) would reach
// `matchMedia` and `Element.animate`, neither of which jsdom implements. Stubbing
// `matchMedia` to report reduced motion makes the deal skip the fly-in animation
// entirely, so the frame — if it fires during the test — stays within jsdom's
// support. The button itself is added synchronously at mount, before any frame.
%%raw(`globalThis.matchMedia = () => ({ matches: true })`)

open Vitest

@val @scope("document") external createElement: string => WebDom.element = "createElement"
@send
external querySelector: (WebDom.element, string) => Nullable.t<WebDom.element> = "querySelector"

let hasFinishButton = (container): bool =>
  container->querySelector(".finish-button")->Nullable.toOption->Option.isSome

describe("TableScene Finish button (#132)", () => {
  test("appears when the opening position is drainable to a win", () => {
    // The trapped-tail scenario is finishable by foundation moves alone, so the
    // button shows the moment the board mounts.
    let container = createElement("div")
    let scene = TableScene.make(~initial=Scenario.freecellFinish(Game.freecell), Game.freecell)
    let _teardown = scene.mount(container)
    expect(hasFinishButton(container))->toBe(true)
  })

  test("is absent on a fresh deal that isn't drainable yet", () => {
    // A fresh FreeCell deal needs plenty of tableau play first — no finish on offer.
    let container = createElement("div")
    let scene = TableScene.make(Game.freecell)
    let _teardown = scene.mount(container)
    expect(hasFinishButton(container))->toBe(false)
  })
})
