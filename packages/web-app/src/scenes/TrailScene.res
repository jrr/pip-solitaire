// The `trail` scene: the two mechanics the victory overlay rests on,
// proved on their own before any of this goes near `TableScene`'s 2400 lines.
//
// The victory animation wants to fling the deck around at 60fps over a board
// that is still live DOM. That plan has exactly two load-bearing assumptions,
// and neither is a thing a unit test can see:
//
//   1  **Transparency over live DOM.** A canvas laid over the board has to let
//      the real cards underneath show through, and stay out of hit-testing.
//   2  **The hand-off.** A card that is a DOM node one frame has to become a
//      sprite on the canvas the next, in the same place, without a flicker —
//      that's how a resting card joins the cascade.
//
// So: a few *real* `.stacking-card` nodes as backdrop, a transparent overlay
// canvas above them, and one sprite stamped at the pointer **without clearing**,
// so the drawing accumulates into a trail. No physics — where a card goes is
// #227's question; this one is only about whether the surface works.
//
// Three things the scene is deliberately built to show:
//
// **The backing store is `css × ratio`, and the ratio is capped.** The store is
// sized in device pixels and the context `scale`d, so everything below draws in
// CSS pixels. The 1×/2×/3× toggle is not a display knob: it rebuilds *both* the
// store and the sprites at the chosen cap, which is the only way to see that
// capping at `CardRaster.maxPixelRatio` costs nothing you can point at. The
// number is the cache's (see `CardRaster.displayPixelRatio`) precisely so the two
// can't drift — a store at one ratio and sprites at another turns every blit into
// a resample.
//
// **Assigning `canvas.width` wipes the trail.** There's a button for it, because
// it is worth seeing on purpose: it is why the integration will *end* the cascade
// on a resize rather than try to rescale mid-flight. The window `resize` listener
// below is the same fact arriving unasked.
//
// **A hand-off looks like nothing happened.** "Hand off a card" takes the
// topmost backdrop card, stamps its sprite at the exact pixel the node occupied,
// and removes the node — and then the pointer carries that card, so it visibly
// continues on the canvas. Topmost, because nothing overlaps it: a buried card
// stamped onto the overlay would paint *over* the neighbour that was covering it.
//
// One difference the hand-off can't hide, and the integration will meet: the
// drop-shadow is the DOM's (`.stacking-card`'s `filter`), not the sprite's. The
// card loses its shadow as it leaves the document. Cheap to live with for a card
// in flight; worth knowing before it's a surprise.
//
// Not in the screenshot report: what this scene shows is a pointer trail, and a
// screenshot with no pointer in it is an empty box. The pixels are checked in
// `browser-tests/trail.spec.mjs`, which can move a pointer and read the overlay's
// own buffer back.

%%raw(`import "./TrailScene.css"`)
// …and the board's, because the backdrop is deliberately the *real* resting card
// — `.stacking-card` is `TableScene`'s rule, and what this scene is proving is
// that an overlay works over that exact node, shadow and all. Importing it here
// says so, rather than relying on `Main` having pulled the board in anyway.
%%raw(`import "./TableScene.css"`)

// --- Pointer / geometry bindings ---------------------------------------------
// The same shape `TableScene` uses: `WebDom`'s `addEventListener` is event-less,
// and a trail needs the pointer's coordinates.
type pointerEvent
@get external clientX: pointerEvent => float = "clientX"
@get external clientY: pointerEvent => float = "clientY"
@send
external onPointer: (WebDom.element, string, pointerEvent => unit) => unit = "addEventListener"

// Viewport coordinates, which is what `getBoundingClientRect` answers with.
type rect = {left: float, top: float, width: float, height: float}
@send external boundingRect: WebDom.element => rect = "getBoundingClientRect"

// The display's own ratio, read live — the number the cap is applied to.
@val @scope("window") external devicePixelRatio: float = "devicePixelRatio"

// The scene mounts detached (see SceneSwitcher), so the overlay has no rect until
// it is in the document and laid out — the first sizing has to wait a frame, the
// same way the board's opening deal does.
@val external requestAnimationFrame: (unit => unit) => int = "requestAnimationFrame"

// --- The numbers -------------------------------------------------------------

// The size a card is drawn at here. Not the board's — the board scales its cards
// to the stage — just a comfortable one for a demo stage.
let cardWidth = 96.

