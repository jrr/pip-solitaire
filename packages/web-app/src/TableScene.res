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
// `style.zIndex`; these are the only style bindings the drag loop needs.
type style
@get external style: WebDom.element => style = "style"
@set external setLeft: (style, string) => unit = "left"
@set external setTop: (style, string) => unit = "top"
@set external setZIndex: (style, string) => unit = "zIndex"

// Toggling the drag/hover/buried marker classes goes through classList rather
// than rewriting the whole `class` attribute each move.
type tokenList
@get external classList: WebDom.element => tokenList = "classList"
@send external addClass: (tokenList, string) => unit = "add"
@send external removeClass: (tokenList, string) => unit = "remove"

// A zone and a card reference each other — the zone owns the ordered pile of
// cards resting in it, and each card knows which zone is its `home` — so the
// two types are mutually recursive.
//
// The pile is the *source of truth* for stacking: a card's slot is simply its
// index in the pile, and the top card is the last element. Because only the
// top card is draggable (below), a pile behaves like a stack — cards are only
// ever pushed onto or popped off the top — so the slots of the survivors stay
// contiguous and the Fanned offsets reflow (and reset) instead of a raw count
// that only ever grew. The `stacking` behaviour comes straight from the game's
// pile (`Game.stacking`).
type rec dropZone = {
  el: WebDom.element,
  stacking: Game.stacking,
  pile: ref<array<card>>,
}
// A draggable card: its element, its live playfield-local position, the zone it
// currently rests in (if any), and whether it may be picked up right now. Only
// the top card of a pile — or a free card resting nowhere — is `draggable`.
and card = {
  wrapper: WebDom.element,
  x: ref<float>,
  y: ref<float>,
  home: ref<option<dropZone>>,
  draggable: ref<bool>,
}

// How far each Fanned card steps off the one beneath it. The zones sit at the
// top of the stage and the pile grows downward, so the fan steps *down*, the
// newest card landing lowest and fully exposed.
let fanStep = 26.

