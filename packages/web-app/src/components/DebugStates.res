// The debug "states" menu: a sibling to SceneSwitcher's "scenes" group (both sit
// under the menu's bottom "debug" section header, #185) that lists the named
// starting *positions* (`core`'s `Scenario`) rather than the demo scenes. Each row
// drops the board straight into that position — the same jump the URL's `?state=`
// makes, surfaced in the menu so a position is one tap away instead of a
// hand-edited query string.
//
// Purely presentational: it's handed a `label` and an `onSelect` thunk per state and
// builds the collapsible group, reusing the scene menu's group/row styling. The
// chrome (`Main`) wires each `onSelect` to surface FreeCell and force the state onto
// it; nothing about `Scenario`, `GameState` or the switcher leaks in here.
//
// **It used to build that markup by hand** — 47 lines of `createElement` /
// `setAttribute` / `appendChild` — and reach the menu as an opaque `Html.element`
// spliced in with `Html.node`. That was the shape the old hand-rolled runtime forced
// on a list: unkeyed children were diffed by position, so a list was cheaper to own
// outright than to describe. Preact diffs a list properly, so the markup is now just
// markup, and the menu takes `entries` — data the compiler can check — where it used
// to take a DOM node it could say nothing about.
//
// A native `<details>`, so the show/hide costs no JS and stays keyboard-accessible,
// and it opens collapsed. Nothing sets `open`, which is also what lets a reader's
// choice survive a re-render: the attribute is the browser's to write and the diff
// has no opinion to impose on it.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).

// One state row: its menu `label` and the action a tap runs.
type entry = {
  label: string,
  onSelect: unit => unit,
}

type props = {
  // With no entries the group is empty but harmless; the caller simply doesn't
  // place it. (`Main` always has some — `Scenario` ships a handful for FreeCell.)
  entries: array<entry>,
}

let make = ({entries}) =>
  <details className="scene-menu__group">
    <summary className="scene-menu__group-label"> {Html.string("states")} </summary>
    <div className="scene-menu__group-body">
      {entries
      ->Array.map(entry =>
        <button
          className="scene-menu__row"
          type_="button"
          onClick={_ => entry.onSelect()}
          key={entry.label}
        >
          {Html.string(entry.label)}
        </button>
      )
      ->Html.array}
    </div>
  </details>
