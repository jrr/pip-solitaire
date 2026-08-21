// Serialize a game's *progress* to a string and back (#177), so the web app can
// persist an in-progress game to `localStorage` and resume it after a reload, a
// closed tab, or a crash. The thing being saved is the board's undo/redo history —
// a `History.t<GameState.t>` — plus the play tally beside it (`Stats.t`, #289), so
// restoring lands on the same board, the same card positions, the same Undo stack
// the player left, *and* the same move/undo counts.
//
// It lives in `core`, beside the state it serializes, for two reasons: the
// encoding is pure (no `localStorage`, no `Math.random`) and so is unit-testable
// here, and keeping the wire format next to `GameState`/`History` means a change
// to those types is a change to this file, not a silently-drifting copy in the
// view. The web app's `SavedGame` is the thin impure wrapper that only reads and
// writes the browser storage; the moment a byte is in hand, (de)serialization is
// this module's job.
//
// The format is deliberately small and self-describing:
//
//   {"v":1,"past":[S,…],"present":S,"future":[S,…],
//    "stats":{"moves":n,"undos":n,"autoplays":n},
//    "timing":{"dealtAt":ms,"wonAt":ms}}
//
// where a state S is `{"piles":[[C,…],…],"loose":[C,…]}` and a card C is a
// two-character code — rank char then suit char, e.g. "TS" (Ten of Spades),
// "AH" (Ace of Hearts). The `v` is a format version: a saved game from an older,
// incompatible layout (or any corrupt/foreign string) fails to `decode` and is
// ignored rather than crashing the board — the "never a broken board" guarantee.
//
// `"stats"` (#289) is **optional, and the version deliberately stays at 1.** It's
// an additive field in both directions: a blob written before it existed decodes
// here with the tally filled in by `ofHistory` below, and a blob written *with* it
// still decodes in a build that predates it, which reads the fields it knows and
// ignores the rest. Bumping `v` would have bought nothing and cost everything the
// version is for — every saved game on every device dropped, and every share link
// already in a chat turned into "couldn't read that". Reserve the bump for a change
// that genuinely can't be read both ways.
//
// `"autoplays"` (#291) joined `"stats"` on exactly those terms, one level down: a
// blob without it decodes to a game the solver never touched, which is what a save
// written before autoplay existed *is*.
//
// `"timing"` (#302) joins on the same terms again, and its *inner* fields too: a blob
// without it is a game whose clock nobody kept (`Timing.unknown`), and one with a
// `"dealtAt"` but no `"wonAt"` is a game still being played. Absence is a shape we
// support at every level here; a field that's *present* and isn't a timestamp still
// fails the whole save, because that isn't a blob we wrote.

open Card

// The wire-format version. Bump this whenever the shape below changes
// incompatibly; `decode` rejects any other version, so an old save is dropped and
// the player gets a fresh deal instead of a misread board.
let version = 1

// What a save *is*: the line of play, the tally of how much play it took, and the
// clock either side of it (#302). Three fields rather than one because they answer to
// different rules — the history is stepped by undo/redo, the tally only ever counts
// up (see `Stats`), the clock is two wall-clock readings (see `Timing`) — and keeping
// them apart is what lets `undo` stay the plain pop it has always been.
type t = {
  history: History.t<GameState.t>,
  stats: Stats.t,
  timing: Timing.t,
}

// The tally a save with no `"stats"` of its own is credited with.
//
// `moves` falls back to `History.steps` — the length of the line behind the present,
// which is the one thing such a save can still say about how it got there, and the
// number the victory share reported before this existed. `undos` falls back to none:
// an undo leaves no trace in a history, so a save that didn't count them has no way
// to remember, and guessing high would be a worse lie than guessing zero.
let inferredStats = (history: History.t<GameState.t>): Stats.t => {
  moves: History.steps(history),
  undos: 0,
  autoplays: 0,
}

// A save for a history with nothing recorded beside it: what a blob written before
// #289 decodes to, and what any caller holding only a history starts from. The tally
// is inferred as above; the clock isn't inferred at all, because a game whose deal
// nobody timed has no honest time to report (see `Timing.unknown`).
let ofHistory = (history: History.t<GameState.t>): t => {
  history,
  stats: inferredStats(history),
  timing: Timing.unknown,
}

// --- Card codes --------------------------------------------------------------
// A card is two characters: its rank then its suit. Compact, human-legible in a
// stored blob, and trivially reversible. The rank/suit vocabularies are closed,
// so the char maps below are total in one direction and partial (returning
// `None` on any stray character) in the other.

let rankChar = (rank: rank): string =>
  switch rank {
  | Ace => "A"
  | Two => "2"
  | Three => "3"
  | Four => "4"
  | Five => "5"
  | Six => "6"
  | Seven => "7"
  | Eight => "8"
  | Nine => "9"
  | Ten => "T"
  | Jack => "J"
  | Queen => "Q"
  | King => "K"
  }

