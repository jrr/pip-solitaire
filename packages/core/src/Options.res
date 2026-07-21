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
//
// `allowColumnReorder` (#159): a **house rule** for our variant — may the player
// pull a cascade column out and drop it into the gap between two others, the rest
// sliding over (a `Reducer.MoveColumn`)? Strict FreeCell doesn't sanction moving
// whole columns around, so it's opt-in, defaulting *on* for our game with no UI
// toggle surfaced yet. Gated exactly like `autoCollect`: when off, a driver never
// dispatches the reorder, so it's an exact no-op.
type t = {autoCollect: bool, allowColumnReorder: bool}

// The shipped default: auto-collect on and column reordering allowed (our
// variant's house rule). Both drivers read this today; no UI control is exposed
// yet, so this is the only value in play until a settings toggle (#112) is wired
// to set the fields.
let default = {autoCollect: true, allowColumnReorder: true}
