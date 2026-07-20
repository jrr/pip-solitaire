// Undo/redo as a stack of prior states (#85) — the payoff immutability buys.
// Now that the source of truth for a game is an immutable `GameState.t` owned by
// `core`, undo is just a pop: keep the states you've passed through and step back
// and forth over them.
//
// The classic past/present/future *zipper*: `past` holds the states behind the
// current one (oldest first, so its last element is the one undo returns to),
// `present` is the live state, and `future` holds the states undo has stepped back
// over (nearest first, so its first element is the one redo returns to). Every
// function here is pure — it returns a fresh value and never mutates its input —
// so a driver simply adopts the returned history, exactly as it adopts a reducer
// result.
//
// It's deliberately generic over the value it wraps (`t<'a>`), not tied to
// `GameState.t`: the zipper has nothing to say about *what* a state is, so keeping
// it abstract makes it trivially testable and reusable. The drivers instantiate it
// at `GameState.t` and decide *when* to record — the reducer stays pure, and only
// an accepted `Reducer.reduce` result is ever handed to `record`, so a rejected
// move is never undoable (there was no state change to undo).
//
// There is nothing here that a "game over" could snag on: a won `GameState` is
// just another value in `past`/`present`, so undoing back out of a victory is the
// same pop as any other (#85 follow-up) — the state model imposes no one-way door.

type t<'a> = {
  past: array<'a>, // states behind the present, oldest first
  present: 'a, // the live state
  future: array<'a>, // states undone away, nearest first (redo replays these)
}

// A fresh history holding just `present` — nothing to undo or redo yet.
let make = (present: 'a): t<'a> => {past: [], present, future: []}

// The live state.
let present = (h: t<'a>): 'a => h.present

// Is there a prior state to step back to / a stepped-over state to replay?
let canUndo = (h: t<'a>): bool => Array.length(h.past) > 0
let canRedo = (h: t<'a>): bool => Array.length(h.future) > 0

// Record a new present reached from the current one: the old present is pushed
// onto `past`, `next` becomes the present, and `future` is cleared — a fresh
// action after an undo abandons the redo branch, the standard undo-stack
// behaviour. Callers hand this only *accepted* transitions (an `Ok` from
// `Reducer.reduce`), so a rejected move records nothing and stays un-undoable.
let record = (h: t<'a>, next: 'a): t<'a> => {
  past: Array.concat(h.past, [h.present]),
  present: next,
  future: [],
}

// Step back one state: the last of `past` becomes the present, and the state we
// leave is pushed to the front of `future` so `redo` can replay it. A no-op (the
// history unchanged) when there's nothing behind the present.
let undo = (h: t<'a>): t<'a> =>
  switch h.past->Array.get(Array.length(h.past) - 1) {
  | None => h
  | Some(prev) => {
      past: h.past->Array.slice(~start=0, ~end=Array.length(h.past) - 1),
      present: prev,
      future: Array.concat([h.present], h.future),
    }
  }

// Step forward one state: the first of `future` becomes the present, and the
// state we leave is pushed onto `past`. A no-op when there's nothing ahead.
let redo = (h: t<'a>): t<'a> =>
  switch h.future->Array.get(0) {
  | None => h
  | Some(next) => {
      past: Array.concat(h.past, [h.present]),
      present: next,
      future: h.future->Array.slice(~start=1, ~end=Array.length(h.future)),
    }
  }
