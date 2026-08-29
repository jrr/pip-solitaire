// A "scene": a named, self-contained demo mounted into one shared container.
// The switcher (SceneSwitcher) keeps exactly one scene mounted at a time —
// selecting another tears the current one down and mounts the next. This is the
// scaffolding the throwaway demos (drag-and-drop #21, animation #22, a card
// gallery, …) live in without each one fighting over a single hard-coded slot.
//
// `mount` populates the given container and returns a teardown thunk for any
// cleanup beyond removing the DOM nodes themselves — the switcher clears the
// container after tearing a scene down, so a scene whose nodes carry no extra
// resources can just return `() => ()`.

// What a scene *is*, as opposed to where it happens to sit in the menu (#352). A scene
// says which it is and the switcher groups on that, so a second game is filed as a game
// rather than as a render demo.
type kind =
  | Game // a playable table (`TableScene`, one per `Game.all` entry)
  | Demo // a debug/render demo (Gallery, Raster, Motion)

type t = {
  id: string,
  label: string,
  kind: kind,
  mount: WebDom.element => unit => unit,
}

// A scene that is just a view: no model, no messages, nothing to tear down.
// `GalleryScene` is the one — a grid of all 52 cards that never changes — and
// spelling that as an `Html.mount` loop meant a unit model, an `update` that
// returns its argument, and a teardown that does nothing. Reach for `static`
// when all three of those would be placeholders; keep the full `Html.mount`
// form when any of them is real (`MotionScene` and `RasterScene` hold models,
// `TableScene` has flights to cancel on the way out).
//
// This is still a *mount*, not an `Html.create`: the container stays live and
// Preact keeps diffing into it, so the hook constraint documented at
// `Html.create` does not apply here, and a view that later grows state can move
// to the full form without anything else changing. Teardown is `() => ()`
// because the switcher clears the container itself when another scene is
// picked.
let static = (~id, ~label, ~kind, view: Html.vnode): t => {
  id,
  label,
  kind,
  mount: container => {
    Html.renderInto(view, container)
    () => ()
  },
}
