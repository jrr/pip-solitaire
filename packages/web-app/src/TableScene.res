// A card table that *interprets a modelled game* (`Game.t` from core) rather
// than hard-coding one board. Grown out of the drag-and-drop spike (#21) and the
// stacking demo (#56), and now driven by data (#62): the piles, their stacking
// behaviours and the opening deal all come from the game, so a new game is a new
// value in `Game`, not new code here.
//
// The view holds its own presentation assumptions — the piles hang from the top
// of the stage and grow downward; the loose cards are dealt as a sloppy cluster
// below them — and applies them to whatever the model describes, be it two piles
// or sixteen. The piles are grouped into rows by role (#94/#97): free cells and
// foundations across the top, cascades below, so a full FreeCell board is
// playable; a single-role board (every other demo) is just one row, as before.
//
// Dragging is transient *view* state (where a finger is right now), so unlike
// the other scenes this one is built with plain imperative DOM bindings rather
// than the `Html` Elm loop — a pointermove doesn't belong in a reduced model,
// and driving the card straight from the event keeps it glued to the finger.
// The card faces themselves are still typed `CardArt` vnodes, materialised once
// with `Html.create` and then moved around by mutating `style.left/top`.
//
// The mechanics the demo is here to exercise:
//   - Pointer Events (`pointerdown`/`pointermove`/`pointerup`) instead of mouse
//     + touch, so one code path covers phone and desktop.
//   - `setPointerCapture`, so a card keeps receiving moves even when the pointer
//     outruns it and leaves its bounds mid-drag.
//   - `touch-action: none` (in CSS) on the cards, so a drag doesn't also scroll
//     or trigger a browser gesture on touch.
//   - Hit-testing the card's centre against each zone's rect to pick a drop
//     target, and snapping the card to that zone's centre on release.
//   - Squared vs fanned pile layout, reflowed live from the zones' rects.

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
// the pure-CSS drop zones it doesn't reflow itself when the stage resizes (#172).
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
// the snap maths use, converting to playfield-local left/top only at the end.
type domRect = {left: float, top: float, width: float, height: float}
@send external boundingRect: WebDom.element => domRect = "getBoundingClientRect"

// The card scale is sized to the box the row *actually lays out in* — narrower than
// the stage by the safe-area cutout (#179 pins `.drop-rows` inside `left`/`right:
// env(safe-area-inset-*)`), and, for the height fit, offset from the top by the row's
// `top` and split by its inter-row `rowGap`. None of these are in a rect we already
// read, so pull them off the row's *computed* style; `parseFloat` turns "44px" → 44.
@val
external getComputedStyle: WebDom.element => {
  "left": string,
  "right": string,
  "top": string,
  "rowGap": string,
} = "getComputedStyle"
@val external parseFloat: string => float = "parseFloat"

// The opening deal (#115) flies each card in from a single origin below the
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
// The finish sweep (#160) also animates z: a card holds its resting layer while it
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

// The double-tap "where can this go?" hint (#197, reworked in #217): when no
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
// Read a card's current layer back, so the finish sweep (#160) can hold each
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

// `core`'s `GameState` now owns *where every card rests* (#83): the scene holds
// one immutable `GameState.t` and re-derives each pile from it, so a zone no
// longer carries its own `pile` and a card no longer remembers a `home`. What's
// left on these records is purely presentational.
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
// (or a loose card) ends up `draggable`, set each reflow.
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
// subscription (#235): `jostle` nudges the current cards off their resting spots on
// a shake, `squareUp` re-lays them clean when listening stops. Republished on every
// `buildBoard` so the mount-scope subscription always drives the live board's nodes.
type boardOps = {
  jostle: unit => unit,
  squareUp: unit => unit,
}

// The shake control the scene publishes to the chrome (#235), one field of the
// `controls` record below: `start` begins listening for shakes (Settings turns Wiggle
// Waggle on, once permission is granted), `stop` ends it and squares the board back
// up. Held at mount scope so it survives re-deals — the chrome calls it as the
// switch flips, never rebuilding the board.
type shakeControl = {
  start: unit => unit,
  stop: unit => unit,
}

// Everything a mounted board offers the chrome (#300) — its published surface, as one
// typed value handed over the moment the scene mounts (`~publish` below).
//
// It replaces eleven separate `~publishX` callbacks and the eleven module-level `ref`s
// the driver kept them in. The driver-side win is the one that motivated it: a scene
// swap now replaces this record wholesale, where before every hook had to be nulled by
// name on each scene change and nothing type-checked that the list was complete. A
// hook someone forgot to add to it was the chrome quietly driving a torn-down board —
// a bug the compiler couldn't see. There is no list any more.
//
// Every field here is *mount*-scoped, not build-scoped. A board is torn down and
// rebuilt on every re-deal (New Game, Restart, a forced state, a shared game landing),
// so the three that genuinely belong to a build — `undo`, `runCommand`, `relayout` —
// dispatch through mount-scope refs that each `buildBoard` repoints at its own. The
// record the chrome took at mount therefore goes on driving whatever is actually on
// the table, and a stale closure over a torn-down build isn't something a caller can
// hold even by accident.
//
// `newGame` and `loadGame` are the two a board can genuinely lack: both open a board
// the caller names — a fresh seed, a chosen deal number — which only a *re-dealable*
// game has (`~newDeal`; FreeCell today). A fixed-layout demo answers `None`, which is
// what lets the menu and the console's `deal` say so rather than silently doing
// nothing. Everything else is offered by every card table.
type controls = {
  // Re-deal onto a fresh seed (#108/#156) — the menu's New Game, and the console's
  // bare `deal`.
  newGame: option<unit => unit>,
  // Re-deal onto a *named* game (#273) — the addressed twin of `newGame`, behind the
  // console's `deal <n>`. The caller turns the number into a `Game.t`, since only it
  // knows a deal number is a seeded FreeCell shuffle.
  loadGame: option<Game.t => unit>,
  // Replay the deal now on the table (#156) — the menu's Restart, and the console's
  // `redeal`. Every card table offers it: a fixed-layout demo restarts to its own deal.
  restart: unit => unit,
  // Rebuild the board into a forced position — the debug-states menu's live twin of the
  // URL's `?state=`. Never persisted, so a debug jump can't clobber a saved game.
  loadState: GameState.t => unit,
  // Rebuild the board onto a whole restored undo/redo stack (`ShareLink`): a shared
  // game arrives with its history intact. *Unlike* a forced state this persists — a
  // shared game is adopted as this device's saved game rather than borrowed.
  loadHistory: SaveState.t => unit,
  // …and the read side, for the share button: the live board's saved game, whatever
  // build is currently on the table.
  readHistory: unit => option<SaveState.t>,
  // Step the board's history back (#85) — the top bar's Undo button.
  undo: unit => unit,
  // Play one parsed command against this board (#273) and answer with whatever
  // `DebugLog` won't already have said. Not a second interpreter: the command goes to
  // `Session.step` like the terminal's does, and what comes back is turned into cards
  // moving on a screen.
  runCommand: Command.t => array<Render.line>,
  // Re-lay every resting card (#65), so the menu's tilt switch re-tilts the board in
  // place rather than only on the next move.
  relayout: unit => unit,
  // The board's answer to one question (#275): could you give up this many px of stage
  // width and still deal cards above `minScale`? What the console's dock toggle
  // consults, so the refusal is the layout's own verdict rather than a guessed
  // breakpoint.
  dockFit: float => bool,
  // Start/stop listening for shakes (#235). See `shakeControl` above.
  shake: shakeControl,
}

// What the driver offers the win overlay's Share button (#264), the victory twin of
// the menu's Share Seed. `available` is asked as the overlay goes up and decides
// whether the button is built at all; `share` hands the win over and resolves with
// the one-line status to show beneath the buttons.
//
// The driver answers both because the board can't. A deal number survives a resume
// only in the driver's storage, and a board showing a shared or posed position has
// none at all — which is exactly why `~onDeal` below reports `None` on those builds
// and leaves `Main` to fill the gap. Asking at overlay time rather than at build time
// keeps the answer about the board that was just won.
//
// A pair rather than two separate props because they have to agree: offering a
// button that then has no deal to share is the one failure a share button can't
// afford, and a single record makes that a type-level impossibility rather than a
// convention two call sites have to keep.
type winShare = {
  available: unit => bool,
  // `~moves`/`~undos` are the won game's tally (`Stats`, #289), read off the live
  // board as the button is pressed. The board counts them because it's the thing
  // moves and undos happen to; what the driver does with them — a message, nothing —
  // is its own business.
  share: (~moves: int, ~undos: int) => promise<string>,
}

// The design footprints, at scale 1. Everything the layout measures in pixels —
// the fan step, the card box, the empty zone box — is one of these multiplied by
// the stage's live `scale` (see `make`), so cards, zones and fans all shrink
// together to fit however many piles a game declares onto a narrow screen.

// How far each Fanned card steps off the one beneath it. The zones sit at the
// top of the stage and the pile grows downward, so the fan steps *down*, the
// newest card landing lowest and fully exposed.
let fanStep = 26.

// Card footprint in playfield pixels. The width is the design size; the height
// follows from the art's own 5:7 design box (`CardArt.aspect`) rather than being a
// second literal that has to agree with it. Used by the initial deal, which places
// cards before they're laid out and so can't read their rects yet.
let cardW = 80.
let cardH = cardW *. CardArt.aspect

// The card's corner radius at the design size, from the art's own `rx` over its
// design-box width. The empty-pile slot traces the card, so this is the slot's
// radius too — and the zone frame's radius is this plus `zoneInset` (below), which
// is what makes the two corners concentric. Published to the CSS by `applyScale`
// so the stylesheet no longer restates either ratio.
let cardRadius = cardW *. CardArt.cornerRatio

// The empty drop zone's footprint (matches `.drop-zone` in the CSS): the
// card-sized slot (`cardW` × `cardH`) plus a *uniform* breathing gap on every
// side (#166 follow-up). Sizing it as `card + 2·inset` on both axes — rather
// than the old hand-picked 88×124, which left a 4px side gap but a 6px top/bottom
// one — makes the highlight frame sit an equal distance outside the resting card
// all the way round, and rounds the frame concentrically (the slot's radius + this
// inset). A pile's cards centre vertically within the base-height box, and a fanned
// zone grows *below* it so its outline and highlight wrap the whole pile rather
// than just the top card's footprint (see reflow).
let zoneInset = 4.
let zoneWidth = cardW +. 2. *. zoneInset
let zoneBaseHeight = cardH +. 2. *. zoneInset

