// A card table that *interprets a modelled game* rather than hard-coding one board:
// the piles, their stacking behaviours and the opening deal all come from `Game.t`, so
// a new game is a new value there and not new code here. What the view holds is the
// presentation assumption the model has no opinion on — piles hang from the top of the
// stage and grow downward, grouped into rows by role.
//
// **Built with imperative DOM bindings rather than the `Html` Elm loop**, alone among
// the scenes, because dragging is transient view state: a `pointermove` doesn't belong
// in a reduced model, and driving the card straight from the event keeps it glued to
// the finger. The card faces are still typed `CardArt` vnodes, materialised once with
// `Html.create` and then moved by mutating `style.left/top`.
//
// One pointer path covers phone and desktop (Pointer Events, `setPointerCapture` so a
// card keeps receiving moves when the pointer outruns it, `touch-action: none` so a
// drag doesn't also scroll). The contract with the driver is `docs/board-driver.md`.

%%raw(`import "./TableScene.css"`)

// --- Pointer / geometry bindings ---------------------------------------------
// WebDom's `addEventListener` is event-less; dragging needs the PointerEvent
// (coordinates + id), so bind a pointer-specific listener and the few reads off
// the event and the element that the maths below wants.
type pointerEvent
@get external clientX: pointerEvent => float = "clientX"
@get external clientY: pointerEvent => float = "clientY"
@get external pointerId: pointerEvent => int = "pointerId"
// The event's timestamp (ms since page load); the send-home double-tap is timed
// off this rather than a `dblclick`, which mobile Safari never fires for a
// double-tap (see the pointer loop below).
@get external timeStamp: pointerEvent => float = "timeStamp"
@send external setPointerCapture: (WebDom.element, int) => unit = "setPointerCapture"
@send external releasePointerCapture: (WebDom.element, int) => unit = "releasePointerCapture"
@send
external onPointer: (WebDom.element, string, pointerEvent => unit) => unit = "addEventListener"

// The initial deal is centred on the stage's live size, which isn't known until
// the stage is in the document and laid out. On first load the scene mounts while
// still detached (see SceneSwitcher), so the deal is deferred to the next frame,
// before the first paint — hence this binding.
@val external requestAnimationFrame: (unit => unit) => int = "requestAnimationFrame"

// An autoplay run starts on the *next* tick rather than inside the command that asked
// for it, so the console's reply — the one sentence that describes the whole run — is
// printed above the play-by-play instead of one move down it. See `autoplay` below.
@val external setTimeout: (unit => unit, int) => int = "setTimeout"

// The card layout is pixel-positioned in JS from the stage's live size, so unlike
// the pure-CSS drop zones it doesn't reflow itself when the stage resizes.
// A `ResizeObserver` on the board host is the trigger to re-run the layout: it
// catches every stage size change — window resizes, orientation flips, chrome
// reflowing, late font loads — not just `window.resize`. The callback is passed
// the observed entries, but the relayout reads the live rects itself, so the
// binding ignores them.
type resizeObserver
@new external makeResizeObserver: (unit => unit) => resizeObserver = "ResizeObserver"
@send external observe: (resizeObserver, WebDom.element) => unit = "observe"
@send external disconnect: resizeObserver => unit = "disconnect"
// Look the constructor up off `globalThis` first so an environment without it —
// jsdom in the tests, older engines — skips the resize wiring rather than throwing
// on construction; the layout still runs on every deal, just not on resize. Read
// via `globalThis` (not a bare identifier) so a missing global reads as `undefined`
// instead of a `ReferenceError`.
@val @scope("globalThis") external resizeObserverCtor: Nullable.t<unit> = "ResizeObserver"

// getBoundingClientRect gives viewport coordinates; that's what hit-testing and
// the snap maths use, converting to playfield-local left/top only at the end. The
// rect type is `TableLayout`'s, since the maths that compares these lives there.
@send external boundingRect: WebDom.element => TableLayout.rect = "getBoundingClientRect"

// The card scale is sized to the box the row *actually lays out in*, and three of
// that box's terms — the safe-area cutout it's pinned inside, its `top` offset, its
// inter-row `rowGap` — are in no rect we already read. So pull them off the row's
// *computed* style, keeping the stylesheet the one place each is written down;
// `parseFloat` turns "44px" → 44. What they feed is `docs/board-geometry.md`.
@val
external getComputedStyle: WebDom.element => {
  "left": string,
  "right": string,
  "top": string,
  "rowGap": string,
} = "getComputedStyle"
@val external parseFloat: string => float = "parseFloat"

// The opening deal flies each card in from a single origin below the
// stage — as if a magician were throwing them into place off one stack — with
// the Web Animations API, the same `element.animate(keyframes, options)` the
// card spin in `Board.res` drives. A compositor-friendly `transform` is animated
// (not left/top, which stay reserved for the in-game drop snap): every card
// starts translated to that one off-stage point (a differing X *and* Y per card,
// since each lands in a different spot) and flies to `translate 0`, with `fill:
// "backwards"` so a card holds at the origin until its staggered turn.
type animation
@send
external animate: (
  WebDom.element,
  array<{"transform": string}>,
  {"duration": float, "delay": float, "easing": string, "fill": string},
) => animation = "animate"
// Cancelling an animation (on teardown / undo) reverts its element and — unlike a
// natural finish — does *not* fire `onfinish`, so a cancelled finish sweep can't
// raise a stale win overlay. `onfinish` is how the sweep knows its last card has
// landed (see `animateFinish`).
@send external cancel: animation => unit = "cancel"
@set external setOnFinish: (animation, unit => unit) => unit = "onfinish"
// The finish sweep also animates z: a card holds its resting layer while it
// waits its turn (so the source fan it hasn't left stays correctly stacked), then
// jumps above the board for its flight and landing. `fill: "forwards"` is the whole
// point — the effect is *absent* during the launch delay (so the resting inline z
// shows through) and only takes hold from the flight onward, holding the raised z
// until the final settle cancels it. Two constant keyframes keep the raise instant
// (z-index steps discretely, so a single keyframe would only flip mid-flight).
@send
external animateZ: (
  WebDom.element,
  array<{"zIndex": string}>,
  {"duration": float, "delay": float, "fill": string},
) => animation = "animate"

// The double-tap "where can this go?" hint: when no
// foundation will take a double-tapped card but it can still move, each legal
// destination flashes a strong translucent-green mask (the menu's accent green) so the
// card underneath goes mostly-green for a beat, then clears. The mask is a throwaway
// `.hint-mask` div pulsed over the *individual eligible card* — the exposed bottom card
// of the target pile — rather than the whole column's drop zone. Free cells (the
// obvious park spot) and empty board spaces are never hinted, so only the exposed card
// of an occupied pile lights. A WAAPI animation on `opacity` (looped for the pulse)
// with the same `element.animate` the deal/finish flights use; `setOnFinish` removes
// the mask when the pulse ends. Purely informational: it moves no card and selects
// nothing.
@send
external animateMask: (
  WebDom.element,
  array<{"opacity": string, "offset": float}>,
  {"duration": float, "iterations": int, "easing": string},
) => animation = "animate"

// Honour the OS "reduce motion" preference by collapsing the fly-up to an
// instant placement.
@val external matchMedia: string => {"matches": bool} = "matchMedia"

// A card is positioned by writing `style.left/top`, and layered by writing
// `style.zIndex`; the drag loop needs these, and reflow grows a fanned zone by
// writing `style.height` so its highlight wraps the whole pile (below).
type style
@get external style: WebDom.element => style = "style"
@set external setLeft: (style, string) => unit = "left"
@set external setTop: (style, string) => unit = "top"
@set external setZIndex: (style, string) => unit = "zIndex"
// Read a card's current layer back, so the finish sweep can hold each
// card at its *resting* z while it waits its turn — keeping the source fan it
// hasn't left correctly stacked — before lifting it above the board for the
// flight (see `animateFinish`).
@get external zIndex: style => string = "zIndex"
@set external setHeight: (style, string) => unit = "height"
// Card/zone footprints scale to the stage (see `scale` below); the factor is
// published to the CSS as custom properties so `.stacking-card`/`.drop-zone`
// resize in step with the JS geometry.
@send external setProperty: (style, string, string) => unit = "setProperty"
// …and dropped again, so a card that borrowed a property for the length of one
// animation (the finish sweep's per-card tilt timing, below) falls back to the
// stylesheet's default rather than carrying the sweep's values into normal play.
@send external removeProperty: (style, string) => unit = "removeProperty"

// Toggling the drag/hover/buried marker classes goes through classList rather
// than rewriting the whole `class` attribute each move.
type tokenList
@get external classList: WebDom.element => tokenList = "classList"
@send external addClass: (tokenList, string) => unit = "add"
@send external removeClass: (tokenList, string) => unit = "remove"

// `core`'s `GameState` owns *where every card rests*: the scene holds one immutable
// `GameState.t` and re-derives each pile from it, so a zone carries no `pile` of its own
// and a card remembers no `home`. What's left on these records is purely
// presentational — keep it that way, or the board grows a second answer to "where is
// this card" that only the view can see.
//
// A zone is just its element, its model `index` (the pile it stands for in
// `GameState`), and its `stacking` behaviour (how the fan lays out) — the `rule`
// it enforces lives on the game's pile and is consulted through the reducer, not
// cached here.
type dropZone = {
  el: WebDom.element,
  index: int,
  stacking: Game.stacking,
}
// A draggable card node: its identity, its element, its live playfield-local
// position, and whether it may be picked up right now. Where it *rests* is no
// longer stored here — that comes from `GameState`; only the top card of a pile
// ends up `draggable`, set each reflow.
type card = {
  // The card's identity (suit/rank), the bridge between a `GameState` pile —
  // structural `{suit, rank}` cards — and this DOM node (see `nodeFor`).
  data: Deck.card,
  wrapper: WebDom.element,
  x: ref<float>,
  y: ref<float>,
  draggable: ref<bool>,
}

// The two shake operations a built board exposes to the persistent shake
// subscription: `jostle` nudges the current cards off their resting spots on
// a shake, `squareUp` re-lays them clean when listening stops. Republished on every
// `buildBoard` so the mount-scope subscription always drives the live board's nodes.
type boardOps = {
  jostle: unit => unit,
  squareUp: unit => unit,
}

// The shake control the scene publishes to the chrome, one field of the
// `controls` record below: `start` begins listening for shakes (Settings turns Wiggle
// Waggle on, once permission is granted), `stop` ends it and squares the board back
// up. Held at mount scope so it survives re-deals — the chrome calls it as the
// switch flips, never rebuilding the board.
type shakeControl = {
  start: unit => unit,
  stop: unit => unit,
}

// Everything a mounted board offers the chrome, handed over whole by `~publish`. Why
// it is one record, why every field is mount-scoped, and why two of them are `option`
// is `docs/board-driver.md` § What `~publish` hands back.
type controls = {
  // Re-deal onto a fresh seed — the menu's New Game, the console's bare `deal`.
  newGame: option<unit => unit>,
  // Its addressed twin, behind the console's `deal <n>`. The number becomes a board
  // here, by the game on the table, so the caller needn't know a deal number is a
  // seeded shuffle to put the two together.
  loadDeal: option<int => unit>,
  // Replay the deal now on the table. Every card table offers it — a fixed-layout demo
  // restarts to its own deal.
  restart: unit => unit,
  // The debug-states menu's live twin of `?state=`. **Never persisted**, so a debug
  // jump can't clobber a saved game.
  loadState: GameState.t => unit,
  // A shared game, history intact. *Unlike* a forced state this persists: a shared
  // game is adopted as this device's saved game rather than borrowed.
  loadHistory: SaveState.t => unit,
  readHistory: unit => option<SaveState.t>,
  undo: unit => unit,
  // Not a second interpreter: the command goes to `Session.step` exactly as the
  // terminal's does, and what comes back is turned into cards moving on a screen.
  runCommand: Command.t => array<Render.line>,
  // Re-lay every resting card, so the tilt switch re-tilts the board in place rather
  // than only on the next move.
  relayout: unit => unit,
  // Could you give up this many px of stage width and still deal cards above
  // `minScale`? What the console's dock toggle consults, so the refusal is the
  // layout's own verdict rather than a guessed breakpoint.
  dockFit: float => bool,
  shake: shakeControl,
}

// What the driver offers the win overlay's Share button. `available` is asked as the
// overlay goes up and decides whether the button is built at all — asking then, rather
// than at build time, keeps the answer about the board that was just won.
//
// A pair rather than two props because they have to agree: offering a button that then
// has no deal to share is the one failure a share button can't afford, and one record
// makes that a type error instead of a convention two call sites keep.
type winShare = {
  available: unit => bool,
  // The won game's tally, read off the live board at the press. The board counts them
  // because it's the thing moves and undos happen to; what the driver does with them
  // is its own business.
  share: (~moves: int, ~undos: int) => promise<string>,
}

// A victory cascade in flight, and everything ending one has to reach. Held at *mount*
// scope, because a run outlives the build that started it: an undo, a New Game, or a
// scene switch can all land while cards are still falling, and each has to be able to
// take the canvas down, stop the loop, and put back the cards the run hid.
//
// `reveal` closes over the build's own card nodes, which is why the run carries it rather
// than the mount re-deriving it from a board that may since have been replaced.
type cascadeRun = {
  player: CascadePlayer.t,
  canvas: WebDom.element,
  reveal: unit => unit,
}

