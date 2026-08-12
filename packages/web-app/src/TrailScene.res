// The `trail` scene (#226): the two mechanics the victory overlay rests on,
// proved on their own before going anywhere near `TableScene`'s 1800 lines.
//
// The overlay the victory animation wants is a transparent `<canvas>` laid over
// the live board, with resting cards handed off to it one at a time and flung
// around as sprites. Two things have to be true for that to work, and neither is
// a physics question:
//
//   1  **Transparency over live DOM.** A canvas covering the board must show the
//      board through it — every pixel the animation hasn't drawn on, and every
//      pixel it draws with a transparent sprite. This scene puts a handful of
//      real `.stacking-card` nodes underneath (the same class and the same
//      `CardArt.svg` the board lays out, so it's the actual arrangement, not a
//      stand-in) and draws on top of them.
//
//   2  **The hand-off.** A card resting in the DOM has to become a sprite on the
//      canvas without visibly moving. The "hand off" button does exactly that:
//      it removes one backdrop card from the document and stamps its sprite at
//      the pixel position the node was occupying. Nothing should appear to
//      happen — that's the whole test. The card then becomes the one the pointer
//      carries, so it visibly *continues* on the canvas.
//
// Drawing never clears, so the pointer leaves a trail of cards. That's not
// decoration: a trail is the cheapest way to see a scale bug. Every stamp is one
// `drawImage` at a known size, so if the backing store and the sprites disagreed
// about the pixel ratio the trail would be a row of subtly soft or subtly
// stretched cards, which is far easier to catch than one card in motion.
//
// Two mechanics on show beyond those:
//
//   - **The pixel-ratio cap.** The backing store is `cssSize × ratio` with
//     `ctx.scale(ratio, ratio)`, and the sprites are built at the *same* ratio —
//     `CardRaster.renderRatio`, which is `min(devicePixelRatio, cap)`. The
//     1×/2×/3× toggle moves the cap and rebuilds both together, so the question
//     "does capping at 2 lose anything?" can be answered by looking. (It matters
//     because the raw ratio isn't small: browser zoom multiplies it, and a Retina
//     Mac one step in reports 3.75. See `CardRaster.maxPixelRatio`.) On a plain
//     1× display all three caps are the same number and the status line says so.
//
//   - **Assigning `canvas.width` wipes everything.** Deliberately on a button.
//     It's why the integration ends the cascade on a resize rather than trying to
//     rescale it: there is nothing to rescale, the pixels are gone, and the
//     transform is reset to identity too (which is why `scale` is re-applied
//     every time the backing store is sized).
//
// Everything here is imperative rather than the `Html` Elm loop, for the reason
// `TableScene` is: the canvas holds the drawing, so it must survive across every
// interaction. A view function that re-rendered it would wipe the trail on each
// toolbar tap — the very bug the resize button exists to demonstrate.
//
// `getContext` is guarded rather than trusted (`CardRaster.context2d`): jsdom has
// no rasterizer behind `<canvas>`, so under the unit tests there is no context at
// all, and the scene has to mount empty instead of throwing.

// --- Bindings ---------------------------------------------------------------
// The canvas *vocabulary* — the canvas and context types, `getContext`, and the
// blit itself — is `CardRaster`'s, since it owns the sprites being drawn. Only
// what an overlay needs on top of that is bound here.

@send external scale: (CardRaster.context, float, float) => unit = "scale"

// The stage's live size in CSS pixels, and the origin pointer positions are
// measured against.
type domRect = {left: float, top: float, width: float, height: float}
@send external boundingRect: WebDom.element => domRect = "getBoundingClientRect"

type pointerEvent
@get external clientX: pointerEvent => float = "clientX"
@get external clientY: pointerEvent => float = "clientY"
@send
external onPointer: (WebDom.element, string, pointerEvent => unit) => unit = "addEventListener"

// The scene mounts while the container is still detached (see `SceneSwitcher`),
// so the stage has no size yet; the first sizing waits a frame, exactly as
// `TableScene`'s opening deal does.
@val external requestAnimationFrame: (unit => unit) => int = "requestAnimationFrame"

