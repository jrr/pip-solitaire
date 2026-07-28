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

// Feed the board a synthetic `devicemotion` reading (#236). jsdom has no sensor, but
// the whole path from event to card style is ordinary code — `Motion.subscribeGestures`
// listens on `window`, so dispatching an event carrying an
// `accelerationIncludingGravity` drives the real classifier and the real board.
%%raw(`globalThis.fireMotion = (x, y, z) => {
  const event = new Event("devicemotion")
  event.accelerationIncludingGravity = { x, y, z }
  window.dispatchEvent(event)
}`)

open Vitest

@val @scope("globalThis") external fireMotion: (float, float, float) => unit = "fireMotion"
@val @scope("document") external createElement: string => WebDom.element = "createElement"
@send
external querySelector: (WebDom.element, string) => Nullable.t<WebDom.element> = "querySelector"

// Reading the two style channels back off the card nodes, and a promise-shaped sleep
// for the one behaviour with a timer in it (the shake settle).
type nodeList
@send external querySelectorAll: (WebDom.element, string) => nodeList = "querySelectorAll"
@val @scope("Array") external nodesOf: nodeList => array<WebDom.element> = "from"
type cssStyle
@get external elementStyle: WebDom.element => cssStyle = "style"
@send external getPropertyValue: (cssStyle, string) => string = "getPropertyValue"
@val external setTimeout: (unit => unit, float) => int = "setTimeout"
let delay = ms => Promise.make((resolve, _) => setTimeout(() => resolve(), ms)->ignore)
// A case Vitest awaits, for the one behaviour here with a timer in it. Bound locally
// rather than added to `Vitest`: two modules in this workspace carry that name (this
// package's bindings and `core`'s), and which one an `open Vitest` picks up is not
// something to build on — a local external is unambiguous either way.
@module("vitest") external testAsync: (string, unit => promise<unit>) => unit = "test"

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
// `~persist` sink as it changes, and re-seeds from a `~history` on the way back —
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
    let scene = TableScene.make(~history=History.make(won), game)
    let _teardown = scene.mount(container)
    expect(hasWinOverlay(container))->toBe(true)
  })

  test("an ordinary resumed game opens without a win overlay", () => {
    // A mid-game saved position is not won, so no overlay — the board is just playable.
    let game = Game.freecell
    let container = createElement("div")
    let scene = TableScene.make(~history=History.make(GameState.initial(game)), game)
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
      ~history=resumed,
      ~onHistory=canUndo => lastCanUndo := Some(canUndo),
      game,
    )
    let _teardown = scene.mount(container)
    expect(lastCanUndo.contents->Option.getOr(false))->toBe(true)
  })
})