// The design footprints, the fits they feed, and the hit-test that compares the
// rects — all of it arithmetic over rects and counts, and all of it in
// `TableLayout`; `docs/board-geometry.md` derives it. Referenced by name
// below (`TableLayout.cardW`, `TableLayout.fanStep`, …) rather than opened, so a
// number's home is visible at the site that multiplies it.

// Four things move cards across this board — the opening deal, the finish sweep, a
// console move and an autoplay step — and all four are one staggered flight timed by
// one pair of numbers: a max-in-flight cap C and a per-card budget P.
//
// **The derivation, what each knob does to the feel, and the four tunings side by
// side are in `docs/animation-timing.md`.** Read that before retuning; the pairs are
// deliberately not shared, so each of the four can be re-timed on its own.

// The opening deal: fifty-two cards thrown from one off-stage stack. The
// flourish that opens a game, so it can't outstay its welcome.
let dealMaxInFlight = 5
let dealPerCardMs = 67.

// The end-game "Finish" sweep: fifty-odd cards on their way to a win. It's the
// payoff, so a touch more languid than the deal.
let finishMaxInFlight = 5
let finishPerCardMs = 90.

// A move played by a *typed command*: one card, or a short `moverun`, that has to be
// followable by someone reading the log to see what the command did.
let commandMaxInFlight = 2
let commandPerCardMs = 170.

// A move the solver played: the console's pair, quickened, because this is one
// of forty moves on the way to a win.
let autoplayMaxInFlight = 3
let autoplayPerCardMs = 140.

// A flying card is lifted onto this z base — well above any resting slot layer —
// so it rides over the source fan it's leaving and lands on top of the foundation
// cards already home. A per-card `+ i` (its launch index) preserves arrival-order
// stacking — later ranks on top, King last — while several cards are in flight at
// once; the final `reflowAll` then settles every foundation to its own slot order.
let finishFlightZBase = 100000

// From C, P and the card count n: the start interval Δ between successive cards, and
// each card's flight time t = C·Δ. C is clamped to at most n, or a short sequence
// would pad its last flight past the end of the sequence itself.
let staggerTiming = (~maxInFlight, ~perCardMs, ~n) => {
  let c = Int.toFloat(maxInFlight < n ? maxInFlight : n)
  let total = perCardMs *. Int.toFloat(n)
  let delta = n > 1 ? total /. (Int.toFloat(n - 1) +. c) : total /. c
  let flight = c *. delta
  (delta, flight)
}

// The easing every staggered flight shares — a soft, overshoot-free ease-out.
let flightEasing = "cubic-bezier(0.22, 1, 0.36, 1)"

// One card's staggered flight: animate a compositor-friendly `transform` from an
// offset `(dx, dy)` back to zero, so the card reads as travelling from `(its
// committed spot) + (dx, dy)` home to that spot (its left/top already hold it).
// `fill: "backwards"` holds the card at the offset through its `delay`, so a batch
// launched in one loop each waits its staggered turn. The deal flies every card from
// one shared off-stage origin; a sweep or a commanded move flies each from its own
// resting spot — only `(dx, dy)` differs. Returns the animation so a caller can track
// it (`outstandingAnimations`) or hang the batch's completion off it.
let flyHome = (~wrapper, ~dx, ~dy, ~flight, ~delay) =>
  wrapper->animate(
    [
      {"transform": `translate3d(${Float.toString(dx)}px, ${Float.toString(dy)}px, 0)`},
      {"transform": "translate3d(0, 0, 0)"},
    ],
    {"duration": flight, "delay": delay, "easing": flightEasing, "fill": "backwards"},
  )

// The send-home gesture is a *double-tap* — two taps on the same card,
// each staying under `doubleTapMoveTol` pixels of travel (so it reads as a tap,
// not the start of a drag), within `doubleTapMs` of one another. This is timed
// off the pointer stream by hand because mobile Safari doesn't fire `dblclick`
// for a double-tap (it's the tap-to-zoom gesture); the same code path then also
// covers the desktop double-click, so one loop serves phone and desktop.
let doubleTapMs = 300.
let doubleTapMoveTol = 12.

// The browser's own double-tap gesture — which on iOS scales the viewport, over
// the top of this one — is refused app-wide in `TapZoom`, armed by `Main`. It has
// to be refused in the touch layer, and so can't ride along with the pointer
// bookkeeping here; the two are independent by necessity, not by preference.

// The modifier the empty-pile indicator wears for its pile's role. The three
// roles accept quite different things — a foundation only ever opens with an Ace, a
// free cell takes any one card, a tableau column takes a card or a run — and until
// now the board drew one dashed rectangle for all three, so a player couldn't tell
// where the cells ended and the foundations began. That boundary isn't learnable by
// position either: it moves with the game (`freecell` is 4 cells + 4 foundations,
// `mini` 2 + 4, `micro` 2 + 2), which is why the cue has to be intrinsic to the slot
// rather than a gap in the row.
//
// Only the *paint* varies. The footprint stays identical across the three — the slot
// traces the card exactly, and browser-tests/geometry.spec.mjs pins that on whichever
// slot comes first (a free cell) — so a role may change colour, fill and contents,
// but never its size or corner radius.
let slotRoleClass = (role: Game.role) =>
  switch role {
  | Game.FreeCell => "drop-zone__slot--cell"
  | Game.Foundation => "drop-zone__slot--foundation"
  | Game.Cascade => "drop-zone__slot--tableau"
  }

// The whole span of the hand-placed tilt, not a variance. **Keep it small** or cards
// stop stacking cleanly: a fanned pile's overlap comes from `TableLayout.fanStep`,
// which assumes cards are very nearly square. docs/card-tilt.md is the rest of it.
let maxCardTilt = 2.5
let suitOrdinal = (suit: Deck.suit) =>
  switch suit {
  | Spades => 0
  | Hearts => 1
  | Diamonds => 2
  | Clubs => 3
  }
let rankOrdinal = (rank: Deck.rank) =>
  switch rank {
  | Ace => 0
  | Two => 1
  | Three => 2
  | Four => 3
  | Five => 4
  | Six => 5
  | Seven => 6
  | Eight => 7
  | Nine => 8
  | Ten => 9
  | Jack => 10
  | Queen => 11
  | King => 12
  }
// The tilt in degrees for `card` resting at (`pile`, `slot`) — its resting place, as
// a pile index and a slot within it. **Every input must stay non-negative**: that is
// what keeps `Int.mod` positive, and a negative `h` would throw the angle past
// `-maxCardTilt`. Why a hash rather than a random number, and what each multiplier is
// worth in degrees: docs/card-tilt.md.
let cardTilt = (~card: Deck.card, ~pile, ~slot) => {
  let h = suitOrdinal(card.suit) * 17 + rankOrdinal(card.rank) * 5 + pile * 23 + slot * 11
  let unit = Int.toFloat(Int.mod(h, 100)) /. 100.
  (unit *. 2. -. 1.) *. maxCardTilt
}
// Set (or clear) a card wrapper's tilt, published as the `--card-rot` custom
// property the `.card-art` child rotates by (see the CSS). Kept on the child, not
// the wrapper, so it never fights the wrapper's drag/flight `transform`.
let applyTilt = (wrapper, ~degrees) =>
  style(wrapper)->setProperty("--card-rot", Float.toString(degrees) ++ "deg")

// Give one card's *rotation* the same schedule as its *flight* — docs/card-tilt.md
// § The sweep problem is the board twitch that prevents.
//
// Three rules, every one of them quiet if broken: set these *before* the `reflowAll`
// that applies the new angle, index them off the same loop as the flights, and clear
// them again wherever a flight can end.
let setTiltTiming = (wrapper, ~delay, ~duration) => {
  let s = style(wrapper)
  s->setProperty("--card-rot-delay", Float.toString(delay) ++ "ms")
  s->setProperty("--card-rot-dur", Float.toString(duration) ++ "ms")
}
let clearTiltTiming = wrapper => {
  let s = style(wrapper)
  s->removeProperty("--card-rot-delay")
  s->removeProperty("--card-rot-dur")
}

// The tilt to publish for `card` resting at (`pile`, `slot`), gated on whether the
// player wants the hand-placed look at all. "Off" is a dead-square 0° through
// the same property, not a second code path — so nothing else about the layout
// varies with the setting.
let tiltFor = (~enabled, ~card, ~pile, ~slot) => enabled ? cardTilt(~card, ~pile, ~slot) : 0.

// The game clock, read where the impurity belongs: `Session` stamps a win with a
// moment it's handed, and this is the layer that has a wall clock to hand it. The same
// line the terminal draws — see the comment above `Cli.randomSeed`.
let clock = () => Date.now()

