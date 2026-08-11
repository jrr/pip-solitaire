// The `raster` scene: all 52 cards, drawn one of three ways, with the sheet
// staying put as you switch between them.
//
// This is step one of the victory animation (#225). The animation wants to fling
// hundreds of card images around at 60fps, which means pre-rasterized sprites
// rather than 52 live SVG text subtrees — and rasterizing a text-heavy SVG is
// the part that doesn't work by default (see `CardRaster`'s header for why).
// So before any motion gets written, this scene answers the only question that
// matters: does a rasterized card still *look like* a card?
//
// Both strategies are built and switchable here rather than one being picked on
// paper, because "indistinguishable at card size" is a thing you settle by
// looking. The renderings are:
//
//   1  Live SVG             the `CardArt.svg` the app itself draws — the thing
//                           the other two are trying to be
//   2  SVG + embedded font  `CardRaster`'s default sprite
//   3  Canvas 2D            `CardRaster`'s second sprite
//
// **One at a time, in the same grid cells, on keys 1/2/3.** This was originally
// a side-by-side sheet — each card's live SVG touching its bitmap — and that is
// the weaker instrument. Two cards a card-width apart are compared by moving
// your eye, which is exactly the comparison the eye is worst at; the difference
// that started all this (the middle pip 4.5 design units high, see
// `CardArt.centerGlyphBaseline`) reads as a *jump* when you flip renderings in
// place and as "hmm, about the same" when you look left and right. Nothing moves
// between renderings but the pixels under test, so anything that shifts is real.
//
// The choice is mirrored into `?raster=` (see AppUrl) so a link — and the
// screenshot report — can open any of the three. `Svg` is the one that won (the
// numbers, and why, are in `CardRaster`'s header), so it's the default the plain
// `?scene=raster` link and the report land on.
//
// The sprite build is async (`img.decode()` is), so a rasterizing choice mounts
// empty, shows a status line, and fills in when the cache resolves. The resolved
// cache is exactly what the later `trail` and `cascade` scenes will consume.
// `Live` builds nothing, so it's ready the moment it's chosen.

// The size the comparison is made at: a card as it appears in the game, not
// blown up. A difference that only shows at 4× isn't a difference that matters
// here. Published to the CSS as `--raster-card-w` so the live SVG and the sprite
// are laid out at exactly the same width from one number.
//
// 80 rather than a rounder 75-ish because the card's 5:7 ratio has to come out
// whole: 80 × 1.4 = 112 exactly. A width whose height lands fractional (72 →
// 100.8) makes the bitmap a rounded 101 rows that the browser then resamples
// down to 100.8 CSS px, and that resample — not the rasterization — is what the
// comparison would end up measuring.
let cardWidth = 80.

// What the sheet is showing. `Live` isn't a rasterizing strategy — it's the
// absence of one — which is why this lives here and not in `CardRaster`: that
// module is the sprite cache, and "don't rasterize" is not something it can
// build.
type rendering =
  | Live
  | Raster(CardRaster.strategy)

// The order is the whole keyboard mapping: key *n* picks the *n*th of these, and
// each button is labelled with its own index, so the two can't drift apart.
let renderings = [Live, Raster(CardRaster.Svg), Raster(CardRaster.Canvas)]

let renderingLabel = rendering =>
  switch rendering {
  | Live => "Live SVG"
  | Raster(strategy) => CardRaster.strategyLabel(strategy)
  }

let renderingId = rendering =>
  switch rendering {
  | Live => "live"
  | Raster(strategy) => CardRaster.strategyId(strategy)
  }

// Parse the `?raster=` URL knob. Delegates the two strategy names to
// `CardRaster` so the ids stay stated once; anything unrecognised reads as
// `None` and leaves the scene's own default in place.
let renderingFromString = value =>
  switch value {
  | "live" => Some(Live)
  | _ => CardRaster.strategyFromString(value)->Option.map(strategy => Raster(strategy))
  }

