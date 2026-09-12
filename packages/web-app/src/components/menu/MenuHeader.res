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

%%raw(`import "./MenuHeader.css"`)

// A back button: `label` names where it returns to (it's the accessible name — the
// visible mark is always a bare chevron), `onClick` goes there.
//
// The word is in the label rather than on screen because the header's width is spent
// on the title, and since #427 the title can be a game's name — text this header
// doesn't choose and can't shorten. `label` is what a screen reader announces either
// way, so dropping the visible word costs nothing there.
//
// **Both marks are drawn, not set**, and that is a pair decision rather than two
// separate ones: a glyph and a stroked path sitting either side of the same title
// read as coming from different places however closely their sizes are matched. "‹"
// was the worse of the two — a quotation mark, with modulation, angled terminals and
// about 6×13px of ink in a 32px box — but drawing only it was what made the ✕ look
// wrong. They share a viewBox, a stroke weight and `currentColor`; the same trade
// `TopBar`'s undo icon makes.
//
// The ✕ is drawn *smaller* than the chevron, not the same: it fills its square where
// a chevron fills a tall slice of one, so equal sizes are not equal weights. See
// MenuHeader.css for the numbers.
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
        <svg className="menu-back__icon" viewBox="0 0 24 24" ariaHidden="true" focusable="false">
          <path
            d="M15 5 L8 12 L15 19"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.5"
            strokeLinejoin="round"
          />
        </svg>
      </button>
    | None => Html.empty
    }}
    <h1 className="menu-title" onClick=?{onTitleTap->Option.map(tap => _ => tap())}>
      {Html.string(title)}
    </h1>
    <button className="menu-close" onClick={_ => onClose()} type_="button" ariaLabel="Close menu">
      <svg className="menu-close__icon" viewBox="0 0 24 24" ariaHidden="true" focusable="false">
        <path
          d="M6 6 L18 18 M18 6 L6 18"
          fill="none"
          stroke="currentColor"
          strokeWidth="2.5"
          strokeLinejoin="round"
        />
      </svg>
    </button>
  </div>