// Concentric with the slot: the frame sits `zoneInset` outside it on every side, so
// its radius is the slot's plus that inset and the two corners share a centre.
let zoneRadius = cardRadius +. zoneInset

// Card widths are floored here, so a game with many piles on a narrow phone
// still deals cards you can read and grab rather than shrinking them away.
// Between this and `maxScale`, cards fill `fillFraction × width` of the stage
// split across the piles. The floor is set low enough that eight cascades still
// fit *with room to spare* on a phone — otherwise the columns hit the floor,
// overflow the row and butt together with no gap to distribute (the
// `space-evenly` below has nothing to spread).
let minScale = 0.4

// The ceiling on card size, as a multiple of the design footprint — the single
// knob for "how big do cards get on a roomy screen". Every pixel the layout
// measures (`cardW`/`cardH`, `fanStep`, the zone box, the `cardRadius`/`zoneRadius`
// corners, `maxColumnGap` and the `--rows-max-w` cap derived from them) is
// multiplied by `scale`, so raising this grows the whole board in proportion
// rather than just the cards; the card faces are inline SVG, so they resharpen at
// any size instead of blurring.
//
// Above 1 the design footprint stops being the maximum and becomes what it
// really is — the size the *fits* are expressed in. Both fits still bind first
// on a smaller window (a board needs `maxScale × 711px` of width and
// `maxScale × 526px + 16px` of height to reach the ceiling, for the eight-column
// deal), so this only takes effect once there's genuinely room, and a laptop
// that falls short simply settles a little below it rather than clipping.
let maxScale = 1.35

// The share of the stage width the row of cards fills; the rest is the gaps
// `space-evenly` opens around and between the columns. Kept well below 1 so the
// columns breathe — a squared pile's zone stays framed, and the leftover width
// is real space for `space-evenly` to spread as equal outer/inter-card gaps
// rather than the columns butting card-to-card.
let fillFraction = 0.9

// The narrowest stage a row of `columns` piles can be laid into with the cards still
// clearing the `minScale` floor: `applyScale`'s width target (`fillFraction · avail /
// columns / cardW`) solved for the floor instead of for the scale.
//
// Docking the debug console (#275) takes a strip of that width away from the board, and
// is *refused* when what's left falls below this — the layout's own arithmetic rather
// than a guessed pixel breakpoint. Below the floor `applyScale` clamps rather than
// clipping, so a docked board would still render; it would just render at cards the
// width fit no longer sized, which is precisely the outcome the refusal exists to
// prevent.
//
// Note what this is and isn't: it's the *width* term of the clamp, so it says nothing
// about the height term that binds on a short screen. A landscape phone is wide enough
// on paper to clear this — it just has nothing worth docking beside. Docking there stays
// out of scope by being keyboard-only rather than by being refused here.
let minStageWidth = (~columns: int) => minScale *. Int.toFloat(columns) *. cardW /. fillFraction

// The widest each `space-evenly` gap between columns is allowed to open before
// the row stops spreading (#173). Past the point where the cards have hit their
// ceiling (`scale` capped at `maxScale`), a wider stage keeps pouring its extra
// width into these gaps — on a wide desktop that leaves the columns marooned in a sea
// of green. So the row's width is capped at the point each gap reaches this
// (see `applyScale`'s `--rows-max-w`), and the leftover stage width becomes equal
// left/right margins instead. Half a card reads as a generous-but-tidy column
// gap; the board settles into a solitaire-table shape rather than sprawling.
let maxColumnGap = 0.25 *. cardW

// Headroom, in cards, the height fit (`applyScale`) leaves below the deepest pile
// (#—). Card size is now bounded by height as well as width: on a short screen the
// tallest column — the deepest cascade's fan plus the top row — must fit the safe
// vertical height, or the fan runs off the bottom. Rather than size to the deal's
// depth exactly (which would overflow the moment a pile grew), fit the deepest
// *opening* pile plus this many more cards, so a pile can take on that many before
// it reaches the edge. Held stable from the opening deal so cards don't resize as
// piles grow and shrink mid-game. (A pile that grows past this still overflows;
// the number is a tunable comfort margin, not a hard guarantee.)
let fanHeadroom = 5

// The opening deal animation (#115). The cards fly up from below the stage, one
// at a time, and these two knobs define the whole feel — everything else (the
// interval between cards, and their speed) is derived from them and the card
// count `n`:
//   - `dealMaxInFlight` (C) — how many cards may be moving at once, a cap kept
//     modest so a full deck stays cheap to composite.
//   - `dealPerCardMs` (P) — how long the deal spends *per card*, so the total
//     scales with the count: T = P·n, first card to last. Pacing by time-per-card
//     (rather than a fixed total) keeps small demos snappy — a handful of cards no
//     longer stretches across a whole deck's worth of time.
// From those, with C clamped to at most `n` and T = P·n:
//   - start interval between successive cards:  Δ = T / (n − 1 + C)
//   - per-card flight time (distance is fixed, so this *is* the speed):  t = C·Δ
//   - card i's start delay:  i·Δ
// which makes both constraints exact: at steady state exactly C cards are
// mid-flight, and the last card (start (n−1)·Δ, flight C·Δ) lands at
// (n−1+C)·Δ = T. Raising C deals each card faster but with more simultaneous
// motion; scaling P stretches or tightens the whole deal.
let dealMaxInFlight = 5
let dealPerCardMs = 67.

// The end-game "Finish" sweep animation (#160) reuses the deal's staggered-flight
// model — cards flying home one at a time — but from a different source order and
// trajectory (each card from where it *rests* to its foundation, rather than one
// shared off-stage origin). It carries its own knobs so the sweep can be tuned to
// a different feel than the deal without disturbing it; the C/P → Δ/flight
// derivation is identical (see the deal knobs above).
let finishMaxInFlight = 5
let finishPerCardMs = 90.

// …and a third set for a move played by a *typed command* (#273), which shares the
// same flight path (`flyCards`) and so the same C/P → Δ/flight derivation. The knobs
// differ because the job does: a sweep is fifty-odd cards on their way to a win, while
// a console move is one card — or a short `moverun` — that has to be followable by
// someone reading the log to see what the command did. So each card flies slower, and
// at most two are in the air at once, which is what makes a run read as cards moving
// in order rather than as one undifferentiated blob.
let commandMaxInFlight = 2
let commandPerCardMs = 170.

// …and a fourth for the solver playing a whole line (#291). Autoplay is a *run of
// moves*, not one move with many cards in it, so each planned move flies on its own
// and the next only starts once its cards have landed — what you watch is the line
// being played, in order, rather than a board that rearranged itself while you
// blinked. The knobs are the console's, quickened: a plan is forty-odd moves, and at
// the single-move pace above the whole thing would outstay its welcome. They're a
// separate pair precisely so the sequence can be re-timed (or slowed back down to
// watch a particular deal) without touching how a typed move reads.
let autoplayMaxInFlight = 3
let autoplayPerCardMs = 140.

// A flying card is lifted onto this z base — well above any resting slot layer —
// so it rides over the source fan it's leaving and lands on top of the foundation
// cards already home. A per-card `+ i` (its launch index) preserves arrival-order
// stacking — later ranks on top, King last — while several cards are in flight at
// once; the final `reflowAll` then settles every foundation to its own slot order.
let finishFlightZBase = 100000

// The staggered-flight timing shared by the deal (#115) and the finish sweep
// (#160): from the max-in-flight cap C, the per-card budget P and the card count
// n, derive the start interval Δ between successive cards and each card's flight
// time t = C·Δ (see the deal knobs above for the full derivation). C is clamped to
// at most n so the last card's flight isn't padded past what the sequence needs.
let staggerTiming = (~maxInFlight, ~perCardMs, ~n) => {
  let c = Int.toFloat(maxInFlight < n ? maxInFlight : n)
  let total = perCardMs *. Int.toFloat(n)
  let delta = n > 1 ? total /. (Int.toFloat(n - 1) +. c) : total /. c
  let flight = c *. delta
  (delta, flight)
}

// The easing every staggered flight shares — a soft, overshoot-free ease-out.
let flightEasing = "cubic-bezier(0.22, 1, 0.36, 1)"

// One card's staggered flight, shared by the opening deal (#115) and the finish
// sweep (#160): animate a compositor-friendly `transform` from an offset `(dx, dy)`
// back to zero, so the card reads as travelling from `(its committed spot) + (dx,
// dy)` home to that spot (its left/top already hold it). `fill: "backwards"` holds
// the card at the offset through its `delay`, so a batch launched in one loop each
// waits its staggered turn. The deal flies every card from one shared off-stage
// origin; the sweep flies each from its own resting spot — only `(dx, dy)` differs.
// Returns the animation so a caller can track it (`outstandingAnimations`) or hang
// the sweep's completion off it.
let flyHome = (~wrapper, ~dx, ~dy, ~flight, ~delay) =>
  wrapper->animate(
    [
      {"transform": `translate3d(${Float.toString(dx)}px, ${Float.toString(dy)}px, 0)`},
      {"transform": "translate3d(0, 0, 0)"},
    ],
    {"duration": flight, "delay": delay, "easing": flightEasing, "fill": "backwards"},
  )

// The send-home gesture (#122) is a *double-tap* — two taps on the same card,
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

// A resting card gets a slight, hand-placed tilt (#65) so the tableau reads as
// dealt by a person rather than stamped down by a machine. The angle is
// *deterministic* — a cheap hash of the card's identity and where it now rests —
// which buys three things at once: it's stable across reflows and resizes (a card
// doesn't twitch to a new angle every time a neighbour moves), it *does* change
// when the card is placed somewhere new (so a drop re-tilts it, as a fresh
// placement would), and it needs no `Math.random`, keeping every render — the
// screenshots included — reproducible, in the same spirit as the loose deal's
// deterministic jitter above. Kept small so cards still read and stack cleanly.
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
// The tilt in degrees for `card` resting at (`pile`, `slot`). `pile`/`slot` are
// the resting place (a non-negative pile index and slot, or the loose-cluster
// sentinels below), so the primes below fold the identity and place into a value
// spread across `[-maxCardTilt, maxCardTilt)` without neighbouring cards or slots
// sharing an angle. All inputs are non-negative, so the `mod` stays positive.
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