type model = {
  rendering: rendering,
  cache: option<CardRaster.t>,
  // A failed build (a font that didn't fetch, an SVG the engine wouldn't decode)
  // is the interesting outcome here, so it's surfaced rather than swallowed.
  error: option<string>,
}

type msg =
  | Choose(rendering)
  | Built(CardRaster.t)
  | Failed(string)

// The status line: what's showing, and what it cost. The build time is half of
// "pick by looking" — a strategy can win on fidelity and lose badly on cost —
// and `Live` reports no time because it builds nothing.
let status = model =>
  switch (model.error, model.rendering, model.cache) {
  | (Some(message), _, _) => `couldn't build sprites — ${message}`
  | (None, Live, _) =>
    let width = Float.toString(cardWidth)
    `52 live CardArt SVGs · ${width}px · ` ++ `the card the app draws, and what the other two are measured against`
  | (None, Raster(strategy), None) =>
    `rasterizing 52 cards (${CardRaster.strategyLabel(strategy)})…`
  | (None, Raster(_), Some(cache)) =>
    let ms = Math.round(cache.elapsedMs)->Float.toString
    let dpr = (Math.round(cache.pixelRatio *. 100.) /. 100.)->Float.toString
    `52 cards via ${CardRaster.strategyLabel(cache.strategy)} in ${ms}ms · ` ++
    `${Float.toString(cache.cssWidth)}px @${dpr}× · every card is a bitmap`
  }

let view = (model, dispatch) => {
  // The button carries its own key number, so the mapping is on screen rather
  // than in a legend that can fall out of step with `renderings`.
  let toggle = (rendering, index) => {
    let current = model.rendering == rendering
    <button
      className={current ? "raster-toggle raster-toggle--on" : "raster-toggle"}
      attrs={[("type", "button")]}
      onClick={_ => dispatch(Choose(rendering))}
    >
      <span className="raster-toggle__key"> {Html.string(Int.toString(index + 1))} </span>
      {Html.string(renderingLabel(rendering))}
    </button>
  }

  // One card, one cell, whichever rendering is showing. The cell holds its
  // footprint while the (async) sprites decode, so flipping to a rasterizing
  // choice doesn't reflow the sheet under you and then reflow it back.
  let cell = card =>
    <div className="raster-cell">
      {switch model.rendering {
      | Live => CardArt.svg(card)
      | Raster(_) =>
        switch model.cache->Option.flatMap(cache => CardRaster.get(cache, card)) {
        | Some(sprite) => Html.node(CardRaster.element(sprite))
        | None => <div className="raster-cell__pending" />
        }
      }}
    </div>

  // `data-raster="ready"` is the screenshot report's (and the browser suite's)
  // signal that the sheet is showing what it was asked for — there's no other way
  // to know a decode that started off-frame has landed. `Live` has nothing to
  // decode, so it's ready as soon as it's rendered; without that arm every
  // consumer of this signal would hang on `?raster=live`.
  let settled = switch model.rendering {
  | Live => true
  | Raster(_) => model.cache->Option.isSome
  }
  let rootAttrs = Array.concat(
    [
      ("style", `--raster-card-w: ${Float.toString(cardWidth)}px`),
      ("data-rendering", renderingId(model.rendering)),
    ],
    settled ? [("data-raster", "ready")] : [],
  )

  <div className="raster-scene" attrs={rootAttrs}>
    <div className="raster-scene__toolbar">
      {renderings->Array.mapWithIndex(toggle)->Html.array}
    </div>
    <p className="raster-scene__status"> {Html.string(status(model))} </p>
    <div className="raster-grid"> {Deck.allCards->Array.map(cell)->Html.array} </div>
  </div>
}

