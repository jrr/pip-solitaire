// How much play a game has taken: moves made, undos reached for, times the game was
// handed to the solver. The victory screen's numbers.
//
// A sibling of `GameState` and `History`, not a field in either: a counter inside the
// state would make two identical boards unequal, and a counter inside the history is
// one `undo` would have to lie about. It rides alongside them in the save envelope
// (`SaveState`) and nowhere else.
//
// Every counter is monotonic, which is the rule the rest of the app leans on:
//
//   - playing a move counts as a move; undoing counts as an undo, and subtracts
//     nothing; redoing counts as a move again.
//   - so `moves` is *not* `History.steps`. They agree until the first undo, then
//     diverge: `steps` is the line you ended on, `moves` is the work getting there.
//   - `autoplays` counts the reaching, not the playing — one `autoplay` command is
//     one autoplay however many moves the solver then played, and those moves are
//     also recorded steps.
//
// Monotonicity is why undoing back past the solver's moves doesn't restore the Share
// button: only a new board (New Game, Restart — both start a fresh `zero`) does.
type t = {
  moves: int, // moves played; undo never subtracts, redo adds
  undos: int, // times the player stepped back
  autoplays: int, // times the player handed the game to the solver
}

let zero: t = {moves: 0, undos: 0, autoplays: 0}

let move = (s: t): t => {...s, moves: s.moves + 1}
let undo = (s: t): t => {...s, undos: s.undos + 1}
let autoplay = (s: t): t => {...s, autoplays: s.autoplays + 1}

// Named separately so the call site reads as what happened, not as what it counts as.
let redo = move

// What the victory screen's Share button asks: a win the player didn't play isn't
// theirs to boast about.
let usedAutoplay = (s: t): bool => s.autoplays > 0

// Pluralisation lives here because two surfaces say these counts: the win panel
// (`TableScene`) and the shared victory message (`ShareLink`).
let moveLabel = (n: int): string => Int.toString(n) ++ (n == 1 ? " move" : " moves")
let undoLabel = (n: int): string => Int.toString(n) ++ (n == 1 ? " undo" : " undos")
let autoplayLabel = (n: int): string => Int.toString(n) ++ (n == 1 ? " autoplay" : " autoplays")

// Moves and undos show even at zero — "0 undos" is the boast, and omitting it would
// make an absent number ambiguous with an absent feature. Autoplays invert that: zero
// is a game's default state, so the count appears only once the solver was reached for.
let summary = (s: t): string =>
  moveLabel(s.moves) ++
  " · " ++
  undoLabel(s.undos) ++ (s.autoplays > 0 ? " · " ++ autoplayLabel(s.autoplays) : "")