// Because the tilt is keyed on *where a card rests*, a card re-tilts the moment it
// is laid out somewhere new — which the finish sweep (#160) does to every card at
// once, up front: `reflowAll` snaps each node onto its foundation (and re-tilts it
// there) while the flights hold it visually at its source until its staggered turn.
// Left alone, the whole board would swing to its landing angles in unison, in
// place, before anything moved (#241). These two properties push a card's tilt
// transition out to its own launch delay and stretch it over its flight, so the
// rotation rides along with the movement — a tilt at the source, a tilt at the
// destination, and the turn between them happening while the card is in the air.
// (With the hand-placed look off both angles are 0°, so nothing rotates either
// way.) The CSS defaults these to the plain in-game snap, so they're only set for
// the length of a sweep and cleared again once it settles.
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
// player wants the hand-placed look at all (#65). When they've turned it off the
// angle is a dead-square 0°, so `--card-rot` snaps every card back to true — the
// `.card-art` transition easing it there — without any other layout change.
let tiltFor = (~enabled, ~card, ~pile, ~slot) => enabled ? cardTilt(~card, ~pile, ~slot) : 0.

// The loose cluster isn't a pile, so its cards tilt off this sentinel "pile"
// (a large constant that can't collide with a real pile index) plus their
// cluster index as the slot.
let looseTiltPile = 1000

// Build a scene that plays `game`: its id/label name the scene in the picker,
// and its piles and opening deal drive everything below.
//
// `~initial` forces the board into a given `GameState` instead of the opening
// deal — the hook the URL's `?state=` scenario uses to drop straight into a
// mid-game position (see `AppUrl` / `Scenario`). Omitted, the scene opens from the
// game's own deal exactly as before.
//
// `~newDeal` makes the board *re-dealable* (#108): a thunk that yields a fresh
// game to open — a new seed each call, decided by the caller (the web-app deals
// FreeCell a random seed; #98's deal-number entry can supply a chosen one).
// Omitted, the board isn't re-dealable (the fixed-layout demos).
//
// `~publish` is how the chrome reaches everything the board does *on request* — the
// re-deals, Undo, the console runner, the relayout, the share-link hooks, the shake
// control. One record, handed over once as the scene mounts; see `controls` above for
// what's on it and why it's one value rather than the eleven separate callbacks this
// signature used to carry (#300). Omitted, the board simply publishes nothing: the
// tests that only watch a board play, and any caller with no chrome to drive.
//
// `~options` is a *ref* to the driver preference record (#125), read *live* at
// each post-move step so a menu toggle (#139) that flips a field takes effect on
// the very next move without rebuilding the board. Its `autoCollect` flag (on by
// its `default`) sends every *safe* card home after an accepted move; the app's
// menu owns this ref and rewrites it when the player flips the setting.
//
// `~tiltEnabled` is a *ref* to the hand-placed-tilt preference (#65), read *live*
// wherever a card is laid out so a menu toggle takes hold on the next relayout
// without rebuilding the board — the same live-ref trick as `~options`. When it's
// off, cards rest dead-square. `controls.relayout` is its companion: a thunk that
// re-lays every resting card, so flipping the tilt switch re-tilts (or un-tilts) the
// board in place, immediately, rather than only on the next move.
//
// `~onHistory` is the reverse channel to `controls.undo` (#85) — after every state
// change the board calls it with the current `canUndo` so the top bar can enable or
// disable the button. Undo works even from a won board: a victory is just another
// recorded state, so stepping back tears the win overlay down and returns to the prior
// position. (Redo lives on in `core`'s `History` for the CLI, but the web app's top bar
// no longer surfaces it.)
//
// `~loadHistory` restores a *whole* saved game (#177): the board's undo/redo stack,
// not just its present position — so a resumed game comes back with Undo still
// walking back through the moves played before the player left. It applies only to
// the opening build of each mount (a re-deal starts a clean history); when it
// yields a save, that save's present state seeds the board and `~initial` is
// ignored. It carries the play tally too (`SaveState.t`, #289), so a resumed game's
// move and undo counts pick up where they left off rather than restarting at zero
// on a game that's half played.
//
// It's a *thunk*, read afresh on every mount, and that matters: a scene can be
// mounted more than once (the switcher re-mounts on a scene change), and a value
// read when the scene was *built* is a snapshot of storage at page load. Re-opening
// a board from that snapshot silently rewinds the game to where it stood when the
// page loaded — and if the player had resumed a finished game that session, brings
// the victory back with it. Reading at mount time resumes whatever is saved *now*,
// which is the board they were just playing.
//
// `~persist` is its write side: a
// sink handed the board's full history after every change (each move, undo, and the
// opening/New Game/Restart builds), so the driver can save it. Both are omitted for
// the demos and for any board opened from a `?state=`/`?seed=` link, so
// save-and-resume attaches only to a plain FreeCell game.
// The game clock (#302), read where the impurity belongs: `Session` stamps a win with a
// moment it's handed, and this is the layer that has a wall clock to hand it. The same
// line the terminal draws — see the comment above `Cli.randomSeed`.
let clock = () => Date.now()