// Build a scene that plays `game`: its id and label name it in the picker, its piles
// and opening deal drive everything below.
//
// **The contract with the driver — what each argument is for, why the preferences are
// refs, why the read-backs are thunks, and who resolves the deal number — is
// `docs/board-driver.md`.** Read it before adding an argument; the seam is told from
// `Main`'s side too, and that page is the one place it's told whole.
//
// The notes below are only what a reader needs *here*: which arguments a board can do
// without, and what happens when one is left out.
let make = (
  // Forces the board into a given position instead of the opening deal — what the
  // URL's `?state=` uses. Ignored when `~loadHistory` yields a save, whose present
  // state seeds the board instead.
  ~initial: option<GameState.t>=?,
  // Restores a *whole* saved game, tally included, so Undo still walks back through
  // the moves played before the player left. The opening build of each mount only: a
  // re-deal starts a clean history.
  ~loadHistory: unit => option<SaveState.t>=() => None,
  // Its write side — handed the full history after every change, including the
  // opening/New Game/Restart builds. Omitted, the board saves nothing.
  ~persist: option<SaveState.t => unit>=?,
  // What makes the board *re-dealable*: a thunk yielding a fresh game to open, a new
  // seed each call. Omitted, `controls.newGame` and `controls.loadDeal` are `None` —
  // the fixed-layout demos.
  ~newDeal: option<unit => Game.t>=?,
  // The board's published surface (`controls` above), handed over once as this scene
  // mounts. Omitted, the board publishes nothing: a test that only watches it play.
  ~publish: option<controls => unit>=?,
  // After every state change, whether there is anything to undo. Undo works even from
  // a won board — a victory is just another recorded state — so stepping back tears
  // the win overlay down and returns to the prior position.
  ~onHistory: option<bool => unit>=?,
  // The deal number this build is showing, or `None` where the board can't say. Called
  // on every build, so a New Game reports its fresh seed and a scene switch reports
  // `None`.
  ~onDeal: option<option<int> => unit>=?,
  // …and the read side, for the console's printed board. Defaults to "no number",
  // which is the truthful answer for a board built by a test or a demo.
  ~currentDeal: unit => option<int>=() => None,
  // Omitted, the win overlay is the New Game button alone.
  ~winShare: option<winShare>=?,
  // All three read *live*, so a menu toggle lands without rebuilding the board.
  ~options: ref<Options.t>=ref(Options.default),
  ~tiltEnabled: ref<bool>=ref(true),
  // The hidden "Victory animation" flag. Read at the moment a game is won, so flipping
  // it mid-game decides what *this* win does — and a board built by a test or a demo
  // wins quietly, which is what keeps every other suite here free of a sprite build.
  ~victoryAnimation: ref<bool>=ref(false),
  // Drops the cards straight into their resting places — the URL's `?animate=off`, for
  // a shot of the already-dealt board. The layout is identical either way; only the
  // cosmetic flight is suppressed, as "reduce motion" already does. **Its name is
  // narrower than its scope**: every flight goes through `flyCards`, so this silences
  // the finish sweep and a commanded move too, which is what a deterministic test wants.
  ~skipDealAnimation: bool=false,
  game: Game.t,
): Scene.t => {
  id: game.id,
  label: game.name,
  kind: Game,
  mount: container => {
    // The board lives in its own host so a New Game re-deal can tear the whole
    // board down and rebuild it — fresh zones and card nodes, no stale leftovers
    // from the previous deal — while leaving the New Game control (below) in
    // place. Everything from the playfield down is (re)built into this host by
    // `buildBoard`.
    let boardHost = WebDom.createElement("div")
    boardHost->WebDom.setAttribute("class", "table-board")

    // Any finish-sweep flights still in the air, held at mount scope — above
    // `buildBoard` — so they survive across a re-deal's rebuild and can be cancelled
    // when the board is torn down or an undo steps back out from under them. A
    // cancelled animation doesn't fire its `onfinish`, so an interrupted sweep never
    // raises a stale win overlay; the model is already committed, so state is safe
    // regardless.
    let outstandingAnimations: ref<array<animation>> = ref([])
    let cancelOutstanding = () => {
      outstandingAnimations.contents->Array.forEach(cancel)
      outstandingAnimations := []
    }

    // The victory cascade, if one is falling. Mount scope for the same reason the
    // flights above are: a run started by one build can still be in the air when an
    // undo, a re-deal or a scene teardown arrives, and every one of those has to be able
    // to end it.
    let cascade: ref<option<cascadeRun>> = ref(None)
    // Stop the loop, take the canvas off the board, and put back the cards the run hid
    // as it launched them — in that order, so nothing is drawn onto a surface that is
    // about to be removed. Says nothing about the win: raising the panel is
    // `celebrate`'s, and a teardown wants the cascade gone *without* one.
    let endCascade = () =>
      switch cascade.contents {
      | Some(run) =>
        cascade := None
        CascadePlayer.detach(run.player)
        WebDom.remove(run.canvas)
        run.reveal()
        // The panel is a modal again the moment there is nothing falling behind it.
        classList(boardHost)->removeClass("table-board--cascading")
      | None => ()
      }

    // An autoplay in progress is the one thing on this board that spans several
    // *moves*: it commits each planned move as its own undoable step, flies the cards,
    // and only then plays the next. So anything that takes the board out from under it
    // has to be able to stop it — otherwise the run would go on stamping precomputed
    // states over a board the player has since undone, moved on, or re-dealt.
    //
    // A token rather than a flag: every interruption *bumps* it, and a run compares the
    // value it started with before each step, so a second `autoplay` typed over a
    // running one stops the first without needing to know anything about it. Held at
    // mount scope, above `buildBoard`, because a rebuild is one of the interruptions —
    // a run started on the board a New Game replaced must not keep playing into the
    // torn-down build's `state` (and its `persist`).
    let playToken = ref(0)
    let interruptPlay = () => playToken := playToken.contents + 1

    // --- The mount-scope refs -------------------------------------------------
    // Everything below belongs to a *build* but is held at *mount* scope, because
    // something set up once — the `ResizeObserver`, the shake subscription, the
    // `controls` record the chrome took at mount — has to go on driving the board
    // actually on the table. Every `buildBoard` repoints them at its own; a reader
    // that closed over one build would go on answering for a torn-down one after a
    // New Game.
    //
    // They all start as no-ops or `None`, which is the truthful answer for a board
    // not yet dealt: nothing to undo, nothing to re-lay, nowhere to dock.

    let currentGame = ref(game) // what Restart replays — the *latest* deal, not the first
    let resizeRelayout = ref(() => ())
    let dockFit: ref<float => bool> = ref(_ => false)
    let boardOps = ref({jostle: () => (), squareUp: () => ()})
    let readHistory: ref<unit => option<SaveState.t>> = ref(() => None)
    // The three published actions that genuinely belong to a build. `controls`
    // dispatches through these, which is what lets the chrome take the board's surface
    // a single time instead of each of the three being re-published on every build.
    let liveUndo: ref<unit => unit> = ref(() => ())
    let liveRunCommand: ref<Command.t => array<Render.line>> = ref(_ => [])
    let liveRelayout: ref<unit => unit> = ref(() => ())

    // The active `devicemotion` shake subscription, `Some` while Wiggle Waggle is on
    // and permission granted. `Motion.subscribeShake` already parks the
    // listener while the page is hidden and returns the unsubscribe thunk kept here.
    let shakeUnsub: ref<option<unit => unit>> = ref(None)
    let unsubscribeShake = () =>
      switch shakeUnsub.contents {
      | Some(unsub) =>
        unsub()
        shakeUnsub := None
      | None => ()
      }
    // The chrome's shake control. `start` begins listening (idempotent — a second
    // call while already subscribed is a no-op), jostling the live board on each
    // shake; `stop` ends listening and squares the board back up so the mess doesn't
    // linger once the switch is off.
    let startShake = () =>
      switch shakeUnsub.contents {
      | Some(_) => ()
      | None => shakeUnsub := Some(Motion.subscribeShake(~onShake=() => boardOps.contents.jostle()))
      }
    let stopShake = () => {
      unsubscribeShake()
      boardOps.contents.squareUp()
    }

    // Build (or rebuild) the whole board for `game` into `boardHost`. Every call
    // clears the host first, so a re-deal starts empty — none of the previous
    // deal's card nodes or drop zones survive (the tear-down New Game needs) —
    // and re-runs the same mount-time build with fresh local state (`nodes`,
    // `state`, `topZ`, `scale`). `~initial` forces a starting `GameState` (the
    // `?state=` scenario) and applies only to the opening mount; a re-deal always
    // opens from its game's own fresh deal.
    // `~history as seedHistory` seeds the opening build with a saved undo/redo
    // stack instead of a clean one — the resume path; a re-deal calls
    // `buildBoard` without it and so starts fresh. `~persistThis` gates whether this
    // particular build saves itself: on for the opening/New Game/Restart deals (each
    // becomes the saved game), off for a forced-state load so a debug scenario never
    // clobbers a real saved game (matching the URL's `?state=`).
    let rec buildBoard = (
      ~initial: option<GameState.t>=?,
      ~history as seedHistory: option<SaveState.t>=?,
      ~persistThis: bool=true,
      game: Game.t,
    ) => {
      // Cancel any finish sweep still in flight from the board being torn down, so
      // its cards stop animating and its last-card `onfinish` can't raise a win over
      // the fresh board — and stop an autoplay still walking the old board's
      // line, which the cancelled flight would otherwise hand straight on to.
      cancelOutstanding()
      interruptPlay()
      // A cascade celebrating the board being replaced goes with it — its canvas hangs
      // off the playfield the clear below drops, but its frame loop and its window
      // listener don't, and neither would notice the board had gone.
      endCascade()
      WebDom.clear(boardHost)
      // One line covering every rebuild — the opening deal, a New Game, a Restart, a
      // debug-states load — since all of them pass through here.
      DebugLog.message(
        "build board: " ++ game.id ++ (initial->Option.isSome ? " (forced state)" : ""),
      )
      currentGame := game
      // **The rule is "what's on the table *is* this deal's opening position"**, which
      // is the only claim a deal-number share can make good on. So a fresh deal reports
      // the game's seed, and a restored history or a forced state reports `None` — the
      // driver knows where either came from and fills the gap (`docs/board-driver.md`
      // § Who resolves the deal number).
      //
      // That also keeps reporting in step with saving: a seed is reported on precisely
      // the builds that become the saved game, so the driver needs no second rule.
      //
      // Named, because the session below carries the same fact for the same reason and
      // two spellings of one rule is one too many.
      let boardSeed = initial->Option.isSome || seedHistory->Option.isSome ? None : game.seed
      switch onDeal {
      | Some(report) => report(boardSeed)
      | None => ()
      }
      // The stage everything is positioned within; `position: relative` (in CSS)
      // makes it the origin for the cards' absolute left/top.
      let playfield = WebDom.createElement("div")
      playfield->WebDom.setAttribute("class", "stacking-playfield")
      boardHost->WebDom.appendChild(playfield)->ignore

      // The drop zones, laid out in role-grouped rows so a sixteen-pile
      // FreeCell board is playable: free cells and foundations across the top,
      // cascades below. The rows stack in a flex *column* (`.drop-rows`), so the
      // cascade row is pushed clear of the top row automatically and its fans grow
      // into the space beneath. A board that carries only one of the two groups
      // collapses to a single row. Each row lays itself out with flexbox, so a zone's live
      // rect (read at drop time) reflects wherever the browser placed it — nothing
      // cached up front to go stale on resize.
      let rows = WebDom.createElement("div")
      rows->WebDom.setAttribute("class", "drop-rows")
      playfield->WebDom.appendChild(rows)->ignore

      let makeRow = () => {
        let row = WebDom.createElement("div")
        row->WebDom.setAttribute("class", "drop-row")
        rows->WebDom.appendChild(row)->ignore
        row
      }

      // A cascade lands on the bottom row, a free cell or foundation on the top —
      // but only when the board actually mixes the two groups. With just one group
      // present, everything shares a single row (`bottomRow` aliases `topRow`).
      let hasTop = game.piles->Array.some((p: Game.pile) => p.role != Game.Cascade)
      let hasBottom = game.piles->Array.some((p: Game.pile) => p.role == Game.Cascade)
      let twoRows = hasTop && hasBottom
      let topRow = makeRow()
      let bottomRow = twoRows ? makeRow() : topRow
      let rowFor = (pile: Game.pile) => twoRows && pile.role == Game.Cascade ? bottomRow : topRow

      // One zone per pile in the game, in model order, each carrying its declared
      // stacking behaviour and dropped into its role's row. The `.drop-row`
      // flexbox (`space-evenly`) spreads a row's zones across the stage, so the
      // view never counts them.
      let zones = game.piles->Array.mapWithIndex((pile: Game.pile, index) => {
        let el = WebDom.createElement("div")
        el->WebDom.setAttribute("class", "drop-zone")
        // The static "empty pile" indicator: a purely-visual, card-sized
        // dashed placeholder, split off from the zone's old overloaded outline. A
        // resting card (a sibling `.stacking-card` layered above) occludes it
        // pixel-for-pixel, so the dashed cue shows only on empty piles, while the
        // `.drop-zone` around it stays the hit-test box and the larger highlight
        // frame. `pointer-events: none` (in CSS) keeps it out of hit-testing.
        let slot = WebDom.createElement("div")
        slot->WebDom.setAttribute("class", "drop-zone__slot " ++ slotRoleClass(pile.role))
        el->WebDom.appendChild(slot)->ignore
        rowFor(pile)->WebDom.appendChild(el)->ignore
        {el, index, stacking: pile.stacking}
      })

      // The widest row's pile count drives the card scale below: with the piles
      // split across two rows, cards need only shrink to fit the busier row, not
      // the whole board. A single-row board's widest row is all its piles.
      let widestRow = if twoRows {
        let cascades = game.piles->Array.filter((p: Game.pile) => p.role == Game.Cascade)
        Math.Int.max(Array.length(cascades), Array.length(game.piles) - Array.length(cascades))
      } else {
        Array.length(game.piles)
      }

      // The single source of truth for this board. The view re-derives every pile's
      // layout from its present state and keeps only transient geometry.
      //
      // **A move hands an action to `Session.dispatch` and the view adopts what comes
      // back** — settling, the undo step, the tally and the clock are that one call,
      // the same one the terminal makes. Three sites move a card here, so stepping
      // written out at each is three copies to keep in lockstep, and the field one of
      // them forgets is the one nothing notices.
      let session = ref(
        switch seedHistory {
        | Some(saved) => Session.restore(~seed=boardSeed, ~options=options.contents, game, saved)
        | None =>
          Session.open_(
            ~clock,
            ~options=options.contents,
            ~seed=boardSeed,
            game,
            initial->Option.getOr(GameState.initial(game)),
          )
        },
      )

      // A function rather than a stored value, so the session stays the one answer.
      let state = () => Session.present(session.contents)

      // The house rules live at mount scope and outlive any one board — a New Game
      // doesn't change the rules you're playing under — so they're the driver's to
      // carry and the session's to consult, the split the terminal draws too.
      let current = () => Session.withOptions(session.contents, options.contents)

      // Read at call time, so a caller always gets the board as it now stands.
      let currentSave = (): SaveState.t => Session.save(session.contents)

      // Point the mount-scope reader at *this* build's save, so the share button
      // encodes the board on the table rather than one a re-deal has since replaced.
      readHistory := (() => Some(currentSave()))

      // A no-op unless the driver wired a `~persist` sink, which it does only for the
      // opens that save (`docs/board-driver.md` § Which opens touch storage).
      let persistCurrent = () =>
        switch persist {
        | Some(save) => save(currentSave())
        | None => ()
        }

      // The identity bridge from a model card to its node, so a pile derived from
      // `state` lays out onto the *same* elements every reflow.
      let nodes: array<card> = []
      let nodeFor = (data: Deck.card) => nodes->Array.find(n => GameState.sameCard(n.data, data))

      // Drop the per-card delay/duration a finish sweep borrowed, so a later drop
      // re-tilts immediately rather than on the dead sweep's schedule. Called wherever
      // a sweep can end — its own settle, or an undo cutting it short.
      let clearTiltTimings = () => nodes->Array.forEach(c => clearTiltTiming(c.wrapper))

      // The depth the height fit sizes the deepest fan to. **Captured once**, from the
      // opening state, so cards keep a stable size as piles grow and shrink through
      // play; a New Game rebuild recomputes it for that deal.
      let hasFanned = game.piles->Array.some((p: Game.pile) => p.stacking == Game.Fanned)
      let openingMaxDepth =
        zones->Array.reduce(0, (m, z) =>
          Math.Int.max(m, Array.length(GameState.cardsInPile(state(), z.index)))
        )
      let referenceDepth = openingMaxDepth + TableLayout.fanHeadroom

      // The live scale every design footprint is multiplied by — `TableLayout.scaleFor`
      // computes it; this is where it's kept, in a ref because the reflow and the deal
      // both read it.
      let scale = ref(1.)
      // Zero until the first `deal` runs, which is what gates the resize relayout below.
      let lastWidth = ref(0.)
      let applyScale = () => {
        // Everything this function does is measure, ask and publish. The two fits and
        // the clamp between them are `TableLayout.scaleFor`; what's left here is the
        // measuring, which is the part that needs the page.
        //
        // The stage width already excludes the nav rail — `playfield` is laid out
        // beside it, not under it — so the only term left to subtract is the display
        // cutaway: the safe-area insets `.drop-rows` is pinned inside. Size the
        // cards to that inset width, never the raw stage, or a landscape phone with a
        // side notch sizes its columns for width they don't get and packs them
        // together, `space-evenly` gaps squeezed to nothing. Off a cutout device the
        // insets are 0, so `avail == width`.
        let width = boundingRect(playfield).width
        let cs = getComputedStyle(rows)
        let cutaway = parseFloat(cs["left"]) +. parseFloat(cs["right"])
        let avail = width -. cutaway
        // The height fit's fixed term: the rows' `top` offset, plus the inter-row gap
        // on a two-row board.
        let vFixed = parseFloat(cs["top"]) +. (twoRows ? parseFloat(cs["rowGap"]) : 0.)

        TableLayout.scaleFor(
          ~avail,
          ~availH=boundingRect(playfield).height,
          ~vFixed,
          ~widestRow,
          ~rowsCount=twoRows ? 2 : 1,
          ~fanExtent=TableLayout.fanExtent(~hasFanned, ~referenceDepth),
        )->Option.forEach(next => scale := next)

        if width > 0. {
          lastWidth := width
        }
        // Publish every scaled footprint the CSS needs, so `.stacking-card`,
        // `.drop-zone` and `.drop-zone__slot` resize in step with the JS geometry
        // below. Which numbers those are is `TableLayout.cssVars`; the `px` suffix
        // goes on here, because it is CSS's.
        let s = style(playfield)
        TableLayout.cssVars(~scale=scale.contents, ~widestRow)->Array.forEach(((name, value)) =>
          s->setProperty(name, Float.toString(value) ++ "px")
        )
      }

      // The dock-refusal test for *this* board: could it give up `inset` px of
      // stage width and still deal cards above `minScale`? The arithmetic is
      // `TableLayout.fitsDock`; the measuring is here.
      //
      // Measured off `container`, the scene box the board is laid into, rather than off
      // `playfield`: the playfield is exactly what docking narrows, so reading it would
      // ask whether an *already docked* board could dock again, and undocking-then-
      // redocking would ratchet the board away. The container's width doesn't move.
      dockFit :=
        (
          inset => {
            let stage = boundingRect(container).width
            let cs = getComputedStyle(rows)
            let cutaway = parseFloat(cs["left"]) +. parseFloat(cs["right"])
            TableLayout.fitsDock(~stage, ~cutaway, ~inset, ~columns=widestRow)
          }
        )

      // The zone the dragged card's rect hits, if any. `TableLayout.hits` is the rule;
      // what's here is the search, which measures each zone's rect as it goes rather
      // than caching them, since flexbox may have moved one since the last look.
      let zoneAt = (cardRect: TableLayout.rect) =>
        zones->Array.find(({el}) => TableLayout.hits(~card=cardRect, ~zone=boundingRect(el)))

      // Write a card's live x/y into its style.
      let place = c => {
        let s = style(c.wrapper)
        s->setLeft(Float.toString(c.x.contents) ++ "px")
        s->setTop(Float.toString(c.y.contents) ++ "px")
      }

      // Z-order is a single monotonic counter: whatever was touched most recently
      // (created, grabbed, or dropped) sits on top. Because cards join a pile at
      // grab time — and only the top card can be grabbed — a pile's slot order
      // and its z-order always agree, so stacked cards, free cards and the card
      // in hand all layer coherently without any per-slot bookkeeping.
      let topZ = ref(0)
      let bringToFront = el => {
        topZ := topZ.contents + 1
        style(el)->setZIndex(Int.toString(topZ.contents))
      }

      // Re-lay a zone's pile from scratch: every card squares up on the zone
      // centre, then Fanned cards step *down* by their slot so the newest lands
      // lowest and fully exposed. Only the top (last) card stays draggable; the
      // rest are marked buried, and in a Squared pile — where they're not on
      // screen at all — hidden from the accessible tree too. Reading the
      // rects live keeps the maths correct wherever flexbox placed the zone.
      //
      // Cards centre within the base box (`zoneBaseHeight`), *not* the zone's live
      // height — a fanned zone is then grown *downward* to enclose its whole fan
      // (below), and using the base height here keeps that growth from feeding back
      // and shifting the cards on the next reflow.
      let reflow = zone => {
        let pr = boundingRect(playfield)
        let zr = boundingRect(zone.el)
        // The pile's cards come straight from the model now, bottom-first, and are
        // mapped back onto their nodes by identity — the card's slot is its index.
        let cards = GameState.cardsInPile(state(), zone.index)
        let count = Array.length(cards)
        // The pile's stacking rule, consulted to decide which cards head a
        // legal run and so may be lifted as a supermove span.
        let rule = switch game.piles->Array.get(zone.index) {
        | Some(p) => p.rule
        | None => Rules.Free
        }
        cards->Array.forEachWithIndex((data, i) =>
          switch nodeFor(data) {
          | Some(c) =>
            let cr = boundingRect(c.wrapper)
            let baseX = zr.left +. zr.width /. 2. -. cr.width /. 2. -. pr.left
            let baseY =
              zr.top +.
              TableLayout.zoneBaseHeight *. scale.contents /. 2. -.
              cr.height /. 2. -.
              pr.top
            c.x := baseX
            c.y :=
              switch zone.stacking {
              | Game.Squared => baseY
              | Game.Fanned => baseY +. Int.toFloat(i) *. TableLayout.fanStep *. scale.contents
              }
            place(c)
            // Re-tilt the card for where it now rests: stable while the pile
            // sits still, freshly angled when a drop lands it in a new slot, and
            // dead-square if the player has turned the hand-placed look off.
            applyTilt(
              c.wrapper,
              ~degrees=tiltFor(
                ~enabled=tiltEnabled.contents,
                ~card=data,
                ~pile=zone.index,
                ~slot=i,
              ),
            )
            // Layer by slot so the pile stacks bottom-to-top regardless of the order
            // the nodes were created in. During normal play slot order already
            // matches creation order, but a forced state (a `?state=` scenario) moves
            // cards into piles they weren't dealt into, so without this a Squared
            // pile would show whichever card happened to be created last, not its
            // real top card. `bringToFront` still lifts a card above these while it's
            // dragged; the next reflow settles the pile back to slot order.
            style(c.wrapper)->setZIndex(Int.toString(i))
            // A card is grabbable when it *heads a legal run*: the tail from
            // its slot to the top of the pile must itself be a run under the pile's
            // rule. The top card is the length-1 case (a run of one), so single-card
            // play is unchanged; a deeper run-head lifts its whole span as a
            // supermove. Every other buried card stays pinned.
            let headsRun = Rules.isRun(rule, cards->Array.slice(~start=i, ~end=count))
            c.draggable := headsRun
            headsRun
              ? classList(c.wrapper)->removeClass("stacking-card--buried")
              : classList(c.wrapper)->addClass("stacking-card--buried")
            // Take the cards this pile *hides* out of the accessible tree.
            // Every card is a `role="img"` with an `aria-label` (see `CardArt`), and a
            // Squared pile draws its whole contents on one spot — so a screen reader
            // was read the cards behind the top one as if they were on the table: six
            // of them mid-game, and forty-eight of fifty-two on a won board, whose
            // four foundations show exactly four cards. Only the top card is visible,
            // so only the top card is announced.
            //
            // Fanned piles are untouched: every card there keeps a visible edge, so
            // every card is something the player can actually see. Free cells hold one
            // card and so never occlude. Derived here from the live pile like the rest
            // of the layout, so the mark tracks the board — a card sent home goes quiet
            // as the next one covers it, and an undo brings it back.
            let covered = zone.stacking == Game.Squared && i < count - 1
            covered
              ? c.wrapper->WebDom.setAttribute("aria-hidden", "true")
              : c.wrapper->WebDom.removeAttribute("aria-hidden")
          | None => ()
          }
        )
        // Grow a fanned zone so its outline (and the drop highlight) covers the
        // fan that spills below the base box; a squared or empty zone keeps the
        // base height. `zoneAt` hit-tests this same box, so the whole fanned pile
        // becomes the drop target too, not just the foundation.
        let fanExtent = switch zone.stacking {
        | Game.Fanned if count > 1 =>
          Int.toFloat(count - 1) *. TableLayout.fanStep *. scale.contents
        | _ => 0.
        }
        style(zone.el)->setHeight(
          Float.toString(TableLayout.zoneBaseHeight *. scale.contents +. fanExtent) ++ "px",
        )
      }

      // Re-derive every pile from the current `state`. Cheap for a handful of zones,
      // and it always reflows both ends of a move (the pile a card left and the one
      // it joined) without the view tracking which those were.
      let reflowAll = () => zones->Array.forEach(reflow)

      // Run `body` with the cards' left/top snap transition switched off (the
      // `.stacking-playfield.dealing` rule), restoring it a frame later — once the
      // new left/top are committed without animating. Both flight paths reposition
      // cards and then fly them there on a `transform`: the snap transition must be
      // off for that window or it animates left/top start → end at the same time and
      // fights the flight (a card overshoots to `2·start − end` and slides back). The
      // transform animations run on independently of the class. Used by the opening
      // deal and the finish sweep.
      let withSnapSuppressed = body => {
        classList(playfield)->addClass("dealing")
        body()
        requestAnimationFrame(() => classList(playfield)->removeClass("dealing"))->ignore
      }

      // Every way a card can move — a drop, a send-home, a typed command, a step of a
      // solver's line — ends in a `Session.change`, and this is the one thing that turns
      // one into a sentence. That's why a change carries its `action`: the move a typed
      // command made is one this file never saw, and it still has to be able to say it.
      //
      // **One line per move**, not two: the move is a sentence with a ✓ on the end of
      // it, and only a *rejection* spends a second line saying why, in `core`'s own
      // words so a refusal reads the same in a terminal.
      //
      // Built only when something is listening. `DebugLog`'s own calls short-circuit on
      // that, but this composes a document *before* calling one, so it checks first.
      let narrate = (~before: GameState.t, change: Session.change) => {
        if DebugLog.enabled() {
          let accepted: Render.span = {text: " ✓", ink: Render.Title}
          let refused: Render.span = {text: " ✗", ink: Render.Plain}
          // A lawful no-op — an identity re-drop onto the pile a card already
          // tops — is accepted with the board untouched. It keeps the ✓; saying nothing
          // changed is what stops the log reading as a move that did something (it
          // records no undo step either).
          let noChange: Render.span = {text: " (no change)", ink: Render.Plain}
          switch change {
          | Session.Settled({action, collected}) =>
            let mark = GameState.equal(state(), before) ? [accepted, noChange] : [accepted]
            DebugLog.line(Array.concat(Render.action(~game, action), mark))

            // The collection is its own line, and only when it actually sent cards home:
            // an empty sweep is the common no-op and isn't worth one.
            if Array.length(collected) > 0 {
              DebugLog.line(
                Render.concat([[Render.plain("auto-collect ")], Render.cardSpans(collected)]),
              )
            }
          | Session.Rejected({action, error}) =>
            DebugLog.line(Array.concat(Render.action(~game, action), [refused]))
            DebugLog.line([Render.plain(`  ${Command.reason(error)}`)])
          // A house rule that refused before the reducer saw it, a step through history,
          // a board simply shown: none of those is a move, and the verbs that ask for
          // them say so themselves.
          | _ => ()
          }
        }
      }

      // The pointer paths — a drop, the double-tap send-home — come through here; a
      // typed command reaches the same `Session.dispatch` via `Session.step`.
      let dispatch = (action: Reducer.action): Session.change => {
        // Autoplay's own steps are committed by the session and never come through
        // here, which is what makes this the clean "the player did something" signal —
        // and a move of the player's own takes the board off the line a run was walking.
        interruptPlay()
        let before = state()
        let (next, change) = Session.dispatch(~clock, current(), action)
        session := next
        narrate(~before, change)
        change
      }

      // The panel is `<WinOverlay>`; what lives here is *when* it is raised and torn
      // down, which is the half that needs this closure. Appended to `boardHost`, so
      // `buildBoard` clearing that host is also what stops a panel lingering onto the
      // next board.
      //
      // It **reports** the clock and the tally but doesn't take either: both were
      // settled by the move that won, which is why raising a panel saves nothing.
      // **Whether the victory has taken over the board**, which is not the same question
      // as whether the panel is on screen: a cascade takes the board over for forty
      // seconds before raising anything, and a tap can put the panel away again while
      // the cards are still falling. `updateFinishButton` is why the distinction has
      // teeth — an already-won board is still `canFinish` (draining it wins it again),
      // so without this the Finish button would offer itself over the celebration.
      let winShown = ref(false)
      // The panel, while it is actually up. Kept so undo can tear it down when stepping
      // back out of a win, and so a tap can toggle it over a running cascade.
      let winOverlay = ref(None)

      // Say the game is won, once. A tap that brings the panel back is not the game
      // being won again, which is why this is its own step rather than the panel's.
      let announceWin = () =>
        if !winShown.contents {
          DebugLog.message("win")
          winShown := true
        }

      let raiseWin = () =>
        if winOverlay.contents->Option.isNone {
          // **The clock stopped when the board was won, not here** — the session stamps
          // it as it records the winning move, so the number is how long the game took
          // rather than how long the last card took to fly. Both numbers are read
          // *now*, as the panel goes up, so they describe the game just won: undoing
          // back out and playing on raises a fresh panel with the larger numbers.
          let overlay = Html.create(
            WinOverlay.make({
              time: Timing.summary(session.contents.timing),
              tally: Stats.summary(session.contents.stats),
              onNewGame: () =>
                switch newDeal {
                | Some(freshDeal) => buildBoard(freshDeal())
                | None => buildBoard(game)
                },
              // Offered only when the driver has a deal to hand out, and withheld
              // entirely from a game the solver had a hand in. That second half is why
              // the tally counts autoplays at all: it's the one fact about a game that
              // has to survive every undo back past the solver's moves, which it does
              // because `Stats` only ever counts up.
              share: switch winShare {
              | Some(offer) if offer.available() && !Stats.usedAutoplay(session.contents.stats) =>
                Some({
                  onShare: () =>
                    offer.share(
                      ~moves=session.contents.stats.moves,
                      ~undos=session.contents.stats.undos,
                    ),
                })
              | _ => None
              },
            }),
          )
          boardHost->WebDom.appendChild(overlay)->ignore
          winOverlay := Some(overlay)
        }

      // The victory, announced and shown. Idempotent in both halves and separately so:
      // a cascade announces the win when it starts and raises the panel forty seconds
      // later, and between those two a tap may have raised it already.
      let showWin = () => {
        announceWin()
        raiseWin()
      }

      // The panel off the screen, without conceding that the game is still on. That is
      // the whole difference between this and `removeWinOverlay` below: a tap over a
      // running cascade wants the message out of the way, not the victory taken back.
      let hideWin = () =>
        switch winOverlay.contents {
        | Some(overlay) =>
          WebDom.remove(overlay)
          winOverlay := None
        | None => ()
        }

      // Clears the flag too, so a later win can raise the panel again. The clock starts
      // again with it, but not from here: stepping the *session* back is what clears
      // the won-at, because a board that isn't won hasn't been.
      let removeWinOverlay = () => {
        hideWin()
        winShown := false
      }

      // What a tap on a running cascade does. **It doesn't skip** — the cards go on
      // falling either way; all that moves is whether the message is over them. Reading
      // the panel rather than a flag of its own is what keeps the two from disagreeing.
      let toggleWin = () =>
        switch winOverlay.contents {
        | Some(_) => hideWin()
        | None => showWin()
        }

      // --- The victory cascade --------------------------------------------------
      // The Windows 3.1 payoff: the foundations give their cards up one at a time and
      // each one bounces its way off the table, leaving a trail behind it. The motion,
      // the sprite sheet, the frame loop and the resize policy are all
      // `CascadePlayer`'s — `docs/cascade.md` is the model. What belongs *here* is the
      // board's half: which cards fall, from where, and every way a run can end.

      // The one exit every cascade takes, however it got there — it emptied the
      // foundations, an undo stepped out of the victory, a resize wiped the surface, the
      // sprites never arrived. The panel is the point; the cascade plays in front of it,
      // and a tap can bring it forward without ending anything.
      let finishCascade = () => {
        endCascade()
        showWin()
      }

      // Each foundation as the cascade needs it: where its cards fall from, in
      // card-widths, paired with the cards themselves. The seat is the resting spot of
      // the pile's own top card — a Squared pile draws every card it holds on that one
      // spot, so one reading serves the whole pile, and it is the pixel the DOM has
      // been drawing there, so a sprite takes over exactly where its node left off.
      let foundationPiles = () => {
        let cardWidth = TableLayout.cardW *. scale.contents
        game.piles
        ->Array.mapWithIndex((pile: Game.pile, index) => (pile.role, index))
        ->Array.filterMap(((role, index)) =>
          switch role {
          | Game.Cascade | Game.FreeCell => None
          | Game.Foundation =>
            let cards = GameState.cardsInPile(state(), index)
            // An empty foundation has nothing to give up, and no node to read a seat
            // off either — so it contributes neither cards nor a seat, rather than a
            // seat nothing ever launches from.
            cards
            ->Array.at(-1)
            ->Option.flatMap(nodeFor)
            ->Option.map(node => (
              (node.x.contents /. cardWidth, node.y.contents /. cardWidth),
              cards,
            ))
          }
        )
      }

      // The deck in the order a won game gives it up: King first, one pile at a time,
      // round-robin. **That round-robin is what seats each card**: `Cascade` launches
      // card `i` from seat `i mod seats`, so taking the piles in the same turn is what
      // makes a card fall from the foundation it was resting on. A won board gives
      // every foundation the same depth, which is what keeps the two in step.
      let cascadeOrder = piles => {
        let depth = piles->Array.reduce(0, (m, (_, cards)) => Math.Int.max(m, Array.length(cards)))
        let ordered = []
        for slot in depth - 1 downto 0 {
          piles->Array.forEach(((_, cards)) =>
            switch cards[slot] {
            | Some(card) => ordered->Array.push(card)
            | None => ()
            }
          )
        }
        ordered
      }

      // Raise the cascade over the live board. The canvas covers the *playfield*, not
      // the board host, so it shares an origin with the cards' own left/top and a
      // flight starts at the very pixel its node was resting on — no conversion to get
      // wrong. It layers above the cards and below the panel it ends with
      // (`.table-cascade` in `TableScene.css`).
      //
      // **It takes pointer events**, which is the one way it differs from the demo
      // scene's overlay: a tap anywhere skips to the panel. It is in the DOM from the
      // moment the win lands rather than from the first card, so a tap lands during the
      // sprite build too — otherwise a slow first build reads as a hang on the most
      // emotionally loaded screen in the app.
      let startCascade = () => {
        let piles = foundationPiles()
        let canvas = Canvas.make()
        let canvasEl = Canvas.element(canvas)
        canvasEl->WebDom.setAttribute("class", "table-cascade")
        playfield->WebDom.appendChild(canvasEl)->ignore
        // Marks the board for the length of the run, which is what turns the win panel
        // from a modal into a peek: the scrim stops hit-testing so a tap on it reaches
        // the canvas underneath (see `.table-board--cascading`).
        classList(boardHost)->addClass("table-board--cascading")

        // The nodes the run has hidden, so ending it anywhere puts every one of them
        // back — an undo mid-cascade returns to a board with all its cards on it.
        let flown: array<card> = []
        let reveal = () =>
          flown->Array.forEach(c => classList(c.wrapper)->removeClass("stacking-card--flown"))

        let player = CascadePlayer.attach(
          ~canvas,
          ~options={
            ...CascadePlayer.defaults,
            cards: Some(cascadeOrder(piles)),
            // The deal the board is showing, so one game's victory always falls the
            // same way; a board with no number to name takes the demo's own seed.
            seed: currentDeal()->Option.getOr(CascadePlayer.defaults.seed),
            cardWidth: TableLayout.cardW *. scale.contents,
            launchpad: CascadePlayer.At(piles->Array.map(((seat, _)) => seat)),
          },
          // Hide each card as its copy leaves, so the foundation empties under the
          // cascade rather than sitting full behind it.
          ~onLaunch=card =>
            nodeFor(card)->Option.forEach(c => {
              flown->Array.push(c)
              classList(c.wrapper)->addClass("stacking-card--flown")
            }),
          ~onChange=status =>
            switch status.phase {
            // The three ways a run stops without being skipped, and they all end the
            // same: the last card left, a resize wiped the surface (rescaling a painted
            // trail isn't worth it), or the sprite sheet never arrived. **A failed
            // build degrades rather than throwing** — a won game must never be held up
            // by its celebration failing to load.
            | CascadePlayer.Settled | Interrupted | Failed(_) => finishCascade()
            | Building | Running | Posed => ()
            },
        )
        canvasEl->WebDom.addEventListener("pointerdown", toggleWin)
        cascade := Some({player, canvas: canvasEl, reveal})
        CascadePlayer.start(player)
      }

      // **A win as it happens**, as against one restored from storage — which is the
      // whole distinction between this and the bare `showWin` below it. Three things
      // send a live win down the quiet path anyway: the hidden flag is off, the OS asks
      // for reduced motion, or a panel is already up. All three land on the same
      // `showWin` the cascade itself ends with.
      let celebrate = () =>
        switch cascade.contents {
        // Already celebrating. Every call site guards on `Session.hasWon`, so this only
        // catches a second ask about the *same* win — which is one cascade, not two.
        | Some(_) => ()
        | None =>
          if (
            winShown.contents ||
            !victoryAnimation.contents ||
            matchMedia("(prefers-reduced-motion: reduce)")["matches"]
          ) {
            showWin()
          } else {
            // Announced up front rather than when the panel finally goes up: the game is
            // won *now*, and everything that reads `winShown` — the Finish button most
            // of all — has forty seconds of cascade to be wrong for otherwise.
            announceWin()
            startCascade()
          }
        }

      let reportHistory = () =>
        switch onHistory {
        | Some(f) => f(Session.canUndo(session.contents))
        | None => ()
        }

      // All that's left once the session has taken a change. **The recording is not
      // here**: one undoable step per accepted move, one move on the tally per step,
      // the clock stamped on a win — all `Session.dispatch`'s, which is what makes the
      // drop, the send-home, the typed command and the terminal agree by construction
      // rather than by four places remembering to.
      let afterChange = () => {
        reportHistory()
        persistCurrent()
      }

      // The shared flight path: fly cards to wherever the *already-committed* `state`
      // says they now rest. Where the two timings come from, what rides along, and the
      // three ways this collapses to an instant `reflowAll`: `docs/animation-timing.md`.
      //
      // The mechanism is `animateDeal`'s inverse-offset trick — capture each card's
      // current spot, let `reflowAll` snap every node onto its new home, then animate
      // the transform back from (start − end) to zero. **The z-hold is what that trick
      // costs**: `reflowAll` relayers every pile by slot the instant it runs, so
      // without it a departing card drops behind the fan it is still visually atop.
      let flyCards = (movedCards: array<Deck.card>, ~flight: float, ~stagger: float, ~onDone) => {
        let reduceMotion = matchMedia("(prefers-reduced-motion: reduce)")["matches"]
        let cards = movedCards->Array.filterMap(nodeFor)
        let n = Array.length(cards)
        if reduceMotion || skipDealAnimation || n == 0 {
          reflowAll()
          onDone()
        } else {
          // Reflow-and-launch with the left/top snap transition suppressed: the
          // inverse-offset trick needs `reflowAll` to move each node onto its new
          // slot *instantly*, or the snap transition fights the flight (see
          // `withSnapSuppressed`). The transform flights run on past that window.
          withSnapSuppressed(() => {
            // Each card's resting spot *and resting layer* before the flight, captured
            // before `reflowAll` moves its node to its destination and relayers every
            // pile by slot. The z-index matters as much as the position: a card holds
            // at its start (via `fill: "backwards"`) until its staggered turn, so a
            // still-resting source fan must keep its own slot order until then —
            // restoring `sz` below stops the relayer from inverting those fans (or
            // dropping a departing card behind the fan it's leaving) the instant the
            // flight starts.
            let starts =
              cards->Array.map(c => (c, c.x.contents, c.y.contents, style(c.wrapper)->zIndex))
            // The caller's stagger, under the name the loops below use. Both timings
            // have to be in hand *before* the reflow, because each card's tilt timing
            // has to be in place by the time `reflowAll` re-tilts it.
            let delta = stagger
            // Hold each card at its *source* angle until it launches, then turn it to
            // its destination angle over the flight. Before the `reflowAll`
            // below, which is what applies the new angle, and on the same index as the
            // flight loop, so a card's rotation and its flight start together.
            cards->Array.forEachWithIndex((c, i) =>
              setTiltTiming(c.wrapper, ~delay=Int.toFloat(i) *. delta, ~duration=flight)
            )
            // Snap every node to its new slot; the flights below are a visual
            // catch-up over nodes that already "belong" there.
            reflowAll()
            starts->Array.forEachWithIndex(((c, sx, sy, sz), i) => {
              // Hold this node at its *resting* layer for now: `reflowAll` above
              // relayered it by its new slot, which would scramble the source fan it
              // hasn't left yet. It waits at `sz` (via the z animation's absent
              // before-phase) until its staggered turn, then that animation lifts it
              // above the board for the flight and landing (see `animateZ`).
              style(c.wrapper)->setZIndex(sz)
              let delay = Int.toFloat(i) *. delta
              let anim = flyHome(
                ~wrapper=c.wrapper,
                ~dx=sx -. c.x.contents,
                ~dy=sy -. c.y.contents,
                ~flight,
                ~delay,
              )
              outstandingAnimations.contents->Array.push(anim)
              // Lift the card above the board the moment it launches, and land it on
              // top of whatever is already there: an ascending `+ i` so cards in flight
              // together (and the piles they land on) stack in arrival order — in a
              // sweep, King last. `fill: "forwards"` keeps this out of the pre-launch
              // wait, so the resting `sz` above shows until this card's turn. This is
              // also what carries a card *over* the fan it's leaving rather than under
              // it, which is the whole reason a one-card console move comes here.
              let flightZ = Int.toString(finishFlightZBase + i)
              let zAnim =
                c.wrapper->animateZ(
                  [{"zIndex": flightZ}, {"zIndex": flightZ}],
                  {"duration": flight, "delay": delay, "fill": "forwards"},
                )
              outstandingAnimations.contents->Array.push(zAnim)

              // The last card to launch is the last to land (every flight is the same
              // length), so its finish is the whole batch's finish. Drop the raised
              // flight layers (cancelling reverts each node to its inline z) and settle
              // every pile to slot order, then hand back to the caller.
              if i == n - 1 {
                anim->setOnFinish(
                  () => {
                    cancelOutstanding()
                    // Every card has landed at its final angle, so the deferred tilt
                    // timing has served its purpose; the settling reflow below
                    // re-applies the same angles, so this drops nothing.
                    clearTiltTimings()
                    reflowAll()
                    onDone()
                  },
                )
              }
            })
          })
        }
      }

      // The finishing sweep's flight: cards flying home one at a time from
      // wherever they rest, with `onDone` raising the win overlay so the victory reads
      // as the sweep's payoff.
      let animateFinish = (movedCards: array<Deck.card>, ~onDone) => {
        let (stagger, flight) = staggerTiming(
          ~maxInFlight=finishMaxInFlight,
          ~perCardMs=finishPerCardMs,
          ~n=Array.length(movedCards),
        )
        flyCards(movedCards, ~flight, ~stagger, ~onDone)
      }

      // The same flight for a move nobody dragged — a command typed into the debug
      // console.
      let animateCommand = (movedCards: array<Deck.card>, ~onDone) => {
        let (stagger, flight) = staggerTiming(
          ~maxInFlight=commandMaxInFlight,
          ~perCardMs=commandPerCardMs,
          ~n=Array.length(movedCards),
        )
        flyCards(movedCards, ~flight, ~stagger, ~onDone)
      }

      // …and one more for a move the *solver* played. One call per planned move,
      // chained on `onDone` so the next only starts once these cards have landed — which
      // is what makes the line read as a game being played rather than as a board that
      // changed by itself.
      let animateAutoplayStep = (movedCards: array<Deck.card>, ~onDone) => {
        let (stagger, flight) = staggerTiming(
          ~maxInFlight=autoplayMaxInFlight,
          ~perCardMs=autoplayPerCardMs,
          ~n=Array.length(movedCards),
        )
        flyCards(movedCards, ~flight, ~stagger, ~onDone)
      }

      // The end-game "Finish" button — the same show-when-relevant shape as the win
      // overlay above, appearing exactly when `Session.canFinish` says victory is one
      // tap away. Held in a ref so `updateFinishButton` can add or remove it as that
      // flips after each move; `winShown` hides it once the overlay has taken over.
      let finishButton = ref(None)
      let removeFinishButton = () =>
        switch finishButton.contents {
        | Some(btn) =>
          WebDom.remove(btn)
          finishButton := None
        | None => ()
        }

      // The *view's* half of a sweep: the session has already taken it — one undoable
      // step, the clock stamped if it won — so what's left is to say it, save it and
      // fly it. Shared by the Finish button and the typed `finish` verb, which reach
      // the sweep by different routes and have to land it the same way.
      let flySweep = (moved: array<Deck.card>) => {
        DebugLog.line(Render.concat([[Render.plain("finish ")], Render.cardSpans(moved)]))
        afterChange()
        removeFinishButton()
        // A staggered flight rather than an instant jump, so the celebration lands only
        // once the last card has arrived.
        animateFinish(moved, ~onDone=() =>
          if Session.hasWon(session.contents) {
            celebrate()
          }
        )
      }

      let playFinish = () => {
        // The sweep takes the board somewhere no planned move goes, so it ends any
        // autoplay still walking a line. Autoplay's own hand-over to the sweep
        // happens after its last step, so this only ever stops a run someone reached
        // past — the Finish button (or a typed `finish`) pressed mid-line.
        interruptPlay()
        let (next, outcome) = Session.finish(~clock, current())
        session := next
        switch outcome.change {
        | Session.Swept({moved}) =>
          flySweep(moved)
          moved
        | _ => [] // unreachable: every caller checks `canFinish` before asking
        }
      }

      let updateFinishButton = () =>
        if winShown.contents || !Session.canFinish(session.contents) {
          removeFinishButton()
        } else {
          switch finishButton.contents {
          | Some(_) => () // already shown
          | None =>
            // One button, raised and removed whole like the win panel above, so it's
            // built the same way — as markup through `Html.create` rather than four
            // `setAttribute` calls. It stays here rather than becoming a component of
            // its own: the markup is a line, and the part worth naming is the rule
            // above it, which reads `winShown` and the session and so belongs to this
            // closure.
            let btn = Html.create(
              <button className="finish-button" type_="button" onClick={_ => playFinish()->ignore}>
                {Html.string("Finish")}
              </button>,
            )
            boardHost->WebDom.appendChild(btn)->ignore
            finishButton := Some(btn)
          }
        }

      // The shared tail of undo and redo. It **re-derives** the layout rather than
      // animating: a step through history isn't a *move*, and easing cards along a path
      // they never took would misreport what happened.
      let adoptHistoryPresent = () => {
        // A sweep still in flight would keep flying toward foundations the step has
        // just emptied, and an autoplay would keep playing forward — but a step through
        // history is the player saying they'd like the board back. (The state is
        // already committed either way, so nothing corrupts.)
        cancelOutstanding()
        interruptPlay()
        // A cascade in the air belongs to a victory the step has just walked out of, so
        // it ends with the rest of them — putting back every card it had already flung
        // off the table.
        endCascade()
        // …including the tilt timing a cut-short sweep left on its cards, or the
        // restored angles arrive on the dead sweep's schedule.
        clearTiltTimings()
        reflowAll()
        updateFinishButton()
        reportHistory()
        // The redo stack too, so a reload resumes exactly where the step left it.
        persistCurrent()
      }

      // Bring the view to whatever position the session now holds after a step through
      // history, whoever asked for one: the top bar's button, or a typed verb.
      //
      // **Symmetric in the win overlay, and it has to be**: undoing out of a victory
      // takes the panel down, and redoing back into the winning move raises it again.
      //
      // Raises it *quietly*, though — `showWin`, never `celebrate`. A step through
      // history is a position being restored, not a game being won, and a cascade on
      // every redo would make undo-then-redo a forty-second round trip through a
      // celebration the player has already watched.
      let adoptRestored = () => {
        if !Session.hasWon(session.contents) {
          removeWinOverlay()
        }
        adoptHistoryPresent()
        if Session.hasWon(session.contents) {
          showWin()
        }
      }

      // The top bar's Undo button. The console's `undo` verb doesn't come through here —
      // it goes through `Session.step` like every other typed verb — but both end in
      // the same `Session.undo` and the same `adoptRestored`, so they can't drift.
      // (`redo` has no button, only a typed verb, so there's no twin of this.)
      let undo = () =>
        if Session.canUndo(session.contents) {
          DebugLog.message("undo")
          let (stepped, _) = Session.undo(~clock, current())
          session := stepped
          adoptRestored()
        }

      // --- Typed commands ---------------------------------------------------
      // What the debug console's input line does with a parsed command.
      //
      // It does not *interpret* one. Every board verb — `move`, `home`, `undo`,
      // `finish`, `autoplay`, `print` — is `Session.step`'s to run, which is the same
      // interpreter the terminal runs, so a typed command means one thing rather than
      // two. What's here is the other half: turning the `Session.change` that comes back
      // into cards moving on a screen.
      //
      // The three shapes that need more than a reflow get a function each below; the rest
      // is `react`, which is the whole of this file's answer to "what did that do".

      // Fly the cards a settled move displaced. Which cards those are is the session's
      // answer: the ones the action named, plus whatever auto-collect swept up behind
      // them, flown together so a move and its collection read as one gesture rather than
      // a move followed by a jump. A column reorder names no cards, so nothing flies and
      // the reflow inside the flight path simply re-lays the board.
      let flySettled = (~before: GameState.t, ~moved, ~collected) => {
        // The session records an accepted move as one undoable step — unless
        // nothing changed (a lawful no-op), which isn't undoable and so leaves
        // nothing to save or report.
        if !GameState.equal(state(), before) {
          afterChange()
        }
        animateCommand(Array.concat(moved, collected), ~onDone=() => {
          // A move that completes every foundation ends the game. Raised once the
          // cards have landed, so the celebration is the payoff of the flight rather
          // than something that beats it to the board.
          if Session.hasWon(session.contents) {
            celebrate()
          }
          updateFinishButton()
        })
      }

      // Play a solver's line, a move at a time.
      //
      // The thinking and the playing are both `Session`'s — it hands back a *trail* of
      // sessions, one per planned move. **What's this file's is the pace**: adopting
      // them one at a time, each as the previous flight lands, is what makes a run
      // something you watch being played rather than a board that changes while you
      // blink, and it's the whole reason to autoplay in front of a person.
      //
      // That makes this the one thing on the board that runs *forward in time* after
      // the command has answered, so it holds the interruption token and re-checks it
      // before every step. It can afford to stop anywhere precisely because each entry
      // is a whole session: a real position with a real history and tally behind it,
      // not something half-applied that has to be unwound.
      let playLine = (~reached: Session.t, ~trail: array<Session.played>) => {
        DebugLog.message("autoplay")
        // The reach is counted once, not once per move — the moves themselves are
        // counted as moves, like any others. Adopted before the first step, so the very
        // first save this writes already carries "this game was autoplayed", and adopted
        // even on a line with no moves in it (a board that was already finishable), which
        // is the case a trail alone wouldn't cover.
        session := reached
        // Any flight still in the air belongs to the position the line starts from (and
        // the tilt timings with it — see `adoptHistoryPresent`). This also ends an
        // autoplay already running, so a second `autoplay` replaces the first rather than
        // racing it.
        cancelOutstanding()
        clearTiltTimings()
        interruptPlay()
        let token = playToken.contents

        // Where the line ends: the solver stops where the Finish button lights up, so
        // finishing is that button's own sweep — same flight, same win overlay, one
        // further undoable step. A board it couldn't get all the way there stays where
        // the line left it, with the reply saying how far that was.
        let handOver = () => {
          updateFinishButton()
          if Session.canFinish(session.contents) {
            playFinish()->ignore
          } else if Session.hasWon(session.contents) {
            celebrate()
          }
        }

        let rec playFrom = i =>
          // Bumped since we started: the board is no longer the one this line was planned
          // for, so the rest of the plan is not ours to play.
          if token != playToken.contents {
            ()
          } else {
            switch trail->Array.get(i) {
            | None => handOver()
            | Some(step: Session.played) =>
              // The play-by-play, in the very words a typed or dragged move is logged in
              // (`Render.action`, see `narrate`) — narrated as each move is played, so the
              // log keeps time with the cards. No outcome mark: these were played against
              // `core` before they got here, and a move that didn't take never became a
              // step.
              if DebugLog.enabled() {
                DebugLog.line(Render.action(~game, step.action))
              }
              // Adopted *before* the flight, as every other move here is, so an
              // interruption mid-air leaves the model settled.
              session := step.session
              afterChange()
              animateAutoplayStep(step.moved, ~onDone=() => playFrom(i + 1))
            }
          }
        // **Started on the next tick, not here.** The command's reply is the sentence
        // that heads a play-by-play, but the console prints a command's answer once the
        // command *returns* — so a run played inline narrates its first move before the
        // summary lands, and the summary arrives a line down its own play-by-play. A
        // tick is invisible next to a flight and puts the sentence back on top.
        //
        // Safe to defer for the same reason the run is safe to interrupt: `playFrom`
        // re-checks `token` before every step, so a run whose board moved on in the
        // meantime never plays its first move at all.
        setTimeout(() => playFrom(0), 0)->ignore
      }

      // What a change means to a board with cards on it.
      let react = (~before: GameState.t, change: Session.change) =>
        switch change {
        | Session.Settled({moved, collected}) =>
          // A move of the player's own takes the board off whatever line an autoplay was
          // walking, exactly as a drop does.
          interruptPlay()
          flySettled(~before, ~moved, ~collected)
        | Session.Swept({moved}) =>
          interruptPlay()
          flySweep(moved)
        | Session.Restored => adoptRestored()
        // A refusal moved nothing, so there's nothing to draw; `narrate` has already put
        // the move and the reason it bounced into the log.
        | Session.Rejected(_) => interruptPlay()
        // Nothing to draw for these either: a house rule that refused before the reducer
        // saw it, a verb with nothing to do, a board simply shown — each says its piece
        // in the reply. `Dealt` never arrives: dealing a board means tearing this one
        // down and building another, which is the chrome's (see `Main`), and it doesn't
        // forward `deal`/`redeal` here.
        | Session.Blocked(_) | Session.Unchanged | Session.Shown | Session.Dealt => ()
        // Played by `playLine` rather than adopted whole — intercepted before `react`.
        | Session.Played(_) => ()
        }

      let runCommand = (command: Command.t): array<Render.line> => {
        let before = state()
        let (next, outcome) = Session.step(~clock, current(), command)
        switch outcome.change {
        // A solver line is walked, not adopted: `next` is where it *ends up*, and getting
        // there a move at a time is the point (see `playLine`).
        | Session.Played({reached, trail}) => playLine(~reached, ~trail)
        | change =>
          session := next
          narrate(~before, change)
          // A step through history isn't a move and carries no action to say, so the
          // verb itself is what goes in the log — and only when it actually stepped, so a
          // `redo` with nothing ahead of it doesn't read as one.
          switch (command, change) {
          | (Command.Undo, Session.Restored) => DebugLog.message("undo")
          | (Command.Redo, Session.Restored) => DebugLog.message("redo")
          | _ => ()
          }
          react(~before, change)
        }
        // Two verbs answer with something other than the session's own reply. `print`
        // asks for the board, and this driver draws it with the deal number the *app*
        // resolved (`~currentDeal`) rather than the one the board can prove — a resumed
        // game really is a deal, and the chrome is what knows which. A refusal is already
        // in the log, with its reason under it, so repeating it here would say it twice.
        switch outcome.change {
        | Session.Shown => Render.stateLines(~game, ~deal=?currentDeal(), state())
        | Session.Rejected(_) => []
        | _ => outcome.reply
        }
      }

      // Build one draggable card and wire its pointer loop. It starts at 0,0 and is
      // positioned by the initial deal (below); returning `self` lets the caller
      // collect the free cards and lay them out together.
      let makeCard = (cardData: Deck.card) => {
        let wrapper = WebDom.createElement("div")
        wrapper->WebDom.setAttribute("class", "stacking-card")
        wrapper->WebDom.appendChild(Html.create(CardArt.svg(cardData)))->ignore

        // The card's transient view state: position (kept here rather than parsed
        // back out of the style each move) and whether it's on top and so pickable.
        // Cards start draggable; reflow corrects buried ones. Where the card *rests*
        // is not stored — that's `GameState`.
        let self = {
          data: cardData,
          wrapper,
          x: ref(0.),
          y: ref(0.),
          draggable: ref(true),
        }
        // Register the node so a pile derived from `state` can be laid out onto it.
        nodes->Array.push(self)

        // Position and layer before insertion so the card appears in place instead
        // of sliding in from the corner (the CSS `transition` would otherwise
        // animate 0,0 → here on mount).
        place(self)
        bringToFront(wrapper)
        playfield->WebDom.appendChild(wrapper)->ignore

        // The drag in progress: the pointer's position at grab time, and the whole
        // *span* being carried — the run this card heads, bottom-first (`self` at
        // index 0), each node paired with its position at grab time. A move is
        // "each start position + how far the pointer has travelled since". `None`
        // when not dragging. A lone top card is just a span of one, so the ordinary
        // single-card drag is the length-1 case here.
        let grab = ref(None)

        // Send-home double-tap bookkeeping. `movedFar` records whether the
        // pointer travelled far enough during the current press to count as a drag
        // rather than a tap; `lastTapAt` is the timestamp of the previous tap on
        // *this* card (each card has its own closure, so a double-tap must land on
        // one card, never split across two). Seeded well in the past so the first
        // tap after load can never read as the second half of a double-tap.
        let movedFar = ref(false)
        let lastTapAt = ref(-1000.)

        // May the span `spanCards` (bottom-first) land on `zone`? The hover
        // highlight and the drop below both funnel through `core`'s shared
        // legality (`canDrop` for one card, `canMoveRun` for a run) so
        // the green "valid" outline can never disagree with the accepted drop. The
        // one thing those can't see is that re-dropping onto the pile the span
        // already sits on is a lawful no-op — during a drag the cards still rest in
        // `state`, so the query would weigh them against themselves — so mirror the
        // reducer's identity case here, keeping hover in step with `reduce`.
        let accepts = (spanCards, zone) =>
          switch GameState.locationOf(state(), cardData) {
          | Some(GameState.InPile(i, _)) if i == zone.index => true
          | _ =>
            Array.length(spanCards) <= 1
              ? Reducer.canDrop(~game, state(), cardData, ~onto=zone.index)
              : Reducer.canMoveRun(~game, state(), spanCards, ~onto=zone.index)
          }

        let clearHover = () =>
          zones->Array.forEach(zone => {
            classList(zone.el)->removeClass("drop-zone--over")
            classList(zone.el)->removeClass("drop-zone--invalid")
          })

        // Outline the zone the grabbed card's centre is currently over (and only
        // that one) so the drop is legible before release: green when the rule
        // accepts the span, red when it rejects it.
        let highlightHover = spanCards => {
          let over = zoneAt(boundingRect(wrapper))
          zones->Array.forEach(zone => {
            let cls = classList(zone.el)
            switch over {
            | Some(z) if z === zone && accepts(spanCards, zone) =>
              cls->addClass("drop-zone--over")
              cls->removeClass("drop-zone--invalid")
            | Some(z) if z === zone =>
              cls->addClass("drop-zone--invalid")
              cls->removeClass("drop-zone--over")
            | _ =>
              cls->removeClass("drop-zone--over")
              cls->removeClass("drop-zone--invalid")
            }
          })
        }

        wrapper->onPointer("pointerdown", ev =>
          // Only a card that heads a legal run can be picked up; every other buried
          // card ignores the pointer (its `draggable` is false, set each reflow).
          if self.draggable.contents {
            // A fresh press: assume a tap until the pointer travels far enough
            // (below) to be a drag, which is what tells the double-tap apart.
            movedFar := false
            // Capture so the cards keep getting moves/up even if the pointer leaves
            // their bounds.
            wrapper->setPointerCapture(pointerId(ev))
            // Gather the span this card heads: itself and every card resting above
            // it in its pile, bottom-first. A lone card is a span of one.
            let span = switch GameState.locationOf(state(), self.data) {
            | Some(GameState.InPile(pileIdx, slot)) =>
              let pile = GameState.cardsInPile(state(), pileIdx)
              pile->Array.slice(~start=slot, ~end=Array.length(pile))->Array.filterMap(nodeFor)
            | _ => nodeFor(self.data)->Option.mapOr([], c => [c])
            }
            grab :=
              Some((
                clientX(ev),
                clientY(ev),
                span->Array.map(c => (c, c.x.contents, c.y.contents)),
              ))
            // Raise the whole span above the rest of the board, keeping bottom-first
            // order so the run stays coherently stacked while it's carried.
            span->Array.forEach(c => {
              classList(c.wrapper)->addClass("dragging")
              bringToFront(c.wrapper)
            })
          }
        )

        wrapper->onPointer("pointermove", ev =>
          switch grab.contents {
          | Some((startPX, startPY, spanStarts)) =>
            let dx = clientX(ev) -. startPX
            let dy = clientY(ev) -. startPY

            // Once the pointer has travelled past the tap tolerance this press is a
            // drag, not a tap, and so can't be half of a double-tap.
            if Math.abs(dx) +. Math.abs(dy) > doubleTapMoveTol {
              movedFar := true
            }
            spanStarts->Array.forEach(((c, sx, sy)) => {
              c.x := sx +. dx
              c.y := sy +. dy
              place(c)
            })
            highlightHover(spanStarts->Array.map(((c, _, _)) => c.data))
          | None => ()
          }
        )

        // Send this card home — the shortcut for the tedium of dragging every card home
        // one at a time. Eligibility and legality both come from `core`'s `validMoves`,
        // which lists every drop a hand-drag would accept with movability already
        // gated, so this is just "find the `Foundation` move and take it". At most one
        // foundation ever accepts a card. The move dispatched is the very `Move` a drag
        // would make, so a completing card still raises the win overlay.
        let sendHome = () =>
          switch Reducer.validMoves(~game, state(), self.data)->Array.find(m =>
            m.role == Game.Foundation
          ) {
          | Some({to: i}) =>
            let before = state()
            switch dispatch(Reducer.Move({card: self.data, to: Reducer.ToPile(i)})) {
            | Session.Settled(_) =>
              // The session has already settled the move (auto-collect included) and
              // recorded it as one undoable step — unless it changed nothing (a
              // lawful no-op), which leaves nothing to save or report.
              if !GameState.equal(state(), before) {
                afterChange()
              }
              reflowAll()
              if Session.hasWon(session.contents) {
                celebrate()
              }
              updateFinishButton()
            | _ => ()
            }
          | None => ()
          }

        // When no foundation will take a double-tapped card but it can still move
        // somewhere, flash those destinations instead. Purely informational: no card
        // moves, nothing is selected, `state` is untouched.
        //
        // **Reduced motion keeps the information rather than losing it.** A colour fade
        // carries no movement, so the pulse becomes a single hold-then-fade — lit long
        // enough to read, then settled — instead of the hint being dropped. (Reading
        // `matchMedia`/`animate` also keeps clear of jsdom, which implements neither.)
        let flashMoveTargets = (moves: array<Reducer.move>) => {
          let reduceMotion = matchMedia("(prefers-reduced-motion: reduce)")["matches"]
          // Mostly-green at its peak — opaque enough to read as green for a frame or
          // two, translucent enough to keep the pip showing through — then fades to
          // nothing. No `fill`, so the mask ends fully transparent.
          let peak = "0.82"
          let (keyframes, options) = reduceMotion
            ? (
                [
                  {"opacity": peak, "offset": 0.},
                  {"opacity": peak, "offset": 0.6},
                  {"opacity": "0", "offset": 1.},
                ],
                {"duration": 900., "iterations": 1, "easing": "ease-out"},
              )
            : (
                [
                  {"opacity": "0", "offset": 0.},
                  {"opacity": peak, "offset": 0.2},
                  {"opacity": peak, "offset": 0.5},
                  {"opacity": "0", "offset": 1.},
                ],
                {"duration": 500., "iterations": 2, "easing": "ease-in-out"},
              )
          // Pulse a throwaway `.hint-mask` over one eligible card wrapper (card-sized)
          // and drop it when the pulse ends.
          let flash = el => {
            let mask = WebDom.createElement("div")
            mask->WebDom.setAttribute("class", "hint-mask")
            el->WebDom.appendChild(mask)->ignore
            animateMask(mask, keyframes, options)->setOnFinish(() => mask->WebDom.remove)
          }
          // Never hint free cells — they're the obvious park spot — nor a blank
          // space on the board: an empty target (an empty cascade) is skipped entirely
          // rather than lighting its slot placeholder. Each remaining target lights its
          // *individual eligible card* — the exposed bottom card of the pile the drop
          // would land on.
          moves
          ->Array.filter(({role}) => role != Game.FreeCell)
          ->Array.forEach(({to: i}) => {
            let cards = GameState.cardsInPile(state(), i)
            switch cards->Array.get(Array.length(cards) - 1)->Option.flatMap(nodeFor) {
            | Some(node) => flash(node.wrapper)
            | None => ()
            }
          })
        }

        // The double-tap gesture, branching on the card's `validMoves`:
        // a `Foundation` move sends it home; otherwise, if it has
        // any other legal destination, flash those; a card that can't move does nothing.
        let doubleTap = () => {
          let moves = Reducer.validMoves(~game, state(), self.data)
          switch moves->Array.find(m => m.role == Game.Foundation) {
          | Some(_) => sendHome()
          | None => flashMoveTargets(moves)
          }
        }

        let endDrag = ev =>
          switch grab.contents {
          | Some((_, _, spanStarts)) =>
            wrapper->releasePointerCapture(pointerId(ev))
            grab := None
            spanStarts->Array.forEach(((c, _, _)) => classList(c.wrapper)->removeClass("dragging"))
            let spanCards = spanStarts->Array.map(((c, _, _)) => c.data)
            // Where the grabbed card's centre was released decides the *action*:
            // onto a zone is a `Move`/`MoveRun` to that pile. Released over no zone
            // at all there is no move to make — a card only ever rests in a pile —
            // so nothing is dispatched and the span reflows home. Every drop that
            // *is* a move goes to the reducer, so `core` owns every rest position.
            switch zoneAt(boundingRect(wrapper)) {
            | None => reflowAll()
            | Some(zone) =>
              let target = Reducer.ToPile(zone.index)
              // One card dispatches the unchanged single-card `Move`; a span of two or
              // more dispatches the supermove `MoveRun`.
              let action =
                Array.length(spanCards) <= 1
                  ? Reducer.Move({card: self.data, to: target})
                  : Reducer.MoveRun({cards: spanCards, to: target})
              let before = state()
              switch dispatch(action) {
              // Lawful move (including the identity re-drop): the session has adopted it,
              // auto-collected any now-safe cards behind it so the whole cascade
              // settles in one pass, and recorded the settled position as one undoable step
              // — so a move and its collection undo together. Reflow every pile from
              // it, so the cards that joined a pile snap to their slots.
              | Session.Settled(_) =>
                // …unless nothing changed (dropping a card back where it started is a
                // no-op), which records no step and so leaves nothing to save.
                if !GameState.equal(state(), before) {
                  afterChange()
                }
                reflowAll()

                // A move that completes every foundation ends the game: celebrate it
                // following the accepted `reduce` (and any auto-collect that played the
                // final cards).
                if Session.hasWon(session.contents) {
                  celebrate()
                }
                // Recompute the "Finish" button: a move can make the board
                // drainable (show it) or, via auto-collect, no longer so (hide it).
                updateFinishButton()
              // Illegal move: bounce the span back where it came from — every card
              // rests in a pile, so reflowing returns each to its slot.
              | _ => reflowAll()
              }
            }
            clearHover()

            // With the drop settled, decide whether this press completed a
            // double-tap send-home. Only a press that stayed a tap (never
            // moved far enough to be a drag) counts; a real drag breaks the chain by
            // pushing `lastTapAt` into the past. Two qualifying taps within
            // `doubleTapMs` fire `sendHome` and reset, so a third tap starts fresh
            // rather than chaining off the second.
            if movedFar.contents {
              lastTapAt := -1000.
            } else {
              let now = timeStamp(ev)
              if now -. lastTapAt.contents <= doubleTapMs {
                lastTapAt := -1000.
                doubleTap()
              } else {
                lastTapAt := now
              }
            }
          | None => ()
          }

        wrapper->onPointer("pointerup", endDrag)
        // A cancelled pointer (e.g. the OS stealing the gesture) must tear the drag
        // down too, or the cards would stay stuck to a pointer that's gone.
        wrapper->onPointer("pointercancel", endDrag)

        self
      }

      // A DOM node for every card a pile opens holding — where each rests is
      // already recorded in `state`, so no zone pairing is needed here, just the
      // nodes (which register themselves in `nodes`).
      game.piles->Array.forEach((pile: Game.pile) =>
        pile.cards->Array.forEach(card => makeCard(card)->ignore)
      )

      // The shake jostle: a vigorous shake nudges every card a little off its
      // resting spot, so the tableau ends messier than it was dealt. Each nudge is a
      // small random offset written straight to the card's live x/y and eased in by
      // the `.stacking-card` left/top snap transition, so the board visibly jostles.
      // It's deliberately physical and cumulative — repeated shakes pile on more mess
      // — and never touches the model, so it's purely presentational; squaring up
      // (below) re-lays every card onto its deterministic resting place, undoing it.
      // `Math.random` is fine here: this fires only on a real device shake, never on
      // the reproducible screenshot path.
      let jostle = () => {
        let amp = 12. *. scale.contents
        nodes->Array.forEach(c => {
          c.x := c.x.contents +. (Math.random() -. 0.5) *. 2. *. amp
          c.y := c.y.contents +. (Math.random() -. 0.5) *. 2. *. amp
          place(c)
        })
      }

      // Re-lay every resting card onto its deterministic spot: reflow the piles against
      // their zones, reading `tiltEnabled` live. It's what the tilt switch asks for
      // (`controls.relayout`), so a flip re-tilts or squares the board in place
      // rather than waiting for the next move, and it's what ends a shake, so
      // turning Wiggle Waggle off snaps the mess back to exactly that board.
      let squareUp = () => reflowAll()

      // Publish this build's shake operations into the mount-scope `boardOps` ref, so
      // the persistent subscription drives the live board's nodes (a New Game rebuild
      // swaps in fresh ones).
      boardOps := {jostle, squareUp}

      // Lay out each opening pile from `state`: reflow reads the cards the model
      // deals that pile and positions their nodes, so the pile ends laid out exactly
      // as an interactively built one would.
      let dealPiles = () => reflowAll()

      // The order the cards fly in: a real dealer's pass — round-robin across the
      // piles by slot (every pile's first card, then every pile's second, …). This is
      // just the sequence the staggered start delays below run over; the cards are
      // already at their final resting spots.
      let dealSequence = () => {
        let piles = zones->Array.map(z => GameState.cardsInPile(state(), z.index))
        let depth = piles->Array.reduce(0, (m, p) => Math.Int.max(m, Array.length(p)))
        let ordered = []
        for slot in 0 to depth - 1 {
          piles->Array.forEach(p =>
            switch p[slot] {
            | Some(data) =>
              switch nodeFor(data) {
              | Some(c) => ordered->Array.push(c)
              | None => ()
              }
            | None => ()
            }
          )
        }
        ordered
      }

      // Fly the just-placed cards in from a single origin below the stage into
      // their rest positions, staggered. Every card starts translated to one
      // shared point — the middle of the stage's bottom edge, just off-screen —
      // so they all launch from the same "stack" a magician would throw from, and
      // animates to `translate 0` (its left/top already hold the final spot). The
      // per-card start offset therefore differs on *both* axes, since each card
      // travels from that one origin to a different landing spot. With the OS
      // asking for reduced motion — or the URL's `?animate=off` (`~skipDealAnimation`)
      // — the cards simply stay where they were placed, no fly-in.
      let animateDeal = () => {
        let reduceMotion = matchMedia("(prefers-reduced-motion: reduce)")["matches"]
        let cards = dealSequence()
        let n = Array.length(cards)
        if !reduceMotion && !skipDealAnimation && n > 0 {
          let pr = boundingRect(playfield)
          let cw = TableLayout.cardW *. scale.contents
          let ch = TableLayout.cardH *. scale.contents
          // The single origin every card launches from: horizontally centred on
          // the stage, seated a card's height below its bottom edge — one stack,
          // in playfield-local coords (matching the cards' left/top).
          let originX = pr.width /. 2. -. cw /. 2.
          let originY = pr.height +. ch
          // The stagger (Δ) and per-card flight time, from the deal's knobs and the
          // card count.
          let (delta, flight) = staggerTiming(
            ~maxInFlight=dealMaxInFlight,
            ~perCardMs=dealPerCardMs,
            ~n,
          )
          cards->Array.forEachWithIndex((card, i) => {
            flyHome(
              ~wrapper=card.wrapper,
              ~dx=originX -. card.x.contents,
              ~dy=originY -. card.y.contents,
              ~flight,
              ~delay=Int.toFloat(i) *. delta,
            )->ignore
          })
        }
      }

      let deal = () => {
        // Size the cards to the now-laid-out stage first, so both deals below place
        // and reflow cards at their final footprint.
        applyScale()
        // Place and fly the cards in with the left/top snap transition suppressed, so
        // they don't *also* slide in from the corner (0,0) while the fly-up plays (see
        // `withSnapSuppressed`); the transform fly-up runs on past that window.
        withSnapSuppressed(() => {
          dealPiles()
          animateDeal()
        })
      }

      // Re-run the layout for the stage's current size — a resize snaps the
      // piled cards to the resized zones and rescales them, *without* re-animating
      // the opening deal. The cards follow the zones' live rects (`reflowAll`). The
      // left/top snap transition is suppressed so they track the zones immediately
      // rather than easing after every resize step (`withSnapSuppressed`). Gated on a
      // prior deal (`lastWidth > 0`, set by `applyScale`), so the observer's initial
      // callback — before the deferred opening deal has sized anything — is a harmless
      // no-op.
      let relayoutForResize = () => {
        let width = boundingRect(playfield).width
        if width > 0. && lastWidth.contents > 0. {
          withSnapSuppressed(() => {
            applyScale()
            reflowAll()
          })
        }
      }
      // Publish this build's relayout as the live one the mount-scope observer
      // drives, so a resize after a New Game reflows *this* board, not the one it
      // replaced.
      resizeRelayout := relayoutForResize

      // Deal now if the stage is already laid out (a later scene switch); otherwise
      // on the next frame, before the first paint, once the detached-at-mount stage
      // has been inserted and sized (the first page load). The cards need the stage's
      // live rects, so the deal waits on this.
      boundingRect(playfield).width > 0. ? deal() : requestAnimationFrame(deal)->ignore

      // Come back to a won board: a resumed game saved in its victory state
      // opens with the win overlay already up, rather than a silently finished board.
      // **Quietly** — `showWin`, not `celebrate`: this is a victory from storage,
      // possibly days old, and replaying the cascade every time a finished game is
      // reopened would be both wrong and unasked for.
      // Checked before the "Finish" button below so a completed board never offers to
      // finish itself. A fresh deal, a re-deal, or a `?state=` scenario is never
      // already won, so this only fires on a restored victory.
      if Session.hasWon(session.contents) {
        showWin()
      }

      // Show the "Finish" button straight away when the opening position is
      // already drainable — a `?state=` scenario can drop the board into one.
      // Layout-independent, so it needn't wait on the deal's frame.
      updateFinishButton()

      // Point the published `undo`, `runCommand` and `relayout` at *this* build,
      // and report the opening history (nothing to undo yet) so the top bar's button
      // starts disabled. Each of the three closes over the board it was built
      // with — a command closes over the `session` it dispatches into, undo over that
      // board's history, the relayout over its card nodes — so a re-deal has to repoint
      // them or a typed `move` would address the board that was just torn down.
      //
      // The chrome doesn't see this happen: it took `controls` once at mount, and every
      // field dispatches through these refs.
      liveUndo := undo
      liveRunCommand := runCommand
      liveRelayout := squareUp
      reportHistory()

      // Persist this freshly-built board when saving is on: the opening deal,
      // a New Game, or a Restart each *become* the saved game, so a later reload
      // resumes this board — and New Game replaces whatever was saved before. Skipped
      // for a forced-state load (`~persistThis=false`), which must leave the saved
      // game untouched; a no-op when no `~persist` sink is wired.
      if persistThis {
        persistCurrent()
      }
    }

    // Hand the chrome the board's published surface: one record, once, as this
    // scene mounts.
    //
    // Everything here is written to survive a re-deal, which is the whole reason a
    // mount-scope hand-over is safe:
    //
    //   - the four rebuilds (`newGame`, `loadDeal`, `restart`, `loadState`) and the
    //     share-link restore call `buildBoard` directly, which clears the host and
    //     builds a fresh board in place — so they're about the *scene*, not a build;
    //   - `readHistory`, `undo`, `runCommand`, `relayout` and `dockFit` dispatch
    //     through mount-scope refs that each build repoints at its own board;
    //   - `shake` drives the live board's nodes through `boardOps`, the same way.
    //
    // The two re-deals that open a board the caller names are the re-dealable game's: a
    // fresh seed for `newGame` (the menu's Random and the console's bare `deal`),
    // invented by the driver and handed over as `~newDeal`, and a *chosen* one for
    // `loadDeal` (the menu's Enter seed and the console's `deal <n>`), laid out by the
    // game itself (`Game.t.deal`) — a board knows how to deal another of its own. A
    // fixed-layout demo has no seed to vary and offers neither — `~newDeal` is still
    // what says so, since it's the driver that decides whether a board may be re-dealt
    // at all.
    //
    // `restart` is offered by *every* card table — a demo restarts to its own
    // opening deal — and rebuilds from `currentGame`, the deal actually on the table, so
    // a Restart after a New Game replays the new seed rather than the one this scene
    // first mounted with. It passes no `~initial`, so a `?state=` board restarts to the
    // game's real deal rather than the posed position.
    //
    // `loadState` forces a position without persisting it (`~persistThis=false`), so a
    // debug-states jump never clobbers a real saved game — where `loadHistory` *does*
    // persist, because a shared game takes over as this device's saved game and play
    // continues from it normally. (Whether either write reaches storage is still the
    // driver's call; the sink is only wired for the opens that may write. See `Main`'s
    // `~persist`.)
    switch publish {
    | Some(publish) =>
      publish({
        newGame: newDeal->Option.map(freshDeal => () => buildBoard(freshDeal())),
        loadDeal: switch (newDeal, game.deal) {
        | (Some(_), Some(deal)) => Some(seed => buildBoard(deal(seed)))
        | _ => None
        },
        restart: () => buildBoard(currentGame.contents),
        loadState: state => buildBoard(~initial=state, ~persistThis=false, game),
        loadHistory: restored => buildBoard(~history=restored, game),
        readHistory: () => readHistory.contents(),
        undo: () => liveUndo.contents(),
        runCommand: command => liveRunCommand.contents(command),
        relayout: () => liveRelayout.contents(),
        dockFit: inset => dockFit.contents(inset),
        shake: {start: startShake, stop: stopShake},
      })
    | None => ()
    }
    container->WebDom.appendChild(boardHost)->ignore

    // Open the board: from a saved undo/redo history when one was restored,
    // else the forced `~initial` scenario when the URL named one, else the game's own
    // deal. The save is read *here*, as this mount opens — not once when the scene
    // was built — so a scene mounted a second time resumes the game as it stands
    // now rather than re-opening a page-load snapshot of it over the board the
    // player was on. It seeds only this opening build; every later re-deal within
    // the mount starts clean.
    buildBoard(~initial?, ~history=?loadHistory(), game)

    // Reflow the card layout whenever the stage resizes. One observer serves
    // the scene's whole life: it watches the persistent `boardHost` and always
    // dispatches through `resizeRelayout`, which each `buildBoard` repoints at its
    // own board — so a resize after a New Game reflows the live board, not the torn-
    // down one. The callback storm a drag-resize fires is coalesced to one relayout
    // per frame with `requestAnimationFrame`. Absent a `ResizeObserver` (jsdom, old
    // engines) the wiring is simply skipped.
    switch resizeObserverCtor->Nullable.toOption {
    | Some(_) =>
      let resizePending = ref(false)
      let observer = makeResizeObserver(() =>
        if !resizePending.contents {
          resizePending := true
          requestAnimationFrame(() => {
            resizePending := false
            resizeRelayout.contents()
          })->ignore
        }
      )
      observer->observe(boardHost)
      // The switcher clears the container on scene change, dropping the board host,
      // the New Game control and every listener with them. What outlives the DOM is
      // everything hung off `window` or a clock: the `devicemotion` subscription, a
      // cascade's frame loop, its own resize listener and a sprite build still in
      // flight, and this observer. Each has to be detached explicitly.
      () => {
        unsubscribeShake()
        endCascade()
        observer->disconnect
      }
    | None =>
      () => {
        unsubscribeShake()
        endCascade()
      }
    }
  },
}
