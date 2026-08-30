// Which scene is mounted into a shared container, and the scenes the menu offers as
// rows. Exactly one scene is live at a time: selecting one tears the current down,
// clears the container and mounts the chosen. Mount and teardown is *all* this is.
//
// **It builds no menu DOM at all.** Scenes leave as *data* for `<MenuDisclosure>` to
// draw, and which is mounted leaves as a *value* (`active`, each entry's `selected`)
// for the menu to re-render from. Keep it that way: a highlight written onto a row by
// hand is the job the diff exists to do, done by a module that must reach outside it.
//
// The rows are three groups, not a flat list — the primary game up top, and two
// disclosures under the menu's "debug" header. **Group on `Scene.kind`, never on "is
// this the launch default?"**: that reads as games-vs-demos only while there is
// exactly one game, and a second game would land under "scenes" filed as a render demo.
//
// Nothing here is persisted: the app launches into `~default`, or into the `~forced`
// scene the URL named, and a reload does not resume the last one.

// A scene the menu can offer. Not `MenuRow.entry`, deliberately — the chrome pairs
// these with the active id to decide the highlight and closes over `select` itself, so
// what crosses this boundary is the scene, not a row already decided.
type choice = {id: string, label: string}

// Handed back in pieces so the caller can place the rows (inside the menu) apart from
// the scene box. `scene` is the one real node here and the only thing that has to be
// one, a scene mounting a foreign subtree into it.
type t = {
  primaryScenes: array<choice>,
  // The caller's *seed*, not a live reading: the initial activation happens in here
  // during module init, before the chrome's `dispatch` exists, so `Main` reads this
  // into its model and every later change arrives through `~onActivate`. `None` only
  // when there are no scenes at all.
  active: option<string>,
  select: string => unit,
  gameScenes: unit => array<MenuDisclosure.entry>,
  gameScenesOpen: bool,
  // Thunks rather than arrays, because which entry is `selected` is whichever scene is
  // mounted *at the moment the menu renders*. The chrome calls them while building the
  // Debug screen's props, and a scene change is always followed by a render.
  debugScenes: unit => array<MenuDisclosure.entry>,
  debugScenesOpen: bool,
  scene: WebDom.element,
  ensureActive: string => unit,
}

// The initial scene is the first of these that names a real one: the `~forced` id, so
// a link always lands where it says, then the launch `~default`, then the first scene.
//
// `~onActivate` fires at the *start* of every activation, with the scene about to
// mount, so the chrome can reset the per-scene actions it tracks — the top bar's New
// Game hook, which the mounting scene re-publishes if it's re-dealable. `~onReselect`
// is its counterpart for the tap that *doesn't* switch scene, where nothing mounts and
// so **no hook may be reset**: the live board's New Game and Undo must keep pointing
// at it.
let render = (
  ~default: option<string>=?,
  ~forced: option<string>=?,
  ~onActivate: option<Scene.t => unit>=?,
  ~onReselect: option<unit => unit>=?,
  scenes: array<Scene.t>,
): t => {
  let container = WebDom.createElement("section")
  container->WebDom.setAttribute("id", "scene-container")

  // Teardown for the currently mounted scene; a noop until one is mounted.
  let teardown = ref(() => ())

  let byId = id => scenes->Array.find(scene => scene.id == id)
  let initial =
    forced
    ->Option.flatMap(byId)
    ->Option.orElse(default->Option.flatMap(byId))
    ->Option.orElse(scenes[0])

  // The one scene surfaced at the top of the menu — the game is home.
  let primaryId =
    default->Option.flatMap(byId)->Option.orElse(scenes[0])->Option.map(scene => scene.id)

  let isPrimary = (scene: Scene.t) => primaryId == Some(scene.id)

  // The primary keeps its top-level row and appears in neither disclosure — including
  // when `~default` names a demo, where surfacing it up top *and* in the demos group
  // would list it twice.
  let group = (scene: Scene.t) =>
    if isPrimary(scene) {
      #primary
    } else {
      switch scene.kind {
      | Game => #games
      | Demo => #demos
      }
    }

  let primaryScenes =
    scenes
    ->Array.filter(isPrimary)
    ->Array.map((scene): choice => {id: scene.id, label: scene.label})

  let activeId = ref(None)

  let activate = (scene: Scene.t) => {
    // The chrome hears which scene is coming *before* it mounts, which is also how it
    // learns to move the menu's highlight.
    onActivate->Option.forEach(f => f(scene))
    teardown.contents()
    WebDom.clear(container)
    teardown := scene.mount(container)
    activeId := Some(scene.id)
  }

  // **Never re-mount what's already up** — the rule `ensureActive` applies too.
  // Activation tears the live scene down and mounts it afresh, so a tap on the current
  // game's own row would throw the game in progress away. `onReselect` still runs, so
  // the row acknowledges the tap without restarting the game behind it.
  let select = (scene: Scene.t) =>
    if activeId.contents == Some(scene.id) {
      onReselect->Option.forEach(f => f())
    } else {
      activate(scene)
    }

  // Recomputed per call, so `selected` names the scene mounted now: the highlight
  // rides in the data the menu renders from and moves through the diff like any other
  // row's state, rather than by rewriting a mounted row's classes in place.
  let entriesIn = which =>
    () =>
      scenes
      ->Array.filter(scene => group(scene) == which)
      ->Array.map((scene): MenuDisclosure.entry => {
        label: scene.label,
        onSelect: () => select(scene),
        selected: activeId.contents == Some(scene.id),
      })

  let gameScenes = entriesIn(#games)
  let debugScenes = entriesIn(#demos)

  // Open the group the initial scene is in, so a `?scene=gallery` deep link's
  // highlighted row is visible rather than hidden behind a collapsed disclosure. A
  // scene that got the top-level row opens neither.
  let openedIn = which =>
    switch initial {
    | Some(scene) => group(scene) == which
    | None => false
    }

  let gameScenesOpen = openedIn(#games)
  let debugScenesOpen = openedIn(#demos)

  switch initial {
  | Some(scene) => activate(scene)
  | None => ()
  }

  // Bring a scene forward by id, so the chrome can surface FreeCell before forcing a
  // named position onto it. A no-op when it's already current; an unknown id does
  // nothing.
  let ensureActive = id =>
    if activeId.contents != Some(id) {
      byId(id)->Option.forEach(activate)
    }

  {
    primaryScenes,
    active: activeId.contents,
    // By id, because that is what the chrome holds: the row it draws came from a
    // `choice`, and looking the scene back up here keeps `Scene.t` — mount function
    // and all — inside this module.
    select: id => byId(id)->Option.forEach(select),
    gameScenes,
    gameScenesOpen,
    debugScenes,
    debugScenesOpen,
    scene: container,
    ensureActive,
  }
}
