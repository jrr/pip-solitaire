// Hidden settings, and the tap gesture that reveals them.
//
// Some settings aren't ready to be found yet — "Wiggle Waggle" is the first
// — but they still have to be reachable on the device that's being tested, in the
// installed PWA, where there's no address bar to add a query parameter to. So they
// hide behind the same gesture Android uses for its developer options: tap the
// screen's title enough times and they appear.
//
// The target is the big green `menu-title` at the head of the **Settings** screen.
// The other two screens (the main menu's "Pip", the Debug screen's "Debug") render
// that same element, so "only Settings unlocks" is an invariant this module can't
// enforce on its own — the caller decides which taps to feed in. `Main` drops any tap
// arriving while another screen shows, on its way into the Settings screen's `update`.
//
// The gesture is a *toggle*: every run of ten flips the reveal, so ten more taps
// put the rows away again. The reveal is persisted like any other preference —
// nobody wants to tap ten times a day — and the tap count itself is session state,
// held in the Settings screen's own model and reset on the way out of that screen, so
// a half-finished run doesn't lie in wait to be completed hours later.
//
// Re-hiding deliberately does *not* turn the hidden settings off: whatever was
// switched on stays on and keeps running. So a device can sit with Wiggle Waggle
// jostling the board and no switch on screen to stop it, and the only way back to
// that switch is another ten taps. That's the accepted cost of being able to tidy
// the menu without disturbing what's under test — worth knowing before assuming a
// hidden row means an inactive setting.
//
// Deliberately unfeedbacked for now: ten silent taps, then the rows appear (or go).
// The "you are N steps away" countdown Android shows is a follow-up.

// How many taps on the Settings title flip the reveal, in either direction.
let tapsToReveal = 10

// The reveal state: whether the hidden options are showing, and how far into a
// run of taps we are.
type t = {
  revealed: bool,
  taps: int,
}

// The opening state, seeded from the persisted reveal flag. A fresh run of taps.
let initial = (~revealed) => {revealed, taps: 0}

// Count one tap on the Settings title. Every `tapsToReveal`th one flips the reveal
// and starts the count over, so the gesture works the same in both directions —
// hiding is just revealing again.
let tap = state => {
  let taps = state.taps + 1
  taps >= tapsToReveal ? {revealed: !state.revealed, taps: 0} : {...state, taps}
}

// Abandon a part-finished run — the way out of the Settings screen. Already-clear
// state is returned physically unchanged, so the chrome loop can skip the
// re-render (see `Html.mount`'s equality check).
let reset = state => state.taps == 0 ? state : {...state, taps: 0}

// Whether this tap flipped the reveal, given the state before it. What the caller
// persists on — the other nine taps in a run change nothing worth storing.
let revealChanged = (~before: t, ~after: t) => before.revealed != after.revealed
