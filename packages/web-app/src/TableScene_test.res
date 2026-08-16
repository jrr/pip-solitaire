// The end-game "Finish" button (#132): it appears in the mounted board exactly
// when the position is drainable to a win by foundation moves alone
// (`Reducer.canFinish`), and is absent otherwise. Mounting the real scene into a
// jsdom container and querying for the control proves the conditional wiring end
// to end.
//
// The deferred opening deal (scheduled on the next animation frame) would reach
// `matchMedia` and `Element.animate`, neither of which jsdom implements. Stubbing
// `matchMedia` to report reduced motion makes the deal skip the fly-in animation
// entirely, so the frame — whenever it runs — stays within jsdom's support. The
// button itself is added synchronously at mount, before any frame.
%%raw(`globalThis.matchMedia = () => ({ matches: true })`)

// The opening deal itself is deferred to the next animation frame — the stage is
// detached at mount and has no layout yet — and jsdom's own frames never run
// inside a synchronous test body. Queueing the callbacks instead makes that frame
// something a test can *ask* for (`flushFrames`), which is what the tests below
// that read the laid-out board need. Tests that only assert on the chrome (the
// buttons and the overlay, all added synchronously at mount) simply never flush.
%%raw(`
  globalThis.__frames = []
  globalThis.requestAnimationFrame = (cb) => globalThis.__frames.push(cb)
`)
let flushFrames: unit => unit = %raw(`() => {
  // Splice first: a flushed callback may queue the next frame, and that one is
  // the *next* flush's business, not this one's (or the deal would recurse).
  globalThis.__frames.splice(0).forEach((cb) => cb(0))
}`)

open Vitest

@val @scope("document") external createElement: string => WebDom.element = "createElement"
@send
external querySelector: (WebDom.element, string) => Nullable.t<WebDom.element> = "querySelector"
@send external querySelectorAll: (WebDom.element, string) => {"length": int} = "querySelectorAll"
@send external click: WebDom.element => unit = "click"

// How many nodes in the mounted board match a selector.
let countOf = (container, selector) => (container->querySelectorAll(selector))["length"]

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

