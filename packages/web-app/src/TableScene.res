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

// getBoundingClientRect gives viewport coordinates; that's what hit-testing and
// the snap maths use, converting to playfield-local left/top only at the end.
type domRect = {left: float, top: float, width: float, height: float}
@send external boundingRect: WebDom.element => domRect = "getBoundingClientRect"

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
// card at its *resting* z while it flies and only relayer to foundation order
// once it lands (see `animateFinish`).
@get external zIndex: style => string = "zIndex"
@set external setHeight: (style, string) => unit = "height"
// Card/zone footprints scale to the stage (see `scale` below); the factor is
// published to the CSS as custom properties so `.stacking-card`/`.drop-zone`
// resize in step with the JS geometry.
@send external setProperty: (style, string, string) => unit = "setProperty"

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

// The design footprints, at scale 1. Everything the layout measures in pixels —
// the fan step, the card box, the empty zone box — is one of these multiplied by
// the stage's live `scale` (see `make`), so cards, zones and fans all shrink
// together to fit however many piles a game declares onto a narrow screen.

// How far each Fanned card steps off the one beneath it. The zones sit at the
// top of the stage and the pile grows downward, so the fan steps *down*, the
// newest card landing lowest and fully exposed.
let fanStep = 26.

// Card footprint in playfield pixels (width matches `.stacking-card` in the CSS;
// height from the 5:7 viewBox). Used by the initial deal, which places cards
// before they're laid out and so can't read their rects yet.
let cardW = 80.
let cardH = 112.

// The empty drop zone's footprint (matches `.drop-zone` in the CSS). A pile's
// cards centre vertically within the base-height box, and a fanned zone grows
// *below* it so its outline and highlight wrap the whole pile rather than just
// the top card's footprint (see reflow). The width tracks the card with a little
// breathing room, so a squared pile sits framed inside its zone.
let zoneWidth = 88.
let zoneBaseHeight = 124.

// Card widths are capped at the design size (`cardW`) and floored here, so a
// game with many piles on a narrow phone still deals cards you can read and grab
// rather than shrinking them away. Between the two, cards fill `fillFraction ×
// width` of the stage split across the piles. The floor is set low enough that
// eight cascades still fit *with room to spare* on a phone — otherwise the
// columns hit the floor, overflow the row and butt together with no gap to
// distribute (the `space-evenly` below has nothing to spread).
let minScale = 0.4

// The share of the stage width the row of cards fills; the rest is the gaps
// `space-evenly` opens around and between the columns. Kept well below 1 so the
// columns breathe — a squared pile's zone stays framed, and the leftover width
// is real space for `space-evenly` to spread as equal outer/inter-card gaps
// rather than the columns butting card-to-card.
let fillFraction = 0.9

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

