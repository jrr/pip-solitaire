// What a Hint press found, said in a line at the bottom-left of the screen while the
// board shows the move: a toast, in the look of a status caption rather than a panel,
// because it asks nothing of the player and goes away on its own.
//
// `Thinking` stays up for as long as the search runs; every other news fades once it
// has been read (`fades`). The fading is the driver's to time (`Main`), and `leaving`
// is the toast on its way out.

%%raw(`import "./HintToast.css"`)

type news =
  | Thinking
  // A line, `moves` long from the board on the table, its first move being shown.
  | Found({moves: int})
  // A line with no moves in it: the board finishes from here.
  | Finishable
  | Unwinnable
  // The wait ran out with the search still going. A second press carries on with the
  // same search rather than starting over, which is why the words offer one.
  | OutOfPatience
  | OutOfRoom
  | Unreadable

type props = {news: news, leaving: bool}

let fades = (news: news) => news != Thinking

let plural = (n: int, word: string) => `${Int.toString(n)} ${word}${n == 1 ? "" : "s"}`

let text = (news: news): string =>
  switch news {
  | Thinking => "Looking for a solution…"
  | Found({moves}) => `Solution found · ${plural(moves, "move")} to go`
  | Finishable => "Solved · the board can finish from here"
  | Unwinnable => "No solution from here · try undoing"
  | OutOfPatience => "No solution found yet · press Hint to keep looking"
  | OutOfRoom => "The solver ran out of memory before finding a solution"
  | Unreadable => "The solver can't read this board"
  }

let make = ({news, leaving}) =>
  <div
    id="hint-toast"
    className={`hint-toast${news == Thinking ? " hint-toast--thinking" : ""}${leaving
        ? " hint-toast--leaving"
        : ""}`}
    role="status"
  >
    {Html.string(text(news))}
  </div>