// Card footprint in playfield pixels (width from CSS; height from the 5:7
// viewBox). Used by the initial deal, which places cards before they're laid
// out and so can't read their rects yet.
let cardW = 80.
let cardH = 112.

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
    let zones = game.piles->Array.map((pile: Game.pile) => {
      let el = WebDom.createElement("div")
      el->WebDom.setAttribute("class", "drop-zone")
      dropRow->WebDom.appendChild(el)->ignore
      {el, stacking: pile.stacking, pile: ref([])}
    })

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
    let reflow = zone => {
      let pr = boundingRect(playfield)
      let zr = boundingRect(zone.el)
      let top = Array.length(zone.pile.contents) - 1
      zone.pile.contents->Array.forEachWithIndex((c, i) => {
        let cr = boundingRect(c.wrapper)
        let baseX = zr.left +. zr.width /. 2. -. cr.width /. 2. -. pr.left
        let baseY = zr.top +. zr.height /. 2. -. cr.height /. 2. -. pr.top
        c.x := baseX
        c.y :=
          switch zone.stacking {
          | Game.Squared => baseY
          | Game.Fanned => baseY +. Int.toFloat(i) *. fanStep
          }
        place(c)
        c.draggable := i == top
        i == top
          ? classList(c.wrapper)->removeClass("stacking-card--buried")
          : classList(c.wrapper)->addClass("stacking-card--buried")
      })
    }

    // Pop a card off its home pile (it's always the top card, so the survivors
    // stay contiguous) and let it float free again.
    let leaveHome = c =>
      switch c.home.contents {
      | Some(zone) =>
        zone.pile := zone.pile.contents->Array.filter(other => other !== c)
        c.home := None
        c.draggable := true
        reflow(zone)
      | None => ()
      }

    // Settle a card into a zone. Re-dropping onto the zone it already tops just
    // reflows it back into place; otherwise it leaves its old home and is pushed
    // onto this zone's pile as the new top card.
    let joinZone = (c, zone) =>
      switch c.home.contents {
      | Some(h) if h === zone => reflow(zone)
      | _ =>
        leaveHome(c)
        zone.pile := zone.pile.contents->Array.concat([c])
        c.home := Some(zone)
        reflow(zone)
      }

    // Build one draggable card and wire its pointer loop. It starts at 0,0 and is
    // positioned by the initial deal (below); returning `self` lets the caller
    // collect the free cards and lay them out together.
    let makeCard = (cardData: Deck.card) => {
      let wrapper = WebDom.createElement("div")
      wrapper->WebDom.setAttribute("class", "stacking-card")
      wrapper->WebDom.appendChild(Html.create(CardArt.svg(cardData)))->ignore

      // The card's mutable state: position (kept here rather than parsed back
      // out of the style each move), its home zone, and whether it's on top and
      // so pickable. Cards start free and draggable.
      let self = {
        wrapper,
        x: ref(0.),
        y: ref(0.),
        home: ref(None),
        draggable: ref(true),
      }

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

      // Light up the zone the card's centre is currently over (and only that one)
      // so the drop target is legible before you let go.
      let highlightHover = () => {
        let r = boundingRect(wrapper)
        let over = zoneAt(r.left +. r.width /. 2., r.top +. r.height /. 2.)
        zones->Array.forEach(zone => {
          let isOver = switch over {
          | Some(z) => z === zone
          | None => false
          }
          isOver
            ? classList(zone.el)->addClass("drop-zone--over")
            : classList(zone.el)->removeClass("drop-zone--over")
        })
      }

      let clearHover = () =>
        zones->Array.forEach(zone => classList(zone.el)->removeClass("drop-zone--over"))

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
        | Some(_) =>
          wrapper->releasePointerCapture(pointerId(ev))
          grab := None
          classList(wrapper)->removeClass("dragging")
          // Snap onto the zone the card's centre was released over, if any.
          // On a miss the game's `free` rule decides: a free game leaves the card
          // loose where it was dropped, while a non-free game (#63) snaps it back
          // to the pile it came from so cards only ever rest in piles.
          let cr = boundingRect(wrapper)
          switch zoneAt(cr.left +. cr.width /. 2., cr.top +. cr.height /. 2.) {
          | Some(zone) => joinZone(self, zone)
          | None =>
            switch (game.free, self.home.contents) {
            | (false, Some(zone)) => reflow(zone)
            | _ => leaveHome(self)
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

    // The cards a pile opens holding (#63), built now so they exist as DOM
    // before the deal and paired with their target zone (model order matches
    // `zones`); they're settled into that zone once the stage is laid out
    // (below). Created before the loose cards so a later loose card layers on top.
    let pileCards =
      game.piles
      ->Array.mapWithIndex((pile: Game.pile, i) =>
        switch zones->Array.get(i) {
        | Some(zone) => pile.cards->Array.map(card => (makeCard(card), zone))
        | None => []
        }
      )
      ->Array.flat

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
      // Nominal horizontal step, squeezed so a wide cluster still fits the stage.
      let avail = pr.width -. cardW -. 32.
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
        c.x := pr.width /. 2. -. spread /. 2. +. Int.toFloat(i) *. stepX -. cardW /. 2. +. jitterX
        c.y := centerY -. cardH /. 2. +. stagger +. jitterY
        place(c)
      })
    }

    // Settle each opening pile card into its zone: `joinZone` stacks and reflows
    // it, so the pile ends laid out exactly as an interactively built one would.
    let dealPiles = () => pileCards->Array.forEach(((c, zone)) => joinZone(c, zone))

    let deal = () => {
      dealPiles()
      dealFree()
    }

    // Deal now if the stage is already laid out (a later scene switch); otherwise
    // on the next frame, before the first paint, once the detached-at-mount stage
    // has been inserted and sized (the first page load). Both the pile cards and
    // the loose cards need the stage's live rects, so both wait on this.
    boundingRect(playfield).width > 0. ? deal() : requestAnimationFrame(deal)->ignore

    let caption = WebDom.createElement("p")
    caption->WebDom.setAttribute("class", "stacking-caption")
    caption->WebDom.setTextContent(
      game.free
        ? "Drag the cards onto a slot to pile them up, or drop them loose on the table."
        : "Drag the cards between the slots — they can only rest in a pile.",
    )
    container->WebDom.appendChild(caption)->ignore

    // The switcher clears the container on scene change, dropping the playfield
    // and every listener with it — nothing extra to tear down.
    () => ()
  },
}
