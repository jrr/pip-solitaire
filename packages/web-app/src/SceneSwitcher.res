// The scene switcher: a list of tappable rows (surfaced in the menu, #109) that
// select which scene is mounted into a separate shared container.
// Selecting a scene tears the current one down, clears the container, and mounts
// the chosen one — exactly one scene is live at a time. This is the mount/teardown
// engine kept from the old `<select>` picker; only its control surface changed
// from a drop-down to menu rows.
//
// The rows aren't a flat list: the primary game (the launch `~default`, FreeCell)
// sits as a single row at the top, and the debug/demo scenes are buried inside a
// collapsible "Debug scenes" disclosure below it (#135), so the menu leads with the
// game and keeps the demos out of the way.
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

// The switcher's pieces, handed back separately so the caller can place them
// independently — the `controls` rows live inside the menu overlay, while the
// `scene` container is what the scene band wraps. `ensureActive` lets the chrome
// bring a scene forward by id (the debug "states" menu uses it to surface FreeCell
// before forcing a named position onto it).
type t = {
  controls: WebDom.element, // the tappable scene rows (placed in the menu)
  scene: WebDom.element, // the shared container hosting the active scene
  ensureActive: string => unit, // mount the scene with this id, unless it's already current
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
  // can be highlighted and a tap can look its scene back up. The buttons are only
  // built here; where each is placed (the primary row up top, the rest under
  // Debug) is decided once the initial/primary scene is known, below.
  let rows = scenes->Array.map(scene => {
    let row = WebDom.createElement("button")
    row->WebDom.setAttribute("type", "button")
    row->WebDom.setAttribute("class", idleClass)
    row->WebDom.setTextContent(scene.label)
    (scene, row)
  })

  // The id of the scene currently mounted, so `ensureActive` can skip a redundant
  // re-mount when the wanted scene is already showing.
  let activeId = ref(None)

  let activate = (scene: Scene.t) => {
    onActivate->Option.forEach(f => f(scene))
    teardown.contents()
    WebDom.clear(container)
    teardown := scene.mount(container)
    activeId := Some(scene.id)
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

  // The one scene surfaced at the top of the menu: the launch default (FreeCell —
  // the game is home, #135) if it names a scene, else the first scene. Every other
  // scene is a debug/demo table and goes into the Debug group below.
  let primaryId =
    default->Option.flatMap(byId)->Option.orElse(scenes[0])->Option.map(scene => scene.id)

  // The "Debug scenes" group: a native <details> disclosure holding the debug/demo
  // rows, so the show/hide costs no JS and stays keyboard-accessible. Its body
  // collects the rows; the group itself is only spliced into the menu if any debug
  // scene exists. (A sibling "Debug states" group — the named starting positions —
  // is built separately by the chrome; see `DebugStates`.)
  let debugBody = WebDom.createElement("div")
  debugBody->WebDom.setAttribute("class", "scene-menu__group-body")

  let debugGroup = WebDom.createElement("details")
  debugGroup->WebDom.setAttribute("class", "scene-menu__group")
  let debugSummary = WebDom.createElement("summary")
  debugSummary->WebDom.setAttribute("class", "scene-menu__group-label")
  debugSummary->WebDom.setTextContent("Debug scenes")
  debugGroup->WebDom.appendChild(debugSummary)->ignore
  debugGroup->WebDom.appendChild(debugBody)->ignore

  // Place each row: the primary game as a plain row at the top of the menu, every
  // other scene inside the Debug group.
  let hasDebug = ref(false)
  rows->Array.forEach(((scene, row)) =>
    if primaryId == Some(scene.id) {
      nav->WebDom.appendChild(row)->ignore
    } else {
      hasDebug := true
      debugBody->WebDom.appendChild(row)->ignore
    }
  )

  // Only mount the Debug group when it has something to hold. Open it from the
  // start when the initial scene lives inside it (e.g. a `?scene=spinner` deep
  // link), so its highlighted row is visible rather than hidden behind the
  // collapsed disclosure.
  if hasDebug.contents {
    switch initial {
    | Some(scene) if primaryId != Some(scene.id) => debugGroup->WebDom.setAttribute("open", "")
    | _ => ()
    }
    nav->WebDom.appendChild(debugGroup)->ignore
  }

  switch initial {
  | Some(scene) => activate(scene)
  | None => ()
  }

  // Bring the scene with `id` forward — a no-op when it's already current, so a
  // caller can surface a scene without re-dealing one that's already showing. An
  // unknown id does nothing.
  let ensureActive = id =>
    if activeId.contents != Some(id) {
      byId(id)->Option.forEach(activate)
    }

  {controls: nav, scene: container, ensureActive}
}
