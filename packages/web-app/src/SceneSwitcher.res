// The scene switcher: a list of tappable rows (surfaced in the menu, #109) that
// select which scene is mounted into a separate shared container.
// Selecting a scene tears the current one down, clears the container, and mounts
// the chosen one — exactly one scene is live at a time. This is the mount/teardown
// engine kept from the old `<select>` picker; only its control surface changed
// from a drop-down to menu rows.
//
// The rows aren't a flat list: the primary game (the launch `~default`, FreeCell)
// sits as a single row in the menu's "games" section, and the debug/demo scenes are
// buried inside a collapsible "scenes" disclosure (#135) that the menu tucks under
// its bottom "debug" section header (#185), so the menu leads with the game and
// keeps the demos out of the way.
//
// The app always *launches* into its `~default` scene (FreeCell — the game is
// home), or the `~forced` scene the URL names (`?scene=`); there is no longer any
// "resume the last scene on reload" behaviour, so nothing is persisted.
//
// `render` hands the row controls and the scene container back separately (see `t`)
// so the caller can place the rows (inside the menu) apart from the scene box. The
// disclosure itself is no longer among them: the debug/demo scenes leave here as
// *data* — a list of `{label, onSelect}` — and `<MenuDisclosure>` draws them (#336).
// This module used to build that `<details>`, its `<summary>` and its body by hand,
// beside a `DebugStates` that described the same tree in twelve lines of JSX.

// This component's stylesheet, in the `components` layer (see src/styles/index.css).
%%raw(`import "./SceneSwitcher.css"`)

// The row's class in its two states — plain, and the active scene's highlight.
let idleClass = "scene-menu__row"
let activeClass = "scene-menu__row scene-menu__row--active"

// The switcher's pieces, handed back separately so the caller can place them
// independently (#185): the `controls` hold the primary game row(s) and go in the
// menu's "games" section up top, while the debug/demo scenes go in the "debug"
// section pushed to the bottom, as one `<MenuDisclosure>` beside the debug-states
// group. The `scene` container is what the scene band wraps. `ensureActive` lets the
// chrome bring a scene forward by id (the debug "states" menu uses it to surface
// FreeCell before forcing a named position onto it).
type t = {
  controls: WebDom.element, // the primary game row(s) (placed in the menu's "games" section)
  // The debug/demo scenes as menu entries. A thunk rather than an array, because
  // which entry is `selected` is whichever scene is mounted *at the moment the menu
  // renders* — the chrome calls this while building the Debug screen's props, and a
  // scene change is always followed by a render (activation closes the menu).
  debugScenes: unit => array<MenuDisclosure.entry>,
  // Whether that group should start open: decided once, here, because only this
  // module knows whether the scene it opened on lives inside the group.
  debugScenesOpen: bool,
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
// and each row tap that changes scene) with the scene about to mount — the chrome
// uses it to reset any per-scene action it tracks (the top bar's New Game hook,
// which the mounting scene then re-publishes if it's re-dealable) and to close the
// menu. `~onReselect` is its counterpart for the tap that *doesn't* switch scene —
// the current scene's own row — where nothing mounts and so no hook may be reset
// (the live board's New Game/Undo hooks must keep pointing at it); the chrome
// wires it to close the menu alone.
let render = (
  ~default: option<string>=?,
  ~forced: option<string>=?,
  ~onActivate: option<Scene.t => unit>=?,
  ~onReselect: option<unit => unit>=?,
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

  // Which scene is which is decided up front, because it decides what gets built:
  // the primary game is a real row in `nav`, every other scene is an entry in the
  // "scenes" disclosure the menu renders.
  //
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

  let isPrimary = (scene: Scene.t) => primaryId == Some(scene.id)

  // One row button per *primary* scene, remembered alongside its scene so the
  // active row can be highlighted and a tap can look its scene back up. These are
  // the only real DOM the switcher still owns on the menu side; the debug scenes
  // are handed over as data below.
  let rows =
    scenes
    ->Array.filter(isPrimary)
    ->Array.map(scene => {
      let row = WebDom.createElement("button")
      row->WebDom.setAttribute("type", "button")
      row->WebDom.setAttribute("class", idleClass)
      row->WebDom.setTextContent(scene.label)
      nav->WebDom.appendChild(row)->ignore
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

  // Selecting a scene activates it — unless that scene is the one already showing,
  // which is the same "don't re-mount what's already up" rule `ensureActive` applies
  // below, and for the same reason: activation tears the live scene down and mounts
  // it afresh, so a tap on the current game's own row would throw the game in
  // progress away and re-open whatever that scene opens with. `onReselect` still
  // runs, so the chrome can close the menu — the row acknowledges the tap, it just
  // doesn't restart the game behind it.
  let select = (scene: Scene.t) =>
    if activeId.contents == Some(scene.id) {
      onReselect->Option.forEach(f => f())
    } else {
      activate(scene)
    }

  rows->Array.forEach(((scene, row)) => row->WebDom.addEventListener("click", () => select(scene)))

  // The "scenes" group's entries: every scene that isn't the primary game, as menu
  // data for `<MenuDisclosure>` to draw (#336). It lives under the menu's "debug"
  // section header (#185), which is why its label — the chrome's, not ours — is just
  // "scenes"; the sibling "states" group is the same component fed by `Main`.
  //
  // Recomputed per call so `selected` names the scene that is mounted now: this is
  // the highlight the row classes used to be rewritten for, moved from a mutation
  // into the value the menu is rendered from.
  let debugScenes = () =>
    scenes
    ->Array.filter(scene => !isPrimary(scene))
    ->Array.map((scene): MenuDisclosure.entry => {
      label: scene.label,
      onSelect: () => select(scene),
      selected: activeId.contents == Some(scene.id),
    })

  // Open the group from the start when the initial scene lives inside it (e.g. a
  // `?scene=gallery` deep link), so its highlighted row is visible rather than
  // hidden behind the collapsed disclosure.
  let debugScenesOpen = switch initial {
  | Some(scene) => !isPrimary(scene)
  | None => false
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

  {controls: nav, debugScenes, debugScenesOpen, scene: container, ensureActive}
}
