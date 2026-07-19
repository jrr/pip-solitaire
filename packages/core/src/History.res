// Undo/redo as a stack of prior states (#85) — the payoff `core`'s immutable
// `GameState` buys. Because each state is a value of its own, keeping the states
// we've passed through and *popping* one is undo; there's no inverse-move to
// compute, no diff to replay. The ROADMAP calls this out directly as the
// load-bearing principle: "keep a stack of prior `state` values; undo is a pop."
//
// The shape is the classic past / present / future zipper:
//   - `past`    — the states behind the present, oldest first; the top is where
//                 `undo` steps back to.
//   - `present` — the current state, what a driver renders.
//   - `future`  — the states `undo` has stepped out of, ready for `redo` to
//                 replay, nearest-first.
//
// It's generic in the value it carries (`'a`), but built for `GameState.t`: the
// drivers keep a `History.t<GameState.t>` and swap it for the value these pure
// functions return, exactly as they adopt a fresh `GameState` from the reducer.
// Nothing here mutates its input.

type t<'a> = {
  past: array<'a>,
  present: 'a,
  future: array<'a>,
}

// A history holding just the opening state — nothing to undo or redo yet. This is
// what a driver seeds from the initial `GameState` (or a `?state=` scenario) and
// what a fresh deal resets to.
let make = (present: 'a): t<'a> => {past: [], present, future: []}

// The current value — what a driver renders each frame.
let present = (h: t<'a>): 'a => h.present

// Is there a prior state to step back to? A driver enables its Undo control on
// this.
let canUndo = (h: t<'a>): bool => Array.length(h.past) > 0

// Is there an undone state to replay forward? A driver enables its Redo control
// on this.
let canRedo = (h: t<'a>): bool => Array.length(h.future) > 0

// Record a new present: the old present is pushed onto `past` and `future` is
// cleared. Clearing `future` is the standard linear-undo behaviour — a fresh move
// after an undo abandons the branch you'd undone into, since it can no longer be
// reached by replaying forward. This is the only way history grows, and a driver
// calls it once per *accepted* state change (a rejected reducer action never
// reaches here), so only real changes are ever undoable.
let record = (h: t<'a>, next: 'a): t<'a> => {
  past: Array.concat(h.past, [h.present]),
  present: next,
  future: [],
}

// Step one state back: the top of `past` becomes the present, and the state we
// leave is pushed onto the front of `future` so `redo` can replay it. Undoing
// past the very first state is a no-op — with an empty `past` the history is
// returned unchanged.
let undo = (h: t<'a>): t<'a> =>
  switch h.past->Array.get(Array.length(h.past) - 1) {
  | None => h
  | Some(prev) => {
      past: h.past->Array.slice(~start=0, ~end=Array.length(h.past) - 1),
      present: prev,
      future: Array.concat([h.present], h.future),
    }
  }

// Step one state forward through a branch `undo` left in `future`: its front
// becomes the present, and the state we leave returns to the top of `past`.
// Redoing with nothing undone (an empty `future`) is a no-op.
let redo = (h: t<'a>): t<'a> =>
  switch h.future->Array.get(0) {
  | None => h
  | Some(next) => {
      past: Array.concat(h.past, [h.present]),
      present: next,
      future: h.future->Array.slice(~start=1, ~end=Array.length(h.future)),
    }
  }

// Apply a reducer action (#82) to the present state, recording history only when
// the move is *accepted*: an `Ok` result becomes the new present (the old one
// pushed onto `past`, `future` cleared); a rejected `Error` returns the history
// unchanged, so a bounced move is never undoable. Keeps the reducer itself pure —
// this only threads its result through `record`.
//
// Safe auto-collect (#125) is driver behaviour layered *on top* of the reducer,
// so a driver that sweeps cards home records the settled state directly with
// `record` (grouping the move and the collection it triggered as one undoable
// unit); this convenience is the plain, collect-free path the tests drive.
let apply = (~game: Game.t, h: t<GameState.t>, action: Reducer.action): result<
  t<GameState.t>,
  Reducer.moveError,
> =>
  switch Reducer.reduce(~game, h.present, action) {
  | Ok(next) => Ok(record(h, next))
  | Error(e) => Error(e)
  }