let suitChar = (suit: suit): string =>
  switch suit {
  | Spades => "S"
  | Hearts => "H"
  | Diamonds => "D"
  | Clubs => "C"
  }

let rankOfChar = (ch: string): option<rank> =>
  switch ch {
  | "A" => Some(Ace)
  | "2" => Some(Two)
  | "3" => Some(Three)
  | "4" => Some(Four)
  | "5" => Some(Five)
  | "6" => Some(Six)
  | "7" => Some(Seven)
  | "8" => Some(Eight)
  | "9" => Some(Nine)
  | "T" => Some(Ten)
  | "J" => Some(Jack)
  | "Q" => Some(Queen)
  | "K" => Some(King)
  | _ => None
  }

let suitOfChar = (ch: string): option<suit> =>
  switch ch {
  | "S" => Some(Spades)
  | "H" => Some(Hearts)
  | "D" => Some(Diamonds)
  | "C" => Some(Clubs)
  | _ => None
  }

let encodeCard = (c: card): string => rankChar(c.rank) ++ suitChar(c.suit)

// A card code is exactly two known characters; anything else (wrong length, a
// stray glyph) is `None`, so a corrupt blob can't smuggle a bogus card through.
let decodeCard = (s: string): option<card> =>
  String.length(s) == 2
    ? switch (rankOfChar(String.charAt(s, 0)), suitOfChar(String.charAt(s, 1))) {
      | (Some(rank), Some(suit)) => Some({suit, rank})
      | _ => None
      }
    : None

