// A card table that *interprets a modelled game* (`Game.t` from core) rather
// than hard-coding one board. Grown out of the drag-and-drop spike (#21) and the
// stacking demo (#56), and now driven by data (#62): the piles, their stacking
// behaviours and the opening deal all come from the game, so a new game is a new
// value in `Game`, not new code here.
//
// The view holds its own presentation assumptions — the piles hang from the top
// of the stage as a row and grow downward; the loose cards are dealt as a sloppy
// cluster below them — and applies them to whatever the model describes, be it
// two piles or four.
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

// A card is positioned by writing `style.left/top`, and layered by writing
// `style.zIndex`; the drag loop needs these, and reflow grows a fanned zone by
// writing `style.height` so its highlight wraps the whole pile (below).
type style
@get external style: WebDom.element => style = "style"
@set external setLeft: (style, string) => unit = "left"
@set external setTop: (style, string) => unit = "top"
@set external setZIndex: (style, string) => unit = "zIndex"
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
let fillFraction = 0.66

// Build a scene that plays `game`: its id/label name the scene in the picker,
// and its piles and opening deal drive everything below.
let make = (game: Game.t): Scene.t => {
  id: game.id,
  label: game.name,
  mount: container => {
    // The stage everything is positioned within; `position: relative` (in CSS)
    // makes it the origin for the cards' absolute left/top.
    let playfield = WebDom.createElement("div")
    playfield->WebDom.setAttribute("class", "stacking-playfield")
    container->WebDom.appendChild(playfield)->ignore

    // A row of drop zones pinned to the top of the stage. They lay themselves
    // out with flexbox, so their live rects (read at drop time) reflect wherever
    // the browser actually placed them — no positions cached up front to go
    // stale on resize. The row spaces however many zones the game declares.
    let dropRow = WebDom.createElement("div")
    dropRow->WebDom.setAttribute("class", "drop-row")
    playfield->WebDom.appendChild(dropRow)->ignore

    // One zone per pile in the game, in model order, each carrying its declared
    // stacking behaviour. The `.drop-row` flexbox (`space-between`) spreads them
    // across the top of the stage, so two piles hug the edges and four spread
    // evenly — the view never counts them.
    let zones = game.piles->Array.mapWithIndex((pile: Game.pile, index) => {
      let el = WebDom.createElement("div")
      el->WebDom.setAttribute("class", "drop-zone")
      dropRow->WebDom.appendChild(el)->ignore
      {el, index, stacking: pile.stacking}
    })

    // The single source of truth for *where every card rests* (#77/#82): the view
    // holds one immutable `GameState`, seeded from the board's opening deal, and
    // re-derives every pile's layout from it. Drops dispatch reducer actions and
    // adopt the returned state; the view keeps only transient geometry (below).
    let state = ref(GameState.initial(game))

    // The DOM node for each model card, so a pile derived from `state` (structural
    // `{suit, rank}` cards) lays out onto the *same* elements every reflow — the
    // identity bridge (#45) from model card to node. Every `makeCard` registers
    // itself here; lookup is the deck-scoped `GameState.sameCard`.
    let nodes: array<card> = []
    let nodeFor = (data: Deck.card) => nodes->Array.find(n => GameState.sameCard(n.data, data))

    // How much the design footprints are shrunk to fit the stage. Cards fill
    // `fillFraction × width` split across the piles (`fillFraction · width / n`),
    // capped at the design size so a wide screen doesn't blow the cards up, and
    // floored so a crowded, narrow one keeps them legible. Held in a ref because the geometry
    // (reflow, the deal) reads it, and recomputed from the stage's live width the
    // moment before the deal — the one point at which the stage is known laid out.
    let numPiles = Array.length(game.piles)
    let scale = ref(1.)
    let applyScale = () => {
      let width = boundingRect(playfield).width
      if width > 0. && numPiles > 0 {
        let target = fillFraction *. width /. Int.toFloat(numPiles) /. cardW
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
      let top = count - 1
      cards->Array.forEachWithIndex((data, i) =>
        switch nodeFor(data) {
        | Some(c) =>
          let cr = boundingRect(c.wrapper)
          let baseX = zr.left +. zr.width /. 2. -. cr.width /. 2. -. pr.left
          let baseY = zr.top +. zoneBaseHeight *. scale.contents /. 2. -. cr.height /. 2. -. pr.top
          c.x := baseX
          c.y :=
            switch zone.stacking {
            | Game.Squared => baseY
            | Game.Fanned => baseY +. Int.toFloat(i) *. fanStep *. scale.contents
            }
          place(c)
          c.draggable := i == top
          i == top
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

      // The pointer offset at grab time, plus the card's position then; a move is
      // "start position + how far the pointer has travelled since". `None` when
      // not dragging.
      let grab = ref(None)

      // May this card land on `zone`? The hover highlight and the drop below both
      // funnel through `core`'s shared `canDrop` (#82) so the green "valid"
      // outline can never disagree with the accepted drop. The one thing `canDrop`
      // can't see is that re-dropping a card onto the pile it already tops is a
      // lawful no-op — during a drag the card still rests in `state`, so `canDrop`
      // would weigh it against itself — so mirror the reducer's identity case
      // here, keeping hover exactly in step with `reduce`.
      let accepts = zone =>
        switch GameState.locationOf(state.contents, cardData) {
        | Some(GameState.InPile(i, _)) if i == zone.index => true
        | _ => Reducer.canDrop(~game, state.contents, cardData, ~onto=zone.index)
        }

      let clearHover = () =>
        zones->Array.forEach(zone => {
          classList(zone.el)->removeClass("drop-zone--over")
          classList(zone.el)->removeClass("drop-zone--invalid")
        })

      // Outline the zone the card's centre is currently over (and only that one)
      // so the drop is legible before release: green when the rule accepts the
      // drop, red when it rejects it.
      let highlightHover = () => {
        let r = boundingRect(wrapper)
        let over = zoneAt(r.left +. r.width /. 2., r.top +. r.height /. 2.)
        zones->Array.forEach(zone => {
          let cls = classList(zone.el)
          switch over {
          | Some(z) if z === zone && accepts(zone) =>
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
        // Buried cards ignore the pointer entirely — for now only the top card
        // of a pile (or a free card) can be picked up.
        if self.draggable.contents {
          // Capture so the card keeps getting moves/up even if the pointer leaves
          // its bounds; raise it above every other card for the drag.
          wrapper->setPointerCapture(pointerId(ev))
          grab := Some((clientX(ev), clientY(ev), self.x.contents, self.y.contents))
          classList(wrapper)->addClass("dragging")
          bringToFront(wrapper)
        }
      )

      wrapper->onPointer("pointermove", ev =>
        switch grab.contents {
        | Some((startPX, startPY, startX, startY)) =>
          self.x := startX +. (clientX(ev) -. startPX)
          self.y := startY +. (clientY(ev) -. startPY)
          place(self)
          highlightHover()
        | None => ()
        }
      )

      let endDrag = ev =>
        switch grab.contents {
        | Some((_, _, startX, startY)) =>
          wrapper->releasePointerCapture(pointerId(ev))
          grab := None
          classList(wrapper)->removeClass("dragging")
          // Where the card's centre was released decides the *action*: onto a zone
          // is a `Move` to that pile; a miss is a `Move` to the loose table. The
          // reducer — not the view — then rules on it against the game's rules and
          // its `free` flag, so `core` owns every rest position (#83).
          let cr = boundingRect(wrapper)
          let target = switch zoneAt(cr.left +. cr.width /. 2., cr.top +. cr.height /. 2.) {
          | Some(zone) => Reducer.ToPile(zone.index)
          | None => Reducer.ToTable
          }
          switch Reducer.reduce(
            ~game,
            state.contents,
            Reducer.Move({card: self.data, to: target}),
          ) {
          // Lawful move (including the identity re-drop): adopt the new state and
          // reflow every pile from it. A card that joined a pile snaps to its slot;
          // a card left loose stays at the pixel it was dropped (no pile claims it).
          | Ok(next) =>
            state := next
            reflowAll()
          // Illegal move: bounce the card back where it came from. A card that
          // rests in a pile returns to its slot when that pile reflows; a loose
          // card (a rejected drop in a `free` game) returns to where the drag began.
          | Error(_) =>
            switch GameState.locationOf(state.contents, self.data) {
            | Some(GameState.InPile(_, _)) => reflowAll()
            | _ =>
              self.x := startX
              self.y := startY
              place(self)
            }
          }
          clearHover()
        | None => ()
        }

      wrapper->onPointer("pointerup", endDrag)
      // A cancelled pointer (e.g. the OS stealing the gesture) must tear the drag
      // down too, or the card would stay stuck to a pointer that's gone.
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

    let deal = () => {
      // Size the cards to the now-laid-out stage first, so both deals below place
      // and reflow cards at their final footprint.
      applyScale()
      dealPiles()
      dealFree()
    }

    // Deal now if the stage is already laid out (a later scene switch); otherwise
    // on the next frame, before the first paint, once the detached-at-mount stage
    // has been inserted and sized (the first page load). Both the pile cards and
    // the loose cards need the stage's live rects, so both wait on this.
    boundingRect(playfield).width > 0. ? deal() : requestAnimationFrame(deal)->ignore

    // The caption is the game's own prose (`Game.caption`); a game without one
    // simply shows no caption.
    switch game.caption {
    | Some(text) =>
      let caption = WebDom.createElement("p")
      caption->WebDom.setAttribute("class", "stacking-caption")
      caption->WebDom.setTextContent(text)
      container->WebDom.appendChild(caption)->ignore
    | None => ()
    }

    // The switcher clears the container on scene change, dropping the playfield
    // and every listener with it — nothing extra to tear down.
    () => ()
  },
}