// The keyboard shortcut reads the plain `KeyboardEvent` fields it needs.
// `WebDom.addWindowListener` is polymorphic over its payload, so the shape is
// declared here, where it's used.
type keyEvent
@get external eventKey: keyEvent => string = "key"
@get external metaKey: keyEvent => bool = "metaKey"
@get external ctrlKey: keyEvent => bool = "ctrlKey"
@get external altKey: keyEvent => bool = "altKey"

let make = (~rendering=Raster(CardRaster.Svg)): Scene.t => {
  id: "raster",
  label: "Raster",
  mount: container => {
    // A build takes a moment (52 decodes), and two things can happen inside that
    // moment: the scene can be torn down, and the rendering can be changed.
    // `wanted` is the number of the one build whose result is still wanted —
    // each request takes the next number, and unmount takes a number no request
    // can hold. A promise resolving under any other number is a build nobody is
    // waiting for any more, and dispatching it would be wrong twice over: into a
    // dismantled tree, or over the top of a newer build.
    //
    // The overwrite is the live hazard, because the strategies don't cost the
    // same. Choosing Canvas (~80ms) while the default Svg build (~270ms) is
    // still in flight resolves Canvas first and then lets Svg land on top of it
    // — leaving the grid full of Svg sprites under a Canvas toggle, with the
    // status line (which reads `cache.strategy`) disagreeing with the toolbar
    // (which reads `model.rendering`) in the same render.
    //
    // `Live` takes a number too, without building anything: it has to *cancel*
    // an in-flight build the same way, or flipping 2 → 1 would let the sprites
    // arrive underneath the live sheet.
    let wanted = ref(0)
    let request = ref(_ => ())

    let update = (msg, model) =>
      switch msg {
      | Choose(next) if next == model.rendering => (model, Html.noEffect)
      | Choose(next) => ({rendering: next, cache: None, error: None}, () => request.contents(next))
      | Built(cache) => ({...model, cache: Some(cache), error: None}, Html.noEffect)
      | Failed(message) => ({...model, cache: None, error: Some(message)}, Html.noEffect)
      }

    let dispatch = Html.mount(
      ~root=container,
      ~init={rendering, cache: None, error: None},
      ~update,
      ~view,
    )

    request :=
      (
        chosen => {
          wanted := wanted.contents + 1
          let mine = wanted.contents
          let stillWanted = () => mine == wanted.contents

          switch chosen {
          | Live => ()
          | Raster(strategy) =>
            CardRaster.build(~strategy, ~cssWidth=cardWidth, Deck.allCards)
            ->Promise.thenResolve(cache =>
              if stillWanted() {
                dispatch(Built(cache))
              }
            )
            ->Promise.catch(error => {
              if stillWanted() {
                let message = switch error->JsExn.fromException {
                | Some(e) => e->JsExn.message->Option.getOr("unknown error")
                | None => "unknown error"
                }
                dispatch(Failed(message))
              }
              Promise.resolve()
            })
            ->ignore
          }
        }
      )

    request.contents(rendering)

    // Keys 1..n pick the nth rendering — the point of the scene is flipping
    // between them fast enough to see a difference move, and reaching for a
    // button is slower than the afterimage lasts. Indexed off `renderings` so
    // the keys, the buttons' numbers and the order are one fact.
    //
    // Modified presses are left alone: ⌘1/^1 switch browser tabs, and a debug
    // scene has no business eating that.
    let onKey = event =>
      if !(event->metaKey) && !(event->ctrlKey) && !(event->altKey) {
        switch Int.fromString(event->eventKey) {
        | Some(n) => renderings->Array.get(n - 1)->Option.forEach(next => dispatch(Choose(next)))
        | None => ()
        }
      }
    WebDom.addWindowListener("keydown", onKey)

    () => {
      // No request holds 0, so unmount abandons every build in flight.
      wanted := 0
      // The listener is on `window`, which clearing the scene container can't
      // reach — so it has to come off by hand, with the same handler value.
      WebDom.removeWindowListener("keydown", onKey)
    }
  },
}