// --- Small decode helpers ----------------------------------------------------
// `allSome` collapses an array of optional results into an optional array: it's
// `Some` only when *every* element decoded, so one bad card, column or state
// fails the whole parse (and the save is ignored) rather than yielding a
// partial, broken board.
let allSome = (xs: array<option<'a>>): option<array<'a>> =>
  xs->Array.every(Option.isSome) ? Some(xs->Array.filterMap(x => x)) : None

// --- Encoding to JSON --------------------------------------------------------
// Built straight from the `JSON.t` constructors (no `Encode` helpers) so the
// shape is visible here and matches `decode` field-for-field.

let encodeCards = (cards: array<card>): JSON.t => JSON.Array(
  cards->Array.map(c => JSON.String(encodeCard(c))),
)

let encodeState = (s: GameState.t): JSON.t => JSON.Object(
  Dict.fromArray([
    ("piles", JSON.Array(s.piles->Array.map(encodeCards))),
    ("loose", encodeCards(s.loose)),
  ]),
)

let encodeStats = (s: Stats.t): JSON.t => JSON.Object(
  Dict.fromArray([
    ("moves", JSON.Number(Int.toFloat(s.moves))),
    ("undos", JSON.Number(Int.toFloat(s.undos))),
    ("autoplays", JSON.Number(Int.toFloat(s.autoplays))),
  ]),
)

// The clock (#302), written as only the stamps that exist: an unfinished game has no
// `"wonAt"`, and a game whose clock was never kept writes `{}`. Absence is how this
// format says "not recorded" everywhere else (see the header), so a `null` or a `0`
// standing in for a missing stamp would be a second, worse way to say it — and a `0`
// in particular is a real timestamp (midnight, 1970) that `decode` would believe.
let encodeTiming = (t: Timing.t): JSON.t => JSON.Object(
  Dict.fromArray(
    [
      t.dealtAt->Option.map(ms => ("dealtAt", JSON.Number(ms))),
      t.wonAt->Option.map(ms => ("wonAt", JSON.Number(ms))),
    ]->Array.filterMap(x => x),
  ),
)

// --- Decoding from JSON ------------------------------------------------------

let decodeCards = (json: JSON.t): option<array<card>> =>
  switch json {
  | JSON.Array(items) =>
    items
    ->Array.map(item =>
      switch item {
      | JSON.String(s) => decodeCard(s)
      | _ => None
      }
    )
    ->allSome
  | _ => None
  }

let decodePiles = (json: JSON.t): option<array<array<card>>> =>
  switch json {
  | JSON.Array(cols) => cols->Array.map(decodeCards)->allSome
  | _ => None
  }

let decodeState = (json: JSON.t): option<GameState.t> =>
  switch json {
  | JSON.Object(dict) =>
    switch (
      dict->Dict.get("piles")->Option.flatMap(decodePiles),
      dict->Dict.get("loose")->Option.flatMap(decodeCards),
    ) {
    | (Some(piles), Some(loose)) => Some({GameState.piles, loose})
    | _ => None
    }
  | _ => None
  }

let decodeStates = (json: JSON.t): option<array<GameState.t>> =>
  switch json {
  | JSON.Array(items) => items->Array.map(decodeState)->allSome
  | _ => None
  }

// A counter is a whole number and nothing else — a JSON string, a float, a missing
// field all read as `None`, which fails the `stats` object and so the whole save.
// That's the same all-or-nothing stance the card and pile decoders take: `stats`
// being *absent* is a supported shape (an older blob — see `decode`), but `stats`
// being *present and malformed* means this isn't a blob we wrote, and half-reading
// a stranger's JSON is how a broken board gets built.
let decodeCount = (json: JSON.t): option<int> =>
  switch json {
  | JSON.Number(n) if n >= 0.0 && n == Math.trunc(n) => Some(Int.fromFloat(n))
  | _ => None
  }

// `autoplays` (#291) is read the way the whole `stats` object is (see `decode`): a
// *missing* one is a save written before the counter existed and reads as none — the
// truthful answer, since a game played before autoplay could be reached for can't
// have used it — while a present-but-malformed one fails the object like any other
// field. Absence and nonsense stay different things.
let decodeAutoplays = (dict: Dict.t<JSON.t>): option<int> =>
  switch dict->Dict.get("autoplays") {
  | None => Some(0)
  | Some(json) => decodeCount(json)
  }

let decodeStats = (json: JSON.t): option<Stats.t> =>
  switch json {
  | JSON.Object(dict) =>
    switch (
      dict->Dict.get("moves")->Option.flatMap(decodeCount),
      dict->Dict.get("undos")->Option.flatMap(decodeCount),
      decodeAutoplays(dict),
    ) {
    | (Some(moves), Some(undos), Some(autoplays)) => Some({Stats.moves, undos, autoplays})
    | _ => None
    }
  | _ => None
  }

// A stamp on the clock (#302): milliseconds since the epoch, so a whole number isn't
// required (fractional milliseconds are a legal `Date.now()` in some browsers) but a
// finite, non-negative one is — a game dealt before the epoch is a blob we didn't
// write. Absent is a supported shape and reads as "not recorded"; present-and-not-a-
// timestamp fails the object, like every other malformed field here.
let decodeStamp = (dict: Dict.t<JSON.t>, key: string): option<option<float>> =>
  switch dict->Dict.get(key) {
  | None => Some(None)
  | Some(JSON.Number(ms)) if ms >= 0.0 && Float.isFinite(ms) => Some(Some(ms))
  | Some(_) => None
  }

let decodeTiming = (json: JSON.t): option<Timing.t> =>
  switch json {
  | JSON.Object(dict) =>
    switch (decodeStamp(dict, "dealtAt"), decodeStamp(dict, "wonAt")) {
    | (Some(dealtAt), Some(wonAt)) => Some({Timing.dealtAt, wonAt})
    | _ => None
    }
  | _ => None
  }

// --- The public seam ---------------------------------------------------------

// Serialize a saved game — the whole undo/redo history, and the tally beside it —
// to a storable string.
let encode = (s: t): string =>
  JSON.stringify(
    JSON.Object(
      Dict.fromArray([
        ("v", JSON.Number(Int.toFloat(version))),
        ("past", JSON.Array(s.history.past->Array.map(encodeState))),
        ("present", encodeState(s.history.present)),
        ("future", JSON.Array(s.history.future->Array.map(encodeState))),
        ("stats", encodeStats(s.stats)),
        ("timing", encodeTiming(s.timing)),
      ]),
    ),
  )

// Parse a stored string back into a saved game, or `None` when it can't be trusted:
// not valid JSON, the wrong (or missing) format version, or any structural
// mismatch — a card that isn't a real card, a field of the wrong JSON shape. The
// caller treats `None` as "no saved game" and deals fresh, so a corrupt or
// outdated blob degrades to a new board instead of an error (#177).
//
// A blob with no `"stats"` at all is *not* one of those failures: it's a save
// written before #289, and it decodes to a real game whose tally is inferred by
// `inferredStats`. Nor is one with no `"timing"` (#302) — that's a save from before
// the clock existed, and it decodes to a game with no time to report. That's the
// whole reason the version didn't move.
let decode = (raw: string): option<t> => {
  let parsed = try Some(JSON.parseOrThrow(raw)) catch {
  | _ => None
  }
  switch parsed {
  | Some(JSON.Object(dict)) =>
    switch dict->Dict.get("v") {
    | Some(JSON.Number(v)) if v == Int.toFloat(version) =>
      switch (
        dict->Dict.get("past")->Option.flatMap(decodeStates),
        dict->Dict.get("present")->Option.flatMap(decodeState),
        dict->Dict.get("future")->Option.flatMap(decodeStates),
      ) {
      | (Some(past), Some(present), Some(future)) =>
        let history = {History.past, present, future}
        let stats = switch dict->Dict.get("stats") {
        | None => Some(inferredStats(history))
        | Some(json) => decodeStats(json)
        }
        let timing = switch dict->Dict.get("timing") {
        | None => Some(Timing.unknown)
        | Some(json) => decodeTiming(json)
        }
        switch (stats, timing) {
        | (Some(stats), Some(timing)) => Some({history, stats, timing})
        | _ => None
        }
      | _ => None
      }
    | _ => None
    }
  | _ => None
  }
}
