// Where the drop-down debug console sits (#275): over the board, or docked into the
// width beside it.
//
// The console (#271) is a top-anchored translucent overlay — the familiar Quake shape,
// and the only sensible one in a small window. In a desktop window it's the wrong axis
// for FreeCell: `TableScene` fits the tallest cascade fan plus the top row into the
// available *height*, so a top overlay eats the scarce dimension and shrinks every
// card. Width is the opposite — past a point `applyScale` clamps the rows
// (`--rows-max-w`) and throws the surplus away as equal left/right margins. Docking the
// console into that discarded width costs the board almost nothing.
//
// The mechanism is one custom property and one root attribute, published here and
// consumed entirely by the stylesheet — the same seam `NotchDisplay` uses for
// `data-notch-wings` and `CutoutSide` for `data-cutout`:
//
//   - `--console-dock-inset` — the dock's width in px, stated once here in ReScript
//     because two consumers need the same number: the CSS lays the panel out in it,
//     and the refusal test below subtracts it from the stage. The same
//     one-number-published-to-the-CSS arrangement as `applyScale`'s `--card-w`.
//   - `data-console-dock="on"` — set while the console is *docked and showing*. The
//     inset it switches on lands on `.table-board`, the box `TableScene`'s
//     `ResizeObserver` watches (#172), so narrowing that box re-runs the whole existing
//     relayout: `applyScale` resizes the cards, `reflowAll` moves the piles, loose cards
//     scale by the width ratio. Nothing else has to know the console exists.
//
// Which edge it docks to is the stylesheet's business, not this module's: the console
// docks *opposite the menu*, and the menu enters from the left and mirrors right under
// `html[data-cutout="right"]` — so the docked rules mirror off that same attribute. In
// practice the mirror branch never fires (it's phone-only, and docking is refused at
// those widths), but stating the invariant keeps it correct if the menu ever moves for
// another reason.

type t =
  | Overlay
  | Docked

// The dock's width in CSS px. One width, tuned once — a resizable or draggable dock is
// deliberately out of scope. Wide enough that a `dispatch` line's JSON payload wraps
// only a couple of times, narrow enough that an ordinary laptop window still clears the
// refusal test (`TableScene.minStageWidth`) with room over.
let width = 340.

@val @scope("document") external documentElement: WebDom.element = "documentElement"

type style
@get external style: WebDom.element => style = "style"
@send external setProperty: (style, string, string) => unit = "setProperty"

let isDocked = mode =>
  switch mode {
  | Docked => true
  | Overlay => false
  }

// How the mode is spelled in `localStorage` (see `Preferences`). A named value rather
// than a boolean so a third mode — a bottom dock, say — could join it without a
// migration, and so a stored value reads clearly when you go looking.
let toString = mode =>
  switch mode {
  | Overlay => "overlay"
  | Docked => "docked"
  }

let fromString = stored =>
  switch stored {
  | "overlay" => Some(Overlay)
  | "docked" => Some(Docked)
  | _ => None
  }

// Reflect the *effective* dock onto the document root: docked **and** showing. Both
// halves matter — a closed console must not go on holding a strip of the board, and the
// menu's backdrop (which stops at the dock edge, so an open menu leaves the log
// readable) keys off this same attribute for the same reason.
let reflect = (~dock: t, ~open_: bool): unit => {
  documentElement->style->setProperty("--console-dock-inset", Float.toString(width) ++ "px")
  isDocked(dock) && open_
    ? documentElement->WebDom.setAttribute("data-console-dock", "on")
    : documentElement->WebDom.removeAttribute("data-console-dock")
}
