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

// An autoplay run starts on the tick *after* the command that asked for it, so the
// console's reply heads the play-by-play instead of landing a move down it (see
// `TableScene`'s `autoplay`). That's the one thing in this scene a synchronous test
// body can't see the end of, so the tests that ask for one wait a tick.
//
// A real timer here rather than a queued stub like `requestAnimationFrame` above:
// `setTimeout` is the test runner's own too, and swapping it out from under vitest
// costs more than the tick these tests can simply await.
@val external setTimeout: (unit => unit, int) => int = "setTimeout"
let nextTick = (): promise<unit> =>
  Promise.make((resolve, _) => setTimeout(() => resolve(), 0)->ignore)

open Vitest
open TestDom

// How many nodes in the mounted board match a selector.
let countOf = (container, selector) => container->findAll(selector)->Array.length

// The board's published surface (#300), as the tests below take hold of it. The scene
// hands the whole thing over as one `TableScene.controls` record when it mounts
// (`~publish`), so a test that wants to press Undo or type a command captures the
// record and reads the action off it — where it used to name a `~publishUndo` or
// `~publishConsole` callback apiece.
//
// Read through this rather than off a saved field, because these actions outlive a
// *build*: a New Game tears the board down and builds another, and the record goes on
// driving whichever board is now on the table. `getOrThrow` is the assertion that the
// scene published at all, which every card table does on mount.
let live = (board: ref<option<TableScene.controls>>) => board.contents->Option.getOrThrow

let hasFinishButton = (container): bool => container->find(".finish-button")->Option.isSome

