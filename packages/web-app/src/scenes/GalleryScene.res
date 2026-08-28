// The card gallery scene: every card in `Deck.allCards`, run through the
// `CardArt` generator and laid out in a responsive CSS grid. This is the first
// end-to-end exercise of the card generator (#36) — deliberately rudimentary,
// the point is to see all 52 cards on screen at once.
//
// The grid never changes, so this is a `Scene.static` rather than an Elm loop
// (#338) — see `Scene.static` for when that's the right shape.

// This component's stylesheet, in the `scenes` layer (see src/styles/index.css).
%%raw(`import "./GalleryScene.css"`)

let view =
  <div className="card-gallery">
    {Deck.allCards->Array.map(card => CardArt.svg(card))->Html.array}
  </div>

let make = (): Scene.t => Scene.static(~id="gallery", ~label="Gallery", view)