// Where the backdrop fan sits in the stage, and how far each card steps off the
// one before it. The step is a fraction of the card rather than a fixed gap, so
// the fan stays inside a phone-width stage: five cards land in
// `cardWidth × (1 + 4 × step)`, about 260px at 0.42. It sits low enough to leave
// clear canvas above it, which is where the trail is easiest to read.
let fanLeft = 20.
let fanTop = 110.
let fanStep = 0.42

// The caps the toggle offers. 2 is the one that ships (`CardRaster.maxPixelRatio`);
// 1 and 3 are the comparison it has to survive — 1 to see what capping *too* hard
// costs, 3 to see whether the cap gives anything up.
let caps = [1., 2., 3.]

// What a canvas is actually drawn at: the display's ratio, capped. Below the cap
// the display wins, and asking for 3× on a 1× monitor gets you 1× — a backing
// store finer than the screen is pure cost.
let drawRatio = (~display, ~cap) => Math.min(display, cap)

// A backing-store dimension, in device pixels, from a CSS one. Rounded, not
// truncated: a fractional store is not a thing, and rounding down would leave the
// last row of CSS pixels drawing into nothing.
let storePixels = (~css, ~ratio) => Math.round(css *. ratio)->Float.toInt

// A ratio as it reads in the status line: "2" rather than "2", "3.75" rather than
// "3.7500000001".
let showRatio = ratio => (Math.round(ratio *. 100.) /. 100.)->Float.toString

// The backdrop, bottom card first — so the last of these is the topmost, and the
// one "hand off" takes. A sixth card, not in the fan, is what the pointer carries
// to begin with, so the trail reads as its own thing until a hand-off replaces it.
let backdropCards: array<Deck.card> = [
  {suit: Deck.Spades, rank: Deck.Seven},
  {suit: Deck.Hearts, rank: Deck.Queen},
  {suit: Deck.Diamonds, rank: Deck.Two},
  {suit: Deck.Clubs, rank: Deck.Ten},
  {suit: Deck.Hearts, rank: Deck.Ace},
]
let carriedCard: Deck.card = {suit: Deck.Spades, rank: Deck.Ace}

