// The card gallery scene: every card in `Deck.allCards`, run through the
// `CardArt` generator and laid out in a responsive CSS grid. This is the first
// end-to-end exercise of the card generator (#36) — deliberately rudimentary,
// the point is to see all 52 cards on screen at once.
//
// The grid is static, so there's no real Elm state here — but rendering typed
// vnodes still goes through `Html.mount`, so a trivial unit-state loop hosts the
// grid the same way SvgScene hosts its card. The switcher clears the container
// when another scene is picked, so there's no extra teardown.

let view = (_model, _dispatch) =>
  <div className="card-gallery">
    {Deck.allCards->Array.map(card => CardArt.svg(card))->Html.array}
  </div>

let make = (): Scene.t => {
  id: "gallery",
  label: "Gallery",
  mount: container => {
    Html.mount(
      ~root=container,
      ~init=(),
      ~update=(_msg, model) => (model, Html.noEffect),
      ~view,
    )->ignore
    () => ()
  },
}
