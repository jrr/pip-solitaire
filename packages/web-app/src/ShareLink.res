// "Share game state": turn the board's live undo/redo history into a link, and
// turn that link back into a board.
//
// The payload is exactly what `SavedGame` writes to `localStorage` — `core`'s
// `SaveState` JSON — run through `Compression` and hung off the URL. Reusing the
// save format rather than inventing a share format means one versioned encoding to
// keep honest, and `SaveState.decode`'s existing "reject anything I don't
// recognise" guarantee covers a stale or corrupt link for free.
//
// **The blob rides in the fragment (`#g=…`), not the query string.** Two reasons,
// both decisive:
//
//   - A fragment is never sent to the server. That sidesteps the ~8 KB request-line
//     limit that Apache, nginx, CloudFront and friends impose on a URL's path and
//     query — the only hard length limit anywhere in this path, since browsers
//     themselves accept URLs orders of magnitude longer than anything we'd
//     generate. On the fragment there is effectively no ceiling to design around.
//   - It keeps a player's board out of server logs, `Referer` headers, and any
//     analytics the host runs. The state is the client's business.
//
// The cost is that a fragment is invisible to link-preview crawlers, so a shared
// link can never render a picture of the position. Not something this app offers
// anyway, and not worth the ceiling to buy.
//
// **Delivery** prefers the OS share sheet (`navigator.share`) when the platform has
// one — the phone case, where "copy to clipboard" is the more awkward of the two —
// and falls back to writing the clipboard. See `deliver` for the transient-
// activation constraint that shapes how this gets called.

// The fragment parameter carrying a shared game. Read back by `AppUrl`, which owns
// all URL parsing; this module owns the format, so the name lives here.
let fragmentKey = "g"

@val @scope(("window", "location")) external origin: string = "origin"
@val @scope(("window", "location")) external pathname: string = "pathname"

// --- Building a link ---------------------------------------------------------

// A shareable URL for `history`, or `None` if the platform can't compress (see
// `Compression.supported`).
//
// The current page's *query* is deliberately dropped: whatever `?scene=`/`?seed=`
// /`?state=` got this board onto the screen, the blob already carries the resulting
// position in full, so a share link is the bare page plus the state. Keeping
// `pathname` preserves the GitHub Pages subpath (and a PR preview's deeper one), so
// a link shared from a preview build opens that preview.
let urlFor = async (history: History.t<GameState.t>): option<string> =>
  (await Compression.compress(SaveState.encode(history)))->Option.map(blob =>
    origin ++ pathname ++ "#" ++ fragmentKey ++ "=" ++ blob
  )

// The history a shared blob carries, or `None` for anything that isn't one: a
// truncated paste, a link from an incompatible `SaveState` version, or a browser
// that can't decompress. Every one of those means "ignore the link and deal
// normally" to the caller — a bad link never takes the board down with it.
let historyFrom = async (blob: string): option<History.t<GameState.t>> =>
  (await Compression.decompress(blob))->Option.flatMap(SaveState.decode)

// --- Handing the link to the player ------------------------------------------

// What became of a share attempt, for the status line the menu shows.
type outcome =
  | Shared // handed off to the OS share sheet
  | Copied // written to the clipboard
  | Failed // neither route was available, or both refused

let canShare: bool = %raw(`
  typeof navigator !== "undefined" && typeof navigator.share === "function"
`)

let canCopy: bool = %raw(`
  typeof navigator !== "undefined" &&
  !!navigator.clipboard &&
  typeof navigator.clipboard.writeText === "function"
`)

type shareData
@obj
external makeShareData: (~title: string=?, ~text: string=?, ~url: string=?) => shareData = ""
@val @scope("navigator") external navigatorShare: shareData => promise<unit> = "share"
@val @scope(("navigator", "clipboard")) external writeText: string => promise<unit> = "writeText"

// Get `url` to the player by whichever route the platform offers.
//
// **Call this straight out of the click handler, with nothing awaited first.**
// `navigator.share` requires transient activation, and Safari in particular
// rejects it when it's reached after an `await` — so the *compression* has to have
// happened already by the time a share is attempted. That's why `Main` encodes the
// link when the Debug screen opens rather than when the button is pressed: the
// board can't change while the menu is covering it, so the link is ready and this
// function's first act can be the share itself.
//
// A rejected share falls through to the clipboard. That folds two cases together —
// a genuine failure and a player who opened the sheet and thought better of it —
// and lands both on "the URL is on your clipboard", which is a harmless place to
// end up and saves inspecting `DOMException` names to tell them apart.
let deliver = async (url: string): outcome => {
  let shared = if canShare {
    try {
      await navigatorShare(makeShareData(~title="Pip", ~text="A game of FreeCell", ~url))
      true
    } catch {
    | _ => false
    }
  } else {
    false
  }
  if shared {
    Shared
  } else if canCopy {
    try {
      await writeText(url)
      Copied
    } catch {
    | _ => Failed
    }
  } else {
    Failed
  }
}

// The one-line status the menu shows after an attempt.
let message = (outcome: outcome): string =>
  switch outcome {
  | Shared => "Link shared."
  | Copied => "Link copied to clipboard."
  | Failed => "Couldn't share the link."
  }
