// The drag-and-drop tech demo (#21): a few cards you can drag freely with a
// pointer, and a row of drop zones they snap into when released over one. It's a
// throwaway spike to learn pointer-based dragging in isolation — no game logic,
// no card model beyond the local `Deck` the gallery already uses.
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

// getBoundingClientRect gives viewport coordinates; that's what hit-testing and
// the snap maths use, converting to playfield-local left/top only at the end.
type domRect = {left: float, top: float, width: float, height: float}
@send external boundingRect: WebDom.element => domRect = "getBoundingClientRect"

// A card is positioned by writing `style.left/top`; these are the only style
// bindings the drag loop needs.
type style
@get external style: WebDom.element => style = "style"
@set external setLeft: (style, string) => unit = "left"
@set external setTop: (style, string) => unit = "top"

// Toggling the drag/hover marker classes goes through classList rather than
// rewriting the whole `class` attribute each move.
type tokenList
@get external classList: WebDom.element => tokenList = "classList"
@send external addClass: (tokenList, string) => unit = "add"
@send external removeClass: (tokenList, string) => unit = "remove"

// The three cards on the table. Any `Deck.card` would do; a mixed handful just
// reads better than three of a kind.
let demoCards: array<Deck.card> = [
  {suit: Deck.Spades, rank: Deck.Ace},
  {suit: Deck.Hearts, rank: Deck.King},
  {suit: Deck.Diamonds, rank: Deck.Seven},
]

let make = (): Scene.t => {
  id: "drag",
  label: "Drag",
  mount: container => {
    // The stage everything is positioned within; `position: relative` (in CSS)
    // makes it the origin for the cards' absolute left/top.
    let playfield = WebDom.createElement("div")
    playfield->WebDom.setAttribute("class", "drag-playfield")
    container->WebDom.appendChild(playfield)->ignore

    // A row of drop zones pinned to the bottom of the stage. They lay themselves
    // out with flexbox, so their live rects (read at drop time) reflect wherever
    // the browser actually placed them — no positions cached up front to go
    // stale on resize.
    let dropRow = WebDom.createElement("div")
    dropRow->WebDom.setAttribute("class", "drop-row")
    playfield->WebDom.appendChild(dropRow)->ignore

    let zones = [0, 1, 2]->Array.map(_ => {
      let zone = WebDom.createElement("div")
      zone->WebDom.setAttribute("class", "drop-zone")
      dropRow->WebDom.appendChild(zone)->ignore
      zone
    })

    // The zone whose rect contains point (px, py), if any — the shared primitive
    // for both the live hover highlight and the snap-on-drop decision.
    let zoneAt = (px, py) =>
      zones->Array.find(zone => {
        let r = boundingRect(zone)
        px >= r.left && px <= r.left +. r.width && py >= r.top && py <= r.top +. r.height
      })

    // Build one draggable card and wire its pointer loop. `initX`/`initY` are its
    // starting position in playfield-local pixels.
    let makeCard = (card: Deck.card, ~initX, ~initY) => {
      let wrapper = WebDom.createElement("div")
      wrapper->WebDom.setAttribute("class", "drag-card")
      wrapper->WebDom.appendChild(Html.create(CardArt.svg(card)))->ignore

      // The card's current position, kept here rather than parsed back out of the
      // style each move.
      let x = ref(initX)
      let y = ref(initY)
      let place = () => {
        let s = style(wrapper)
        s->setLeft(Float.toString(x.contents) ++ "px")
        s->setTop(Float.toString(y.contents) ++ "px")
      }
      // Position before insertion so the card appears in place instead of sliding
      // in from the corner (the CSS `transition` would otherwise animate 0,0 →
      // here on mount).
      place()
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
            ? classList(zone)->addClass("drop-zone--over")
            : classList(zone)->removeClass("drop-zone--over")
        })
      }

      let clearHover = () =>
        zones->Array.forEach(zone => classList(zone)->removeClass("drop-zone--over"))

      wrapper->onPointer("pointerdown", ev => {
        // Capture so the card keeps getting moves/up even if the pointer leaves
        // its bounds; raise it above its siblings for the duration.
        wrapper->setPointerCapture(pointerId(ev))
        grab := Some((clientX(ev), clientY(ev), x.contents, y.contents))
        classList(wrapper)->addClass("dragging")
      })

      wrapper->onPointer("pointermove", ev =>
        switch grab.contents {
        | Some((startPX, startPY, startX, startY)) =>
          x := startX +. (clientX(ev) -. startPX)
          y := startY +. (clientY(ev) -. startPY)
          place()
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
          // Snap the card's centre onto the zone it was released over, if any;
          // otherwise it just stays where it was dropped (free placement).
          let cr = boundingRect(wrapper)
          switch zoneAt(cr.left +. cr.width /. 2., cr.top +. cr.height /. 2.) {
          | Some(zone) =>
            let zr = boundingRect(zone)
            let pr = boundingRect(playfield)
            x := zr.left +. zr.width /. 2. -. cr.width /. 2. -. pr.left
            y := zr.top +. zr.height /. 2. -. cr.height /. 2. -. pr.top
            place()
          | None => ()
          }
          clearHover()
        | None => ()
        }

      wrapper->onPointer("pointerup", endDrag)
      // A cancelled pointer (e.g. the OS stealing the gesture) must tear the drag
      // down too, or the card would stay stuck to a pointer that's gone.
      wrapper->onPointer("pointercancel", endDrag)
    }

    demoCards->Array.forEachWithIndex((card, i) =>
      makeCard(card, ~initX=16. +. Int.toFloat(i) *. 92., ~initY=20.)
    )

    let caption = WebDom.createElement("p")
    caption->WebDom.setAttribute("class", "drag-caption")
    caption->WebDom.setTextContent("Drag the cards. Drop one on a slot to snap it in.")
    container->WebDom.appendChild(caption)->ignore

    // The switcher clears the container on scene change, dropping the playfield
    // and every listener with it — nothing extra to tear down.
    () => ()
  },
}
