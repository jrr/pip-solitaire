// The scene switcher: which scene is mounted into a shared container, and the list
// of them the menu offers as tappable rows. Selecting a scene tears the
// current one down, clears the container, and mounts the chosen one — exactly one
// scene is live at a time. Mount and teardown is *all* this module is — the menu
// draws the rows themselves.
//
// The rows aren't a flat list: the primary game (the launch `~default`, FreeCell)
// sits as a single row in the menu's "games" section, and the rest are buried inside
// collapsible disclosures that the menu tucks under its bottom "debug" section
// header, so the menu leads with the game and keeps the demos out of the way.
//
// There are two of those disclosures, not one, and which a scene goes in is the
// scene's own `Scene.kind` — the non-primary `Game` scenes have a "games" group
// of their own, and "scenes" holds the `Demo`s. **Group on `kind`, never on "is this
// the launch default?"**: that reads as games-vs-demos only while there is exactly one
// game, and a second game would land under "scenes" between Gallery and Motion, filed
// as a render demo. With today's single game the games group is empty and the menu
// doesn't place it.
//
// The app always *launches* into its `~default` scene (FreeCell — the game is home),
// or the `~forced` scene the URL names (`?game=` or `?scene=`, resolved to one id by
// `Main`). A reload doesn't resume the last scene; nothing here is persisted.
//
// `render` hands the menu's scene lists and the scene container back separately (see
// `t`) so the caller can place the rows (inside the menu) apart from the scene box.
// **It builds no menu DOM at all**: the scenes leave as *data* — a list
// of `{label, onSelect}` for `<MenuDisclosure>` to draw — and which one is mounted is a
// *value* this module reports (`active`, and each entry's `selected`) for the menu to
// re-render from. Keep it that way: a highlight written onto a row by hand is the job
// the diff exists to do, done by a module that would have to reach outside it.

// A scene the menu can offer, as data: the label a row shows and the id `select`
// takes. Not `MenuRow.entry`, deliberately — the chrome pairs these with the active
// id to decide the highlight and closes over `select` itself, so what crosses this
// boundary is the scene, not a row already decided.
type choice = {id: string, label: string}

// The switcher's pieces, handed back separately so the caller can place them
// independently: the primary game row(s) go in the menu's "games" section up
// top, while the remaining scenes go in the "debug" section pushed to the bottom, as
// two `<MenuDisclosure>`s beside the debug-states group. The `scene` container is the
// one real node here, and the only thing that has to be one — a scene mounts a foreign
// subtree into it, which is what `Html.node` is for. `ensureActive` lets the chrome
// bring a scene forward by id (the debug "states" menu uses it to surface FreeCell
// before forcing a named position onto it).
type t = {
  // The scenes the menu names at top level — as data, for the chrome to render as
  // `<MenuRow>`s. Fixed for the life of the app (the scene list is), so an array
  // rather than the thunk `debugScenes` needs: what *changes* is which one is
  // current, and that is `active` below.
  primaryScenes: array<choice>,
  // The scene mounted at the moment `render` returned — the caller's *seed*, not a
  // live reading. It exists because the initial activation happens in here, during
  // module init, before the chrome's `dispatch` does: `Main` reads this into its
  // model and every later change arrives through `~onActivate`. (`Main` solves the
  // same ordering problem twice more, for values that can only come from a callback,
  // with the `initialCanUndo`/`initialDealSeed` refs; this one the switcher knows
  // itself and can simply hand over.) `None` only when there are no scenes at all.
  active: option<string>,
  // Show the scene with this id — what a games row's tap runs. Same rule as
  // `ensureActive`, and see `select` below for why tapping the current one must not
  // re-mount it. An unknown id does nothing.
  select: string => unit,
  // The `Game` scenes that aren't the primary one, as menu entries for a "games"
  // disclosure of their own. Empty while FreeCell is the only game, and an
  // empty group is one the menu simply doesn't place — which is why this lands as a
  // no-op today.
  gameScenes: unit => array<MenuDisclosure.entry>,
  // Whether that group should start open, on the same rule as `debugScenesOpen`.
  gameScenesOpen: bool,
  // The demo scenes as menu entries. A thunk rather than an array, because which
  // entry is `selected` is whichever scene is mounted *at the moment the menu
  // renders* — the chrome calls this while building the Debug screen's props, and a
  // scene change is always followed by a render (activation closes the menu).
  debugScenes: unit => array<MenuDisclosure.entry>,
  // Whether that group should start open: decided once, here, because only this
  // module knows which group — if either — holds the scene it opened on.
  debugScenesOpen: bool,
  scene: WebDom.element, // the shared container hosting the active scene
  ensureActive: string => unit, // mount the scene with this id, unless it's already current
}

