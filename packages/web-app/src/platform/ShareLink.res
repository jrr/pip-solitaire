// "Share game state": turn the board's live saved game — its undo/redo history and
// the play tally beside it — into a link, and turn that link back into a board.
//
// The payload is exactly what `SavedGame` writes to `localStorage` — `core`'s
// `SaveState` JSON — run through `Compression` and hung off the URL. Reusing the
// save format rather than inventing a share format means one versioned encoding to
// keep honest, and `SaveState.decode`'s existing "reject anything I don't
// recognise" guarantee covers a stale or corrupt link for free. It's also why the
// move/undo counts (#289) needed nothing of their own here: they went into the save
// envelope, so they ride every link that envelope rides, and a link written before
// they existed still opens (the version didn't move — see `SaveState`).
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
// Being in the fragment also keeps this cleanly apart from the query parameters
// `AppUrl` already understands: `#g=` and `?state=` occupy different halves of the
// URL and never have to agree about precedence, which is why a shared link can take
// over the saved game while a `?state=` scenario deliberately doesn't — the two
// aren't competing readings of one parameter. See `Main`'s `sharedOpen`.
//
// **Delivery** prefers the OS share sheet (`navigator.share`) when the platform has
// one — the phone case, where "copy to clipboard" is the more awkward of the two —
// and falls back to writing the clipboard. See `deliver` for the transient-
// activation constraint that shapes how this gets called.
//
// There are **two things worth sharing**, and this module builds a link for each:
// the game state above, and the *deal* (`urlForDeal`, #98) — a link that says which
// game and which board to lay out and nothing more, so both players start level. They
// differ in what they carry, so they differ in where they ride and what they cost; see
// `urlForDeal`. Delivery is common to both — whatever the link says, getting it to
// the player is the same problem.
//
// Three *buttons* hand those two links out, though: the win overlay's victory share
// (#264) is a deal link wrapped in a message (`victoryMessage`), not a third kind of
// link. Sharing the position from a won board would ship the solution, so a victory
// can only ever offer the deal.

// The fragment parameter carrying a shared game. Read back by `AppUrl`, which owns
// all URL parsing; this module owns the format, so the name lives here.
let fragmentKey = "g"

// The query parameter carrying a shared *deal* (#98), same arrangement: `AppUrl`
// parses it, this module writes it, so the spelling lives in one place.
let dealKey = "seed"

// …and the one naming *which game* that deal is a deal of (#353). `AppUrl` has parsed
// `?scene=` since the beginning — it's how the screenshot report points at a board —
// so a deal link for a second game needs no new knob, only this module writing the one
// that's already there. Same arrangement as the two above: `AppUrl` reads it, this
// module writes it, one spelling.
let sceneKey = "scene"

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
// Deliberately a *different* share from `urlFor` above rather than a cheaper one.
// That link carries a position — this game, mid-play, undo stack and all — so the
// recipient picks up where the sender left off. This one carries only which board
// to deal, so both players start level and play it out themselves, which is what
// sharing a deal number has always meant where solitaire has them.
//
// Carrying so little is what lets it ride in the query rather than the fragment,
// and it should: `?seed=` is a knob `AppUrl` has always parsed, it costs a handful
// of characters (no request-line limit is anywhere in sight), and it survives being
// read off one screen and typed into another by hand — which a compressed blob
// does not. The link being legible is half the point of a deal number.
//
// Synchronous, unlike `urlFor`: there's nothing to compress. That matters at the
// call site — the share can be attempted in the click handler itself, with the
// gesture's transient activation intact (see `deliver`), rather than having to be
// prepared in advance.
//
// The page's own query is dropped rather than kept, for nearly the reason `urlFor`
// drops it: whatever `?state=`/`?seed=` got this board on screen, the deal number now
// says it in full. `pathname` stays, so a link shared from a GitHub Pages subpath — or
// a PR preview's deeper one — opens that same build.
//
// **`?scene=` is the exception, and it's why this takes a game (#353.)** The other
// parameters say something the deal number supersedes; that one says *which board the
// number is a deal of*, which the number can't say by itself. Dropping it was harmless
// only while there was one seeded game to mean, so it's written back here — and written
// from the game in hand rather than copied off the current URL, since the board on the
// table is what's being shared and the query that opened the page may be a scene ago.
//
// **The default game omits it**, and that's the load-bearing half. `Game.default` is
// what a deal number with no game named belongs to (it's the line in `core` that says
// so, and the switcher's launch scene reads from it), so spelling it out would be a
// link saying twice what it already says once. Two things follow, in order of weight:
// every deal link this app has ever emitted stays byte-identical, so a `?seed=7`
// written before this change and one written after are the same string; and `?seed=7`
// stays short and legible, which the note above calls half the point of a deal number —
// it survives being read off one screen and typed into another by hand, and
// `?scene=freecell&seed=7` does not.
let urlForDeal = (~game: Game.t, ~seed: int): string => {
  let scene = game.id == Game.default.id ? "" : sceneKey ++ "=" ++ game.id ++ "&"
  origin ++ pathname ++ "?" ++ scene ++ dealKey ++ "=" ++ Int.toString(seed)
}

// The message a won game shares (#264) — the boast the win overlay's Share button
// hands over, in the shape the Wordle-likes made familiar: a line naming the game
// and the deal, a line saying how it went, and a link to play the same board.
//
// It rides on `urlForDeal`, never `urlFor`, and that's the whole design: a link to
// the *position* would hand the recipient a solved board, which is the one thing a
// victory share must not do. The deal number is the invitation — here's the board I
// beat, go and beat it yourself — and it's the only share where "both players start
// level" is the entire point. Being a `?seed=` link also means there's nothing to
// compress, so the share can be attempted straight out of the click handler with
// the gesture's transient activation intact (see `deliver`).
//
// `moves` and `undos` are the game's tally (`Stats`, #289): every move the player
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
// The game is *named* rather than spelled (#353): "Pip FreeCell #264" is the game's own
// `name`, so the boast says which board was beaten for the same reason the link does,
// and from the same value. A second game needs no edit here.
let victoryMessage = (~game: Game.t, ~seed: int, ~moves: int, ~undos: int): string =>
  "♣️♥️♠️♦️ Pip " ++
  game.name ++
  " #" ++
  Int.toString(seed) ++
  "\nSolved in " ++
  Stats.moveLabel(moves) ++ (undos > 0 ? " (" ++ Stats.undoLabel(undos) ++ ")" : "")

// The saved game a shared blob carries, or `None` for anything that isn't one: a
// truncated paste, a link from an incompatible `SaveState` version, or a browser
// that can't decompress. Every one of those means "ignore the link and deal
// normally" to the caller — a bad link never takes the board down with it.
let savedFrom = async (blob: string): option<SaveState.t> =>
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
