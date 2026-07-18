// The scene switcher: a list of tappable rows (surfaced in the menu, #109) that
// select which scene is mounted into a separate shared container.
// Selecting a scene tears the current one down, clears the container, and mounts
// the chosen one — exactly one scene is live at a time. This is the mount/teardown
// engine kept from the old `<select>` picker; only its control surface changed
// from a drop-down to menu rows.
//
// The app always *launches* into its `~default` scene (FreeCell — the game is
// home), or the `~forced` scene the URL names (`?scene=`); there is no longer any
// "resume the last scene on reload" behaviour, so nothing is persisted.
//
// `render` hands the row controls and the scene container back as two separate
// nodes (see `t`) so the caller can place the rows (inside the menu) apart from
// the scene box.

// The row's class in its two states — plain, and the active scene's highlight.
let idleClass = "scene-menu__row"
let activeClass = "scene-menu__row scene-menu__row--active"

// The switcher's two pieces, handed back separately so the caller can place them
// independently — the `controls` rows live inside the menu overlay, while the
// `scene` container is what the scene band wraps.
type t = {
  controls: WebDom.element, // the tappable scene rows (placed in the menu)
  scene: WebDom.element, // the shared container hosting the active scene
}

// Build the switcher UI and return its two pieces. When `scenes` is empty the
// container simply stays empty. Otherwise the initial scene is the first of these
// that names a real scene: the `~forced` id (from the URL's `?scene=`, so a link
// always lands where it says), then the launch `~default` (FreeCell), then the
// first scene.
//
// `~onActivate` is called at the *start* of every activation (the initial mount
// and each row tap) with the scene about to mount — the chrome uses it to reset
// any per-scene action it tracks (the top bar's New Game hook, which the mounting
// scene then re-publishes if it's re-dealable) and to close the menu.
let render = (
  ~default: option<string>=?,
  ~forced: option<string>=?,
  ~onActivate: option<Scene.t => unit>=?,
  scenes: array<Scene.t>,
): t => {
  // A plain container for the rows; the menu wraps it in a labelled <nav>, so
  // this stays a simple <div> rather than nesting one landmark inside another.
  let nav = WebDom.createElement("div")
  nav->WebDom.setAttribute("id", "scene-menu")

  let container = WebDom.createElement("section")
  container->WebDom.setAttribute("id", "scene-container")

  // Teardown for the currently mounted scene; a noop until one is mounted.
  let teardown = ref(() => ())

  // One row button per scene, remembered alongside its scene so the active row
  // can be highlighted and a tap can look its scene back up.
  let rows = scenes->Array.map(scene => {
    let row = WebDom.createElement("button")
    row->WebDom.setAttribute("type", "button")
    row->WebDom.setAttribute("class", idleClass)
    row->WebDom.setTextContent(scene.label)
    nav->WebDom.appendChild(row)->ignore
    (scene, row)
  })

  let activate = (scene: Scene.t) => {
    onActivate->Option.forEach(f => f(scene))
    teardown.contents()
    WebDom.clear(container)
    teardown := scene.mount(container)
    // Mark the active row so the menu shows which scene is current.
    rows->Array.forEach(((s, row)) =>
      row->WebDom.setAttribute("class", s.id == scene.id ? activeClass : idleClass)
    )
  }

  // Tapping a row activates its scene.
  rows->Array.forEach(((scene, row)) =>
    row->WebDom.addEventListener("click", () => activate(scene))
  )

  // Initial scene: the forced (URL) id if it names a scene, else the launch
  // default, else the first.
  let byId = id => scenes->Array.find(scene => scene.id == id)
  let initial =
    forced
    ->Option.flatMap(byId)
    ->Option.orElse(default->Option.flatMap(byId))
    ->Option.orElse(scenes[0])
  switch initial {
  | Some(scene) => activate(scene)
  | None => ()
  }

  {controls: nav, scene: container}
}
