// How much play a game has taken (#289): how many moves the player has made, and
// how many times they've reached for Undo. The two numbers the victory screen
// reports, and the only things about a game that aren't a card position.
//
// It lives *beside* the game rather than in it, and that's the point. `GameState.t`
// is where every card rests and nothing else — a pure position, which is what makes
// it comparable, replayable and cheap to record — and `History.t` is the line of
// play over those positions. Neither has room for "how much work was this" without
// becoming a different kind of thing: a counter inside the history is a counter
// `undo` would have to lie about (see `History.steps`), and a counter inside the
// state would make two identical boards unequal. So the tally is a sibling of the
// history, carried alongside it in the save envelope (`SaveState`) and nowhere else.
//
// **The counting rules** are the issue's, and they're the self-consistent set:
//
//   - playing a move counts as a move;
//   - undoing does *not* count as a move — it counts as an undo;
//   - redoing counts as a move again, because the position it lands on was reached
//     by a move the player chose to make (twice, now).
//
// So `moves` only ever goes up, and is deliberately *not* `History.steps` — the
// length of the line currently behind the present. The two agree exactly until the
// first undo and diverge after it: `steps` describes the line you ended on, this
// describes the work you did getting there. A player who plays ten moves, undoes
// five and replays five different ones has a ten-step line and twenty moves made,
// and both numbers are true about different questions.

type t = {
  moves: int, // moves played; undo never subtracts, redo adds
  undos: int, // times the player stepped back
}

// A game not yet played: what a fresh deal (and every New Game / Restart) starts on.
let zero: t = {moves: 0, undos: 0}

let move = (s: t): t => {...s, moves: s.moves + 1}
let undo = (s: t): t => {...s, undos: s.undos + 1}

// A redo *is* a move made, by the rule above — named separately so the call site
// reads as what happened rather than as what it's counted as.
let redo = move

// --- Saying the numbers out loud ---------------------------------------------
// Pluralisation in one place, because two different surfaces say these counts: the
// win panel (`TableScene`) and the shared victory message (`ShareLink`).

let moveLabel = (n: int): string => Int.toString(n) ++ (n == 1 ? " move" : " moves")
let undoLabel = (n: int): string => Int.toString(n) ++ (n == 1 ? " undo" : " undos")

// The one-line summary the win overlay shows: both numbers, and both of them even
// at zero. A clean run saying "0 undos" is the boast — leaving it out would make
// the absence of a number ambiguous with the absence of the feature.
let summary = (s: t): string => moveLabel(s.moves) ++ " · " ++ undoLabel(s.undos)
