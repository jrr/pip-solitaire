// How long a game took: when the deal hit the table, and when the win
// landed. The victory screen's third number, beside the moves and the undos.
//
// It's the deliberately simple thing the issue asked for — `wonAt - dealtAt`, two
// readings off the wall clock — and it is *not* a measure of attention. A game left
// open on a second tab over lunch, or resumed from `localStorage` the next morning,
// counts every one of those minutes, because the only alternative is a play-clock
// that has to decide what idleness is, and that's a different (and much larger)
// feature. What this reports is honestly named: elapsed time between two events.
//
// A sibling of `Stats` rather than another field in it, and for the same reason
// `Stats` is a sibling of `History`: the two answer to different rules. The tally is
// a set of monotonic counters over things the player *did*, pure and replayable —
// a value you can construct in a test without a clock. These are two timestamps
// whose origin is impure (`Date.now()`, supplied by the caller — this module never
// reads a clock itself) and whose only invariant is that one comes after the other.
// Mixing them would give `Stats.zero` a meaningless "dealt at the epoch" and force
// every counting rule to explain itself around two fields it has nothing to say
// about. They ride side by side in the save envelope (`SaveState`) instead.
//
// Both stamps are optional, and that carries real information rather than being
// defensive typing: a save written before this existed has neither (its game began
// at a time nobody wrote down), and an in-progress game has a deal but no win yet.
// No stamps, no time on the panel — which is exactly right, since the alternative
// would be inventing one.

// The clock either side of a game. Milliseconds since the Unix epoch, as
// `Date.now()` gives them.
type t = {
  dealtAt: option<float>, // when this deal was built
  wonAt: option<float>, // when the win landed
}

// A game whose clock nobody kept: what a save written before `timing` existed
// decodes to, and
// the starting point for any board that isn't being dealt right now.
let unknown: t = {dealtAt: None, wonAt: None}

// A deal hitting the table at `at` — the opening deal, a New Game, a Restart. Every
// one of those is a new game in every sense (they start a fresh `Stats.zero` too),
// so each starts its own clock.
let dealt = (~at: float): t => {dealtAt: Some(at), wonAt: None}

// The win landing at `at` — stamped once. A victory *resumed* from a save
// raises its overlay again on every reload, and re-stamping there would quietly turn
// "how long the game took" into "how long ago you played it": the number would grow
// each time you came back to a board you'd already won. So an existing stamp wins,
// and the only thing that clears one is stepping back out of the victory (`unwon`).
let won = (t: t, ~at: float): t =>
  switch t.wonAt {
  | Some(_) => t
  | None => {...t, wonAt: Some(at)}
  }

// Undo out of a victory: the game isn't won any more, so the win it was won at
// isn't a fact about it any more either. Playing on and winning again stamps afresh,
// and the time then covers the whole game — including the detour — which is the same
// stance the tally takes (`Stats.undo` never gives a move back).
let unwon = (t: t): t => {...t, wonAt: None}

// How long the game took, in milliseconds, when both ends are known. `None` when
// either stamp is missing — and also when the win reads as *earlier* than the deal,
// which isn't a game that took negative time but a pair of stamps from two different
// clocks: a `?state=` link shared across devices carries the sender's `dealtAt`, and
// the receiver's clock needn't agree with it. Saying nothing beats saying "-3:07".
let elapsed = (t: t): option<float> =>
  switch (t.dealtAt, t.wonAt) {
  | (Some(from), Some(to_)) if to_ >= from => Some(to_ -. from)
  | _ => None
  }

// An elapsed time as a clock reads it: `4:07`, and `1:02:33` once a game has run past
// the hour. Seconds are *floored*, the way a stopwatch shows them — a game 3.9
// seconds old has not been going for 4 seconds — and the fields below the leading one
// are zero-padded so the digits line up as a duration rather than as three numbers.
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

// What the victory screen shows, or `None` when this game has no time to report —
// the one call the panel makes, so "is there a time, and how does it read" is
// answered in one place rather than as an `Option.map` at the call site.
let summary = (t: t): option<string> => elapsed(t)->Option.map(label)
