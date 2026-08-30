// "Share game state": turn the board's live saved game — its undo/redo history and the
// play tally beside it — into a link, and turn that link back into a board.
//
// The payload is exactly what `SavedGame` writes to `localStorage` — `core`'s
// `SaveState` JSON — run through `Compression` and hung off the URL fragment. Reusing
// the save format rather than inventing a share format means one versioned encoding to
// keep honest, and `SaveState.decode`'s "reject anything I don't recognise" guarantee
// covers a stale or corrupt link for free.
//
// **The wire format, why the blob rides in the fragment, and how the two kinds of link
// differ are documented in `docs/save-and-share.md`.**
//
// Three *buttons* hand out those two links: the win overlay's victory share is a
// deal link wrapped in a message (`victoryMessage`), not a third kind of link. Sharing
// the position from a won board would ship the solution, so a victory can only ever
// offer the deal.
// The fragment parameter carrying a shared game. Read back by `AppUrl`, which owns
// all URL parsing; this module owns the format, so the name lives here.
let fragmentKey = "g"

// The query parameter carrying a shared *deal*, same arrangement: `AppUrl`
// parses it, this module writes it, so the spelling lives in one place.
let dealKey = "seed"

// …and the one naming *which game* that deal is a deal of. Same arrangement as
// the two above: `AppUrl` reads it, this module writes it, one spelling.
//
// It says a *game*, so it is spelled `game`. `?scene=` picks which scene to mount and a
// deal link has nothing to say about that; `?game=` picks a board and says nothing about
// scenes.
let gameKey = "game"

@val @scope(("window", "location")) external origin: string = "origin"
@val @scope(("window", "location")) external pathname: string = "pathname"

// --- Building a link ---------------------------------------------------------

// A shareable URL for `saved` — the board's history and its tally — or `None` if
// the platform can't compress (see `Compression.supported`).
//
// The current page's *query* is deliberately dropped: whatever `?scene=`/`?seed=`
// /`?state=` got this board onto the screen, the blob already carries the resulting
// position in full, so a share link is the bare page plus the state. Keeping
// `pathname` preserves the GitHub Pages subpath (and a PR preview's deeper one), so
// a link shared from a preview build opens that preview.
let urlFor = async (saved: SaveState.t): option<string> =>
  (await Compression.compress(SaveState.encode(saved)))->Option.map(blob =>
    origin ++ pathname ++ "#" ++ fragmentKey ++ "=" ++ blob
  )

// A shareable URL for deal number `seed` of `game`: this page plus `?seed=`, which
// opens that game dealt from that exact shuffle (`Game.t.deal`, via `AppUrl`).
//
// Deliberately a *different* share from `urlFor` above rather than a cheaper one; see
// `docs/save-and-share.md` for the two kinds and why this one rides in the query.
//
// **Synchronous, unlike `urlFor`**: there's nothing to compress. That matters at the
// call site — the share can be attempted in the click handler itself, with the gesture's
// transient activation intact (see `deliver`), rather than prepared in advance.
//
// The page's own query is dropped and `pathname` kept, as in `urlFor`: whatever got this
// board on screen, the deal number now says it in full, and the path keeps a link shared
// from a GitHub Pages subpath (or a PR preview's deeper one) opening that same build.
//
// **`?game=` is the exception, and it's why this takes a game.** It says *which
// board the number is a deal of*, which the number can't say by itself — and it's written
// from the game in hand rather than copied off the current URL, since the board on the
// table is what's being shared and the query that opened the page may be a scene ago.
//
// **The default game omits it**, and that's the load-bearing half: `?seed=7` survives
// being read off one screen and typed into another by hand, and `?game=freecell&seed=7`
// does not.
let urlForDeal = (~game: Game.t, ~seed: int): string => {
  let whichGame = game.id == Game.default.id ? "" : gameKey ++ "=" ++ game.id ++ "&"
  origin ++ pathname ++ "?" ++ whichGame ++ dealKey ++ "=" ++ Int.toString(seed)
}

// The message a won game shares — the boast the win overlay's Share button
// hands over, in the shape the Wordle-likes made familiar: a line naming the game
// and the deal, a line saying how it went, and a link to play the same board.
//
// **It rides on `urlForDeal`, never `urlFor`**: a link to the *position* would hand the
// recipient a solved board, which is the one thing a victory share must not do. Being a
// `?seed=` link also means there's nothing to compress, so the share can be attempted
// straight out of the click handler with the gesture's transient activation intact (see
// `deliver`).
//
// `moves` and `undos` are the game's tally (`Stats`): every move the player
// made, and every time they stepped one back. An undo doesn't pad the move count —
// it shows up as an undo instead — and a redo counts as the move it replays.
//
// The undo count is named only when there *were* undos. Zero is the ordinary case
// and the good one, so spelling out "(0 undos)" would spend a whole clause on
// nothing having happened; leaving it out makes the clause's presence itself part
// of what the message says. (The victory panel shows both numbers unconditionally —
// it's a scoreboard, not a boast, and there the absence of a number would read as a
// missing feature rather than a clean run.)
//
// The URL is deliberately *not* in this string: `deliver` adds it, once, on whichever
// route it takes — as the share sheet's own `url` field, or appended for the
// clipboard. Composing it here as well is how a link ends up in the message twice.
//
// The game is *named* rather than spelled: "Pip FreeCell #264" is the game's own
// `name`, so the boast says which board was beaten for the same reason the link does,
// and from the same value. A second game needs no edit here.
let victoryMessage = (~game: Game.t, ~seed: int, ~moves: int, ~undos: int): string =>
  "♣️♥️♠️♦️ Pip " ++
  game.name ++
  " #" ++
  Int.toString(seed) ++
  "\nSolved in " ++
  Stats.moveLabel(moves) ++ (undos > 0 ? " (" ++ Stats.undoLabel(undos) ++ ")" : "")

// What a shared blob turns out to be: the saved game, and **the game it is a game
// of**. A pair rather than the save alone so the caller can bring the named board forward
// instead of decoding onto whichever scene happens to be mounted.
type shared = {game: Game.t, saved: SaveState.t}

// The shared game a blob carries, or `None` for anything that isn't one — a truncated
// paste, an incompatible version, a browser that can't decompress, a game this build
// doesn't have, piles that don't fit the board named. Every one means "ignore the
// link and deal normally": a bad link never takes the board down with it.
//
// A blob naming **no** game at all is *not* one of them — it means the default game, the
// reading `SaveState` deliberately leaves to this end, which is the end that has
// `Game.all` to resolve it against.
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
// A rejected share falls through to the clipboard. That folds two cases together — a
// genuine failure and a player who opened the sheet and thought better of it — and lands
// both on "the URL is on your clipboard", which saves inspecting `DOMException` names to
// tell them apart.
//
// `~text` is the message to carry the link, for the one share that has something to
// say (`victoryMessage`); the plain link shares omit it and keep the generic blurb
// they always had. It's this function's job rather than the caller's because the two
// routes want the URL in different places — the share sheet takes it as its own
// field and lets the OS compose, while the clipboard needs it appended to the text —
// and a caller that folded the URL into its message would have it land twice on the
// sheet.
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
