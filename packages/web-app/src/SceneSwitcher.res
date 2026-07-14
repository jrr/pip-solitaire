// The scene switcher: a picker control (button row, styled like `#flip-button`)
// *outside* the shared container that selects which scene is mounted. Selecting
// a scene tears the current one down, clears the container, and mounts the
// chosen one — exactly one scene is live at a time. The selection is persisted
// to localStorage so a reload returns to the same scene.

// localStorage can throw (private mode, storage disabled), so every access is
// wrapped below; these bindings stay thin.
@val @scope("localStorage") external getItem: string => Nullable.t<string> = "getItem"
@val @scope("localStorage") external setItem: (string, string) => unit = "setItem"

let storageKey = "sleight:active-scene"

let readPersisted = () =>
  try getItem(storageKey)->Nullable.toOption catch {
  | _ => None
  }

let persist = id =>
  try setItem(storageKey, id) catch {
  | _ => ()
  }

// Build the switcher UI and return its root <section>. When `scenes` is empty
// the container simply stays empty. Otherwise the persisted scene (if it still
// exists) mounts initially, falling back to the first scene.
let render = (scenes: array<Scene.t>): WebDom.element => {
  let root = WebDom.createElement("section")
  root->WebDom.setAttribute("id", "scene-switcher")

  let picker = WebDom.createElement("div")
  picker->WebDom.setAttribute("id", "scene-picker")
  root->WebDom.appendChild(picker)->ignore

  let container = WebDom.createElement("section")
  container->WebDom.setAttribute("id", "scene-container")
  root->WebDom.appendChild(container)->ignore

  // Teardown for the currently mounted scene; a noop until one is mounted.
  let teardown = ref(() => ())

  // One picker button per scene, paired with its scene so a click can activate
  // it and so `activate` can move the "pressed" marker across the row.
  let buttons = scenes->Array.map(scene => {
    let button = WebDom.createElement("button")
    button->WebDom.setAttribute("class", "scene-button")
    button->WebDom.setAttribute("type", "button")
    button->WebDom.setTextContent(scene.label)
    picker->WebDom.appendChild(button)->ignore
    (scene, button)
  })

  let activate = (scene: Scene.t) => {
    teardown.contents()
    WebDom.clear(container)
    teardown := scene.mount(container)
    persist(scene.id)
    buttons->Array.forEach(((s, button)) =>
      button->WebDom.setAttribute("aria-pressed", s.id == scene.id ? "true" : "false")
    )
  }

  buttons->Array.forEach(((scene, button)) =>
    button->WebDom.addEventListener("click", () => activate(scene))
  )

  // Initial scene: the persisted one if it's still present, else the first.
  let initial =
    readPersisted()
    ->Option.flatMap(id => buttons->Array.find(((scene, _)) => scene.id == id))
    ->Option.orElse(buttons[0])
  switch initial {
  | Some((scene, _)) => activate(scene)
  | None => ()
  }

  root
}
