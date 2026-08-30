// Turning a board into a link, and a link back into a board. Both kinds: the whole
// position (`urlFor`) and the deal number (`urlForDeal`).
//
// **The wire format, the two kinds of link, and why the blob rides in the fragment
// are all in `docs/save-and-share.md`.** What's here is the building and the handing
// over — including `deliver`, whose transient-activation rule shapes its callers.

// The three URL keys. `AppUrl` reads them and this module writes them, so each
// spelling lives in exactly one place.
let fragmentKey = "g"
let dealKey = "seed"
let gameKey = "game"

@val @scope(("window", "location")) external origin: string = "origin"
@val @scope(("window", "location")) external pathname: string = "pathname"

// --- Building a link ---------------------------------------------------------

// `None` when the platform can't compress (see `Compression.supported`).
//
// Both builders drop the page's *query* and keep its `pathname`. Whatever `?scene=` or
// `?state=` got this board on screen, the link now says the board in full — and the
// path is what keeps a link shared from a GitHub Pages subpath (or a PR preview's
// deeper one) opening that same build.
let urlFor = async (saved: SaveState.t): option<string> =>
  (await Compression.compress(SaveState.encode(saved)))->Option.map(blob =>
    origin ++ pathname ++ "#" ++ fragmentKey ++ "=" ++ blob
  )

// **Synchronous, unlike `urlFor`**: there is nothing to compress. That matters at the
// call site — the share can be attempted inside the click handler itself, with the
// gesture's transient activation intact (see `deliver`), rather than prepared ahead.
//
// `?game=` is written from the game *in hand* rather than copied off the current URL,
// since the board on the table is what's being shared and the query that opened the
// page may be a scene ago. **The default game omits it**, which is the load-bearing
// half: `?seed=7` survives being read off one screen and typed into another, and
// `?game=freecell&seed=7` does not.
let urlForDeal = (~game: Game.t, ~seed: int): string => {
  let whichGame = game.id == Game.default.id ? "" : gameKey ++ "=" ++ game.id ++ "&"
  origin ++ pathname ++ "?" ++ whichGame ++ dealKey ++ "=" ++ Int.toString(seed)
}

// The boast the win overlay's Share button hands over, in the shape the Wordle-likes
// made familiar. Three rules hold it together:
//
// **It rides on `urlForDeal`, never `urlFor`.** A link to the *position* would hand
// the recipient a solved board, which is the one thing a victory share must not do.
//
// **The URL is deliberately not in this string.** `deliver` adds it once, on whichever
// route it takes; composing it here as well is how a link lands in a message twice.
//
// **The undo count is named only when there were undos.** Zero is the ordinary case
// and the good one, so "(0 undos)" would spend a clause on nothing having happened —
// the clause's presence is itself part of what the message says. The victory panel
// shows both numbers unconditionally, because a scoreboard reads the other way round.
let victoryMessage = (~game: Game.t, ~seed: int, ~moves: int, ~undos: int): string =>
  "♣️♥️♠️♦️ Pip " ++
  game.name ++
  " #" ++
  Int.toString(seed) ++
  "\nSolved in " ++
  Stats.moveLabel(moves) ++ (undos > 0 ? " (" ++ Stats.undoLabel(undos) ++ ")" : "")

// A pair rather than the save alone, so the caller can bring the *named* board forward
// instead of decoding onto whichever scene happens to be mounted.
type shared = {game: Game.t, saved: SaveState.t}

// `None` for every way a blob can fail — truncated, wrong version, no decompressor, a
// game this build doesn't have, piles that don't fit — and they all mean the same
// thing: ignore the link and deal normally.
//
// A blob naming **no** game is not one of them. It means the default game, the reading
// `SaveState` leaves to this end because this is the end holding `Game.all`.
let savedFrom = async (blob: string): option<shared> =>
  (await Compression.decompress(blob))
  ->Option.flatMap(SaveState.decode)
  ->Option.flatMap(saved =>
    switch saved.gameId {
    | None => Some(Game.default)
    | Some(id) => Game.byId(id)
    }->Option.flatMap(game => saved->SaveState.fits(~game) ? Some({game, saved}) : None)
  )

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

// **Call this straight out of the click handler, with nothing awaited first.**
// `navigator.share` requires transient activation, and Safari in particular rejects it
// when reached after an `await` — so any compression must already have happened. That
// is why `Main` encodes the `#g=` link when the Debug screen *opens*: the board can't
// change while the menu covers it, so this function's first act can be the share.
//
// A rejected share falls through to the clipboard, folding a genuine failure together
// with a player who opened the sheet and thought better of it. Both land on "the URL
// is on your clipboard", which beats inspecting `DOMException` names to tell them apart.
//
// Composing `~text` and `url` is this function's job, not the caller's, because the
// two routes want the URL in different places: the sheet takes it as its own field and
// lets the OS compose, the clipboard needs it appended.
let deliver = async (~text: option<string>=?, url: string): outcome => {
  let shared = if canShare {
    try {
      await navigatorShare(
        makeShareData(~title="Pip", ~text=text->Option.getOr("A game of FreeCell"), ~url),
      )
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
    let payload = switch text {
    | Some(message) => message ++ "\n\n" ++ url
    | None => url
    }
    try {
      await writeText(payload)
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
