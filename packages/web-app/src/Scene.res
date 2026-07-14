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

type t = {
  id: string,
  label: string,
  mount: WebDom.element => (unit => unit),
}