let make = (
  ~initial: option<GameState.t>=?,
  ~loadHistory: unit => option<SaveState.t>=() => None,
  ~persist: option<SaveState.t => unit>=?,
  ~newDeal: option<unit => Game.t>=?,
  // The board's published surface, handed over once as this scene mounts (#300). See
  // `controls` above, and the note on `~publish` in the prose above this signature.
  ~publish: option<controls => unit>=?,
  ~onHistory: option<bool => unit>=?,
  // The board's other reverse channel (#98), sibling of `~onHistory`: the deal number
  // of the board now on the table, or `None` for a board that isn't showing a deal —
  // a fixed-layout demo (no seed at all), or a build that restored a *history*, where
  // the cards came from a saved or shared stack and the deal underneath them is not
  // this build's to name (the driver knows; see `Main`). Called on every build, so a
  // New Game reports its fresh seed and a scene switch to a demo reports `None` — the
  // chrome's Share button always offers the deal actually showing rather than the one
  // this scene first mounted with. Reported rather than read for the same reason
  // `~onHistory` is: the chrome renders from it, so it can't reach into the board.
  ~onDeal: option<option<int> => unit>=?,
  // …and its read side, for the one thing the board draws rather than reports: the
  // console's `print` (#273) renders a text board, and a board names the deal it's
  // showing. The number can't come from `game.seed` — a posed position sits on a game
  // whose own seed didn't produce it, and a resumed game's number lives in the driver's
  // storage — so the chrome, which resolves all of that for the Share buttons, hands
  // back whatever it resolved. Defaults to "no number", which is the truthful answer for
  // a board built by a test or a demo.
  ~currentDeal: unit => option<int>=() => None,
  // The victory share (#264): what the win overlay's Share button calls, and whether
  // it's offered at all. Omitted by the demos and the tests that don't care, in which
  // case the overlay is the New Game button alone, exactly as before.
  ~winShare: option<winShare>=?,
  ~options: ref<Options.t>=ref(Options.default),
  ~tiltEnabled: ref<bool>=ref(true),
  // `~skipDealAnimation` drops the cards straight into their resting places instead
  // of flying them in — the URL's `?animate=off` (see `AppUrl`), for a screenshot of
  // the *already-dealt* board rather than a frame mid-deal. The board is laid out at
  // its rest positions either way; this only suppresses the cosmetic flight, exactly
  // as the OS "reduce motion" preference already does. Applies to every deal this
  // scene runs, re-deals included — and, since #273 gave the two flight paths one
  // implementation (`flyCards`), to the finish sweep and a commanded move as well.
  // The name is the flag's origin rather than its scope: what it means is "this board
  // isn't animating", which is what a screenshot or a deterministic test wants.
  ~skipDealAnimation: bool=false,
  game: Game.t,
): Scene.t => {
  id: game.id,
  label: game.name,
  mount: container => {
    // The board lives in its own host so a New Game re-deal can tear the whole
    // board down and rebuild it — fresh zones and card nodes, no stale leftovers
    // from the previous deal — while leaving the New Game control (below) in
    // place. Everything from the playfield down is (re)built into this host by
    // `buildBoard`.
    let boardHost = WebDom.createElement("div")
    boardHost->WebDom.setAttribute("class", "table-board")

    // Any finish-sweep flights (#160) still in the air, held at mount scope — above
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

    // An autoplay in progress (#291) is the one thing on this board that spans several
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

    // The deal currently on the table (#156), held at mount scope so Restart can
    // replay it. `buildBoard` records its `game` here on every build, so a New Game
    // re-deal updates it and a later Restart rebuilds the *new* seed's opening
    // layout rather than the one the scene first mounted with.
    let currentGame = ref(game)

    // The current board's resize relayout (#172), held at mount scope so the
    // `ResizeObserver` set up once below always drives the *live* board. Every
    // `buildBoard` swaps in its own board's relayout here, so a resize after a New
    // Game reflows the fresh board rather than the torn-down one whose closure the
    // observer would otherwise still hold. Starts a no-op until the first build.
    let resizeRelayout = ref(() => ())

    // The live board's answer to the debug console's dock-refusal test (#275), held at
    // mount scope for the same reason as `resizeRelayout` above: the column count it
    // measures against belongs to a *build*, so each `buildBoard` repoints this at its
    // own. Until the first build there's no board to ask, so nothing may be docked.
    let dockFit: ref<float => bool> = ref(_ => false)

    // The live board's shake operations (#235), held at mount scope so the single
    // shake subscription below always jostles — or squares up — the *current* board:
    // every `buildBoard` repoints these at its own fresh card nodes. No-ops until the
    // first build.
    let boardOps = ref({jostle: () => (), squareUp: () => ()})

    // The live board's undo/redo history, held at mount scope for the same reason as
    // `resizeRelayout` above: `history` is rebound by every `buildBoard`, so a reader
    // that closed over one build would go on reporting a torn-down board's stack
    // after a New Game. Each build repoints this at its own; the share button
    // (`ShareLink`, via `controls.readHistory`) reads through it and so always
    // encodes what's actually on the table. `None` until the first build.
    let readHistory: ref<unit => option<SaveState.t>> = ref(() => None)

    // The three published actions that genuinely belong to a *build* rather than to the
    // mount — the top bar's Undo (#85), the console's command runner (#273) and the
    // tilt relayout (#65) — held here for the same reason as `readHistory` above. Each
    // closes over one board's nodes and history, so every `buildBoard` repoints these
    // at its own, and the `controls` record published once at mount dispatches through
    // them. That's what lets the chrome take the board's surface a single time and
    // still be driving the board actually on the table after a New Game — where before
    // each of the three had to be re-published, by name, on every build.
    //
    // No-ops until the first build: nothing to undo, nothing to re-lay, and a command
    // answers with nothing, which is the truthful reply for a board not yet dealt.
    let liveUndo: ref<unit => unit> = ref(() => ())
    let liveRunCommand: ref<Command.t => array<Render.line>> = ref(_ => [])
    let liveRelayout: ref<unit => unit> = ref(() => ())

    // The active `devicemotion` shake subscription, `Some` while Wiggle Waggle is on
    // and permission granted (#235). `Motion.subscribeShake` already parks the
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
    // stack (#177) instead of a clean one — the resume path; a re-deal calls
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
      // the fresh board — and stop an autoplay still walking the old board's line
      // (#291), which the cancelled flight would otherwise hand straight on to.
      cancelOutstanding()
      interruptPlay()
      WebDom.clear(boardHost)
      // Narrate the (re)deal to the debug console (#213): every board rebuild — the
      // opening deal, a New Game, a Restart, or a debug-states load — passes through
      // here, so this one line covers them all. A forced `~initial` state marks the
      // scenario/debug-states loads apart from a fresh deal.
      DebugLog.message(
        "build board: " ++ game.id ++ (initial->Option.isSome ? " (forced state)" : ""),
      )
      // Record the deal now on the table so Restart (#156) can replay this exact
      // game — a New Game re-deal that lands here updates what Restart will rebuild.
      currentGame := game
      // Tell the chrome which deal is showing (#98), from the same spot and for the
      // same reason: every board rebuild passes through here, so a New Game reports
      // its new seed and a scene switch to a demo reports `None`.
      //
      // The rule is exactly "what's on the table *is* this deal's opening position",
      // which is the only claim a deal-number share can make good on. So a *fresh*
      // deal — the opening one, a New Game, a Restart — reports the game's seed, and
      // the two builds that put something else on the table report `None`:
      //
      //   - a restored `~history` (a resumed save, or a shared game landing): the
      //     cards come from that stack, and the deal they were first dealt from isn't
      //     the one `game` carries — a resume mounts on a freshly-seeded deal whose
      //     only job is to supply card nodes. Naming that seed would send someone to a
      //     board nobody is looking at, the one failure a share button can't afford.
      //     The driver knows where the history came from and fills the gap (`Main`);
      //   - a forced `~initial` state (`?state=`, or the debug-states rows): a posed
      //     position, not a deal.
      //
      // Falling to `None` on those two also keeps the reporting in step with saving:
      // a seed is reported precisely on the builds that become the saved game
      // (`~persistThis`), so the driver can persist it without a second rule.
      //
      // Named, because the session below carries the same fact for the same reason — the
      // deal a board can honestly say it is — and two spellings of one rule is one too
      // many.
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

      // The drop zones, laid out in role-grouped rows (#94) so a sixteen-pile
      // FreeCell board is playable: free cells and foundations across the top,
      // cascades below. The rows stack in a flex *column* (`.drop-rows`), so the
      // cascade row is pushed clear of the top row automatically and its fans grow
      // into the space beneath. A board that carries only one of the two groups —
      // every existing card-table demo — collapses to a single row, laid out
      // exactly as before. Each row lays itself out with flexbox, so a zone's live
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
        // The static "empty pile" indicator (#166): a purely-visual, card-sized
        // dashed placeholder, split off from the zone's old overloaded outline. A
        // resting card (a sibling `.stacking-card` layered above) occludes it
        // pixel-for-pixel, so the dashed cue shows only on empty piles, while the
        // `.drop-zone` around it stays the hit-test box and the larger highlight
        // frame. `pointer-events: none` (in CSS) keeps it out of hit-testing.
        let slot = WebDom.createElement("div")
        slot->WebDom.setAttribute("class", "drop-zone__slot")
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

      // The single source of truth for this board (#298): one `Session.t` holding where
      // every card rests (#77/#82), the history behind it (#85), the tally (#289) and the
      // clock (#302) beside it, and the house rules it's played under. The view
      // re-derives every pile's layout from its present state and keeps only transient
      // geometry (below).
      //
      // This used to be four refs stepped in lockstep, and the stepping was written out
      // three times — at the drop, at the double-tap send-home, and at a typed command.
      // Now a move hands an action to `Session.dispatch` and the view adopts what comes
      // back: settling, the undo step, the tally and the clock are all one call, and it's
      // the same call the terminal makes.
      //
      // Seeded from a saved game when there is one (#177), otherwise from the board's
      // opening deal or the forced `~initial` scenario. Per-build, like everything else
      // here, so a New Game or a Restart starts from a zero tally and a running clock
      // while a resumed or shared game picks up what its save carried.
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

      // Where every card rests right now. A function rather than a stored value, so the
      // session stays the one answer to the question.
      let state = () => Session.present(session.contents)

      // The live session with the driver's current house rules pushed into it. The
      // switches live at mount scope and outlive any one board — a New Game doesn't
      // change the rules you're playing under — so they're the driver's to carry and the
      // session's to consult, which is the split the terminal draws too (see `Repl`).
      let current = () => Session.withOptions(session.contents, options.contents)

      // What this build would save: read at call time, so a caller always gets the board
      // as it now stands.
      let currentSave = (): SaveState.t => Session.save(session.contents)

      // Point the mount-scope reader at *this* build's save, so the share button
      // encodes the board on the table rather than one a re-deal has since replaced.
      readHistory := (() => Some(currentSave()))

      // Persist the board's whole undo/redo history and tally after any change (#177,
      // #289), when the driver wired a `~persist` sink. A no-op otherwise — the demos,
      // and any board opened from a `?state=`/`?seed=` link, pass none — so saving
      // attaches only to a plain FreeCell game. Called from `afterChange`, `undo`,
      // and each fresh build.
      let persistCurrent = () =>
        switch persist {
        | Some(save) => save(currentSave())
        | None => ()
        }

      // The DOM node for each model card, so a pile derived from `state` (structural
      // `{suit, rank}` cards) lays out onto the *same* elements every reflow — the
      // identity bridge (#45) from model card to node. Every `makeCard` registers
      // itself here; lookup is the deck-scoped `GameState.sameCard`.
      let nodes: array<card> = []
      let nodeFor = (data: Deck.card) => nodes->Array.find(n => GameState.sameCard(n.data, data))

      // Put every card's tilt transition back to the stylesheet's in-game snap,
      // dropping the per-card delay/duration a finish sweep borrowed (#241). Called
      // wherever a sweep ends — its own settle, or an undo cutting it short — so a
      // later drop re-tilts immediately instead of on the dead sweep's schedule.
      let clearTiltTimings = () => nodes->Array.forEach(c => clearTiltTiming(c.wrapper))

      // The depth the height fit sizes the deepest fan to (#—): the deepest *opening*
      // pile plus `fanHeadroom`, captured once here so cards keep a stable size as
      // piles grow and shrink through play. Only Fanned piles grow downward, so a board
      // with no fans (every pile Squared) contributes no fan height — `referenceDepth`
      // then goes unused (see `applyScale`). Read from the opening `state`, so a New
      // Game rebuild recomputes it for that deal.
      let hasFanned = game.piles->Array.some((p: Game.pile) => p.stacking == Game.Fanned)
      let openingMaxDepth =
        zones->Array.reduce(0, (m, z) =>
          Math.Int.max(m, Array.length(GameState.cardsInPile(state(), z.index)))
        )
      let referenceDepth = openingMaxDepth + fanHeadroom

      // How much the design footprints are scaled to fit the stage. Cards fill
      // `fillFraction × width` split across the busiest row (`fillFraction · width
      // / widestRow`), capped at `maxScale` so a wide screen doesn't blow the
      // cards up without bound, and floored so a crowded, narrow one keeps them
      // legible. Held in a ref because the geometry (reflow, the deal) reads it,
      // and recomputed from the stage's live width the moment before the deal —
      // the one point at which the stage is known laid out.
      let scale = ref(1.)
      // The stage width the layout was last sized to (#172). Recorded by every
      // `applyScale` so a later resize can scale the loose cards — which live only
      // as pixel x/y and so aren't touched by `reflowAll` — by the width ratio,
      // keeping them where they sit proportionally. Zero until the first `deal`
      // runs, which also gates the resize relayout below (nothing to reflow yet).
      let lastWidth = ref(0.)
      let applyScale = () => {
        // The stage width already excludes the nav rail — `playfield` is laid out
        // beside it, not under it — so the only term left to subtract is the display
        // cutaway: the safe-area insets `.drop-rows` is pinned inside (#179). Sizing
        // the cards to that inset width (rather than the raw stage) keeps the columns
        // fitting the row on a landscape phone with a side notch, instead of being
        // sized for a stage wider than they actually get and packing together (their
        // `space-evenly` gaps squeezed to nothing). Off a cutout device the insets are
        // 0, so `avail == width` and nothing changes. The cutaway is read here, not
        // folded into the `--rows-max-w` cap below, which stays a pure spreading limit.
        let width = boundingRect(playfield).width
        let cs = getComputedStyle(rows)
        let cutaway = parseFloat(cs["left"]) +. parseFloat(cs["right"])
        let avail = width -. cutaway
        // Height fit (#—): card size is bounded by height as well as width, so a short
        // screen (a landscape phone) shrinks cards to keep the tallest column on-screen
        // instead of letting the fan run off the bottom. The vertical budget mirrors what
        // reflow stacks into the playfield's live height: each row's base box
        // (`rowsCount · zoneBaseHeight`) plus the deepest fan (`(referenceDepth − 1) ·
        // fanStep`), all scaled, above the fixed `top` offset and the inter-row `rowGap`.
        // Solving `budget ≤ height` for the scale gives a height cap; the smaller of it
        // and the width target wins. On a tall screen the width target is smaller, so
        // nothing changes there. A Squared-only board grows no fan, so its fan term is 0.
        let availH = boundingRect(playfield).height
        let rowsCount = twoRows ? 2 : 1
        let fanExtent = hasFanned ? Int.toFloat(referenceDepth - 1) *. fanStep : 0.
        let heightDenom = Int.toFloat(rowsCount) *. zoneBaseHeight +. fanExtent
        let vFixed = parseFloat(cs["top"]) +. (twoRows ? parseFloat(cs["rowGap"]) : 0.)
        if avail > 0. && widestRow > 0 {
          let widthTarget = fillFraction *. avail /. Int.toFloat(widestRow) /. cardW
          let heightTarget =
            availH > 0. && heightDenom > 0. ? (availH -. vFixed) /. heightDenom : widthTarget
          scale := Math.max(minScale, Math.min(maxScale, Math.min(widthTarget, heightTarget)))
        }
        if width > 0. {
          lastWidth := width
        }
        // Publish every scaled footprint the CSS needs, so `.stacking-card`,
        // `.drop-zone` and `.drop-zone__slot` resize in step with the JS geometry
        // below. Each of these is a design constant above times the live scale — the
        // stylesheet consumes them directly and derives nothing, so the proportions
        // (`cardH / cardW`, the corner ratios, `zoneInset`) are stated once, here,
        // rather than restated as `calc()` ratio literals that can drift from them.
        let s = style(playfield)
        let px = v => Float.toString(v *. scale.contents) ++ "px"
        s->setProperty("--card-w", px(cardW))
        s->setProperty("--card-h", px(cardH))
        s->setProperty("--card-radius", px(cardRadius))
        s->setProperty("--zone-w", px(zoneWidth))
        s->setProperty("--zone-h", px(zoneBaseHeight))
        s->setProperty("--zone-radius", px(zoneRadius))
        // Cap the row's width so the columns stop spreading on a wide desktop (#173):
        // the widest row's zones (`widestRow · zoneWidth`) plus its `widestRow + 1`
        // `space-evenly` gaps grown to at most `maxColumnGap` each, all at the live
        // scale. `.drop-rows` takes this as a `max-width` and centres itself, so once
        // the stage is wider than this the extra width falls into equal left/right
        // margins rather than ever-wider gaps. Below the cap the value exceeds the
        // stage width, so the `max-width` is slack and the row spreads as before.
        s->setProperty(
          "--rows-max-w",
          px(Int.toFloat(widestRow) *. zoneWidth +. Int.toFloat(widestRow + 1) *. maxColumnGap),
        )
      }

      // The dock-refusal test for *this* board (#275): could it give up `inset` px of
      // stage width and still deal cards above `minScale`? Same two terms `applyScale`
      // works from — the stage, less the display cutaway `.drop-rows` is pinned inside
      // (#179) — against the floor solved for width (`minStageWidth`).
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
            stage -. cutaway -. inset >= minStageWidth(~columns=widestRow)
          }
        )

      // The zone the dragged card's rect hits, if any — the shared primitive for
      // both the live hover highlight and the snap-on-drop decision. Horizontally
      // it's strict (the card's *centre* must fall inside the zone) so tightly
      // packed columns stay distinguishable; vertically it's generous (any overlap
      // at all counts) so a card need only graze a zone's top or bottom to land in
      // it (#183).
      let zoneAt = (cardRect: domRect) => {
        let cx = cardRect.left +. cardRect.width /. 2.
        let cardTop = cardRect.top
        let cardBottom = cardRect.top +. cardRect.height
        zones->Array.find(({el}) => {
          let r = boundingRect(el)
          cx >= r.left &&
          cx <= r.left +. r.width &&
          cardBottom >= r.top &&
          cardTop <= r.top +. r.height
        })
      }

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
      // screen at all — hidden from the accessible tree too (#267). Reading the
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
        // The pile's stacking rule (#76), consulted to decide which cards head a
        // legal run and so may be lifted as a supermove span (#123).
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
              zr.top +. zoneBaseHeight *. scale.contents /. 2. -. cr.height /. 2. -. pr.top
            c.x := baseX
            c.y :=
              switch zone.stacking {
              | Game.Squared => baseY
              | Game.Fanned => baseY +. Int.toFloat(i) *. fanStep *. scale.contents
              }
            place(c)
            // Re-tilt the card for where it now rests (#65): stable while the pile
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
            // A card is grabbable when it *heads a legal run* (#123): the tail from
            // its slot to the top of the pile must itself be a run under the pile's
            // rule. The top card is the length-1 case (a run of one), so single-card
            // play is unchanged; a deeper run-head lifts its whole span as a
            // supermove. Every other buried card stays pinned.
            let headsRun = Rules.isRun(rule, cards->Array.slice(~start=i, ~end=count))
            c.draggable := headsRun
            headsRun
              ? classList(c.wrapper)->removeClass("stacking-card--buried")
              : classList(c.wrapper)->addClass("stacking-card--buried")
            // Take the cards this pile *hides* out of the accessible tree (#267).
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
        | Game.Fanned if count > 1 => Int.toFloat(count - 1) *. fanStep *. scale.contents
        | _ => 0.
        }
        style(zone.el)->setHeight(
          Float.toString(zoneBaseHeight *. scale.contents +. fanExtent) ++ "px",
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
      // deal (#115) and the finish sweep (#160).
      let withSnapSuppressed = body => {
        classList(playfield)->addClass("dealing")
        body()
        requestAnimationFrame(() => classList(playfield)->removeClass("dealing"))->ignore
      }

      // Narrate one change to the debug console (#213). Every way a card can move — a
      // drop, a double-tap send-home, a typed command, a step of a solver's line — ends
      // in a `Session.change`, and this is the one thing that turns one into a sentence.
      // That's why the change carries its `action`: the move a typed command made is one
      // this file never saw, and it still has to be able to say it.
      //
      // **One line per move**, not two. The old pair said the action and then its
      // outcome, which meant the commonest thing in the log — a move that worked — cost
      // two lines to say one thing, and the second of them said it in the reducer's
      // vocabulary (`result: accepted`) rather than the board's. Now the move is a
      // sentence (`Render.action`) with a ✓ on the end of it, and only a *rejection*
      // spends a second line: the mark says it bounced, the line under it says why, in
      // `core`'s own words (`Command.reason`) so a refusal reads the same in a terminal.
      //
      // Built only when something is listening: `DebugLog`'s own calls short-circuit on
      // that, and this composes a document before it calls one, so it checks first.
      let narrate = (~before: GameState.t, change: Session.change) => {
        if DebugLog.enabled() {
          let accepted: Render.span = {text: " ✓", ink: Render.Title}
          let refused: Render.span = {text: " ✗", ink: Render.Plain}
          // A lawful no-op (#215) — an identity re-drop onto the pile a card already
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

      // Play an action into the board's session (#298). The pointer paths — a drop
      // (`endDrag`) and the double-tap send-home — come through here; a typed command
      // reaches the same `Session.dispatch` through `Session.step` instead, and is
      // narrated by the same `narrate` above.
      let dispatch = (action: Reducer.action): Session.change => {
        // A move of the player's own — a drop, a send-home, a typed one — takes the
        // board off whatever line an autoplay was walking (#291), so it stops the run.
        // Autoplay's own steps are committed by the session and never come through here,
        // which is what makes this the clean "the player did something" signal.
        interruptPlay()
        let before = state()
        let (next, change) = Session.dispatch(~clock, current(), action)
        session := next
        narrate(~before, change)
        change
      }

      // The win overlay (#121): a dimmed panel over the board announcing the win,
      // with a New Game button to play on — and, when the driver has a deal number to
      // hand out, a Share button beside it (#264). Shown when a move completes every
      // foundation (`GameState.hasWon`); the button re-deals a fresh FreeCell
      // (`newDeal`) or, for a fixed-layout board, replays the same deal — either way
      // `buildBoard` clears `boardHost` first, so the overlay is torn down with the
      // rest of the board and can't linger. Only one is ever raised at a time.
      //
      // It reports the game — the clock and the tally — but doesn't *take* either. Both
      // were settled by the move that won (#298), which is why this raises a panel and
      // saves nothing: the winning move's own save already says the game is over.
      let winShown = ref(false)
      // The live overlay element, kept so undo can tear it down when stepping back
      // out of a win (#85) — undoing a victory removes the panel and returns the
      // board to the prior, still-playable position.
      let winOverlay = ref(None)
      let showWin = () =>
        if !winShown.contents {
          DebugLog.message("win")
          winShown := true
          // The clock stopped when the *board* was won, not here (#302/#298): the
          // session stamps it as it records the winning move, so the number reports how
          // long the game took rather than how long the last card took to fly. A save
          // that already carries a `wonAt` keeps it, so reopening a won board reports the
          // game's own length rather than how long ago you played it.
          let overlay = WebDom.createElement("div")
          overlay->WebDom.setAttribute("class", "win-overlay")

          let panel = WebDom.createElement("div")
          panel->WebDom.setAttribute("class", "win-panel")

          let title = WebDom.createElement("p")
          title->WebDom.setAttribute("class", "win-panel__title")
          title->WebDom.setTextContent("You win!")

          // What the game cost (#289), under the title: every move made and every undo
          // taken. Read now, as the overlay goes up, so it describes the game that was
          // just won — and re-read on each win, since undoing back out of a victory and
          // playing on raises a fresh panel with the larger numbers it earned.
          let tally = WebDom.createElement("p")
          tally->WebDom.setAttribute("class", "win-panel__stats")
          tally->WebDom.setTextContent(Stats.summary(session.contents.stats))

          // The buttons sit in a row of their own, so a second one lands beside New
          // Game rather than under it and the panel stays as wide as its widest line.
          let actions = WebDom.createElement("div")
          actions->WebDom.setAttribute("class", "win-panel__actions")

          let button = WebDom.createElement("button")
          button->WebDom.setAttribute("type", "button")
          button->WebDom.setAttribute("class", "win-panel__button")
          button->WebDom.setTextContent("New Game")
          button->WebDom.addEventListener("click", () =>
            switch newDeal {
            | Some(freshDeal) => buildBoard(freshDeal())
            | None => buildBoard(game)
            }
          )
          actions->WebDom.appendChild(button)->ignore

          panel->WebDom.appendChild(title)->ignore
          // How long it took (#302), between the headline and the tally: the biggest of
          // the three numbers to look at, since it's the one you'd say out loud. Its own
          // element rather than another clause on the tally line, because it's the one
          // that can be missing — a game restored from a save written before the clock
          // existed has no time to report, and a line that sometimes reads
          // "94 moves · 0 undos" and sometimes "4:07 · 94 moves · 0 undos" is harder to
          // read at a glance than a line that's sometimes simply not there.
          switch Timing.summary(session.contents.timing) {
          | Some(text) =>
            let time = WebDom.createElement("p")
            time->WebDom.setAttribute("class", "win-panel__time")
            time->WebDom.setTextContent(text)
            panel->WebDom.appendChild(time)->ignore
          | None => ()
          }
          panel->WebDom.appendChild(tally)->ignore
          panel->WebDom.appendChild(actions)->ignore

          // The victory share (#264), offered only when the driver has a deal to hand
          // out — asked *now*, as the overlay goes up, so the answer is about the board
          // that was just won rather than whatever the scene mounted with.
          //
          // The click calls `share` with nothing awaited in front of it, so the
          // gesture's transient activation survives into `navigator.share` (see
          // `ShareLink.deliver`). That's affordable here precisely because a victory
          // shares the *deal*: a `?seed=` link is built from a number, with no
          // compression standing between the tap and the sheet.
          //
          // The status line beneath reports where the link went — the only
          // acknowledgement a desktop player gets, since the clipboard route opens no
          // OS sheet. Unlike the menu's, it doesn't clear itself: the panel is torn
          // down by the very next thing the player does, so there's no stale state for
          // a timer to save us from. Its height is reserved in CSS so the line landing
          // doesn't jostle the buttons above it.
          //
          // …and withdrawn entirely from a game the solver had a hand in (#291). A
          // shared victory is a claim about how you played, and "I typed `autoplay`"
          // isn't one worth passing on — so the button is simply not built, rather
          // than built and made to explain itself. The test is `Stats.usedAutoplay`,
          // which is why the tally counts autoplays at all: it's the one fact about a
          // game that has to survive every undo back past the solver's moves, and it
          // does because the tally only ever counts up and is only ever reset by a
          // board being replaced (a New Game or a Restart, both of which build afresh
          // from `Stats.zero`).
          switch winShare {
          | Some(offer) if offer.available() && !Stats.usedAutoplay(session.contents.stats) =>
            let status = WebDom.createElement("p")
            status->WebDom.setAttribute("class", "win-panel__status")
            status->WebDom.setAttribute("aria-live", "polite")

            let shareButton = WebDom.createElement("button")
            shareButton->WebDom.setAttribute("type", "button")
            shareButton->WebDom.setAttribute("class", "win-panel__button win-panel__button--share")
            shareButton->WebDom.setTextContent("Share")
            shareButton->WebDom.addEventListener("click", () =>
              offer.share(~moves=session.contents.stats.moves, ~undos=session.contents.stats.undos)
              // Writing into the panel is safe even if it's been torn down by the time
              // the share resolves (an undo out of the win, a New Game): the node is
              // detached by then, and setting text on it changes nothing anyone sees.
              ->Promise.thenResolve(line => status->WebDom.setTextContent(line))
              ->ignore
            )
            actions->WebDom.appendChild(shareButton)->ignore
            panel->WebDom.appendChild(status)->ignore
          | _ => ()
          }

          overlay->WebDom.appendChild(panel)->ignore
          boardHost->WebDom.appendChild(overlay)->ignore
          winOverlay := Some(overlay)
        }

      // Tear the win overlay down (#85) — undo out of a victory removes the panel
      // and clears the flag so a later win can raise it again. A no-op when no
      // overlay is up.
      //
      // The clock starts again with it (#302), but not from here: stepping the session
      // back is what clears the won-at, because a board that isn't won hasn't been. It
      // stamps afresh on winning again, and the time then covers the detour — the same
      // stance the tally takes, where undoing never gives a move back.
      let removeWinOverlay = () =>
        switch winOverlay.contents {
        | Some(overlay) =>
          WebDom.remove(overlay)
          winOverlay := None
          winShown := false
        | None => ()
        }

      // Report the current undo availability to the chrome (#85) so the top bar
      // can enable or disable its button. Called after every state change.
      let reportHistory = () =>
        switch onHistory {
        | Some(f) => f(Session.canUndo(session.contents))
        | None => ()
        }

      // What's left to do once the session has taken a change: tell the chrome the undo
      // button has something to undo, and write the board to storage (#177) so a reload
      // resumes here, mid-game.
      //
      // The recording itself isn't here any more (#298). One undoable step per accepted
      // move, one move on the tally per recorded step, the clock stamped when the board
      // is won — that is `Session.dispatch`'s, which is what makes the drop, the
      // send-home, the typed command and the terminal agree by construction rather than
      // by four places remembering to.
      let afterChange = () => {
        reportHistory()
        persistCurrent()
      }

      // Fly a set of cards to wherever the *already-committed* `state` says they now
      // rest — the shared flight path (#273), extracted from the finish sweep (#160)
      // that first needed it. With the model already settled (so undo and persistence
      // are correct and robust to interruption), this is a pure *visual* catch-up over
      // `movedCards`: each card travels from where it was resting to its new slot,
      // `stagger` ms apart, over `flight` ms each. `onDone` fires once the last card
      // lands.
      //
      // The mechanism is the inverse-offset trick `animateDeal` uses: capture each
      // card's current spot, let `reflowAll` snap every node onto its new home, then
      // animate the transform back from (start − end) to zero. Two things ride along
      // with it, and they're the reason a console move goes through here rather than
      // leaning on `.stacking-card`'s plain left/top transition:
      //
      //   - the **z-hold**, so a card doesn't slide *under* the fan it's leaving.
      //     `reflowAll` relayers every pile by slot the instant it runs, which would
      //     drop a departing card behind cards it's still visually on top of;
      //   - the **tilt timing** (#241), so the hand-placed angle (#65) turns *over the
      //     move* instead of swinging in place before anything has moved.
      //
      // With the OS asking for reduced motion, with `?animate=off` (the same URL flag
      // that skips the opening fly-in), or with nothing to move, this collapses to an
      // instant `reflowAll` and fires `onDone` straight away.
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
            // its destination angle over the flight (#241) — otherwise the re-tilt that
            // `reflowAll` is about to apply would swing every card in place, in unison,
            // before anything had moved. Same index as the flight loop below, so a
            // card's rotation and its flight start together.
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
                    // timing has served its purpose (#241); the settling reflow below
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

      // The finishing sweep's flight (#160): the shared path above, timed by the finish
      // knobs — cards flying home one at a time from wherever they rest, with `onDone`
      // raising the win overlay so the victory reads as the sweep's payoff.
      let animateFinish = (movedCards: array<Deck.card>, ~onDone) => {
        let (stagger, flight) = staggerTiming(
          ~maxInFlight=finishMaxInFlight,
          ~perCardMs=finishPerCardMs,
          ~n=Array.length(movedCards),
        )
        flyCards(movedCards, ~flight, ~stagger, ~onDone)
      }

      // The same flight for a move nobody dragged — a command typed into the debug
      // console (#273). Its own knobs, because the two are different beasts: a sweep is
      // fifty-odd cards and wants to move along, while a typed move is one card (or a
      // short run) that has to be *followable* — you're reading the log to see what the
      // command did. Hence a slower flight and at most a couple in the air at once, so a
      // `moverun` reads as cards moving in order rather than as one blob.
      let animateCommand = (movedCards: array<Deck.card>, ~onDone) => {
        let (stagger, flight) = staggerTiming(
          ~maxInFlight=commandMaxInFlight,
          ~perCardMs=commandPerCardMs,
          ~n=Array.length(movedCards),
        )
        flyCards(movedCards, ~flight, ~stagger, ~onDone)
      }

      // …and one more for a move the *solver* played (#291), which is a commanded move
      // in every respect except its pace: it's one of forty on the way to a win, so it
      // flies to its own quicker knobs. One call per planned move, chained on `onDone`,
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

      // The end-game "Finish" button (#132): a conditional control — the same
      // show-when-relevant shape as the win overlay above — that appears exactly
      // when the board can be drained to a win by foundation moves alone
      // (`Reducer.canFinish`), i.e. victory is one tap away, and is hidden the rest
      // of the time. Tapping it plays the finishing sweep (`Session.finish`)
      // home to the detected win. It never gates manual play: you can still drag or
      // double-tap cards home one at a time — this is only the shortcut. Held in a
      // ref so `updateFinishButton` can add or remove it as `canFinish` flips after
      // each move; `winShown` hides it once the win overlay has taken over.
      let finishButton = ref(None)
      let removeFinishButton = () =>
        switch finishButton.contents {
        | Some(btn) =>
          WebDom.remove(btn)
          finishButton := None
        | None => ()
        }

      // Play the finishing sweep, whoever asked for it — the button below, or the
      // console's `finish` verb (#273). Written once so the two can't drift on what
      // "finish" does to the model: the sweep is committed *immediately* as one
      // undoable step (#85), so undo after a finish steps back to the position it
      // started from regardless of what the animation is doing.
      // The view's half of a sweep: the session has already taken it (one undoable step,
      // and the clock stamped if it won), so what's left is to say it, save it and fly
      // it. Shared by the Finish button below and the typed `finish` verb, which reach
      // the sweep by different routes and have to land it the same way.
      let flySweep = (moved: array<Deck.card>) => {
        DebugLog.line(Render.concat([[Render.plain("finish ")], Render.cardSpans(moved)]))
        afterChange()
        removeFinishButton()
        // Deliver the sweep as a staggered flight (#160) rather than an instant
        // jump; the win overlay lands only once the last card has arrived.
        animateFinish(moved, ~onDone=() =>
          if Session.hasWon(session.contents) {
            showWin()
          }
        )
      }

      let playFinish = () => {
        // The sweep takes the board somewhere no planned move goes, so it ends any
        // autoplay still walking a line (#291). Autoplay's own hand-over to the sweep
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
            let btn = WebDom.createElement("button")
            btn->WebDom.setAttribute("type", "button")
            btn->WebDom.setAttribute("class", "finish-button")
            btn->WebDom.setTextContent("Finish")
            btn->WebDom.addEventListener("click", () => playFinish()->ignore)
            boardHost->WebDom.appendChild(btn)->ignore
            finishButton := Some(btn)
          }
        }

      // Adopt whatever `history` now points at as the board's position — the shared
      // tail of undo and redo (#85). It re-derives the layout from the restored state
      // rather than animating: a step through history isn't a *move*, and easing cards
      // along a path they never took would misreport what happened.
      let adoptHistoryPresent = () => {
        // Stop any finish sweep still in flight before laying out the restored
        // position, so its cards don't keep flying toward foundations the step has
        // just emptied (the state is already committed, so nothing corrupts) — and
        // any autoplay still playing forward (#291), since a step through history is
        // the player saying they'd like the board back.
        cancelOutstanding()
        interruptPlay()
        // …including the tilt timing a cut-short sweep left on its cards (#241), or
        // the restored position's angles would arrive on the dead sweep's schedule.
        clearTiltTimings()
        reflowAll()
        updateFinishButton()
        reportHistory()
        // Save the stepped position (#177), redo stack and all, so a reload resumes
        // exactly where the step left the board.
        persistCurrent()
      }

      // Step the board's history back (#85), re-deriving the layout from the
      // restored state. Undo doesn't re-run auto-collect — it restores the prior
      // *settled* state exactly. It tears down the win overlay first, so it steps
      // cleanly back out of a victory.
      // Bring the view to whatever position the session now holds after a step through
      // history — the shared tail of undo and redo, whoever asked for one: the top bar's
      // button, or the console's `undo`/`redo` verb.
      //
      // Symmetric in the win overlay, and it has to be: undoing out of a victory takes
      // the panel down, and redoing back into the move that won raises it again.
      let adoptRestored = () => {
        if !Session.hasWon(session.contents) {
          removeWinOverlay()
        }
        adoptHistoryPresent()
        if Session.hasWon(session.contents) {
          showWin()
        }
      }

      // The top bar's Undo button (#85). The console's `undo` verb doesn't come through
      // here — it goes through `Session.step` like every other typed verb — but both end
      // in the same `Session.undo` and the same `adoptRestored`, so they can't drift.
      //
      // (`redo` has no button; it exists only as a typed verb, which is why there's no
      // twin of this function. `core`'s `History` has always carried the redo side.)
      let undo = () =>
        if Session.canUndo(session.contents) {
          DebugLog.message("undo")
          // Counted as an undo, never as a move, and it never takes a move back off the
          // tally (#289) — the session's rule, applied wherever a board is stepped back.
          // Inside the `canUndo` guard, so a press with nothing behind the present isn't
          // counted as one.
          let (stepped, _) = Session.undo(~clock, current())
          session := stepped
          adoptRestored()
        }

      // --- Typed commands (#273) ---------------------------------------------------
      // What the debug console's input line does with a parsed command.
      //
      // It no longer *interprets* one (#298). Every board verb — `move`, `home`, `undo`,
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
        // The session records an accepted move as one undoable step (#85) — unless
        // nothing changed (a lawful no-op, #215), which isn't undoable and so leaves
        // nothing to save or report.
        if !GameState.equal(state(), before) {
          afterChange()
        }
        animateCommand(Array.concat(moved, collected), ~onDone=() => {
          // A move that completes every foundation ends the game (#121). Raised once the
          // cards have landed, so the overlay is the payoff of the flight rather than
          // something that beats it to the board.
          if Session.hasWon(session.contents) {
            showWin()
          }
          updateFinishButton()
        })
      }

      // Play a solver's line (#291), a move at a time.
      //
      // The thinking and the playing are both `Session`'s: it hands back the line already
      // played, as a *trail* of sessions — one per planned move, each the board as that
      // move left it. What's this file's is the pace. Adopting them one at a time, each
      // as the previous flight lands, is what makes a run something you watch being
      // played rather than a board that changes while you blink, and it's the whole
      // reason to hand a board to a solver in front of a person rather than in a test.
      //
      // That makes this the one thing on the board that runs *forward in time* after the
      // command has answered, so it holds the interruption token (see `interruptPlay`)
      // and re-checks it before every step: an undo, a move of the player's own, a New
      // Game, a second `autoplay` — any of those and the run stops where it stands. It
      // can afford to stop anywhere precisely because each entry is a whole session: what
      // it stops on is a real position with a real history and a real tally behind it,
      // not something half-applied that has to be unwound.
      let playLine = (~reached: Session.t, ~trail: array<Session.played>) => {
        DebugLog.message("autoplay")
        // The reach is counted once, not once per move (#291) — the moves themselves are
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
            showWin()
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
        // Started on the next tick, not here. Everything above is bookkeeping the command
        // has to do before it answers — the tally, the cancellations, the token — but the
        // first *move* is the first line of a play-by-play, and the command's reply is the
        // sentence that heads it. Played inline, that reply came back to the console after
        // the run had already narrated a move into it (the console prints a command's
        // answer once the command returns), so the summary landed a line down its own
        // play-by-play. A tick's delay is invisible next to a move's flight, and it puts
        // the sentence back on top.
        //
        // Safe to defer for the same reason the run is safe to interrupt: `playFrom`
        // re-checks `token` before every step, and anything that happens in between — a
        // drag, an undo, a re-deal, a second `autoplay` — bumps it, so a run whose board
        // has moved on never plays its first move at all.
        setTimeout(() => playFrom(0), 0)->ignore
      }

      // What a change means to a board with cards on it.
      let react = (~before: GameState.t, change: Session.change) =>
        switch change {
        | Session.Settled({moved, collected}) =>
          // A move of the player's own takes the board off whatever line an autoplay was
          // walking (#291), exactly as a drop does.
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
        // when not dragging. A single card (a loose card, or a lone top card) is
        // just a span of one, so the old single-card drag is the length-1 case here.
        let grab = ref(None)

        // Send-home double-tap bookkeeping (#122). `movedFar` records whether the
        // pointer travelled far enough during the current press to count as a drag
        // rather than a tap; `lastTapAt` is the timestamp of the previous tap on
        // *this* card (each card has its own closure, so a double-tap must land on
        // one card, never split across two). Seeded well in the past so the first
        // tap after load can never read as the second half of a double-tap.
        let movedFar = ref(false)
        let lastTapAt = ref(-1000.)

        // May the span `spanCards` (bottom-first) land on `zone`? The hover
        // highlight and the drop below both funnel through `core`'s shared
        // legality (`canDrop` for one card, `canMoveRun` for a run — #82/#123) so
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
            // it in its pile, bottom-first. A loose or lone card is a span of one.
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

        // Send this card home (#122): a top-of-pile or loose card whose foundation
        // will take it flies straight to that foundation — the FreeCell shortcut for
        // the tedium of dragging every card home one at a time. Both eligibility and
        // legality come from the shared `core` primitive `validMoves` (#196): it lists
        // every drop a hand-drag would accept, movability already gated in core, so
        // the send-home is just "find the `Foundation` move and take it". At most one
        // foundation ever accepts a card, so this is behaviour-identical to the old
        // `foundationTarget` path; a buried card, or one no foundation wants, yields no
        // such move and is ignored. The move dispatched is the very `Move` a drag
        // would, so a completing card still raises the win overlay.
        let sendHome = () =>
          switch Reducer.validMoves(~game, state(), self.data)->Array.find(m =>
            m.role == Game.Foundation
          ) {
          | Some({to: i}) =>
            let before = state()
            switch dispatch(Reducer.Move({card: self.data, to: Reducer.ToPile(i)})) {
            | Session.Settled(_) =>
              // The session has already settled the move (auto-collect included) and
              // recorded it as one undoable step (#85) — unless it changed nothing (a
              // lawful no-op, #215), which leaves nothing to save or report.
              if !GameState.equal(state(), before) {
                afterChange()
              }
              reflowAll()
              if Session.hasWon(session.contents) {
                showWin()
              }
              updateFinishButton()
            | _ => ()
            }
          | None => ()
          }

        // When no foundation will take a double-tapped card but it can still move
        // somewhere, flash those destinations instead of sending it home (#197): each
        // legal target's *exposed card* pulses a green mask, then clears. Purely
        // informational: no card moves, nothing is selected, `state` is untouched.
        // Free cells and empty board spaces are never hinted (#217) — only the eligible
        // card of an occupied pile lights, matching the menu's accent green.
        //
        // Reduced-motion users still get the information (#197 review): a colour fade
        // carries no movement, so instead of dropping the hint entirely the pulse
        // becomes a single hold-then-fade — the targets are lit long enough to read,
        // then settle back. (Reading `matchMedia`/`animate` also keeps clear of jsdom,
        // which implements neither.)
        let flashMoveTargets = (moves: array<Reducer.move>) => {
          let reduceMotion = matchMedia("(prefers-reduced-motion: reduce)")["matches"]
          // The mask goes mostly-green at its peak — opaque enough to read the card as
          // "green for a frame or two" (#217) while a little translucency keeps the pip
          // showing through — then fades to nothing. No `fill`, so the mask ends fully
          // transparent (and is removed on finish anyway). Reduced-motion users get a
          // single hold-then-fade rather than the two-beat pulse: the colour still lands
          // long enough to read without the flashing.
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
          // Never hint free cells — they're the obvious park spot (#217) — nor a blank
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

        // The double-tap gesture (#197), branching on the card's `validMoves` (#196):
        // a `Foundation` move sends it home (unchanged from #122); otherwise, if it has
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
            // onto a zone is a `Move`/`MoveRun` to that pile; a miss is a move to
            // the loose table. The reducer — not the view — rules on it against the
            // game's rules and `free` flag, so `core` owns every rest position (#83).
            let target = switch zoneAt(boundingRect(wrapper)) {
            | Some(zone) => Reducer.ToPile(zone.index)
            | None => Reducer.ToTable
            }
            // One card dispatches the unchanged single-card `Move`; a span of two or
            // more dispatches the supermove `MoveRun` (#123).
            let action =
              Array.length(spanCards) <= 1
                ? Reducer.Move({card: self.data, to: target})
                : Reducer.MoveRun({cards: spanCards, to: target})
            let before = state()
            switch dispatch(action) {
            // Lawful move (including the identity re-drop): the session has adopted it,
            // auto-collected any now-safe cards behind it (#125) so the whole cascade
            // settles in one pass, and recorded the settled position as one undoable step
            // (#85) — so a move and its collection undo together. Reflow every pile from
            // it: cards that joined a pile snap to their slots, a card left loose stays
            // at the pixel it was dropped.
            | Session.Settled(_) =>
              // …unless nothing changed (dropping a card back where it started is a
              // no-op, #215), which records no step and so leaves nothing to save.
              if !GameState.equal(state(), before) {
                afterChange()
              }
              reflowAll()

              // A move that completes every foundation ends the game (#121): raise
              // the win overlay following the accepted `reduce` (and any auto-collect
              // that played the final cards).
              if Session.hasWon(session.contents) {
                showWin()
              }
              // Recompute the "Finish" button (#132): a move can make the board
              // drainable (show it) or, via auto-collect, no longer so (hide it).
              updateFinishButton()
            // Illegal move: bounce the span back where it came from. Cards that rest
            // in a pile return to their slots when that pile reflows; a loose card (a
            // rejected drop in a `free` game) returns to where the drag began.
            | _ =>
              switch GameState.locationOf(state(), self.data) {
              | Some(GameState.InPile(_, _)) => reflowAll()
              | _ =>
                switch spanStarts->Array.get(0) {
                | Some((c, sx, sy)) =>
                  c.x := sx
                  c.y := sy
                  place(c)
                | None => ()
                }
              }
            }
            clearHover()

            // With the drop settled, decide whether this press completed a
            // double-tap send-home (#122). Only a press that stayed a tap (never
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

      // A DOM node for every card a pile opens holding (#63) — where each rests is
      // already recorded in `state`, so no zone pairing is needed here, just the
      // nodes (which register themselves in `nodes`). Created before the loose cards
      // so a later loose card layers on top.
      game.piles->Array.forEach((pile: Game.pile) =>
        pile.cards->Array.forEach(card => makeCard(card)->ignore)
      )

      let freeCards = game.loose->Array.map(makeCard)

      // Deal the free cards as a loose, staggered cluster in the lower-middle of
      // the stage — below the zones, so they're dragged *up* into the piles.
      // Everything is derived from the stage's live size, so the cluster stays
      // centred and works for any number of cards: the cards spread out from the
      // centre with a step that's squeezed to fit the width, and a deterministic
      // per-card jitter plus an alternating vertical stagger keep it sloppy rather
      // than a rigid line. The step and stagger together guarantee neighbouring
      // cards each keep a visible edge, so none is completely occluded.
      let dealFree = () => {
        let pr = boundingRect(playfield)
        let n = Array.length(freeCards)
        let cw = cardW *. scale.contents
        let ch = cardH *. scale.contents
        // Nominal horizontal step, squeezed so a wide cluster still fits the stage.
        let avail = pr.width -. cw -. 32.
        let nominal = Int.toFloat(n - 1) *. 44.
        let spread = nominal < avail ? nominal : avail > 0. ? avail : 0.
        let stepX = n > 1 ? spread /. Int.toFloat(n - 1) : 0.
        // Sit the cluster around 60% down the stage (but clear of the top zones),
        // scaling with the stage yet never riding up over the piles on a short one.
        let frac = pr.height *. 0.6
        let centerY = frac > 205. ? frac : 205.
        freeCards->Array.forEachWithIndex((c, i) => {
          let jitterX = Int.toFloat(Int.mod(i * 37, 21)) -. 10.
          let jitterY = Int.toFloat(Int.mod(i * 53, 17)) -. 8.
          let stagger = Int.mod(i, 2) == 0 ? 16. : -16.
          c.x := pr.width /. 2. -. spread /. 2. +. Int.toFloat(i) *. stepX -. cw /. 2. +. jitterX
          c.y := centerY -. ch /. 2. +. stagger +. jitterY
          place(c)
          // Tilt the loose cards too (#65), off the loose sentinel "pile" so the
          // scattered cluster reads as hand-strewn rather than machine-aligned —
          // unless the player has turned the hand-placed look off.
          applyTilt(
            c.wrapper,
            ~degrees=tiltFor(
              ~enabled=tiltEnabled.contents,
              ~card=c.data,
              ~pile=looseTiltPile,
              ~slot=i,
            ),
          )
        })
      }

      // The shake jostle (#235): a vigorous shake nudges every card a little off its
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
      // their zones and re-strew the loose cluster, both reading `tiltEnabled` live.
      // One function because it's one board state — the clean deal — reached from two
      // directions: it's what the tilt switch asks for (`controls.relayout`, #65), so a
      // flip re-tilts or squares the board in place rather than waiting for the next
      // move, and it's what ends a shake (#235), so turning Wiggle Waggle off snaps the
      // mess back to exactly that board.
      let squareUp = () => {
        reflowAll()
        dealFree()
      }

      // Publish this build's shake operations into the mount-scope `boardOps` ref, so
      // the persistent subscription drives the live board's nodes (a New Game rebuild
      // swaps in fresh ones).
      boardOps := {jostle, squareUp}

      // Lay out each opening pile from `state`: reflow reads the cards the model
      // deals that pile and positions their nodes, so the pile ends laid out exactly
      // as an interactively built one would.
      let dealPiles = () => reflowAll()

      // The order the cards fly in: a real dealer's pass — round-robin across the
      // piles by slot (every pile's first card, then every pile's second, …), with
      // the loose cards last. This is just the sequence the staggered start delays
      // below run over; the cards are already at their final resting spots.
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
        freeCards->Array.forEach(c => ordered->Array.push(c))
        ordered
      }

      // Fly the just-placed cards in from a single origin below the stage into
      // their rest positions, staggered. Every card starts translated to one
      // shared point — the middle of the stage's bottom edge, just off-screen —
      // so they all launch from the same "stack" a magician would throw from, and
      // animates to `translate 0` (its left/top already hold the final spot). The
      // per-card start offset therefore differs on *both* axes, since each card
      // travels from that one origin to a different landing spot. The timing is
      // entirely the `dealMaxInFlight`/`dealPerCardMs` math above. With the OS
      // asking for reduced motion — or the URL's `?animate=off` (`~skipDealAnimation`)
      // — the cards simply stay where they were placed, no fly-in.
      let animateDeal = () => {
        let reduceMotion = matchMedia("(prefers-reduced-motion: reduce)")["matches"]
        let cards = dealSequence()
        let n = Array.length(cards)
        if !reduceMotion && !skipDealAnimation && n > 0 {
          let pr = boundingRect(playfield)
          let cw = cardW *. scale.contents
          let ch = cardH *. scale.contents
          // The single origin every card launches from: horizontally centred on
          // the stage, seated a card's height below its bottom edge — one stack,
          // in playfield-local coords (matching the cards' left/top).
          let originX = pr.width /. 2. -. cw /. 2.
          let originY = pr.height +. ch
          // The stagger (Δ) and per-card flight time, from the deal's knobs and the
          // card count — the same derivation the finish sweep reuses.
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
          dealFree()
          animateDeal()
        })
      }

      // Re-run the layout for the stage's current size (#172) — a resize snaps the
      // piled cards to the resized zones and rescales them, *without* re-animating
      // the opening deal. The pile cards follow the zones' live rects (`reflowAll`);
      // the loose cards, which `reflowAll` doesn't touch (they hold only pixel x/y),
      // scale by the width ratio so they keep their spot proportionally as the cards
      // around them shrink or grow by that same factor. The left/top snap transition
      // is suppressed so the cards track the zones immediately rather than easing
      // after every resize step (`withSnapSuppressed`). Gated on a prior deal
      // (`lastWidth > 0`, set by `applyScale`), so the observer's initial callback —
      // before the deferred opening deal has sized anything — is a harmless no-op,
      // and so the ratio never divides by a zero start width.
      let relayoutForResize = () => {
        let width = boundingRect(playfield).width
        if width > 0. && lastWidth.contents > 0. {
          let ratio = width /. lastWidth.contents
          withSnapSuppressed(() => {
            applyScale()
            reflowAll()
            nodes->Array.forEach(c =>
              switch GameState.locationOf(state(), c.data) {
              | Some(GameState.Loose) =>
                c.x := c.x.contents *. ratio
                c.y := c.y.contents *. ratio
                place(c)
              | _ => ()
              }
            )
          })
        }
      }
      // Publish this build's relayout as the live one the mount-scope observer
      // drives, so a resize after a New Game reflows *this* board, not the one it
      // replaced.
      resizeRelayout := relayoutForResize

      // Deal now if the stage is already laid out (a later scene switch); otherwise
      // on the next frame, before the first paint, once the detached-at-mount stage
      // has been inserted and sized (the first page load). Both the pile cards and
      // the loose cards need the stage's live rects, so both wait on this.
      boundingRect(playfield).width > 0. ? deal() : requestAnimationFrame(deal)->ignore

      // Come back to a won board (#177): a resumed game saved in its victory state
      // opens with the win overlay already up, rather than a silently finished board.
      // Checked before the "Finish" button below so a completed board never offers to
      // finish itself. A fresh deal, a re-deal, or a `?state=` scenario is never
      // already won, so this only fires on a restored victory.
      if Session.hasWon(session.contents) {
        showWin()
      }

      // Show the "Finish" button (#132) straight away when the opening position is
      // already drainable — a `?state=` scenario can drop the board into one.
      // Layout-independent, so it needn't wait on the deal's frame.
      updateFinishButton()

      // Point the published `undo`, `runCommand` and `relayout` at *this* build (#300),
      // and report the opening history (nothing to undo yet) so the top bar's button
      // starts disabled (#85). Each of the three closes over the board it was built
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

      // The caption is the game's own prose (`Game.caption`); a game without one
      // simply shows no caption.
      switch game.caption {
      | Some(text) =>
        let caption = WebDom.createElement("p")
        caption->WebDom.setAttribute("class", "stacking-caption")
        caption->WebDom.setTextContent(text)
        boardHost->WebDom.appendChild(caption)->ignore
      | None => ()
      }

      // Persist this freshly-built board (#177) when saving is on: the opening deal,
      // a New Game, or a Restart each *become* the saved game, so a later reload
      // resumes this board — and New Game replaces whatever was saved before. Skipped
      // for a forced-state load (`~persistThis=false`), which must leave the saved
      // game untouched; a no-op when no `~persist` sink is wired.
      if persistThis {
        persistCurrent()
      }
    }

    // Hand the chrome the board's published surface (#300): one record, once, as this
    // scene mounts. What used to be eleven separate `publishX` calls scattered across
    // the mount and every build is this single value — and the eleven `ref`s on the
    // driver's side, plus the by-name reset that had to clear each one on a scene
    // change, went with it.
    //
    // Everything here is written to survive a re-deal, which is the whole reason a
    // mount-scope hand-over is safe:
    //
    //   - the four rebuilds (`newGame`, `loadGame`, `restart`, `loadState`) and the
    //     share-link restore call `buildBoard` directly, which clears the host and
    //     builds a fresh board in place — so they're about the *scene*, not a build;
    //   - `readHistory`, `undo`, `runCommand`, `relayout` and `dockFit` dispatch
    //     through mount-scope refs that each build repoints at its own board;
    //   - `shake` drives the live board's nodes through `boardOps`, the same way.
    //
    // The two re-deals that open a board the caller names ride `~newDeal`: a fresh seed
    // for `newGame` (#109 — the menu's New Game and the console's bare `deal`), and a
    // caller-supplied `Game.t` for `loadGame` (#273 — `deal <n>`, where the driver turns
    // the number into a board because only it knows a deal is a seeded FreeCell
    // shuffle). A fixed-layout demo has no seed to vary and offers neither.
    //
    // `restart` (#156) is offered by *every* card table — a demo restarts to its own
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
        loadGame: newDeal->Option.map(_ => chosen => buildBoard(chosen)),
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

    // Open the board: from a saved undo/redo history when one was restored (#177),
    // else the forced `~initial` scenario when the URL named one, else the game's own
    // deal. The save is read *here*, as this mount opens — not once when the scene
    // was built — so a scene mounted a second time resumes the game as it stands
    // now rather than re-opening a page-load snapshot of it over the board the
    // player was on. It seeds only this opening build; every later re-deal within
    // the mount starts clean.
    buildBoard(~initial?, ~history=?loadHistory(), game)

    // Reflow the card layout whenever the stage resizes (#172). One observer serves
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
      // the New Game control and every listener with them; the observer and the
      // window-level shake listener are all that outlive the DOM, so tear both down
      // here (#235 — the `devicemotion` subscription must be detached explicitly).
      () => {
        unsubscribeShake()
        observer->disconnect
      }
    | None => () => unsubscribeShake()
    }
  },
}
