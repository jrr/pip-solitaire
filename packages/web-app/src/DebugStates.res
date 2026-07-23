// The debug "states" menu: a sibling to SceneSwitcher's "scenes" group (both sit
// under the menu's bottom "debug" section header, #185) that lists the named
// starting *positions* (`core`'s `Scenario`) rather than the demo scenes. Each row
// drops the board straight into that position — the same jump the URL's `?state=`
// makes, surfaced in the menu so a position is one tap away instead of a
// hand-edited query string.
//
// Purely presentational, like SceneSwitcher's row-building: it's handed a `label`
// and an `onSelect` thunk per state and builds the collapsible group, reusing the
// scene menu's group/row styling. The chrome (`Main`) wires each `onSelect` to
// surface FreeCell and force the state onto it; nothing about `Scenario`,
// `GameState` or the switcher leaks in here.

// One state row: its menu `label` and the action a tap runs.
type entry = {
  label: string,
  onSelect: unit => unit,
}

// Build the "Debug states" disclosure group from its entries, returning the real
// DOM node for the chrome to splice into the menu (with `Html.node`, like the scene
// rows). A native <details>, so show/hide costs no JS and stays keyboard-accessible,
// and it opens collapsed like the "scenes" group. With no entries the group is empty but
// harmless; the caller simply doesn't place it.
let render = (entries: array<entry>): WebDom.element => {
  let group = WebDom.createElement("details")
  group->WebDom.setAttribute("class", "scene-menu__group")

  let summary = WebDom.createElement("summary")
  summary->WebDom.setAttribute("class", "scene-menu__group-label")
  summary->WebDom.setTextContent("states")
  group->WebDom.appendChild(summary)->ignore

  let body = WebDom.createElement("div")
  body->WebDom.setAttribute("class", "scene-menu__group-body")
  entries->Array.forEach(entry => {
    let row = WebDom.createElement("button")
    row->WebDom.setAttribute("type", "button")
    row->WebDom.setAttribute("class", "scene-menu__row")
    row->WebDom.setTextContent(entry.label)
    row->WebDom.addEventListener("click", entry.onSelect)
    body->WebDom.appendChild(row)->ignore
  })
  group->WebDom.appendChild(body)->ignore

  group
}
