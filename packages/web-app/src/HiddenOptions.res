// Hidden settings, and the tap gesture that reveals them.
//
// Some settings aren't ready to be found yet — "Wiggle Waggle" (#235) is the first
// — but they still have to be reachable on the device that's being tested, in the
// installed PWA, where there's no address bar to add a query parameter to. So they
// hide behind the same gesture Android uses for its developer options: tap the
// screen's title enough times and they appear.
//
// The target is the big green `menu-title` at the head of the **Settings** screen.
// The other two screens (the main menu's "Pip", the Debug screen's "Debug") render
// that same element, so "only Settings unlocks" is an invariant this module can't
// enforce on its own — the caller decides which taps to feed in. See `Main`'s
// `SettingsTitleTapped`, which drops any tap arriving while another screen shows.
//
// Once revealed it *stays* revealed, persisted like any other preference: nobody
// wants to tap ten times a day, and a switch you can turn on but can't find again
// to turn off is worse than one that was never hidden. The tap count itself is
// session state, held in the chrome model and reset on the way out of Settings, so
// a half-finished run doesn't lie in wait to be completed hours later.
//
// Deliberately unfeedbacked for now: ten silent taps, then the rows appear. The
// "you are N steps away" countdown Android shows is a follow-up.

// How many taps on the Settings title reveal the hidden options.
let tapsToReveal = 10

// The reveal state: whether the hidden options are showing, and how far into a
// run of taps we are. `taps` is meaningless once `revealed` — the counter stops.
type t = {
  revealed: bool,
  taps: int,
}

// The opening state, seeded from the persisted reveal flag. A fresh run of taps.
let initial = (~revealed) => {revealed, taps: 0}

// Count one tap on the Settings title. The `taps`th one flips the reveal on, and
// from then on taps are inert (`state` is returned unchanged, so the chrome loop
// can skip the re-render — see `Html.mount`'s physical-equality check).
let tap = state =>
  if state.revealed {
    state
  } else {
    let taps = state.taps + 1
    taps >= tapsToReveal ? {revealed: true, taps: 0} : {...state, taps}
  }

// Abandon a part-finished run — the way out of the Settings screen. Already-clear
// state is returned as-is, again so an unchanged model skips the re-render.
let reset = state => state.taps == 0 ? state : {...state, taps: 0}

// Whether this tap is the one that just revealed the options, given the state
// before it. What the caller persists (and, later, what a reveal animation would
// key off) — a plain `revealed` test would re-persist on every subsequent tap.
let justRevealed = (~before: t, ~after: t) => after.revealed && !before.revealed