// The send-home gesture (#122) is a *double-tap* — two taps on the same card,
// each staying under `doubleTapMoveTol` pixels of travel (so it reads as a tap,
// not the start of a drag), within `doubleTapMs` of one another. This is timed
// off the pointer stream by hand because mobile Safari doesn't fire `dblclick`
// for a double-tap (it's the tap-to-zoom gesture); the same code path then also
// covers the desktop double-click, so one loop serves phone and desktop.
let doubleTapMs = 300.
let doubleTapMoveTol = 12.

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
// `~publishNewGame` is how the chrome's top bar (#109) reaches the re-deal: when
// the board is re-dealable, the scene hands its `buildBoard(freshDeal())` thunk
// to `publishNewGame` on mount, and the top bar's New Game button calls it. (The
// New Game control lives in the top bar now, not on the board.) The chrome resets
// its hook on every scene switch, so a non-re-dealable scene simply leaves it
// unset — it never calls `publishNewGame`.
// `~options` is a *ref* to the driver preference record (#125), read *live* at
// each post-move step so a menu toggle (#139) that flips a field takes effect on
// the very next move without rebuilding the board. Its `autoCollect` flag (on by
// its `default`) sends every *safe* card home after an accepted move; the app's
// menu owns this ref and rewrites it when the player flips the setting.
//
// `~publishLoadState` is the debug "states" hook (sibling to `~publishNewGame`):
// on mount the scene hands the chrome a `GameState.t => unit` that rebuilds the
// board into any forced position — the same `~initial` path a `?state=` scenario
// takes, but reachable live from the menu instead of only at load. The debug-states
// menu (see `DebugStates` / `Main`) calls it with a `Scenario` snapshot.
//
// `~publishUndo` / `~publishRedo` are the undo/redo hooks (#85), siblings of
// `~publishNewGame`: on every build the board hands the top bar a thunk that steps
// its `GameState` history back / forward and re-derives the layout. `~onHistory`
// is the reverse channel — after every state change the board calls it with the
// current `(canUndo, canRedo)` so the top bar can enable or disable each button.
// Undo works even from a won board: a victory is just another recorded state, so
// stepping back tears the win overlay down and returns to the prior position.
let make = (
  ~initial: option<GameState.t>=?,
  ~newDeal: option<unit => Game.t>=?,
  ~publishNewGame: option<(unit => unit) => unit>=?,
  ~publishLoadState: option<(GameState.t => unit) => unit>=?,
  ~publishUndo: option<(unit => unit) => unit>=?,
  ~publishRedo: option<(unit => unit) => unit>=?,
  ~onHistory: option<(bool, bool) => unit>=?,
  ~options: ref<Options.t>=ref(Options.default),
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

    // Build (or rebuild) the whole board for `game` into `boardHost`. Every call
    // clears the host first, so a re-deal starts empty — none of the previous
    // deal's card nodes or drop zones survive (the tear-down New Game needs) —
    // and re-runs the same mount-time build with fresh local state (`nodes`,
    // `state`, `topZ`, `scale`). `~initial` forces a starting `GameState` (the
    // `?state=` scenario) and applies only to the opening mount; a re-deal always
    // opens from its game's own fresh deal.
    let rec buildBoard = (~initial: option<GameState.t>=?, game: Game.t) => {
      // Cancel any finish sweep still in flight from the board being torn down, so
      // its cards stop animating and its last-card `onfinish` can't raise a win over
      // the fresh board.
      cancelOutstanding()
      WebDom.clear(boardHost)
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

      // The single source of truth for *where every card rests* (#77/#82): the view
      // holds one immutable `GameState`, seeded from the board's opening deal (or the
      // forced `~initial` scenario, when one is given), and re-derives every pile's
      // layout from it. Drops dispatch reducer actions and adopt the returned state;
      // the view keeps only transient geometry (below).
      let state = ref(initial->Option.getOr(GameState.initial(game)))

      // Undo/redo history over the board's `GameState` (#85): the states the board
      // has passed through, so a step back is a pop. `state` stays the live snapshot
      // the layout reads; `history` records each *settled* move as one undoable step
      // and is stepped by `undo`/`redo` (defined below, once the reflow/win helpers
      // they drive exist). A fresh build (a re-deal, or the opening mount) starts a
      // clean history from the opening position.
      let history = ref(History.make(state.contents))

      // The DOM node for each model card, so a pile derived from `state` (structural
      // `{suit, rank}` cards) lays out onto the *same* elements every reflow — the
      // identity bridge (#45) from model card to node. Every `makeCard` registers
      // itself here; lookup is the deck-scoped `GameState.sameCard`.
      let nodes: array<card> = []
      let nodeFor = (data: Deck.card) => nodes->Array.find(n => GameState.sameCard(n.data, data))

      // How much the design footprints are shrunk to fit the stage. Cards fill
      // `fillFraction × width` split across the busiest row (`fillFraction · width
      // / widestRow`), capped at the design size so a wide screen doesn't blow the
      // cards up, and floored so a crowded, narrow one keeps them legible. Held in
      // a ref because the geometry (reflow, the deal) reads it, and recomputed from
      // the stage's live width the moment before the deal — the one point at which
      // the stage is known laid out.
      let scale = ref(1.)
      let applyScale = () => {
        let width = boundingRect(playfield).width
        if width > 0. && widestRow > 0 {
          let target = fillFraction *. width /. Int.toFloat(widestRow) /. cardW
          scale := Math.max(minScale, Math.min(1., target))
        }
        // Publish the factor to the CSS so `.stacking-card`/`.drop-zone` resize in
        // step with the JS geometry below.
        let s = style(playfield)
        s->setProperty("--card-w", Float.toString(cardW *. scale.contents) ++ "px")
        s->setProperty("--zone-w", Float.toString(zoneWidth *. scale.contents) ++ "px")
        s->setProperty("--zone-h", Float.toString(zoneBaseHeight *. scale.contents) ++ "px")
      }

      // The zone whose rect contains point (px, py), if any — the shared primitive
      // for both the live hover highlight and the snap-on-drop decision.
      let zoneAt = (px, py) =>
        zones->Array.find(({el}) => {
          let r = boundingRect(el)
          px >= r.left && px <= r.left +. r.width && py >= r.top && py <= r.top +. r.height
        })

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
      // rest are marked buried. Reading the rects live keeps the maths correct
      // wherever flexbox placed the zone.
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
        let cards = GameState.cardsInPile(state.contents, zone.index)
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
        // Light the "done" marker once this pile holds a full Ace→King run (#76) —
        // the satisfying completion a foundation builds toward. Driven off the same
        // pure `core` predicate, so a foundation and an assembled tableau alike
        // signal completion; full win detection is later.
        let complete = Rules.isCompleteRun(cards)
        complete
          ? classList(zone.el)->addClass("drop-zone--complete")
          : classList(zone.el)->removeClass("drop-zone--complete")
      }

      // Re-derive every pile from the current `state`. Cheap for a handful of zones,
      // and it always reflows both ends of a move (the pile a card left and the one
      // it joined) without the view tracking which those were.
      let reflowAll = () => zones->Array.forEach(reflow)

      // After an accepted move, auto-collect the safe cards to the foundations
      // (#125) when the option is on (its default), adopting the settled state so
      // the following reflow lays out the swept board. Gated entirely by the flag,
      // so `autoCollect: false` leaves the reducer's result untouched — an exact
      // no-op path. Runs *before* the win check, since a collection often plays the
      // final cards and so is what trips `hasWon`.
      // Once the board is finishable (#132), auto-collect steps aside so the
      // "Finish" button owns the end-game sweep — otherwise safe auto-collect
      // would often cascade to the win on its own and rob the player of the
      // trigger.
      let autoCollectIfEnabled = () =>
        if options.contents.autoCollect && !Reducer.canFinish(~game, state.contents) {
          let (collected, _moved) = Reducer.autoCollect(~game, state.contents)
          state := collected
        }

      // The win overlay (#121): a dimmed panel over the board announcing the win,
      // with a New Game button to play on. Shown when a move completes every
      // foundation (`GameState.hasWon`); the button re-deals a fresh FreeCell
      // (`newDeal`) or, for a fixed-layout board, replays the same deal — either way
      // `buildBoard` clears `boardHost` first, so the overlay is torn down with the
      // rest of the board and can't linger. Only one is ever raised at a time.
      let winShown = ref(false)
      // The live overlay element, kept so undo can tear it down when stepping back
      // out of a win (#85) — undoing a victory removes the panel and returns the
      // board to the prior, still-playable position.
      let winOverlay = ref(None)
      let showWin = () =>
        if !winShown.contents {
          winShown := true
          let overlay = WebDom.createElement("div")
          overlay->WebDom.setAttribute("class", "win-overlay")

          let panel = WebDom.createElement("div")
          panel->WebDom.setAttribute("class", "win-panel")

          let title = WebDom.createElement("p")
          title->WebDom.setAttribute("class", "win-panel__title")
          title->WebDom.setTextContent("You win!")

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

          panel->WebDom.appendChild(title)->ignore
          panel->WebDom.appendChild(button)->ignore
          overlay->WebDom.appendChild(panel)->ignore
          boardHost->WebDom.appendChild(overlay)->ignore
          winOverlay := Some(overlay)
        }

      // Tear the win overlay down (#85) — undo out of a victory removes the panel
      // and clears the flag so a later win can raise it again. A no-op when no
      // overlay is up.
      let removeWinOverlay = () =>
        switch winOverlay.contents {
        | Some(overlay) =>
          WebDom.remove(overlay)
          winOverlay := None
          winShown := false
        | None => ()
        }

      // Report the current undo/redo availability to the chrome (#85) so the top
      // bar can enable or disable its buttons. Called after every state change.
      let reportHistory = () =>
        switch onHistory {
        | Some(f) => f(History.canUndo(history.contents), History.canRedo(history.contents))
        | None => ()
        }

      // Record the current (settled) `state` as one undoable step, then report the
      // updated availability. Called after each accepted move, once auto-collect has
      // settled — so a move and the collection it triggered undo as a unit.
      let recordHistory = () => {
        history := History.record(history.contents, state.contents)
        reportHistory()
      }

      // Fly the finishing sweep home (#160): with the final `settled` state already
      // committed (so the model and undo are correct and robust to interruption),
      // play a pure *visual* catch-up over `movedCards` — each card flying from where
      // it was resting to its foundation slot, staggered by the finish knobs. Same
      // inverse-offset trick as `animateDeal`: capture each card's current spot, let
      // `reflowAll` snap every node onto its foundation, then animate the transform
      // back from (start − end) to zero. `onDone` fires once the last card lands (it
      // raises the win overlay), so the victory reads as the payoff of the sweep. With
      // the OS asking for reduced motion — or nothing to move — the sweep collapses to
      // today's instant `reflowAll`, `onDone` firing immediately.
      let animateFinish = (movedCards: array<Deck.card>, ~onDone) => {
        let reduceMotion = matchMedia("(prefers-reduced-motion: reduce)")["matches"]
        let cards = movedCards->Array.filterMap(nodeFor)
        let n = Array.length(cards)
        if reduceMotion || n == 0 {
          reflowAll()
          onDone()
        } else {
          // Each card's resting spot *and resting layer* before the sweep, captured
          // before `reflowAll` moves its node onto its foundation and relayers every
          // pile by foundation slot. The z-index matters as much as the position: a
          // card holds at its start (via `fill: "backwards"`) until its staggered
          // turn, so a still-resting source fan must keep its own slot order until
          // then — restoring `sz` below stops the foundation-slot relayer from
          // inverting those fans the instant the sweep starts.
          let starts =
            cards->Array.map(c => (c, c.x.contents, c.y.contents, style(c.wrapper)->zIndex))
          // Snap every node to its foundation slot; the flights below are a visual
          // catch-up over nodes that already "belong" there.
          reflowAll()
          let (delta, flight) = staggerTiming(
            ~maxInFlight=finishMaxInFlight,
            ~perCardMs=finishPerCardMs,
            ~n,
          )
          starts->Array.forEachWithIndex(((c, sx, sy, sz), i) => {
            // Fly from the resting spot, layered as it rested: `reflowAll` above
            // relayered this node by its foundation slot, which would scramble the
            // source fan it hasn't left yet, so restore its resting z for the flight.
            // The final settle (below) puts every foundation back in slot order.
            style(c.wrapper)->setZIndex(sz)
            let dx = sx -. c.x.contents
            let dy = sy -. c.y.contents
            let anim = c.wrapper->animate(
              [
                {
                  "transform": `translate3d(${Float.toString(dx)}px, ${Float.toString(dy)}px, 0)`,
                },
                {"transform": "translate3d(0, 0, 0)"},
              ],
              {
                "duration": flight,
                "delay": Int.toFloat(i) *. delta,
                "easing": "cubic-bezier(0.22, 1, 0.36, 1)",
                "fill": "backwards",
              },
            )
            outstandingAnimations.contents->Array.push(anim)

            // The last card to launch is the last to land (every flight is the same
            // length), so its finish is the whole sweep's finish. Settle every
            // foundation back to slot order (King on top) now that the resting-layer
            // flights are done, then hand off to the win overlay.
            if i == n - 1 {
              anim->setOnFinish(() => {
                reflowAll()
                onDone()
              })
            }
          })
        }
      }

      // The end-game "Finish" button (#132): a conditional control — the same
      // show-when-relevant shape as the win overlay above — that appears exactly
      // when the board can be drained to a win by foundation moves alone
      // (`Reducer.canFinish`), i.e. victory is one tap away, and is hidden the rest
      // of the time. Tapping it plays the finishing sweep (`Reducer.finishSequence`)
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
      let updateFinishButton = () =>
        if winShown.contents || !Reducer.canFinish(~game, state.contents) {
          removeFinishButton()
        } else {
          switch finishButton.contents {
          | Some(_) => () // already shown
          | None =>
            let btn = WebDom.createElement("button")
            btn->WebDom.setAttribute("type", "button")
            btn->WebDom.setAttribute("class", "finish-button")
            btn->WebDom.setTextContent("Finish")
            btn->WebDom.addEventListener("click", () => {
              let (settled, moved) = Reducer.finishSequence(~game, state.contents)
              state := settled
              // The whole sweep is one undoable step (#85): the model transition and
              // its single `recordHistory` commit immediately, so undo after a finish
              // steps back to the position it started from regardless of the animation.
              recordHistory()
              removeFinishButton()
              // Deliver the sweep as a staggered flight (#160) rather than an instant
              // jump; the win overlay lands only once the last card has arrived.
              animateFinish(moved, ~onDone=() =>
                if GameState.hasWon(game, state.contents) {
                  showWin()
                }
              )
            })
            boardHost->WebDom.appendChild(btn)->ignore
            finishButton := Some(btn)
          }
        }

      // Step the board's history back / forward (#85), re-deriving the layout from
      // the restored state. Neither re-runs auto-collect — undo restores the prior
      // *settled* state exactly. Undo tears down the win overlay first, so it steps
      // cleanly back out of a victory; redo re-raises the win if the state it
      // replays to is itself a won board.
      let undo = () =>
        if History.canUndo(history.contents) {
          // Stop any finish sweep still in flight before laying out the restored
          // position, so its cards don't keep flying toward foundations the undo has
          // just emptied (the state is already committed, so nothing corrupts).
          cancelOutstanding()
          history := History.undo(history.contents)
          state := History.present(history.contents)
          removeWinOverlay()
          reflowAll()
          updateFinishButton()
          reportHistory()
        }
      let redo = () =>
        if History.canRedo(history.contents) {
          cancelOutstanding()
          history := History.redo(history.contents)
          state := History.present(history.contents)
          reflowAll()
          if GameState.hasWon(game, state.contents) {
            showWin()
          }
          updateFinishButton()
          reportHistory()
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
          switch GameState.locationOf(state.contents, cardData) {
          | Some(GameState.InPile(i, _)) if i == zone.index => true
          | _ =>
            Array.length(spanCards) <= 1
              ? Reducer.canDrop(~game, state.contents, cardData, ~onto=zone.index)
              : Reducer.canMoveRun(~game, state.contents, spanCards, ~onto=zone.index)
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
          let r = boundingRect(wrapper)
          let over = zoneAt(r.left +. r.width /. 2., r.top +. r.height /. 2.)
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
            let span = switch GameState.locationOf(state.contents, self.data) {
            | Some(GameState.InPile(pileIdx, slot)) =>
              let pile = GameState.cardsInPile(state.contents, pileIdx)
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
        // the tedium of dragging every card home one at a time. Eligibility and
        // legality are the same shared `core` queries a hand-drag consults
        // (`foundationTarget` over the same `canDrop`), so the shortcut and a dragged
        // drop can never disagree; a buried card, or one no foundation wants, is
        // simply ignored. The move dispatched is the very `Move` a drag would, so a
        // completing card still raises the win overlay.
        let sendHome = () => {
          let eligible = switch GameState.locationOf(state.contents, self.data) {
          | Some(GameState.Loose) => true
          | Some(GameState.InPile(i, slot)) =>
            slot == Array.length(GameState.cardsInPile(state.contents, i)) - 1
          | None => false
          }
          if eligible {
            switch Reducer.foundationTarget(~game, state.contents, self.data) {
            | Some(i) =>
              switch Reducer.reduce(
                ~game,
                state.contents,
                Reducer.Move({card: self.data, to: Reducer.ToPile(i)}),
              ) {
              | Ok(next) =>
                state := next
                autoCollectIfEnabled()
                // Record the settled position as one undoable step (#85).
                recordHistory()
                reflowAll()
                if GameState.hasWon(game, state.contents) {
                  showWin()
                }
                updateFinishButton()
              | Error(_) => ()
              }
            | None => ()
            }
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
            let cr = boundingRect(wrapper)
            let target = switch zoneAt(cr.left +. cr.width /. 2., cr.top +. cr.height /. 2.) {
            | Some(zone) => Reducer.ToPile(zone.index)
            | None => Reducer.ToTable
            }
            // One card dispatches the unchanged single-card `Move`; a span of two or
            // more dispatches the supermove `MoveRun` (#123).
            let action =
              Array.length(spanCards) <= 1
                ? Reducer.Move({card: self.data, to: target})
                : Reducer.MoveRun({cards: spanCards, to: target})
            switch Reducer.reduce(~game, state.contents, action) {
            // Lawful move (including the identity re-drop): adopt the new state and
            // reflow every pile from it. Cards that joined a pile snap to their
            // slots; a card left loose stays at the pixel it was dropped.
            | Ok(next) =>
              state := next
              // Auto-collect any now-safe cards (#125) before the reflow, so the
              // whole cascade settles in one pass; gated by the option.
              autoCollectIfEnabled()
              // Record the settled position as one undoable step (#85), so a move
              // and the auto-collection it triggered undo together.
              recordHistory()
              reflowAll()

              // A move that completes every foundation ends the game (#121): raise
              // the win overlay following the accepted `reduce` (and any auto-collect
              // that played the final cards).
              if GameState.hasWon(game, state.contents) {
                showWin()
              }
              // Recompute the "Finish" button (#132): a move can make the board
              // drainable (show it) or, via auto-collect, no longer so (hide it).
              updateFinishButton()
            // Illegal move: bounce the span back where it came from. Cards that rest
            // in a pile return to their slots when that pile reflows; a loose card (a
            // rejected drop in a `free` game) returns to where the drag began.
            | Error(_) =>
              switch GameState.locationOf(state.contents, self.data) {
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
                sendHome()
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
        })
      }

      // Lay out each opening pile from `state`: reflow reads the cards the model
      // deals that pile and positions their nodes, so the pile ends laid out exactly
      // as an interactively built one would.
      let dealPiles = () => reflowAll()

      // The order the cards fly in: a real dealer's pass — round-robin across the
      // piles by slot (every pile's first card, then every pile's second, …), with
      // the loose cards last. This is just the sequence the staggered start delays
      // below run over; the cards are already at their final resting spots.
      let dealSequence = () => {
        let piles = zones->Array.map(z => GameState.cardsInPile(state.contents, z.index))
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
      // asking for reduced motion, the cards simply stay where they were placed —
      // no fly-in.
      let animateDeal = () => {
        let reduceMotion = matchMedia("(prefers-reduced-motion: reduce)")["matches"]
        let cards = dealSequence()
        let n = Array.length(cards)
        if !reduceMotion && n > 0 {
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
            let dx = originX -. card.x.contents
            let dy = originY -. card.y.contents
            card.wrapper
            ->animate(
              [
                {
                  "transform": `translate3d(${Float.toString(dx)}px, ${Float.toString(dy)}px, 0)`,
                },
                {"transform": "translate3d(0, 0, 0)"},
              ],
              {
                "duration": flight,
                "delay": Int.toFloat(i) *. delta,
                "easing": "cubic-bezier(0.22, 1, 0.36, 1)",
                "fill": "backwards",
              },
            )
            ->ignore
          })
        }
      }

      let deal = () => {
        // Size the cards to the now-laid-out stage first, so both deals below place
        // and reflow cards at their final footprint.
        applyScale()
        // Suppress the left/top snap transition for the opening placement so the
        // cards don't *also* slide in from the corner (0,0) while the fly-up plays
        // (see `.stacking-playfield.dealing` in the CSS). Restored on the next
        // frame, once the final left/top are committed without animating — the
        // transform fly-up runs on independently.
        classList(playfield)->addClass("dealing")
        dealPiles()
        dealFree()
        animateDeal()
        requestAnimationFrame(() => classList(playfield)->removeClass("dealing"))->ignore
      }

      // Deal now if the stage is already laid out (a later scene switch); otherwise
      // on the next frame, before the first paint, once the detached-at-mount stage
      // has been inserted and sized (the first page load). Both the pile cards and
      // the loose cards need the stage's live rects, so both wait on this.
      boundingRect(playfield).width > 0. ? deal() : requestAnimationFrame(deal)->ignore

      // Show the "Finish" button (#132) straight away when the opening position is
      // already drainable — a `?state=` scenario can drop the board into one.
      // Layout-independent, so it needn't wait on the deal's frame.
      updateFinishButton()

      // Publish this build's undo/redo actions to the chrome and report the opening
      // history (nothing to undo or redo yet), so the top bar's buttons start
      // disabled (#85). Re-published every build, so after a re-deal the top bar
      // drives the fresh board's history, not the torn-down one's.
      switch publishUndo {
      | Some(publish) => publish(undo)
      | None => ()
      }
      switch publishRedo {
      | Some(publish) => publish(redo)
      | None => ()
      }
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
    }

    // Publish the re-deal to the chrome (#109). When the game is re-dealable
    // (`~newDeal` — FreeCell today), hand the top bar a thunk that asks for a fresh
    // deal (a new seed each press, decided by whoever built `newDeal`) and rebuilds
    // the board in place from it, tearing the previous deal down. The board host
    // stays put across a re-deal — `buildBoard` rebuilds only its contents — so the
    // top bar's New Game button can drive this hook without touching the chrome.
    switch (newDeal, publishNewGame) {
    | (Some(freshDeal), Some(publish)) => publish(() => buildBoard(freshDeal()))
    | _ => ()
    }

    // Publish the debug "states" loader: hand the chrome a thunk that rebuilds
    // the board into a forced `GameState` — the debug-states menu drops the board
    // straight into a named `Scenario` position through this, exactly as `~initial`
    // does at load. Like a re-deal, `buildBoard` clears the host first, so the
    // forced position replaces the current board cleanly.
    switch publishLoadState {
    | Some(publish) => publish(state => buildBoard(~initial=state, game))
    | None => ()
    }
    container->WebDom.appendChild(boardHost)->ignore

    // Open the board from the game's deal, or the forced `~initial` scenario when
    // the URL named one.
    buildBoard(~initial?, game)

    // The switcher clears the container on scene change, dropping the board host,
    // the New Game control and every listener with them — nothing extra to tear
    // down.
    () => ()
  },
}