// The keyboard shortcut reads the plain `KeyboardEvent` fields it needs, the same
// shape `RasterScene` declares for the same purpose.
type keyEvent
@get external eventKey: keyEvent => string = "key"
@get external metaKey: keyEvent => bool = "metaKey"
@get external ctrlKey: keyEvent => bool = "ctrlKey"
@get external altKey: keyEvent => bool = "altKey"

// --- Geometry ----------------------------------------------------------------

// The card size everything here is drawn at, in CSS pixels. 80 rather than
// something rounder for the reason the `raster` scene picks it: the card's 5:7
// ratio has to come out whole, and 80 × 1.4 = 112 exactly, so no stage of the
// pipeline is quietly resampling to a fractional height.
let cardWidth = 80.
let cardHeight = cardWidth *. CardArt.aspect

// The backdrop: a few cards from across the deck (both colours, a court card, the
// double-width "10"), overlapped in a fan the way a cascade sits, so the canvas
// above has something with detail and edges to show through. Indices into
// `Deck.allCards` — suits grouped, ranks ascending.
let backdropDeck = [0, 9, 25, 30, 44, 51]->Array.filterMap(index => Deck.allCards->Array.get(index))

// Where the *i*th backdrop card rests, in stage CSS pixels. A steady horizontal
// step with alternating rows: overlapping enough that a card lifted out of the
// middle leaves an obvious gap, which is what makes the hand-off legible.
let restingX = index => 16. +. Int.toFloat(index) *. (cardWidth *. 0.66)
let restingY = index => mod(index, 2) == 0 ? 24. : 24. +. cardHeight *. 0.28

// The stage's height: two overlapped rows of cards plus room to draw above and
// below them.
let stageHeight = 24. +. cardHeight *. 1.28 +. 40.

// The caps the toggle offers. The order *is* the 1/2/3 key mapping and the number
// printed on each button, so there's one fact rather than three that can drift.
let caps = [1., 2., 3.]

let capLabel = cap => Float.toString(cap) ++ "×"

// --- The backdrop cards ------------------------------------------------------

// One card of the backdrop: the DOM node, where it rests, and whether it's been
// handed off to the canvas. The node is kept after removal so Reset can put it
// back — a hand-off detaches it from the document, it doesn't destroy it.
type backdropCard = {
  card: Deck.card,
  node: WebDom.element,
  x: float,
  y: float,
  mutable handedOff: bool,
}

