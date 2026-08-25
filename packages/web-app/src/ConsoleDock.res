// Where the drop-down debug console sits (#275): over the top of the board, docked into
// the width beside it, along the bottom, or over the whole window. ⇧` steps through the
// four in that order.
//
// The console (#271) started as a top-anchored translucent overlay — the familiar Quake
// shape, and the only sensible one in a small window. In a desktop window it's the wrong
// axis for FreeCell: `TableScene` fits the tallest cascade fan plus the top row into the
// available *height*, so a top overlay eats the scarce dimension and shrinks every
// card. Width is the opposite — past a point `applyScale` clamps the rows
// (`--rows-max-w`) and throws the surplus away as equal left/right margins. Docking the
// console into that discarded width costs the board almost nothing.
//
// The other two placements are the same panel pointed elsewhere, and each answers a
// question the first two don't:
//
//   - **Bottom** is the top overlay's mirror, and what you want when the row the top
//     band covers is the row you're watching: the free cells and the foundations live up
//     there, and a log that hides them hides the state a `dispatch` line is about. It
//     costs the board exactly what the top band costs it (nothing — both are overlays
//     the board is never told about), so it's a preference between two coverings rather
//     than a trade.
//   - **Full** gives the log the whole window, for the times the board isn't what you're
//     reading: `print` draws a ~150-column, ~20-row text board (#273), which a 340px dock
//     crops in both axes and a 40vh band crops in one. Full window is the only placement
//     a printed board arrives in whole — the one that admits the game can wait.
//
// The mechanism is one custom property and one root attribute, published here and
// consumed entirely by the stylesheet — the same seam `NotchDisplay` uses for
// `data-notch-wings` and `CutoutSide` for `data-cutout`:
//
//   - `--console-dock-inset` — the side dock's width in px, stated once here in ReScript
//     because two consumers need the same number: the CSS lays the panel out in it,
//     and the refusal test below subtracts it from the stage. The same
//     one-number-published-to-the-CSS arrangement as `applyScale`'s `--card-w`.
//   - `data-console-dock="<placement>"` — the placement, set while the console is
//     *showing* and removed when it isn't. It's the placement's own name (`toString`), so
//     the stylesheet's four branches read as the four shapes. The inset the `side` branch
//     switches on lands on `.table-board`, the box `TableScene`'s `ResizeObserver`
//     watches (#172), so narrowing that box re-runs the whole existing relayout:
//     `applyScale` resizes the cards, `reflowAll` moves the piles, loose cards scale by
//     the width ratio. Nothing else has to know the console exists. The attribute going
//     away on close is what keeps a closed console from holding a strip of the board.
//
// Which edge the side dock takes is the stylesheet's business, not this module's: the
// console docks *opposite the menu*, and the menu enters from the left and mirrors right
// under `html[data-cutout="right"]` — so the docked rules mirror off that same attribute.
// In practice the mirror branch never fires (it's phone-only, and docking is refused at
// those widths), but stating the invariant keeps it correct if the menu ever moves for
// another reason.

type t =
  | Top
  | Side
  | Bottom
  | Full

// The side dock's width in CSS px. One width, tuned once — a resizable or draggable dock
// is deliberately out of scope. Wide enough that a `dispatch` line's JSON payload wraps
// only a couple of times, narrow enough that an ordinary laptop window still clears the
// refusal test (`TableLayout.minStageWidth`) with room over.
let width = 340.

@val @scope("document") external documentElement: WebDom.element = "documentElement"

type style
@get external style: WebDom.element => style = "style"
@send external setProperty: (style, string, string) => unit = "setProperty"

// Whether this placement is the one that takes a strip of the board for itself. Two
// things follow from it and nothing else does: `.table-board` gives up
// `--console-dock-inset`, and the menu is allowed up alongside the panel (see `Main`) —
// the side dock is the only shape that leaves the Menu button, the whole board and the
// menu's own panel somewhere the console isn't.
let isSide = placement =>
  switch placement {
  | Side => true
  | Top | Bottom | Full => false
  }

// Whether the panel takes pointer events where it lies. The two overlays don't: they
// cover the free cells, the foundations and the top bar, so refusing input is what keeps
// the game playable underneath a log that's narrating it (`DebugConsole` forwards wheel
// turns to the scrollback by hand in that shape). The side dock and the full window both
// do: one covers nothing, the other covers everything, and in neither case is there a
// board underneath worth protecting.
let takesPointerEvents = placement =>
  switch placement {
  | Side | Full => true
  | Top | Bottom => false
  }

// Whether this placement has to ask the board for room before it can be shown. Only the
// side dock does — it's the only one built out of width the layout was discarding, and
// the only one that can push the cards below `minScale` if that width isn't there. The
// overlays and the full window cover the board rather than displacing it, so they fit
// any window by construction.
let needsRoom = placement =>
  switch placement {
  | Side => true
  | Top | Bottom | Full => false
  }

// The order ⇧` walks, stated once and used for both the step and its length. Top first
// because it's what the console opens as, `Side` next because it's the placement the
// desktop window is for, then the two that were added around them — the bottom band
// beside its mirror image, and the full window last, furthest from the shape you started
// in.
let cycle = [Top, Side, Bottom, Full]

let next = placement => {
  let here = cycle->Array.findIndex(candidate => candidate == placement)
  cycle->Array.get(mod(here + 1, Array.length(cycle)))->Option.getOr(Top)
}

// The next placement this window can actually show: the cycle above with the ones it
// hasn't the room for stepped *over* rather than landed on. Stepping over is the whole
// point — a phone refusing the side dock must still reach the bottom band and the full
// window beyond it, and a key that goes inert on a narrow window is a key that looks
// broken.
//
// Written as a bounded walk rather than as "skip `Side` if it doesn't fit" so that a
// second demanding placement couldn't quietly break it. The walk always lands: `Top`
// asks for nothing.
let nextFitting = (placement, ~roomToDock) => {
  let rec walk = (candidate, remaining) =>
    if remaining <= 0 {
      Top
    } else if needsRoom(candidate) && !roomToDock {
      walk(next(candidate), remaining - 1)
    } else {
      candidate
    }
  walk(next(placement), Array.length(cycle))
}

// How the placement is spelled in `localStorage` (see `Preferences`) and in the root
// attribute the stylesheet reads. A named value rather than a boolean, which is what let
// the bottom band and the full window join the original two without a stored-shape
// migration — and what makes a stored value read clearly when you go looking.
let toString = placement =>
  switch placement {
  | Top => "top"
  | Side => "side"
  | Bottom => "bottom"
  | Full => "full"
  }

// `overlay`/`docked` are what the first two placements were called when they were the
// only two, and a developer who left one saved shouldn't be silently moved somewhere
// else by an update. They're read-only aliases: the next ⇧` writes the current spelling
// back over them.
let fromString = stored =>
  switch stored {
  | "top" | "overlay" => Some(Top)
  | "side" | "docked" => Some(Side)
  | "bottom" => Some(Bottom)
  | "full" => Some(Full)
  | _ => None
  }

// Reflect the *effective* placement onto the document root: where the panel is, but only
// while it's showing. Both halves matter — a closed console must not go on holding a
// strip of the board, and the menu's backdrop (which stops at the dock edge, so an open
// menu leaves the log readable) keys off this same attribute for the same reason.
let reflect = (~dock: t, ~open_: bool): unit => {
  documentElement->style->setProperty("--console-dock-inset", Float.toString(width) ++ "px")
  open_
    ? documentElement->WebDom.setAttribute("data-console-dock", toString(dock))
    : documentElement->WebDom.removeAttribute("data-console-dock")
}