describe("TableScene Finish button (#132)", () => {
  test("appears when the opening position is drainable to a win", () => {
    // The trapped-tail scenario is finishable by foundation moves alone, so the
    // button shows the moment the board mounts.
    let container = host("div")
    let scene = TableScene.make(~initial=Scenario.freecellFinish(Game.freecell), Game.freecell)
    let _teardown = scene.mount(container)
    expect(hasFinishButton(container))->toBe(true)
  })

  test("is absent on a fresh deal that isn't drainable yet", () => {
    // A fresh FreeCell deal needs plenty of tableau play first — no finish on offer.
    let container = host("div")
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
    let container = host("div")
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
    let container = host("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(SaveState.ofHistory(History.make(won))),
      game,
    )
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
      let board = ref(None)
      let container = host("div")
      let scene = TableScene.make(
        ~initial=Scenario.freecellFinish(game),
        ~publish=published => board := Some(published),
        game,
      )
      let _teardown = scene.mount(container)
      flushFrames()
      // The starting position has cards home already, but nowhere near all of them —
      // so "before" is a real count that the win's 48 can't be confused with, and the
      // restored count below can't match it by both being zero.
      let before = hidden(container)
      expect(before > 0 && before < 48)->toBe(true)

      container->find(".finish-button")->Option.getOrThrow->click
      expect(hidden(container))->toBe(48)

      live(board).undo()
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
  let hasWinOverlay = (container): bool => container->find(".win-overlay")->Option.isSome

  test("persists the opening board so a plain reload can resume it", () => {
    // With a `~persist` sink wired, the opening deal saves itself straight away, so a
    // reload before any move still resumes this exact board rather than dealing anew.
    let saved = ref(None)
    let container = host("div")
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
    let container = host("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(SaveState.ofHistory(History.make(won))),
      game,
    )
    let _teardown = scene.mount(container)
    expect(hasWinOverlay(container))->toBe(true)
  })

  test("an ordinary resumed game opens without a win overlay", () => {
    // A mid-game saved position is not won, so no overlay — the board is just playable.
    let game = Game.freecell
    let container = host("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(SaveState.ofHistory(History.make(GameState.initial(game)))),
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
    let resumed = SaveState.ofHistory(History.record(History.make(initial), initial))
    let lastCanUndo = ref(None)
    let container = host("div")
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
  let hasWinOverlay = (container): bool => container->find(".win-overlay")->Option.isSome

  test("a second mount opens the live board, not the one saved at build time", () => {
    let game = Game.freecell
    let (won, _moved) = Reducer.finishSequence(~game, Scenario.freecellAlmostWon(game))
    let saved = ref(Some(SaveState.ofHistory(History.make(won))))
    let container = host("div")
    let board = ref(None)
    let scene = TableScene.make(
      ~loadHistory=() => saved.contents,
      ~persist=h => saved := Some(h),
      ~newDeal=() => Game.freecellDeal(~seed=7),
      ~publish=published => board := Some(published),
      game,
    )
    let _teardown = scene.mount(container)
    // The resumed victory, as #177 intends.
    expect(hasWinOverlay(container))->toBe(true)
    // New Game deals a fresh board: the win is over and done with, and the fresh
    // board is what's saved from here on.
    (live(board).newGame->Option.getOrThrow)()
    expect(hasWinOverlay(container))->toBe(false)
    // Mount the same scene again (a scene change away and back). The board that
    // comes back must be the one that was being played, not the finished game that
    // was saved when the scene was built.
    WebDom.clear(container)
    let _remounted = scene.mount(container)
    expect(hasWinOverlay(container))->toBe(false)
  })
})

// The board's published surface (#300). The scene hands the chrome one
// `TableScene.controls` record when it mounts, and never another — so the record has to
// go on meaning the board *now on the table*, across every re-deal that tears one board
// down and builds the next. That's the invariant the whole hand-over rests on: get it
// wrong and the chrome drives a board that no longer exists, which is exactly the
// stale-closure bug the eleven separate hooks made possible.
//
// It can't be seen from the DOM — a stale action reaches a torn-down board's `session`,
// and the give-away is what that board *saves*. So these read the `~persist` sink, the
// same way the tally tests below do.
describe("TableScene published controls (#300)", () => {
  let tallyOf = (saved: ref<option<SaveState.t>>) =>
    saved.contents->Option.map((s: SaveState.t) => (s.stats.moves, s.stats.undos))

  test(
    "the record taken at mount drives the board after a re-deal, not the one it replaced",
    () => {
      let game = Game.freecell
      let saved = ref(None)
      let board = ref(None)
      let container = host("div")
      let scene = TableScene.make(
        // A finishable opening, so one press gives the first board a move to be stepped
        // back over — something a stale `undo` would find, and the fresh deal won't.
        ~initial=Scenario.freecellFinish(game),
        ~persist=s => saved := Some(s),
        ~newDeal=() => Game.freecellDeal(~seed=7),
        ~publish=published => board := Some(published),
        game,
      )
      let _teardown = scene.mount(container)
      container->find(".finish-button")->Option.getOrThrow->click
      expect(tallyOf(saved))->toEqual(Some((1, 0)))

      // New Game tears that board down and builds another: a fresh deal, clean history,
      // tally back to zero — and it's the fresh board that saves from here on.
      (live(board).newGame->Option.getOrThrow)()
      expect(tallyOf(saved))->toEqual(Some((0, 0)))

      // The record was handed over once, before either board existed. Undo through it now
      // has nothing behind it, because the board on the table is a fresh deal. Were it
      // still the *first* board's undo, it would step that board's finish back and save
      // (1, 1) over the deal actually showing.
      live(board).undo()
      expect(tallyOf(saved))->toEqual(Some((0, 0)))

      // …and the same for a typed command, which reaches the board through the same
      // record: `redo` on the fresh deal has nothing ahead of it either.
      live(board).runCommand(Command.Redo)->ignore
      expect(tallyOf(saved))->toEqual(Some((0, 0)))
    },
  )

  test("`loadDeal` opens the number it's given, laid out by the game on the table", () => {
    // The console's `deal <n>` (#273). Turning the number into a board is the *game's*
    // job now (`Game.t.deal`, #349) rather than the driver's: the chrome hands over a
    // number and the board deals its own game from it, so nothing out there has to know
    // that a deal number is a seeded FreeCell shuffle.
    let saved = ref(None)
    let board = ref(None)
    let container = host("div")
    let scene = TableScene.make(
      ~persist=s => saved := Some(s),
      ~newDeal=() => Game.freecellDeal(~seed=7),
      ~publish=published => board := Some(published),
      Game.freecell,
    )
    let _teardown = scene.mount(container)
    (live(board).loadDeal->Option.getOrThrow)(24680)
    // The board on the table is deal 24680 of the game the scene plays, card for card.
    let onTable: SaveState.t = saved.contents->Option.getOrThrow
    let present = History.present(onTable.history)
    expect(present.piles)->toEqual(GameState.initial(Game.freecellDeal(~seed=24680)).piles)
  })

  test("a board mounted without a re-deal offers neither re-deal", () => {
    // `newGame` and `loadDeal` both open a board named by a seed, which only a scene
    // handed a `~newDeal` can produce — the driver's say on whether this board may be
    // re-dealt at all, even for a game that knows how to deal another of itself.
    // Without one, answering `None` is what lets the menu's New Game and the console's
    // `deal <n>` say so rather than silently doing nothing.
    let board = ref(None)
    let container = host("div")
    let scene = TableScene.make(~publish=published => board := Some(published), Game.freecell)
    let _teardown = scene.mount(container)
    expect(live(board).newGame->Option.isNone)->toBe(true)
    expect(live(board).loadDeal->Option.isNone)->toBe(true)
    // Restart is offered by every card table, though — it restarts to its own deal.
    live(board).restart()
    expect(countOf(container, ".stacking-card") > 0)->toBe(true)
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
    container->find(".win-panel__button--share")

  // A won board resumed with a tally already on it — three moves and one undo — so a
  // share that reported a hardcoded zero, or re-derived the count from the one-step
  // history, would fail rather than pass by looking plausible.
  // `~autoplays` is the #291 half: a game the solver had a hand in is a game whose
  // victory isn't the player's to pass on, and the tally is where that fact lives.
  let wonHistory = (~autoplays=0, game) => {
    let (won, _moved) = Reducer.finishSequence(~game, Scenario.freecellAlmostWon(game))
    let history = History.record(History.make(GameState.initial(game)), won)
    {SaveState.history, stats: {moves: 3, undos: 1, autoplays}, timing: Timing.unknown}
  }

  test("offers the button when the driver has a deal to share", () => {
    let game = Game.freecell
    let container = host("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(wonHistory(game)),
      ~winShare={available: () => true, share: (~moves as _, ~undos as _) => Promise.resolve("")},
      game,
    )
    let _teardown = scene.mount(container)
    expect(shareButton(container)->Option.isSome)->toBe(true)
  })

  test("leaves it out when there's no deal number to offer", () => {
    // A `?state=` scenario or a game landed from a `#saved=` link: the position is real
    // but the deal behind it isn't ours to name, so the overlay is New Game alone
    // rather than a button that would share a board nobody is looking at.
    let game = Game.freecell
    let container = host("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(wonHistory(game)),
      ~winShare={available: () => false, share: (~moves as _, ~undos as _) => Promise.resolve("")},
      game,
    )
    let _teardown = scene.mount(container)
    expect(shareButton(container)->Option.isSome)->toBe(false)
  })

  test("withholds it from a game the solver played (#291)", () => {
    // The driver has a deal and would happily share it; the *game* is the problem. A
    // win reached by typing `autoplay` isn't a claim about how you played, so the
    // button is never built — and the fact that it was autoplayed rides in on the
    // saved tally, which is exactly how it survives a reload and every undo.
    let game = Game.freecell
    let container = host("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(wonHistory(~autoplays=1, game)),
      ~winShare={available: () => true, share: (~moves as _, ~undos as _) => Promise.resolve("")},
      game,
    )
    let _teardown = scene.mount(container)
    expect(shareButton(container)->Option.isSome)->toBe(false)
    // …and the overlay is otherwise the ordinary one: the game was still won.
    expect(container->find(".win-overlay")->Option.isSome)->toBe(true)
  })

  test("a driver that offers no share at all still wins normally", () => {
    // The demos and the CLI-ish call sites pass no `~winShare`; the overlay they get
    // is exactly the one #121 built.
    let game = Game.freecell
    let container = host("div")
    let scene = TableScene.make(~loadHistory=() => Some(wonHistory(game)), game)
    let _teardown = scene.mount(container)
    expect(container->find(".win-overlay")->Option.isSome)->toBe(true)
    expect(shareButton(container)->Option.isSome)->toBe(false)
  })

  test("shares the tally the won game carried (#289)", () => {
    // The counts come off the live game's `Stats`, not the board's opening state and
    // not the shape of its history — so a win resumed mid-tally reports the numbers
    // the player actually earned, undos included.
    let game = Game.freecell
    let shared = ref(None)
    let container = host("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(wonHistory(game)),
      ~winShare={
        available: () => true,
        share: (~moves, ~undos) => {
          shared := Some((moves, undos))
          Promise.resolve("Link copied to clipboard.")
        },
      },
      game,
    )
    let _teardown = scene.mount(container)
    shareButton(container)->Option.getOrThrow->click
    expect(shared.contents)->toEqual(Some((3, 1)))
  })
})

// Counting moves and undos (#289). The tally is the board's to keep — moves and
// undos are things that happen *to* a board — so these drive the real scene and read
// what it saved, rather than testing `Stats` again (that's `Stats_test`). What's at
// stake is the wiring: that every countable thing is counted once, that the count
// survives a resume, and that a fresh deal starts it over.
describe("TableScene move/undo counts (#289)", () => {
  // The tally as the board last persisted it — the same channel `Main` saves through.
  let tallyOf = (saved: ref<option<SaveState.t>>) =>
    saved.contents->Option.map(s => (s.stats.moves, s.stats.undos))

  test("an opening deal starts at nothing played", () => {
    let saved = ref(None)
    let container = host("div")
    let scene = TableScene.make(~persist=s => saved := Some(s), Game.freecell)
    let _teardown = scene.mount(container)
    expect(tallyOf(saved))->toEqual(Some((0, 0)))
  })

  test("a move counts, an undo doesn't take it back, and a redo counts again", () => {
    // The Finish sweep is one recorded step, so it's one move — the same unit undo
    // steps back over. Driving it (rather than a drag) keeps this jsdom-friendly while
    // still going through `recordHistory`, which is where the counting happens.
    let game = Game.freecell
    let saved = ref(None)
    let board = ref(None)
    let container = host("div")
    let scene = TableScene.make(
      ~initial=Scenario.freecellFinish(game),
      ~persist=s => saved := Some(s),
      ~publish=published => board := Some(published),
      game,
    )
    let _teardown = scene.mount(container)
    expect(tallyOf(saved))->toEqual(Some((0, 0)))

    container->find(".finish-button")->Option.getOrThrow->click
    expect(tallyOf(saved))->toEqual(Some((1, 0)))

    live(board).undo()
    expect(tallyOf(saved))->toEqual(Some((1, 1))) // the move was still made

    live(board).runCommand(Command.Redo)->ignore
    expect(tallyOf(saved))->toEqual(Some((2, 1))) // …and making it again counts again
  })

  test("an undo with nothing behind it isn't counted", () => {
    // The top bar's button can be pressed on a board with an empty past (it's the
    // chrome's job to disable it, not a guarantee the board can rely on).
    let saved = ref(None)
    let board = ref(None)
    let container = host("div")
    let scene = TableScene.make(
      ~persist=s => saved := Some(s),
      ~publish=published => board := Some(published),
      Game.freecell,
    )
    let _teardown = scene.mount(container)
    live(board).undo()
    expect(tallyOf(saved))->toEqual(Some((0, 0)))
  })

  test("a resumed game picks the tally up where it left off", () => {
    // The counts live outside the game state and outside the history, so the only way
    // they survive a reload is by riding in the save — which is what this reads back.
    let game = Game.freecell
    let saved = ref(
      Some({
        SaveState.history: History.make(GameState.initial(game)),
        stats: {moves: 12, undos: 4, autoplays: 0},
        timing: Timing.unknown,
      }),
    )
    let container = host("div")
    let scene = TableScene.make(
      ~loadHistory=() => saved.contents,
      ~persist=s => saved := Some(s),
      game,
    )
    let _teardown = scene.mount(container)
    expect(tallyOf(saved))->toEqual(Some((12, 4)))
  })

  test("a new game starts a fresh tally", () => {
    // A resumed game's counts belong to that game. Dealing another one is a new game
    // in every sense, so the numbers start over rather than accumulating for life.
    let game = Game.freecell
    let saved = ref(
      Some({
        SaveState.history: History.make(GameState.initial(game)),
        stats: {moves: 12, undos: 4, autoplays: 0},
        timing: Timing.unknown,
      }),
    )
    let board = ref(None)
    let container = host("div")
    let scene = TableScene.make(
      ~loadHistory=() => saved.contents,
      ~persist=s => saved := Some(s),
      ~newDeal=() => Game.freecellDeal(~seed=7),
      ~publish=published => board := Some(published),
      game,
    )
    let _teardown = scene.mount(container)
    (live(board).newGame->Option.getOrThrow)()
    expect(tallyOf(saved))->toEqual(Some((0, 0)))
  })

  test("the win overlay presents both numbers", () => {
    // What the issue asked for, where the player sees it: the panel says how many
    // moves the game took and how many undos it cost, on the board that was won.
    let game = Game.freecell
    let (won, _moved) = Reducer.finishSequence(~game, Scenario.freecellAlmostWon(game))
    let container = host("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some({
        SaveState.history: History.make(won),
        stats: {moves: 61, undos: 2, autoplays: 0},
        timing: Timing.unknown,
      }),
      game,
    )
    let _teardown = scene.mount(container)
    let line =
      container
      ->find(".win-panel__stats")
      ->Option.getOrThrow
      ->text
    expect(line)->toBe("61 moves · 2 undos")
  })
})

// How long the game took (#302), where the player sees it. The arithmetic and the
// `M:SS` reading are `core`'s (`Timing_test`); what's at stake here is the board's
// half — that the clock starts with the deal, stops at the win, reaches the save so a
// reload doesn't lose the one number that can only be measured as it happens, and
// reports the same length however often a won board is reopened.
describe("TableScene win time (#302)", () => {
  let timeOf = (container): option<string> => container->find(".win-panel__time")->Option.map(text)

  // A won board, with whatever clock the caller wants beside it.
  let wonSave = (~timing, game): SaveState.t => {
    let (won, _moved) = Reducer.finishSequence(~game, Scenario.freecellAlmostWon(game))
    {history: History.make(won), stats: {moves: 61, undos: 2, autoplays: 0}, timing}
  }

  let dealtAt = 1_700_000_000_000.

  test("the victory screen says how long the game took", () => {
    let game = Game.freecell
    let container = host("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(
        wonSave(~timing={dealtAt: Some(dealtAt), wonAt: Some(dealtAt +. 247_000.)}, game),
      ),
      game,
    )
    let _teardown = scene.mount(container)
    expect(timeOf(container))->toEqual(Some("4:07"))
  })

  test("a resumed victory reports the game's length, not how long ago it was", () => {
    // The overlay goes up again on every reload of a won board (#177). Re-stamping the
    // win there would make the number grow each time you came back to it, so the saved
    // stamp stands — even though this board is being opened long after it was won.
    let game = Game.freecell
    let saved = ref(
      Some(wonSave(~timing={dealtAt: Some(dealtAt), wonAt: Some(dealtAt +. 247_000.)}, game)),
    )
    let container = host("div")
    let scene = TableScene.make(
      ~loadHistory=() => saved.contents,
      ~persist=s => saved := Some(s),
      game,
    )
    let _teardown = scene.mount(container)
    expect(timeOf(container))->toEqual(Some("4:07"))
    // …and the save it re-writes on the way past carries the same stamp, so the next
    // reload reads the same thing again.
    expect(saved.contents->Option.map(s => s.timing.wonAt))->toEqual(
      Some(Some(dealtAt +. 247_000.)),
    )
  })

  test("the clock stops at the winning move, not when the last card lands", () => {
    // The stamp used to be taken in `showWin`, which runs once the sweep's last card has
    // flown — so the time included the flight, and the save the winning move wrote
    // carried no win at all until a second one caught up behind it. The session stamps it
    // as it records the move (#298), so the save that move writes already says the game
    // is over.
    let game = Game.freecell
    let saved = ref(None)
    let container = host("div")
    let scene = TableScene.make(
      ~initial=Scenario.freecellFinish(game),
      ~persist=s => saved := Some(s),
      game,
    )
    let _teardown = scene.mount(container)
    expect(saved.contents->Option.flatMap(s => s.timing.wonAt))->toEqual(None)

    container->find(".finish-button")->Option.getOrThrow->click
    expect(saved.contents->Option.flatMap(s => s.timing.wonAt)->Option.isSome)->toBe(true)
  })

  test("a game with no clock behind it simply shows no time", () => {
    // Every save written before this existed. There's nothing in a history to say when
    // it was dealt, so the panel says nothing rather than inventing a number — and the
    // rest of it (the tally, the buttons) is exactly as it was.
    let game = Game.freecell
    let container = host("div")
    let scene = TableScene.make(
      ~loadHistory=() => Some(wonSave(~timing=Timing.unknown, game)),
      game,
    )
    let _teardown = scene.mount(container)
    expect(timeOf(container))->toEqual(None)
    expect(container->find(".win-panel__stats")->Option.map(text))->toEqual(
      Some("61 moves · 2 undos"),
    )
  })

  testAsync("a game won on the table stops the clock, and the save remembers", async () => {
    // The live path, end to end: the board deals (starting its own clock), the game is
    // won, and the panel reads a real duration. The winning move persisted the board
    // *before* there was a win to time, so the stamp reaching the save at all is the
    // thing being pinned here — without it a reload would show a won board with no time.
    let game = Game.freecell
    let saved = ref(None)
    let board = ref(None)
    let container = host("div")
    let scene = TableScene.make(
      ~initial=Scenario.freecellFinish(game),
      ~persist=s => saved := Some(s),
      ~publish=published => board := Some(published),
      game,
    )
    let _teardown = scene.mount(container)
    live(board).runCommand(Command.Autoplay)->ignore
    await nextTick()
    // A test wins in milliseconds, so the digits are the clock's rather than a fixed
    // duration's — what matters is that it reads as one.
    switch timeOf(container) {
    | Some(text) => expect(text->String.match(/^\d+:\d\d$/)->Option.isSome)->toBe(true)
    | None => expect("a time on the panel")->toBe("but there was none")
    }
    switch saved.contents {
    | Some(s) =>
      expect(s.timing.dealtAt->Option.isSome)->toBe(true)
      expect(s.timing.wonAt->Option.isSome)->toBe(true)
    | None => expect("persisted")->toBe("but nothing was saved")
    }
  })

  testAsync("stepping back out of a victory takes the win off the clock", async () => {
    // An undone win isn't a win, so the board it leaves has no won-at — and the save
    // says so, or a reload would resume a playable board that still claimed a time.
    let game = Game.freecell
    let saved = ref(None)
    let board = ref(None)
    let container = host("div")
    let scene = TableScene.make(
      ~initial=Scenario.freecellFinish(game),
      ~persist=s => saved := Some(s),
      ~publish=published => board := Some(published),
      game,
    )
    let _teardown = scene.mount(container)
    live(board).runCommand(Command.Autoplay)->ignore
    await nextTick()
    live(board).undo()
    expect(saved.contents->Option.map(s => s.timing.wonAt))->toEqual(Some(None))
    // …and winning it again times the whole game, detour included: the deal stamp never
    // moved, so the clock still runs from the board it was dealt on.
    live(board).runCommand(Command.Redo)->ignore
    expect(saved.contents->Option.map(s => s.timing.wonAt->Option.isSome))->toEqual(Some(true))
    expect(timeOf(container)->Option.isSome)->toBe(true)
  })
})

// Autoplay, wired to the board (#291). The thinking is `core`'s and is tested there
// (`Solver_test`); what's at stake here is the board's half — that the reach is
// counted, that the moves it plays are recorded like any other, and that the counter
// is the undo-proof thing the victory screen reads. The scenario is deliberately one
// the solver has nothing left to think about (`freecellFinish` is already finishable),
// so these run in milliseconds and still go through the whole path.
describe("TableScene autoplay (#291)", () => {
  let statsOf = (saved: ref<option<SaveState.t>>) => saved.contents->Option.map(s => s.stats)
  let hasWinOverlay = (container): bool => container->find(".win-overlay")->Option.isSome

  testAsync("counts the reach for the solver, and finishes the game", async () => {
    let game = Game.freecell
    let saved = ref(None)
    let board = ref(None)
    let container = host("div")
    let scene = TableScene.make(
      ~initial=Scenario.freecellFinish(game),
      ~persist=s => saved := Some(s),
      ~publish=published => board := Some(published),
      game,
    )
    let _teardown = scene.mount(container)
    live(board).runCommand(Command.Autoplay)->ignore
    await nextTick()
    switch statsOf(saved) {
    | Some(stats) =>
      expect(stats.autoplays)->toBe(1)
      // The board was already finishable, so the solver played nothing and the sweep
      // it handed over to is the one recorded move.
      expect(stats.moves)->toBe(1)
    | None => expect("persisted")->toBe("but nothing was saved")
    }
  })

  testAsync("an autoplayed win keeps its Share button to itself, undo or no undo", async () => {
    // The requirement, end to end: autoplay, undo back out of everything it did, win
    // the game by hand from there — the victory is still not shareable, because the
    // tally remembers.
    let game = Game.freecell
    let board = ref(None)
    let container = host("div")
    let scene = TableScene.make(
      ~initial=Scenario.freecellFinish(game),
      ~publish=published => board := Some(published),
      ~winShare={available: () => true, share: (~moves as _, ~undos as _) => Promise.resolve("")},
      game,
    )
    let _teardown = scene.mount(container)
    live(board).runCommand(Command.Autoplay)->ignore
    await nextTick()
    live(board).undo()
    expect(hasWinOverlay(container))->toBe(false) // stepped back out of the victory
    live(board).runCommand(Command.Redo)->ignore // …and won it again, by hand this time
    expect(hasWinOverlay(container))->toBe(true)
    expect(container->find(".win-panel__button--share")->Option.isSome)->toBe(false)
  })

  test("a board the solver doesn't understand is told so", () => {
    // A board without FreeCell's cells and foundations isn't four cells, four
    // foundations and eight columns, so there's no position to pack it into — an
    // honest refusal rather than a wrong answer, in the words both front ends use.
    let game: Game.t = {
      ...Game.freecell,
      piles: Game.pilesOf(Game.freecell, Game.Cascade),
    }
    let board = ref(None)
    let container = host("div")
    let scene = TableScene.make(~publish=published => board := Some(published), game)
    let _teardown = scene.mount(container)
    expect(Render.toPlain(live(board).runCommand(Command.Autoplay)))->toBe(
      Command.autoplayNotFreeCell,
    )
  })
})
