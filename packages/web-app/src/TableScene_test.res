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

// Save-and-resume (#177): the board hands its whole undo/redo history to the
// `~persist` sink as it changes, and re-seeds from a `~loadHistory` on the way back —
// so a reload lands on the same board with the same Undo stack. These prove the
// scene-level wiring; the byte-level round-trip is `SaveState_test`, and the
// storage edge is `SavedGame_test`.
describe("TableScene save/resume (#177)", () => {
  let hasWinOverlay = (container): bool =>
    container->querySelector(".win-overlay")->Nullable.toOption->Option.isSome

  test("persists the opening board so a plain reload can resume it", () => {
    // With a `~persist` sink wired, the opening deal saves itself straight away, so a
    // reload before any move still resumes this exact board rather than dealing anew.
    let saved = ref(None)
    let container = createElement("div")
    let scene = TableScene.make(~persist=h => saved := Some(h), Game.freecell)
    let _teardown = scene.mount(container)
    expect(saved.contents->Option.isSome)->toBe(true)
  })

  test("a resumed game already won comes back to the won board", () => {
    // Drain an almost-won board to a real win, then resume from that saved state: the
    // board opens with the win overlay already up (#177's "come back to the won board").
    let game = Game.freecell
    let (won, _moved) = Reducer.finishSequence(~game, Scenario.freecellAlmostWon(game))
    expect(GameState.hasWon(game, won))->toBe(true) // the setup really is a win
    let container = createElement("div")
    let scene = TableScene.make(~loadHistory=() => Some(History.make(won)), game)
    let _teardown = scene.mount(container)
    expect(hasWinOverlay(container))->toBe(true)
  })

  test("an ordinary resumed game opens without a win overlay", () => {
    // A mid-game saved position is not won, so no overlay — the board is just playable.
    let game = Game.freecell
    let container = createElement("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(History.make(GameState.initial(game))),
      game,
    )
    let _teardown = scene.mount(container)
    expect(hasWinOverlay(container))->toBe(false)
  })

  test("a resumed game with moves behind it reports it can undo on opening", () => {
    // The board announces undo availability through `~onHistory` as it mounts; a
    // resumed stack that already has a past must report `true` on that opening call,
    // or the top bar's Undo button opens disabled with moves still to walk back — the
    // "undo doesn't work after resuming" regression. `Main` reads exactly this opening
    // report to seed the model's `canUndo`.
    let game = Game.freecell
    let initial = GameState.initial(game)
    // A two-state history: present reached from a prior state, so `canUndo` is true.
    let resumed = History.record(History.make(initial), initial)
    let lastCanUndo = ref(None)
    let container = createElement("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(resumed),
      ~onHistory=canUndo => lastCanUndo := Some(canUndo),
      game,
    )
    let _teardown = scene.mount(container)
    expect(lastCanUndo.contents->Option.getOr(false))->toBe(true)
  })
})

// A scene can be mounted more than once — the switcher re-mounts it on a scene
// change — and each mount must open the game as it stands *now*, from the save as
// it currently reads. Reading the save once, when the scene was built, makes every
// later mount restore a page-load snapshot over the board actually being played;
// when that snapshot is a resumed victory, the finished game (and its win overlay)
// comes back over a game the player never won.
//
// `saved` here stands in for `localStorage`: `~loadHistory` reads it and `~persist`
// writes it, the same round trip `SavedGame` makes in the app.
describe("TableScene re-mount", () => {
  let hasWinOverlay = (container): bool =>
    container->querySelector(".win-overlay")->Nullable.toOption->Option.isSome

  test("a second mount opens the live board, not the one saved at build time", () => {
    let game = Game.freecell
    let (won, _moved) = Reducer.finishSequence(~game, Scenario.freecellAlmostWon(game))
    let saved = ref(Some(History.make(won)))
    let container = createElement("div")
    let newGame = ref(None)
    let scene = TableScene.make(
      ~loadHistory=() => saved.contents,
      ~persist=h => saved := Some(h),
      ~newDeal=() => Game.freecellDeal(~seed=7),
      ~publishNewGame=hook => newGame := Some(hook),
      game,
    )
    let _teardown = scene.mount(container)
    // The resumed victory, as #177 intends.
    expect(hasWinOverlay(container))->toBe(true)
    // New Game deals a fresh board: the win is over and done with, and the fresh
    // board is what's saved from here on.
    (newGame.contents->Option.getOrThrow)()
    expect(hasWinOverlay(container))->toBe(false)
    // Mount the same scene again (a scene change away and back). The board that
    // comes back must be the one that was being played, not the finished game that
    // was saved when the scene was built.
    WebDom.clear(container)
    let _remounted = scene.mount(container)
    expect(hasWinOverlay(container))->toBe(false)
  })
})
