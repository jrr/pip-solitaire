// Where the drop-down debug console sits: over the top of the board, docked into the
// width beside it, along the bottom, or over the whole window. ⇧` steps the four.
//
// **`Side` is the only one that costs the board anything, and it costs it the right
// axis.** `TableScene` fits the tallest cascade fan into the available *height*, so a
// top overlay eats the scarce dimension and shrinks every card; width past
// `--rows-max-w` is being thrown away as equal margins anyway, so a dock built out of
// it is nearly free. `Bottom` and `Full` are the same panel pointed elsewhere — one
// for when the row you're watching is the one a top band covers, one for when a
// ~150-column printed board is what you're reading and the game can wait.
//
// The whole mechanism is two published values the stylesheet consumes, the seam
// `NotchDisplay` and `CutoutSide` also use:
//
//   - `--console-dock-inset` — the dock's width, stated once here because two
//     consumers need the same number: the CSS lays the panel out in it, and the
//     refusal test subtracts it from the stage.
//   - `data-console-dock="<placement>"` — set while the console is *showing* and
//     removed when it isn't. The `side` branch's inset lands on `.table-board`, the
//     box `TableScene`'s `ResizeObserver` watches, so narrowing it re-runs the whole
//     existing relayout and nothing else has to know the console exists.
//
// Which edge the dock takes is the stylesheet's business: it docks *opposite* the
// menu, so the rules mirror off `html[data-cutout]` exactly as the menu does.

type t =
  | Top
  | Side
  | Bottom
  | Full

// One width, tuned once — a resizable dock is deliberately out of scope. Wide enough
// that a `dispatch` line's JSON payload wraps only a couple of times, narrow enough
// that an ordinary laptop window clears `TableLayout.minStageWidth` with room over.
let width = 340.

@val @scope("document") external documentElement: WebDom.element = "documentElement"

type style
@get external style: WebDom.element => style = "style"
@send external setProperty: (style, string, string) => unit = "setProperty"

// Two things follow from this and nothing else does: `.table-board` gives up
// `--console-dock-inset`, and the menu is allowed up alongside the panel (see `Main`),
// this being the only shape that leaves the Menu button, the board and the menu's own
// panel somewhere the console isn't.
let isSide = placement =>
  switch placement {
  | Side => true
  | Top | Bottom | Full => false
  }

// The two overlays refuse input, which is what keeps the game playable underneath a log
// narrating it — `DebugConsole` forwards wheel turns to the scrollback by hand in that
// shape. The dock covers nothing and the full window covers everything, so neither has
// a board underneath worth protecting.
let takesPointerEvents = placement =>
  switch placement {
  | Side | Full => true
  | Top | Bottom => false
  }

// Only the dock has to ask the board for room: it's the only one that can push the
// cards below `minScale`. The rest cover the board rather than displacing it, so they
// fit any window by construction.
let needsRoom = placement =>
  switch placement {
  | Side => true
  | Top | Bottom | Full => false
  }

// Stated once and used for both the step and its length. `Top` first because it's what
// the console opens as, `Full` last because it's furthest from that.
let cycle = [Top, Side, Bottom, Full]

let next = placement => {
  let here = cycle->Array.findIndex(candidate => candidate == placement)
  cycle->Array.get(mod(here + 1, Array.length(cycle)))->Option.getOr(Top)
}

// A placement this window hasn't room for is stepped *over*, never landed on: a phone
// refusing the dock must still reach the bottom band and the full window beyond it,
// because a key that goes inert on a narrow window is a key that looks broken.
//
// A bounded walk rather than "skip `Side` if it doesn't fit", so a second demanding
// placement can't quietly break it. It always lands: `Top` asks for nothing.
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

// How a placement is spelled in `localStorage` and in the root attribute the
// stylesheet reads. A name rather than a boolean, so a new placement joins without a
// stored-shape migration.
let toString = placement =>
  switch placement {
  | Top => "top"
  | Side => "side"
  | Bottom => "bottom"
  | Full => "full"
  }

// `overlay`/`docked` are read-only aliases a developer may still have saved; the next
// ⇧` writes the current spelling back over them.
let fromString = stored =>
  switch stored {
  | "top" | "overlay" => Some(Top)
  | "side" | "docked" => Some(Side)
  | "bottom" => Some(Bottom)
  | "full" => Some(Full)
  | _ => None
  }

// Where the panel is, but **only while it's showing** — a closed console must not go
// on holding a strip of the board. The menu's backdrop stops at the dock edge off this
// same attribute, so an open menu leaves the log readable.
let reflect = (~dock: t, ~open_: bool): unit => {
  documentElement->style->setProperty("--console-dock-inset", Float.toString(width) ++ "px")
  open_
    ? documentElement->WebDom.setAttribute("data-console-dock", toString(dock))
    : documentElement->WebDom.removeAttribute("data-console-dock")
}