// A Squared pile draws every card it holds on one spot, so all but the top card
// are off screen — yet each one stays in the DOM as a `role="img"` carrying the
// card's name (`CardArt`). Without a mark saying so, a screen reader is read a
// foundation's whole history as if it were laid out on the table: forty-eight of
// the fifty-two cards on a won board that shows exactly four. Reflow marks the
// covered ones `aria-hidden`, so the page announces what it actually shows (#267).
//
// These read the *laid-out* board rather than the chrome, so each flushes the deal's
// deferred frame first (see `flushFrames` above).
describe("TableScene squared-pile occlusion (#267)", () => {
  let cards = container => container->countOf(".stacking-card")
  let hidden = container => container->countOf(".stacking-card[aria-hidden='true']")

  test("a fresh deal hides nothing — every card is in a Fanned cascade", () => {
    // FreeCell opens with all 52 in the cascades and its Squared piles (the cells
    // and foundations) empty. A fan exposes every card's edge, so nothing there is
    // occluded and nothing may be marked: Fanned piles are untouched by this.
    let container = createElement("div")
    let scene = TableScene.make(Game.freecell)
    let _teardown = scene.mount(container)
    flushFrames()
    expect(cards(container))->toBe(52)
    expect(hidden(container))->toBe(0)
  })

  test("a won board announces four cards, not fifty-two", () => {
    // Victory puts all 52 into four Squared foundations, which show their four top
    // cards and hide the rest — so 48 are out of the accessible tree.
    let game = Game.freecell
    let (won, _moved) = Reducer.finishSequence(~game, Scenario.freecellAlmostWon(game))
    let container = createElement("div")
    let scene = TableScene.make(~loadHistory=() => Some(History.make(won)), game)
    let _teardown = scene.mount(container)
    flushFrames()
    expect(cards(container))->toBe(52)
    expect(hidden(container))->toBe(48)
  })

  test(
    "the mark tracks the board: cards go quiet as they're covered, undo brings them back",
    () => {
      // Drive a real transition rather than mounting two positions: the Finish sweep
      // sends every remaining card home (collapsing to an instant reflow under the
      // reduced-motion stub above), and undo steps the whole sweep back as one.
      let game = Game.freecell
      let undo = ref(() => ())
      let container = createElement("div")
      let scene = TableScene.make(
        ~initial=Scenario.freecellFinish(game),
        ~publishUndo=u => undo := u,
        game,
      )
      let _teardown = scene.mount(container)
      flushFrames()
      // The starting position has cards home already, but nowhere near all of them —
      // so "before" is a real count that the win's 48 can't be confused with, and the
      // restored count below can't match it by both being zero.
      let before = hidden(container)
      expect(before > 0 && before < 48)->toBe(true)

      container->querySelector(".finish-button")->Nullable.toOption->Option.getOrThrow->click
      expect(hidden(container))->toBe(48)

      undo.contents()
      expect(hidden(container))->toBe(before)
    },
  )
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

// The win overlay's Share button (#264). The button is the driver's to offer: the
// board asks `available` as the overlay goes up and builds the button only if the
// answer is yes, because a deal number can outlive the board that was dealt from it
// (a resumed game's lives in storage) and can also be missing entirely (a posed or
// shared position). Mounting the real scene onto a won history and querying for the
// control proves that conditional end to end, the same way the Finish button above is
// covered.
describe("TableScene win share (#264)", () => {
  let shareButton = (container): option<WebDom.element> =>
    container->querySelector(".win-panel__button--share")->Nullable.toOption

  // A won board reached by one recorded step, so the line of play behind the victory
  // has a length worth reporting (and a bare `History.make(won)` — which has none —
  // couldn't tell a working move count from a hardcoded zero).
  let wonHistory = game => {
    let (won, _moved) = Reducer.finishSequence(~game, Scenario.freecellAlmostWon(game))
    History.record(History.make(GameState.initial(game)), won)
  }

  test("offers the button when the driver has a deal to share", () => {
    let game = Game.freecell
    let container = createElement("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(wonHistory(game)),
      ~winShare={available: () => true, share: (~moves as _) => Promise.resolve("")},
      game,
    )
    let _teardown = scene.mount(container)
    expect(shareButton(container)->Option.isSome)->toBe(true)
  })

  test("leaves it out when there's no deal number to offer", () => {
    // A `?state=` scenario or a game landed from a `#g=` link: the position is real
    // but the deal behind it isn't ours to name, so the overlay is New Game alone
    // rather than a button that would share a board nobody is looking at.
    let game = Game.freecell
    let container = createElement("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(wonHistory(game)),
      ~winShare={available: () => false, share: (~moves as _) => Promise.resolve("")},
      game,
    )
    let _teardown = scene.mount(container)
    expect(shareButton(container)->Option.isSome)->toBe(false)
  })

  test("a driver that offers no share at all still wins normally", () => {
    // The demos and the CLI-ish call sites pass no `~winShare`; the overlay they get
    // is exactly the one #121 built.
    let game = Game.freecell
    let container = createElement("div")
    let scene = TableScene.make(~loadHistory=() => Some(wonHistory(game)), game)
    let _teardown = scene.mount(container)
    expect(container->querySelector(".win-overlay")->Nullable.toOption->Option.isSome)->toBe(true)
    expect(shareButton(container)->Option.isSome)->toBe(false)
  })

  test("shares the length of the line that reached the win", () => {
    // The move count comes off the live history (`History.steps`), not the board's
    // opening state — so a win resumed with a move behind it reports that move.
    let game = Game.freecell
    let shared = ref(None)
    let container = createElement("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(wonHistory(game)),
      ~winShare={
        available: () => true,
        share: (~moves) => {
          shared := Some(moves)
          Promise.resolve("Link copied to clipboard.")
        },
      },
      game,
    )
    let _teardown = scene.mount(container)
    shareButton(container)->Option.getOrThrow->click
    expect(shared.contents)->toEqual(Some(1))
  })
})
