// A collapsible group of menu rows: a summary you tap to reveal a list of labelled
// actions. The menu's bottom "debug" section is built out of two of them —
// the debug/demo **scenes** (`SceneSwitcher`) and the named starting **states**
// (`core`'s `Scenario`, wired up in `Main`). Both are the same
// `<details>/<summary>/<div>` tree with the same four class names, driven by a list
// of `{label, action}`: a third group is another call, not another implementation.
//
// The group is a native `<details>`, so the show/hide costs no JS and stays
// keyboard-accessible, and it opens collapsed unless a caller asks otherwise.
//
// Purely presentational: it's handed a `label` and an `onSelect` thunk per entry and
// knows nothing about scenes, `Scenario` or the switcher. What a tap *does* is the
// caller's business (`Main` wires a state row to surface FreeCell and force the
// position onto it; `SceneSwitcher` wires a scene row to mount that scene).
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).

// This component's stylesheet, in the `components` layer (see src/styles/index.css).
%%raw(`import "./MenuDisclosure.css"`)

// One row: its menu `label`, the action a tap runs, and whether it's the one
// currently in effect. Only the scene rows have a `selected` row — a scene is
// mounted, so one of them is always the one you're looking at; the state rows are
// jumps that leave nothing behind to highlight, and simply omit it.
//
// An alias: the record lives on `MenuRow`, where the row it describes is, because
// the *ungrouped* rows on the main screen want the very same one. The name stays
// here because a disclosure's callers say `entry` and there is no second meaning
// for it to collide with.
type entry = MenuRow.entry

type props = {
  // The disclosure's own label: "scenes", "states".
  summary: string,
  // With no entries the group is empty but harmless; the caller simply doesn't
  // place it. (`Main` always has some for both groups.)
  entries: array<entry>,
  // Start the group open. `SceneSwitcher` asks for this when the initial scene is
  // one of its own rows (a `?scene=gallery` deep link), so the highlighted row
  // isn't hidden behind a collapsed disclosure.
  open_?: bool,
}

let make = (props: props) => {
  // Absent rather than `open={false}` for the closed case, and that's the whole
  // trick that lets a reader's choice survive a re-render: Preact writes a prop
  // only when its value changes, so a group asked to open is opened once at mount
  // and the attribute is the browser's from then on. Passing a steady `false` would
  // read the same on mount but says the diff has an opinion, and one day it would.
  let open_ = props.open_->Option.getOr(false) ? Some(true) : None

  <details className="scene-menu__group" ?open_>
    <summary className="scene-menu__group-label"> {Html.string(props.summary)} </summary>
    <div className="scene-menu__group-body">
      {props.entries
      ->Array.map(entry =>
        // The same `<MenuRow>` the rest of the menu is built from — `selected`
        // goes straight through, and brings `aria-current` with it.
        <MenuRow
          label={entry.label} selected=?{entry.selected} onClick={entry.onSelect} key={entry.label}
        />
      )
      ->Html.array}
    </div>
  </details>
}
