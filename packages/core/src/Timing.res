// How long a game took: `wonAt - dealtAt`, two readings off the wall clock. **Not a
// measure of attention** — a game left open over lunch counts every one of those
// minutes, because a play clock would have to decide what idleness is.
//
// A sibling of `Stats`, not a field in it: the tally is pure counters constructible in
// a test, while these are timestamps whose origin is impure (the caller passes
// `Date.now()`; this module never reads a clock).
//
// Both stamps are optional, and the absence carries information rather than being
// defensive typing: a save predating stamps has neither, an in-progress game has a
// deal but no win. No stamps, no time on the panel.

// Milliseconds since the Unix epoch.
type t = {
  dealtAt: option<float>, // when this deal was built
  wonAt: option<float>, // when the win landed
}

let unknown: t = {dealtAt: None, wonAt: None}

// A New Game and a Restart each start their own clock, as each starts a fresh `zero`.
let dealt = (~at: float): t => {dealtAt: Some(at), wonAt: None}

// Stamped once. A victory resumed from a save raises its overlay again on every
// reload, so re-stamping would turn "how long the game took" into "how long ago you
// played it" — the number would grow each time you came back. Only `unwon` clears it.
let won = (t: t, ~at: float): t =>
  switch t.wonAt {
  | Some(_) => t
  | None => {...t, wonAt: Some(at)}
  }

// Undoing out of a victory drops the stamp; winning again stamps afresh, so the time
// then covers the whole game including the detour — the stance `Stats.undo` takes too.
let unwon = (t: t): t => {...t, wonAt: None}

// `None` when either stamp is missing, and also when the win reads *earlier* than the
// deal: that's not a negative game but two clocks, since a `?state=` link carries the
// sender's `dealtAt` and the receiver's clock needn't agree. Better than "-3:07".
let elapsed = (t: t): option<float> =>
  switch (t.dealtAt, t.wonAt) {
  | (Some(from), Some(to_)) if to_ >= from => Some(to_ -. from)
  | _ => None
  }

// `4:07`, and `1:02:33` past the hour. Seconds are floored the way a stopwatch shows
// them: a game 3.9 seconds old has not been going for 4 seconds.
let label = (ms: float): string => {
  let total = Math.floor(ms /. 1000.)->Float.toInt
  let seconds = mod(total, 60)
  let minutes = mod(total / 60, 60)
  let hours = total / 3600
  let pad = (n: int): string => n < 10 ? "0" ++ Int.toString(n) : Int.toString(n)
  hours > 0
    ? Int.toString(hours) ++ ":" ++ pad(minutes) ++ ":" ++ pad(seconds)
    : Int.toString(minutes) ++ ":" ++ pad(seconds)
}

// The one call the victory panel makes, so it needn't compose the two itself.
let summary = (t: t): option<string> => elapsed(t)->Option.map(label)
