// The `raster` scene: every card in `Deck.allCards`, twice — the live
// `CardArt.svg` the app renders beside the `CardRaster` bitmap of it, at card
// size, touching, so any difference is a seam you can see rather than a claim.
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
// looking. The toggle is mirrored into `?raster=` (see AppUrl) so a link — and
// the screenshot report — can open either one. `Svg` is the one that won (the
// numbers, and why, are in `CardRaster`'s header), so it's the default the plain
// `?scene=raster` link and the report land on.
//
// The sprite build is async (`img.decode()` is), so the scene mounts empty,
// shows a status line, and fills in when the cache resolves. The resolved cache
// is exactly what the later `trail` and `cascade` scenes will consume.

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

type model = {
  strategy: CardRaster.strategy,
  cache: option<CardRaster.t>,
  // A failed build (a font that didn't fetch, an SVG the engine wouldn't decode)
  // is the interesting outcome here, so it's surfaced rather than swallowed.
  error: option<string>,
}

type msg =
  | Choose(CardRaster.strategy)
  | Built(CardRaster.t)
  | Failed(string)

let strategies = [CardRaster.Svg, CardRaster.Canvas]

// The status line: what's showing, and what it cost. The build time is half of
// "pick by looking" — a strategy can win on fidelity and lose badly on cost.
let status = model =>
  switch (model.error, model.cache) {
  | (Some(message), _) => `couldn't build sprites — ${message}`
  | (None, None) => `rasterizing 52 cards (${CardRaster.strategyLabel(model.strategy)})…`
  | (None, Some(cache)) =>
    let ms = Math.round(cache.elapsedMs)->Float.toString
    let dpr = (Math.round(cache.pixelRatio *. 100.) /. 100.)->Float.toString
    `52 cards via ${CardRaster.strategyLabel(cache.strategy)} in ${ms}ms · ` ++
    `${Float.toString(cache.cssWidth)}px @${dpr}× · left is live SVG, right is the bitmap`
  }

let view = (model, dispatch) => {
  let toggle = strategy => {
    let current = model.strategy == strategy
    <button
      className={current ? "raster-toggle raster-toggle--on" : "raster-toggle"}
      attrs={[("type", "button")]}
      onClick={_ => dispatch(Choose(strategy))}
    >
      {Html.string(CardRaster.strategyLabel(strategy))}
    </button>
  }

  // One card, twice. The sprite cell keeps its footprint before the bitmap
  // arrives so the grid doesn't reflow under the comparison as it fills in.
  let pair = card =>
    <div className="raster-pair">
      {CardArt.svg(card)}
      {switch model.cache->Option.flatMap(cache => CardRaster.get(cache, card)) {
      | Some(sprite) => Html.node(CardRaster.element(sprite))
      | None => <div className="raster-pair__pending" />
      }}
    </div>

  // `data-raster="ready"` is the screenshot report's (and the browser suite's)
  // signal that all 52 bitmaps are in — there's no other way to know a decode
  // that started off-frame has landed.
  let rootAttrs = Array.concat(
    [("style", `--raster-card-w: ${Float.toString(cardWidth)}px`)],
    model.cache->Option.isSome ? [("data-raster", "ready")] : [],
  )

  <div className="raster-scene" attrs={rootAttrs}>
    <div className="raster-scene__toolbar"> {strategies->Array.map(toggle)->Html.array} </div>
    <p className="raster-scene__status"> {Html.string(status(model))} </p>
    <div className="raster-grid"> {Deck.allCards->Array.map(pair)->Html.array} </div>
  </div>
}

let make = (~strategy=CardRaster.Svg): Scene.t => {
  id: "raster",
  label: "Raster",
  mount: container => {
    // The scene can be torn down mid-build (52 decodes take a moment, and the
    // switcher won't wait). `live` gates the resolution so a late promise can't
    // dispatch into a dismantled tree.
    let live = ref(true)
    let request = ref(_ => ())

    let update = (msg, model) =>
      switch msg {
      | Choose(next) if next == model.strategy => (model, Html.noEffect)
      | Choose(next) => ({strategy: next, cache: None, error: None}, () => request.contents(next))
      | Built(cache) => ({...model, cache: Some(cache), error: None}, Html.noEffect)
      | Failed(message) => ({...model, cache: None, error: Some(message)}, Html.noEffect)
      }

    let dispatch = Html.mount(
      ~root=container,
      ~init={strategy, cache: None, error: None},
      ~update,
      ~view,
    )

    request :=
      (
        wanted =>
          CardRaster.build(~strategy=wanted, ~cssWidth=cardWidth, Deck.allCards)
          ->Promise.thenResolve(cache =>
            if live.contents {
              dispatch(Built(cache))
            }
          )
          ->Promise.catch(error => {
            if live.contents {
              let message = switch error->JsExn.fromException {
              | Some(e) => e->JsExn.message->Option.getOr("unknown error")
              | None => "unknown error"
              }
              dispatch(Failed(message))
            }
            Promise.resolve()
          })
          ->ignore
      )

    request.contents(strategy)

    () => live := false
  },
}