let make = (): Scene.t => {
  id: "trail",
  label: "Trail",
  kind: Demo,
  mount: container => {
    let el = (tag, className) => {
      let e = WebDom.createElement(tag)
      e->WebDom.setAttribute("class", className)
      e
    }

    // ---- DOM ----
    let scene = el("div", "trail-scene")
    scene->WebDom.setAttribute("style", `--card-w: ${Float.toString(cardWidth)}px`)
    container->WebDom.appendChild(scene)->ignore

    let toolbar = el("div", "trail-toolbar")
    scene->WebDom.appendChild(toolbar)->ignore

    let status = el("p", "trail-status")
    scene->WebDom.appendChild(status)->ignore

    // The stage is framed with an inset `box-shadow`, **not a border** — see
    // TrailScene.css. The overlay is `inset: 0` inside it and its size is read
    // back off its own rect, so nothing here depends on which box is which; the
    // shadow keeps it that way for anyone who copies this into a host that does.
    let stage = el("div", "trail-stage")
    scene->WebDom.appendChild(stage)->ignore

    let overlay = Canvas.make()
    let overlayEl = Canvas.element(overlay)
    overlayEl->WebDom.setAttribute("class", "trail-overlay")

    // Every backdrop card is a real `.stacking-card` holding the real card art,
    // built exactly the way the board builds one — and kept in that order, so the
    // last of them is the one painted on top and the one a hand-off takes. No
    // z-index: they're absolutely positioned siblings, so document order is the
    // stacking order, which is a fan.
    let resting = backdropCards->Array.mapWithIndex((card, index) => {
      let node = el("div", "stacking-card")
      node->WebDom.appendChild(Html.create(CardArt.svg(card)))->ignore
      let left = fanLeft +. Int.toFloat(index) *. cardWidth *. fanStep
      node->WebDom.setAttribute(
        "style",
        `left:${Float.toString(left)}px;top:${Float.toString(fanTop)}px`,
      )
      stage->WebDom.appendChild(node)->ignore
      (card, node)
    })
    // The overlay goes on *after* the cards, so it paints above them without
    // anyone having to hold a z-index. It takes no pointer events (CSS), which is
    // what leaves the stage below hearing the moves.
    stage->WebDom.appendChild(overlayEl)->ignore

    // ---- State ----
    let cap = ref(CardRaster.maxPixelRatio)
    let cache: ref<option<CardRaster.t>> = ref(None)
    let error: ref<option<string>> = ref(None)
    // The sprite the pointer draws. `None` until the (async) build lands — there
    // is nothing to stamp before that, and nothing that pretends otherwise.
    let carried: ref<option<CardRaster.sprite>> = ref(None)
    // Backdrop cards still in the document, topmost last.
    let standing: ref<array<(Deck.card, WebDom.element)>> = ref(resting)
    // The build whose result is still wanted, exactly as `RasterScene` numbers
    // its own: a cap change or an unmount abandons whatever is in flight.
    let wanted = ref(0)

    let ratio = () => drawRatio(~display=devicePixelRatio, ~cap=cap.contents)

    // ---- The overlay's backing store ----
    // The standard hi-dpi setup, and both halves matter: the store is sized in
    // device pixels, and the context is scaled so every `blit` below is written in
    // CSS pixels. Assigning the store **clears it** and resets the transform, so
    // the scale has to be reapplied here, after the sizing, every time.
    let sizeStore = () => {
      let box = boundingRect(overlayEl)
      let scale = ratio()
      overlay->Canvas.setPixelWidth(storePixels(~css=box.width, ~ratio=scale))
      overlay->Canvas.setPixelHeight(storePixels(~css=box.height, ~ratio=scale))
      Canvas.context2d(overlay)->Option.forEach(ctx => ctx->Canvas.scale(scale, scale))
    }

    // Stamp a sprite at a CSS-pixel box, top-left. Nothing is cleared, ever —
    // that is the whole point of the scene.
    let stamp = (sprite, ~x, ~y) =>
      Canvas.context2d(overlay)->Option.forEach(ctx => CardRaster.blit(ctx, sprite, ~x, ~y))

    // ---- The status line, and the controls it keeps honest ----
    let capButtons = caps->Array.map(value => {
      let button = el("button", "trail-toggle")
      button->WebDom.setAttribute("type", "button")
      button->WebDom.setTextContent(`${Float.toString(value)}×`)
      toolbar->WebDom.appendChild(button)->ignore
      (value, button)
    })

    let handOffButton = el("button", "trail-action")
    handOffButton->WebDom.setAttribute("type", "button")
    handOffButton->WebDom.setTextContent("Hand off a card")
    toolbar->WebDom.appendChild(handOffButton)->ignore

    let wipeButton = el("button", "trail-action")
    wipeButton->WebDom.setAttribute("type", "button")
    wipeButton->WebDom.setTextContent("Re-assign canvas.width")
    toolbar->WebDom.appendChild(wipeButton)->ignore

    // Everything the chrome says about the current state, in one place: which cap
    // is on, whether a hand-off is possible at all, and the status line — which
    // reports the store's ratio and the sprites' **side by side**, deliberately,
    // because that is the one comparison this scene exists to make. They agree,
    // or every blit is a resample and nothing says so.
    let refresh = () => {
      capButtons->Array.forEach(((value, button)) =>
        button->WebDom.setAttribute(
          "class",
          value == cap.contents ? "trail-toggle trail-toggle--on" : "trail-toggle",
        )
      )
      scene->WebDom.setAttribute("data-cap", Float.toString(cap.contents))
      scene->WebDom.setAttribute("data-ratio", showRatio(ratio()))
      // A hand-off with no sprite to stamp would delete a card and draw nothing,
      // which is the one way this control can lose information. So it waits.
      let canHandOff = carried.contents->Option.isSome && Array.length(standing.contents) > 0
      if canHandOff {
        handOffButton->WebDom.removeAttribute("disabled")
      } else {
        handOffButton->WebDom.setAttribute("disabled", "")
      }
      switch (error.contents, cache.contents) {
      | (Some(message), _) =>
        scene->WebDom.removeAttribute("data-trail")
        status->WebDom.setTextContent(`couldn't build sprites — ${message}`)
      | (None, None) =>
        scene->WebDom.removeAttribute("data-trail")
        status->WebDom.setTextContent("rasterizing 52 cards…")
      | (None, Some(built)) =>
        let box = boundingRect(overlayEl)
        let whole = v => Math.round(v)->Float.toInt->Int.toString
        scene->WebDom.setAttribute("data-trail", "ready")
        status->WebDom.setTextContent(
          `display ${showRatio(devicePixelRatio)}× · cap ${Float.toString(cap.contents)}× · ` ++
          `overlay ${whole(box.width)}×${whole(box.height)} css, ` ++
          `${Int.toString(Canvas.pixelWidth(overlay))}×${Int.toString(
              Canvas.pixelHeight(overlay),
            )} store @${showRatio(ratio())}× · ` ++
          `sprites @${showRatio(built.pixelRatio)}× (${Math.round(
              built.elapsedMs,
            )->Float.toString}ms)`,
        )
      }
    }

    // ---- Building the sprites ----
    // At the *same* ratio the store is sized at, which is the point: one number,
    // two consumers. A cap change rebuilds rather than rescaling the bitmaps it
    // has, because rescaling is exactly the thing the cap exists to avoid.
    let build = () => {
      wanted := wanted.contents + 1
      let mine = wanted.contents
      let stillWanted = () => mine == wanted.contents
      cache := None
      error := None
      refresh()
      CardRaster.build(~cssWidth=cardWidth, ~pixelRatio=ratio(), Deck.allCards)
      ->Promise.thenResolve(built =>
        if stillWanted() {
          cache := Some(built)
          carried := CardRaster.get(built, carriedCard)
          refresh()
        }
      )
      ->Promise.catch(e => {
        if stillWanted() {
          error :=
            Some(
              switch e->JsExn.fromException {
              | Some(exn) => exn->JsExn.message->Option.getOr("unknown error")
              | None => "unknown error"
              },
            )
          refresh()
        }
        Promise.resolve()
      })
      ->ignore
    }

    // ---- The controls ----
    capButtons->Array.forEach(((value, button)) =>
      button->WebDom.addEventListener("click", () =>
        if value != cap.contents {
          cap := value
          // Both ends of the blit move together, and the trail goes with them:
          // re-sizing the store clears it. Nothing here tries to preserve the
          // drawing across a ratio change — see the header.
          sizeStore()
          build()
        }
      )
    )

    // The hand-off, which is the mechanic the integration needs: stamp *then*
    // remove, so there is no frame in which the card is nowhere.
    let handOff = () => {
      switch (cache.contents, standing.contents->Array.at(-1)) {
      | (Some(built), Some((card, node))) =>
        switch CardRaster.get(built, card) {
        | Some(sprite) =>
          let box = boundingRect(overlayEl)
          let seat = boundingRect(node)
          stamp(sprite, ~x=seat.left -. box.left, ~y=seat.top -. box.top)
          node->WebDom.remove
          standing := standing.contents->Array.slice(~start=0, ~end=-1)
          // …and the pointer picks it up, so the card the board just lost is
          // visibly the one now drawing.
          carried := Some(sprite)
          refresh()
        | None => ()
        }
      | _ => ()
      }
    }
    handOffButton->WebDom.addEventListener("click", handOff)

    // Re-assigning the store — even to the size it already is — clears every
    // pixel. Deliberate, and on a button, because it is the constraint the
    // integration inherits.
    wipeButton->WebDom.addEventListener("click", () => {
      sizeStore()
      refresh()
    })

    // ---- The trail ----
    // On the stage, not the canvas: the overlay is `pointer-events: none`, which
    // is assumption (1) — a canvas over the board must not swallow the drags that
    // reach the cards underneath.
    let draw = ev =>
      switch carried.contents {
      | Some(sprite) =>
        let box = boundingRect(overlayEl)
        stamp(
          sprite,
          ~x=clientX(ev) -. box.left -. sprite.cssWidth /. 2.,
          ~y=clientY(ev) -. box.top -. sprite.cssHeight /. 2.,
        )
      | None => ()
      }
    stage->onPointer("pointerdown", draw)
    stage->onPointer("pointermove", draw)

    // A resize is the unasked-for version of the wipe button: the store has to
    // follow the element's CSS size, and following it costs the drawing. The
    // integration's answer is to end the cascade instead.
    let onResize = () => {
      sizeStore()
      refresh()
    }
    WebDom.addWindowListener("resize", onResize)

    // Size on the next frame, once the scene is in the document and has a rect
    // (see the `requestAnimationFrame` binding). The build is async and lands
    // well after layout, but the store mustn't wait on it — a pointer moving
    // before the sprites arrive has to find a correctly-sized surface.
    requestAnimationFrame(() => {
      sizeStore()
      refresh()
    })->ignore
    build()

    // ---- Teardown ----
    // The container's `clear` drops the stage and the canvas with it; what it
    // can't reach is the `window` listener, and an in-flight build that would
    // otherwise land in a dismantled scene. No request holds 0.
    () => {
      wanted := 0
      WebDom.removeWindowListener("resize", onResize)
    }
  },
}
