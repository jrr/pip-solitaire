// The header row at the top of every menu screen, lifted out of `Menu` into
// its own pure component: an optional **back** button on the left, the
// screen's title in the middle, and the ✕ that closes the whole menu on the right.
//
// The three screens differ only in what they put in those slots — "Pip" with no
// back button on the main menu, "Settings" going back to it, "Debug" going back
// one step to Settings — so they're one component with a `back` option rather than
// three headers that drift apart.
//
// **`onTitleTap` is attached to one screen only.** It's the hidden-options tap
// target (`HiddenOptions`): every ten taps on the *Settings* screen's title flip
// the settings that aren't ready to be found yet into or out of view. The
// identical `menu-title` renders "Pip" and "Debug" on the other two screens and
// must stay inert, which is why this is an option rather than a handler every
// caller supplies. Passing `None` genuinely clears it from a reused <h1>: the
// diff drops a handler that is no longer in the props, so switching screens
// unwires it, and `Main` *also* ignores any tap that arrives while `menuScreen`
// isn't `Settings`. Belt and braces, because a leak here would be invisible
// until someone found it.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).

// This component's stylesheet, in the `components` layer (see src/styles/index.css).
%%raw(`import "./MenuHeader.css"`)

// A back button: `label` names where it returns to (it's the accessible name — the
// visible text is always "‹ Back"), `onClick` goes there.
type back = {
  label: string,
  onClick: unit => unit,
}

type props = {
  title: string,
  back: option<back>,
  onTitleTap: option<unit => unit>,
  onClose: unit => unit,
}

let make = ({title, back, onTitleTap, onClose}) =>
  <div className="menu-panel__header">
    {switch back {
    | Some({label, onClick}) =>
      <button className="menu-back" onClick={_ => onClick()} type_="button" ariaLabel={label}>
        {Html.string("‹ Back")}
      </button>
    | None => Html.empty
    }}
    <h1 className="menu-title" onClick=?{onTitleTap->Option.map(tap => _ => tap())}>
      {Html.string(title)}
    </h1>
    <button className="menu-close" onClick={_ => onClose()} type_="button" ariaLabel="Close menu">
      {Html.string("✕")}
    </button>
  </div>