// Build the switcher and return its pieces. When `scenes` is empty the
// container simply stays empty. Otherwise the initial scene is the first of these
// that names a real scene: the `~forced` id (what the URL asked for, so a link always
// lands where it says), then the launch `~default` (FreeCell), then the first scene.
//
// `~onActivate` is called at the *start* of every activation (the initial mount
// and each row tap that changes scene) with the scene about to mount — the chrome
// uses it to reset any per-scene action it tracks (the top bar's New Game hook,
// which the mounting scene then re-publishes if it's re-dealable), to record which
// scene is now current, and to close the menu. `~onReselect` is its counterpart for
// the tap that *doesn't* switch scene — the current scene's own row — where nothing
// mounts and so no hook may be reset (the live board's New Game/Undo hooks must keep
// pointing at it); the chrome wires it to close the menu alone.
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

  // Which scene is which is decided up front, because it decides which of the three
  // lists below a scene is handed over in: the primary game goes to the menu's
  // "games" section, the other games to the "games" disclosure under Debug, and the
  // demos to the "scenes" one beside it.
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
  // the game is home) if it names a scene, else the first scene. Every other
  // scene goes into one of the two Debug groups below, by kind.
  let primaryId =
    default->Option.flatMap(byId)->Option.orElse(scenes[0])->Option.map(scene => scene.id)

  let isPrimary = (scene: Scene.t) => primaryId == Some(scene.id)

  // Which of the three groups a scene belongs to. The primary keeps its top-level row
  // and appears in neither disclosure — including when the launch `~default` names a
  // demo, where surfacing it up top *and* in the demos group would list it twice.
  // Everything else falls to the group its own `Scene.kind` names.
  let group = (scene: Scene.t) =>
    if isPrimary(scene) {
      #primary
    } else {
      switch scene.kind {
      | Game => #games
      | Demo => #demos
      }
    }

  // The scenes the menu names at top level, as data. Nothing is built for them here:
  // the chrome draws each as a `<MenuRow>` and the highlight follows from the active
  // id, so there is no row to walk and no class to rewrite.
  let primaryScenes =
    scenes
    ->Array.filter(isPrimary)
    ->Array.map((scene): choice => {id: scene.id, label: scene.label})

  // The id of the scene currently mounted, so `ensureActive` can skip a redundant
  // re-mount when the wanted scene is already showing.
  let activeId = ref(None)

  let activate = (scene: Scene.t) => {
    // The chrome hears which scene is coming *before* it mounts, which is also how it
    // learns to move the menu's highlight — one report for both, since a scene change
    // is exactly the thing both are about.
    onActivate->Option.forEach(f => f(scene))
    teardown.contents()
    WebDom.clear(container)
    teardown := scene.mount(container)
    activeId := Some(scene.id)
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

  // A disclosure group's entries, as menu data for `<MenuDisclosure>` to draw.
  // Both groups live under the menu's "debug" section header, which is why
  // their labels — the chrome's, not ours — are just "games" and "scenes"; the
  // sibling "states" group is the same component fed by `Main`.
  //
  // Recomputed per call so `selected` names the scene that is mounted now. The highlight
  // rides in the data the menu is rendered from, so it moves through the diff like every
  // other row's state rather than by rewriting a mounted row's classes in place.
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

  // Open the group the initial scene is in, from the start (e.g. a `?scene=gallery`
  // deep link), so its highlighted row is visible rather than hidden behind the
  // collapsed disclosure. A scene that got the top-level row opens neither.
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

  // Bring the scene with `id` forward — a no-op when it's already current, so a
  // caller can surface a scene without re-dealing one that's already showing. An
  // unknown id does nothing.
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
