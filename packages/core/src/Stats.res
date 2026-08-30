// The victory screen's numbers. A sibling of `GameState` and `History` rather than a
// field in either: a counter inside the state would make two identical boards unequal,
// and a counter inside the history is one `undo` would have to lie about.
//
// **Every counter is monotonic**, which is the rule the rest of the app leans on. So
// `moves` is not `History.steps` — they agree until the first undo, then diverge into
// "the line you ended on" and "the work getting there" — and undoing back past the
// solver's moves doesn't restore the Share button. Only a new board does that, by
// starting a fresh `zero`.
type t = {
  moves: int, // played; undo never subtracts, redo adds
  undos: int, // times the player stepped back
  autoplays: int, // times the solver was *reached for*, whatever it then played
}

let zero: t = {moves: 0, undos: 0, autoplays: 0}

let move = (s: t): t => {...s, moves: s.moves + 1}
let undo = (s: t): t => {...s, undos: s.undos + 1}
let autoplay = (s: t): t => {...s, autoplays: s.autoplays + 1}

// Named apart so a call site reads as what happened, not as what it counts as.
let redo = move

// What the Share button asks: a win the player didn't play isn't theirs to boast about.
let usedAutoplay = (s: t): bool => s.autoplays > 0

// Pluralisation lives here because two surfaces say these counts — the win panel and
// the shared victory message.
let moveLabel = (n: int): string => Int.toString(n) ++ (n == 1 ? " move" : " moves")
let undoLabel = (n: int): string => Int.toString(n) ++ (n == 1 ? " undo" : " undos")
let autoplayLabel = (n: int): string => Int.toString(n) ++ (n == 1 ? " autoplay" : " autoplays")

// Moves and undos show even at zero — "0 undos" is the boast. Autoplays invert that:
// zero is a game's default state, so that count appears only once it isn't.
let summary = (s: t): string =>
  moveLabel(s.moves) ++
  " · " ++
  undoLabel(s.undos) ++ (s.autoplays > 0 ? " · " ++ autoplayLabel(s.autoplays) : "")