let make = (): Scene.t => {
  id: "trail",
  label: "Trail",
  mount: container => {
    let el = (tag, className) => {
      let e = WebDom.createElement(tag)
      e->WebDom.setAttribute("class", className)
      e
    }

    // ---- DOM ----
    let root = el("div", "trail-scene")
    container->WebDom.appendChild(root)->ignore

    let toolbar = el("div", "trail-scene__toolbar")
    root->WebDom.appendChild(toolbar)->ignore

    let status = el("p", "trail-scene__status")
    root->WebDom.appendChild(status)->ignore

    // The stage publishes the card footprint the real board publishes, because
    // the backdrop nodes are real `.stacking-card`s and that's the property they
    // size themselves from.
    let stage = el("div", "trail-stage")
    stage->WebDom.setAttribute(
      "style",
      `--card-w:${Float.toString(cardWidth)}px;` ++
      `--card-h:${Float.toString(cardHeight)}px;` ++
      `height:${Float.toString(stageHeight)}px`,
    )
    root->WebDom.appendChild(stage)->ignore

    let backdrop = el("div", "trail-backdrop")
    stage->WebDom.appendChild(backdrop)->ignore

    // The overlay. It goes *after* the backdrop so it layers above without a
    // z-index, and it takes no pointer events — the cards underneath stay
    // hoverable, which is half of "the DOM below is still live".
    let canvasEl = el("canvas", "trail-canvas")
    stage->WebDom.appendChild(canvasEl)->ignore
    let canvas = CardRaster.elementCanvas(canvasEl)

    let hint = el("p", "trail-scene__hint")
    hint->WebDom.setTextContent(
      "Move the pointer across the stage to draw. The cards underneath are ordinary DOM.",
    )
    root->WebDom.appendChild(hint)->ignore

    // ---- State ----
    // The context is fetched once and held: `getContext` hands back the same
    // object every time, and it's `None` for the whole life of the scene where
    // there's no rasterizer (jsdom), so asking again would never change the
    // answer.
    let ctx = CardRaster.context2d(canvas)
    let cap = ref(CardRaster.maxPixelRatio)
    let cache: ref<option<CardRaster.t>> = ref(None)
    let error: ref<option<string>> = ref(None)
    // The sprite the pointer is currently carrying. It starts as an ordinary card
    // and becomes whichever card was handed off last.
    let brush: ref<option<CardRaster.sprite>> = ref(None)
    // The backing store's CSS size and the ratio it was last sized at, so the
    // status line reports what's actually on screen rather than what was asked
    // for.
    let cssSize = ref((0., 0.))
    let sizedAt = ref(0.)
    let stamps = ref(0)

    // Real `.stacking-card` nodes wrapping the real `CardArt.svg`, positioned the
    // way the board positions a card: absolute, `left`/`top` in pixels, sized from
    // the `--card-w` published on the stage above.
    let backdropCards = backdropDeck->Array.mapWithIndex((card, index) => {
      let node = el("div", "stacking-card")
      node->WebDom.appendChild(Html.create(CardArt.svg(card)))->ignore
      let x = restingX(index)
      let y = restingY(index)
      node->WebDom.setAttribute("style", `left:${Float.toString(x)}px;top:${Float.toString(y)}px`)
      backdrop->WebDom.appendChild(node)->ignore
      {card, node, x, y, handedOff: false}
    })

    let ratio = () => CardRaster.renderRatio(~cap=cap.contents)

    // ---- Status -----------------------------------------------------------
    // Everything the two mechanics are made of, in one line: the ratio the cap
    // resolved to, the backing store that ratio produced, the ratio the *sprites*
    // were built at (these two agreeing is what makes a blit 1:1), and how much
    // has been drawn.
    let describe = () => {
      let (w, h) = cssSize.contents
      let n = value => Math.round(value)->Float.toString
      let device = CardRaster.deviceRatio()
      let effective = ratio()
      let head =
        `stage ${n(w)}×${n(h)} css · device ${Float.toString(device)}× · ` ++
        `cap ${capLabel(cap.contents)} → ${Float.toString(effective)}× · ` ++
        `backing store ${n(w *. sizedAt.contents)}×${n(h *. sizedAt.contents)}`
      switch (error.contents, cache.contents) {
      | (Some(message), _) => `${head} · couldn't build sprites — ${message}`
      | (None, None) => `${head} · rasterizing…`
      | (None, Some(built)) =>
        let handed = backdropCards->Array.filter(entry => entry.handedOff)->Array.length
        `${head} · sprites @${Float.toString(built.pixelRatio)}× · ` ++
        `${Int.toString(stamps.contents)} stamps · ${Int.toString(handed)} handed off` ++ (
          device <= 1. ? " · (1× display: every cap is the same picture here)" : ""
        )
      }
    }

    // Rebuilt on every change so the toolbar's `--on` state, the readiness flag
    // and the status line can't drift out of step with each other.
    let refresh = ref(() => ())

    // ---- Drawing ------------------------------------------------------------

    // Stamp a sprite with its *centre* at a stage position. Nothing is cleared
    // first — this is the call the whole trail accumulates from, and the only
    // place anything is drawn.
    let stamp = (sprite: CardRaster.sprite, ~x, ~y) =>
      switch ctx {
      | Some(ctx) =>
        CardRaster.blit(ctx, sprite, ~x=x -. sprite.cssWidth /. 2., ~y=y -. sprite.cssHeight /. 2.)
        stamps := stamps.contents + 1
      | None => ()
      }

    // Size the backing store to `cssSize × ratio` and pre-scale the context by the
    // same number, so everything downstream can draw in plain CSS pixels.
    //
    // This is also the wipe: assigning `canvas.width` drops every pixel *and*
    // resets the transform to identity, which is why the `scale` is re-applied
    // here rather than once at mount. It's the reason the integration will end the
    // cascade on a resize instead of trying to carry it across one.
    let sizeBackingStore = () => {
      let rect = stage->boundingRect
      let ratio = ratio()
      cssSize := (rect.width, rect.height)
      sizedAt := ratio
      stamps := 0
      canvasEl->WebDom.setAttribute(
        "style",
        `width:${Float.toString(rect.width)}px;height:${Float.toString(rect.height)}px`,
      )
      canvas->CardRaster.setPixelWidth(Math.round(rect.width *. ratio)->Float.toInt)
      canvas->CardRaster.setPixelHeight(Math.round(rect.height *. ratio)->Float.toInt)
      switch ctx {
      | Some(ctx) => ctx->scale(ratio, ratio)
      | None => ()
      }
    }

    // ---- The sprite build ---------------------------------------------------
    // Same cancellation shape as the `raster` scene: a build takes a moment, and
    // inside that moment the cap can change again or the scene can be torn down.
    // Each request takes the next number; a promise resolving under any other
    // number belongs to a build nobody is waiting for. Unmount takes 0, which no
    // request holds.
    let wanted = ref(0)

    let rebuildSprites = () => {
      wanted := wanted.contents + 1
      let mine = wanted.contents
      let stillWanted = () => mine == wanted.contents
      cache := None
      error := None
      brush := None
      refresh.contents()

      CardRaster.build(~cssWidth=cardWidth, ~pixelRatio=ratio(), Deck.allCards)
      ->Promise.thenResolve(built =>
        if stillWanted() {
          cache := Some(built)
          // The pointer picks up the first backdrop card that hasn't been handed
          // off, so there's something to draw with before anything is handed
          // over. Falls back to the first card of the deck if they've all gone.
          brush :=
            backdropCards
            ->Array.find(entry => !entry.handedOff)
            ->Option.map(entry => entry.card)
            ->Option.orElse(Deck.allCards->Array.get(0))
            ->Option.flatMap(card => CardRaster.get(built, card))
          refresh.contents()
        }
      )
      ->Promise.catch(failure => {
        if stillWanted() {
          error :=
            Some(
              switch failure->JsExn.fromException {
              | Some(e) => e->JsExn.message->Option.getOr("unknown error")
              | None => "unknown error"
              },
            )
          refresh.contents()
        }
        Promise.resolve()
      })
      ->ignore
    }

    // ---- Actions ------------------------------------------------------------

    // The hand-off, and the reason this scene exists. Take the first card still in
    // the document, remove it, and stamp its sprite at the exact pixel position it
    // was occupying — so a correct hand-off looks like nothing happened. Then make
    // it the pointer's sprite, so it carries on across the canvas.
    //
    // The position comes from the layout numbers the node was placed with rather
    // than from a fresh `getBoundingClientRect`: the two agree, and reading them
    // back would be measuring the arithmetic against itself.
    let handOff = () =>
      switch (cache.contents, backdropCards->Array.find(entry => !entry.handedOff)) {
      | (Some(built), Some(entry)) =>
        switch CardRaster.get(built, entry.card) {
        | Some(sprite) =>
          entry.node->WebDom.remove
          entry.handedOff = true
          stamp(sprite, ~x=entry.x +. cardWidth /. 2., ~y=entry.y +. cardHeight /. 2.)
          brush := Some(sprite)
          refresh.contents()
        | None => ()
        }
      | _ => ()
      }

    // Put the backdrop back in the document and wipe the canvas under it, so the
    // scene can be run through again without a reload.
    let reset = () => {
      backdropCards->Array.forEach(entry =>
        if entry.handedOff {
          backdrop->WebDom.appendChild(entry.node)->ignore
          entry.handedOff = false
        }
      )
      sizeBackingStore()
      refresh.contents()
    }

    let chooseCap = next =>
      if next != cap.contents {
        cap := next
        // Both halves move together, and they have to: the backing store and the
        // sprites are only blitted 1:1 while they agree on the ratio.
        sizeBackingStore()
        rebuildSprites()
      }

    // ---- Toolbar ------------------------------------------------------------
    let capButtons = caps->Array.mapWithIndex((value, index) => {
      let button = el("button", "trail-toggle")
      button->WebDom.setAttribute("type", "button")
      let key = el("span", "trail-toggle__key")
      key->WebDom.setTextContent(Int.toString(index + 1))
      button->WebDom.appendChild(key)->ignore
      let label = el("span", "trail-toggle__label")
      label->WebDom.setTextContent("cap " ++ capLabel(value))
      button->WebDom.appendChild(label)->ignore
      button->WebDom.addEventListener("click", () => chooseCap(value))
      toolbar->WebDom.appendChild(button)->ignore
      (value, button)
    })

    let action = (label, handler) => {
      let button = el("button", "trail-action")
      button->WebDom.setAttribute("type", "button")
      button->WebDom.setTextContent(label)
      button->WebDom.addEventListener("click", handler)
      toolbar->WebDom.appendChild(button)->ignore
      button
    }

    let handOffButton = action("Hand off a card", handOff)
    // The wipe, on a button, because it's a mechanic rather than an accident: the
    // size doesn't change, only `canvas.width` is written, and everything drawn
    // disappears.
    action("Re-assign canvas.width", () => {
      sizeBackingStore()
      refresh.contents()
    })->ignore
    action("Reset", reset)->ignore

    refresh :=
      (
        () => {
          status->WebDom.setTextContent(describe())
          capButtons->Array.forEach(((value, button)) =>
            button->WebDom.setAttribute(
              "class",
              value == cap.contents ? "trail-toggle trail-toggle--on" : "trail-toggle",
            )
          )
          // Nothing to hand off until the sprites are in, or once they've all
          // gone.
          let handable =
            cache.contents->Option.isSome && backdropCards->Array.some(entry => !entry.handedOff)
          handable
            ? handOffButton->WebDom.removeAttribute("disabled")
            : handOffButton->WebDom.setAttribute("disabled", "")
          root->WebDom.setAttribute("data-cap", capLabel(cap.contents))
          // The browser suite's signal that the sprites have landed — the build is
          // async, so there's nothing else to wait on. `no-canvas` is the jsdom
          // case, kept distinct so a missing context reads as itself rather than
          // as a build that never finished.
          root->WebDom.setAttribute(
            "data-trail",
            switch (ctx, cache.contents) {
            | (None, _) => "no-canvas"
            | (Some(_), Some(_)) => "ready"
            | (Some(_), None) => "building"
            },
          )
        }
      )

    // ---- Input --------------------------------------------------------------
    // The trail. The canvas takes no pointer events (see the CSS), so this rides
    // on the stage — which is also the proof that the DOM under the overlay is
    // still receiving them.
    stage->onPointer("pointermove", event =>
      switch brush.contents {
      | Some(sprite) =>
        let rect = stage->boundingRect
        stamp(sprite, ~x=clientX(event) -. rect.left, ~y=clientY(event) -. rect.top)
        // Only the line, not the whole toolbar: nothing else changes as the
        // pointer moves, and this runs at pointer rate.
        status->WebDom.setTextContent(describe())
      | None => ()
      }
    )

    // Keys 1/2/3 pick the *n*th cap — the same indexing as the number printed on
    // the *n*th button. Modified presses are left alone: ⌘1/^1 switch browser
    // tabs, and a debug scene has no business eating that.
    let onKey = event =>
      if !(event->metaKey) && !(event->ctrlKey) && !(event->altKey) {
        switch Int.fromString(event->eventKey) {
        | Some(n) => caps->Array.get(n - 1)->Option.forEach(chooseCap)
        | None => ()
        }
      }
    WebDom.addWindowListener("keydown", onKey)

    // ---- Start ----------------------------------------------------------------
    // The stage has no size until it's in the document, so the first sizing waits
    // a frame; the sprite build doesn't depend on layout and can start at once.
    refresh.contents()
    rebuildSprites()
    requestAnimationFrame(() => {
      sizeBackingStore()
      refresh.contents()
    })->ignore

    () => {
      // No request holds 0, so unmount abandons every build in flight.
      wanted := 0
      // The listener is on `window`, which clearing the scene container can't
      // reach — so it has to come off by hand, with the same handler value.
      WebDom.removeWindowListener("keydown", onKey)
    }
  },
}
