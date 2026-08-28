// The banded group the menu is built out of: a labelled block with an optional
// heading, holding rows.
//
// Every menu screen was writing this wrapper by hand — seven copies of
// `<div|nav className="menu-section" ariaLabel=…>` with an optional
// `<h2 className="menu-section__heading">` inside. The rules for those classes
// live in Menu.css and haven't moved; this component owns only the shape.
//
// **It is also the app's first component that takes children**, which is worth a
// word since nothing else here does. `children` is an ordinary field on the props
// record, filled by the JSX transform from whatever sits between the tags:
//
//   <MenuSection modifier="menu-section--bottom">  →  children = that one vnode
//     <button className="menu-button">…</button>
//   </MenuSection>
//
//   <MenuSection label="Debug" tag=Nav>   →  children = an array of vnodes,
//     <MenuToggleRow … />                     typed as one `Html.vnode` because
//     <MenuActionRow … />                     `Html.array` is `%identity` — the
//   </MenuSection>                            runtime takes an array wherever it
//                                             takes a node.
//
// The type is `option<Html.vnode>` (spelled `children?:`), so a section with no
// rows in it is legal and needs no `None` at the call site.
//
// Children being a *value* is what makes the tag choice below cheap: the body is
// built once and then placed into whichever element the section wants, since JSX
// needs a literal tag name and can't take one as a variable.

// `nav` where the rows are links onward (the games list, "More", the debug
// screen's rows), `div` where they're controls that act in place. Both draw the
// same; the difference is what a screen reader announces.
type tag = Div | Nav

type props = {
  // The section's accessible name (`aria-label`). Omitted on a group that is
  // purely a layout band, like the bottom-anchored one holding the Settings
  // button — an unnamed group is better than one named for its position.
  label?: string,
  // A visible `<h2>` at the top of the section. Only the main screen's groups
  // carry one; Settings and Debug are labelled but unheaded.
  heading?: string,
  tag?: tag,
  // An extra class alongside `menu-section`, for the two that vary:
  // `menu-section--bottom` (pushed to the foot of the screen) and `menu-refresh`.
  modifier?: string,
  children?: Html.vnode,
}

let make = (props: props) => {
  let className = switch props.modifier {
  | Some(modifier) => "menu-section " ++ modifier
  | None => "menu-section"
  }
  let body =
    <>
      {switch props.heading {
      | Some(heading) => <h2 className="menu-section__heading"> {Html.string(heading)} </h2>
      | None => Html.empty
      }}
      {props.children->Option.getOr(Html.empty)}
    </>

  switch props.tag->Option.getOr(Div) {
  // `ariaLabel=?` passes the option straight through: absent stays absent, which
  // is what an unnamed layout band wants.
  | Div => <div className ariaLabel=?{props.label}> {body} </div>
  | Nav => <nav className ariaLabel=?{props.label}> {body} </nav>
  }
}