// Wiggle Waggle (#235) and Sloppy placement (#65) are independent, and *all four*
// combinations are valid (#236). The mechanism is two custom properties the CSS sums:
// `--card-rot` is the hand-placed base tilt, `--shake-x/y/rot` the disarray a shake
// leaves on top of it. Nothing cross-checks them — so what's worth pinning is the
// semantics that fall out, above all the one that reads as a bug if it isn't written
// down: **squaring up returns the cards to how they were *dealt*, not to
// machine-perfect**. With Sloppy placement on that's the dealt sloppiness; with it off
// it's true square. Both are "back where they were", which is what tapping a real deck
// down on the table does.
//
// The gestures are driven through the real classifier by dispatching synthetic
// `devicemotion` events (see `fireMotion` above), so these exercise the whole path:
// event → gravity projection → board.
describe("TableScene shake disarray and base tilt (#236)", () => {
  let cardsIn = container => container->querySelectorAll(".stacking-card")->nodesOf
  let numeric = value => {
    // Custom properties come back as "3.2deg" / "-4px", and unset reads as "" — which
    // is a zero, since that's what the stylesheet's `var(…, 0)` fallbacks mean.
    let parsed = Float.parseFloat(value)
    Float.isNaN(parsed) ? 0. : parsed
  }
  let prop = (el, name) => numeric(el->elementStyle->getPropertyValue(name))
  let tilts = container => cardsIn(container)->Array.map(el => prop(el, "--card-rot"))
  let messiness = container =>
    cardsIn(container)->Array.map(el =>
      Math.abs(prop(el, "--shake-x")) +.
      Math.abs(prop(el, "--shake-y")) +.
      Math.abs(prop(el, "--shake-rot"))
    )
  let isMessy = container => messiness(container)->Array.some(m => m > 0.)

  // A board with Wiggle Waggle already listening. The relayout hook is called straight
  // away so the cards are laid out (and their base tilt published) without waiting on
  // the deferred deal's animation frame, which jsdom may never run.
  let mountListening = (~sloppy) => {
    let container = createElement("div")
    let relayout = ref(() => ())
    let control = ref(None)
    let scene = TableScene.make(
      ~tiltEnabled=ref(sloppy),
      ~publishRelayout=hook => relayout := hook,
      ~publishShake=c => control := Some(c),
      Game.freecell,
    )
    let _teardown = scene.mount(container)
    relayout.contents()
    switch control.contents {
    | Some(c) => c.start()
    | None => expect("shake control published")->toBe("not published")
    }
    container
  }

  // A still phone seeds the gravity estimate; the second reading is the gesture. A hard
  // sideways swing is energy *across* gravity (a shake); a sharp push along the gravity
  // axis is the deck being tapped down (a square-up).
  let still = () => fireMotion(0., Motion.gravity, 0.)
  let shakeIt = () => {
    still()
    fireMotion(26., Motion.gravity, 0.)
  }
  let tapItDown = () => fireMotion(0., Motion.gravity +. 17.5, 0.)

  test("cards deal machine-perfect with Sloppy placement off, and stay that way", () => {
    let container = mountListening(~sloppy=false)
    expect(tilts(container)->Array.every(t => t == 0.))->toBe(true)
    // A freshly built board carries no disarray, which is also what makes "quit and come
    // back" a way out of the mess: the offsets are transient view state that never
    // reaches the save (#177), so every mount — a re-deal or a resume — opens clean.
    expect(isMessy(container))->toBe(false)
  })

  test("a shake messes up a dead-square board — the sharpest demo of the feature", () => {
    // Sloppy off + waggle on: cards deal perfect and stay perfect until you disturb
    // them, then they're messy and stay messy. The disarray lands entirely in the shake
    // channel, so the base tilt is still dead square underneath it.
    let container = mountListening(~sloppy=false)
    shakeIt()
    expect(isMessy(container))->toBe(true)
    expect(tilts(container)->Array.every(t => t == 0.))->toBe(true)
  })

  test("a shake leaves the hand-dealt tilt alone", () => {
    // Sloppy on + waggle on: the two channels coexist. The base tilt a card was dealt
    // with survives the shake untouched — the mess is added on top of it, not instead
    // of it.
    let container = mountListening(~sloppy=true)
    let dealt = tilts(container)
    expect(dealt->Array.some(t => t != 0.))->toBe(true)
    shakeIt()
    expect(isMessy(container))->toBe(true)
    expect(tilts(container))->toEqual(dealt)
  })

  testAsync("squaring up returns the cards to how they were dealt, not to square", async () => {
    // Both boards are driven by the same synthetic readings — every listening board
    // hears the same `devicemotion` — which is also why they can share the waits.
    let sloppyBoard = mountListening(~sloppy=true)
    let squareBoard = mountListening(~sloppy=false)
    let dealtSloppy = tilts(sloppyBoard)
    let dealtSquare = tilts(squareBoard)

    shakeIt()
    expect(isMessy(sloppyBoard))->toBe(true)
    expect(isMessy(squareBoard))->toBe(true)

    // The cooldown #236 asks for: a vigorous shake's tail would otherwise read as a
    // square-up and tidy the board that was just messed up, so a tap is only taken at
    // face value once the phone has been quiet for `shakeSuppressMs`.
    tapItDown()
    expect(isMessy(sloppyBoard))->toBe(true) // suppressed — still messy
    await delay(Motion.shakeSuppressMs +. 60.)
    tapItDown()
    // The cards are nudged down and then glide home over `settleMs`.
    await delay(CardShake.settleMs +. 60.)

    // Home is the *dealt* board in both cases: the disarray is gone, and each card is
    // back on the base tilt it was dealt with — hand-placed sloppiness on one board,
    // dead square on the other.
    expect(isMessy(sloppyBoard))->toBe(false)
    expect(isMessy(squareBoard))->toBe(false)
    expect(tilts(sloppyBoard))->toEqual(dealtSloppy)
    expect(tilts(squareBoard))->toEqual(dealtSquare)
    expect(dealtSloppy->Array.some(t => t != 0.))->toBe(true)
    expect(dealtSquare->Array.every(t => t == 0.))->toBe(true)
  })

  testAsync("toggling Sloppy placement mid-mess only changes the tilt channel", async () => {
    // The relayout the tilt switch drives (#65) re-publishes `--card-rot` under the
    // existing offsets; it has no business touching the mess, and doesn't.
    let container = createElement("div")
    let sloppy = ref(false)
    let relayout = ref(() => ())
    let control = ref(None)
    let scene = TableScene.make(
      ~tiltEnabled=sloppy,
      ~publishRelayout=hook => relayout := hook,
      ~publishShake=c => control := Some(c),
      Game.freecell,
    )
    let _teardown = scene.mount(container)
    relayout.contents()
    switch control.contents {
    | Some(c) => c.start()
    | None => expect("shake control published")->toBe("not published")
    }
    shakeIt()
    // Wait for the throw to settle first, so what's compared across the toggle is the
    // mess the cards came to rest in rather than a value still mid-transition.
    await delay(CardShake.settleMs +. 60.)
    let messy = messiness(container)
    expect(messy->Array.some(m => m > 0.))->toBe(true)

    // Flip Sloppy placement on, mid-mess: tilts appear, offsets stay exactly as they were.
    sloppy := true
    relayout.contents()
    expect(tilts(container)->Array.some(t => t != 0.))->toBe(true)
    expect(messiness(container))->toEqual(messy)
  })
})
