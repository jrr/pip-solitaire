// How much play a game has taken: how many moves the player has made, how
// many times they've reached for Undo, and how many times they've handed the game
// to the solver. The numbers the victory screen reports, and the only things
// about a game that aren't a card position.
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
//
// `autoplays` is the third of those, and it counts the *reaching* rather than
// the playing: one `autoplay` command is one autoplay, however many moves the solver
// went on to play. Those moves are moves like any other — they're recorded steps, and
// the tally says so — so the two numbers answer different questions: "how long was
// this game" and "how much of it was mine".
//
// It's the same monotonic rule as the other two, which is what the victory screen
// leans on: a game that has been autoplayed *stays* autoplayed. Undoing back past the
// solver's moves doesn't un-ring the bell, so the Share button stays away until the
// board itself is replaced (a New Game or a Restart, both of which start a fresh
// tally at `zero`).
type t = {
  moves: int, // moves played; undo never subtracts, redo adds
  undos: int, // times the player stepped back
  autoplays: int, // times the player handed the game to the solver
}

// A game not yet played: what a fresh deal (and every New Game / Restart) starts on.
let zero: t = {moves: 0, undos: 0, autoplays: 0}

let move = (s: t): t => {...s, moves: s.moves + 1}
let undo = (s: t): t => {...s, undos: s.undos + 1}
let autoplay = (s: t): t => {...s, autoplays: s.autoplays + 1}

// A redo *is* a move made, by the rule above — named separately so the call site
// reads as what happened rather than as what it's counted as.
let redo = move

// Has the solver played any part of this game? The question the victory
// screen's Share button asks — a win the player didn't play isn't theirs to boast
// about — written here rather than as a `> 0` at each call site, so "was this
// autoplayed" has one answer.
let usedAutoplay = (s: t): bool => s.autoplays > 0

// --- Saying the numbers out loud ---------------------------------------------
// Pluralisation in one place, because two different surfaces say these counts: the
// win panel (`TableScene`) and the shared victory message (`ShareLink`).

let moveLabel = (n: int): string => Int.toString(n) ++ (n == 1 ? " move" : " moves")
let undoLabel = (n: int): string => Int.toString(n) ++ (n == 1 ? " undo" : " undos")
let autoplayLabel = (n: int): string => Int.toString(n) ++ (n == 1 ? " autoplay" : " autoplays")

// The one-line summary the win overlay shows: both numbers, and both of them even
// at zero. A clean run saying "0 undos" is the boast — leaving it out would make
// the absence of a number ambiguous with the absence of the feature.
//
// The autoplays are the exception, and for the same reason inverted: zero of them is
// the *default* state of a game, so "0 autoplays" would be a line about a feature
// that wasn't used rather than a number earned. It appears only once the solver has
// been reached for — at which point it's the most interesting thing on the line.
let summary = (s: t): string =>
  moveLabel(s.moves) ++
  " · " ++
  undoLabel(s.undos) ++ (s.autoplays > 0 ? " · " ++ autoplayLabel(s.autoplays) : "")
