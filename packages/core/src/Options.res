// A driver *preference* record (#125): the flags that tune how a driver behaves
// *around* the pure reducer — deliberately not board state. This is the toggle
// seam a future settings screen (#112) flips: a single record both drivers read,
// so wiring a UI control later sets one field here and nothing else changes.
//
// It is **not** `GameState`. Auto-collect is a preference, not "where cards rest",
// so it stays out of the immutable snapshot (which stays purely about the board)
// and is threaded into the drivers' post-move step instead.
//
// `autoCollect` (#125): after each accepted move, automatically send every card
// that is *safe* to play (`Reducer.isSafeToCollect`) home to its foundation, so a
// player never has to click the obvious ones — the behaviour most FreeCell apps
// have on by default. Gated entirely by this flag: `autoCollect: false` is an
// exact no-op, the board left exactly as the reducer returned it.
type t = {autoCollect: bool}

// The shipped default: auto-collect on. Both drivers read this today; no UI
// control is exposed yet, so this is the only value in play until a settings
// toggle (#112) is wired to set the field.
let default = {autoCollect: true}
