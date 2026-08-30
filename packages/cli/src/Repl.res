// The CLI's driver loop: everything a terminal needs around a session, and nothing a
// session needs itself. The *thinking* moved to `core`'s `Session` — which game
// is in play, the history to undo over, the tallies and the clock beside it, the
// post-move auto-collect, and running a board command against all of it. Both front
// ends go through that one implementation now, which is what stops the next `Stats` or
// `Timing` from being wired into only one of them.
//
// What's left here is the part that is genuinely a terminal's:
//
//   - the *chrome* verbs — `help`, `games`, `clear`, `quit`, `set` — which a terminal
//     answers in a terminal's vocabulary (its own help text, its own scrollback), and
//     `deal`, which here replaces a record where in a browser it rebuilds a DOM board.
//   - the "deal a game first" state. A web app always has cards on the table; a
//     terminal starts empty, so the session is an `option` out here and `Session` never
//     has to model a board that doesn't exist.
//   - painting. A session answers in `core`'s document (`Render.line`); this is where
//     it becomes ANSI, because this is the layer that knows it's talking to a terminal.
//   - the two loops. `cli play` reads a terminal and a pipe alike: a live prompt line
//     at a time, and the batch fold `run` below. They share `consider` — one pure "what
//     does this line ask for" — so the only thing the interactive shape adds is
//     readline plumbing, and the shape that can't be tested without a pty decides
//     nothing.
//
// The *grammar* isn't here either: `Command.parse` in `core` turns a line into a
// `Command.t`, and `Session.step` plays the board verbs. The commands themselves are
// documented in docs/command-grammar.md and listed for a player in this package's
// README; a verb answered only in this file is a verb the panel doesn't have.
//
// A line whose first non-space character is `#` is a comment: it's skipped
// entirely (not echoed, not run), so a piped script can document itself. Blank lines
// are skipped too.

open Card

let gamesList = Command.gamesList

let help = () =>
  `Commands:
${Command.renderHelp(
      Array.concat(
        Array.concat(Array.concat(Command.dealHelp, Command.boardHelp), Command.driverHelp),
        [
          ("print", "re-print the current board"),
          ("games", "list the available games"),
          ("help", "show this help"),
          ("quit", "end an interactive session (Ctrl-D does it too)"),
        ],
      ),
    )}

${Command.cardNote}

Games:
${gamesList()}`

// --- Painting ------------------------------------------------------------------
// A session answers in `core`'s document; a terminal wants ANSI. Colour is asked for
// here and nowhere deeper, because this is the layer that knows where the text is
// going — the web console asks the same renderer for the same board and paints it in
// CSS instead.

// Where the game clock comes from. `Date.now` belongs at the impure edge (`Cli.res`),
// not in the interpreter — the same line `~newSeed` draws, and for the same reason: a
// test folds a script and gets the same transcript every time, while a real session gets
// a real clock. A fold takes no time it can honestly report, so a stopped clock says
// `0:00` rather than inventing a duration.
let stoppedClock = () => 0.

// What the game cost, once it's over — the very numbers the web app's
// victory panel reports, from the very same session, because they now ride in the
// session rather than in whichever front end remembered to count them.
//
// One line rather than the panel's two: a terminal reads left to right, and time · moves
// · undos is the order the panel stacks them in. The clock is left out when there's none
// to report — a session restored from a save written before `Timing` existed has no
// dealt-at, and a line that sometimes reads "12 moves · 1 undo" and sometimes
// "0:47 · 12 moves · 1 undo" is easier to read than one with a gap where a time isn't.
let tallyLine = (s: Session.t): string =>
  switch Timing.summary(s.timing) {
  | Some(time) => `${time} · ${Stats.summary(s.stats)}`
  | None => Stats.summary(s.stats)
  }

// The win report shown beneath a board once every foundation is complete, and
// what the game took to get there.
let winLines = (s: Session.t): array<Render.line> => [
  [],
  [Render.plain("🎉 You win! Every foundation is complete. `deal` to play again.")],
  [Render.plain(tallyLine(s))],
]

// The line the solver played, one move to a row, in the very words a typed or a
// dragged move is logged in (`Render.action`) — the same document the web console
// narrates a run with, so a played move reads the same in a terminal and in the panel.
// It's what the board alone can't tell you: the board says where the game ended up,
// and this says how it got there.
//
// The finishing sweep is the last row, said the way the web says it too (`finish `
// and the cards it sent home): the sweep is part of what a run did, and a list that
// stopped at the last planned move would stop a dozen cards short of the win printed
// under it.
//
// Numbered, unlike the panel's. The panel narrates a run as it plays it, a move at a
// time, where a number would be noise beside the card that's moving; a terminal prints
// the whole line at once, where a number is how you find the move you meant.
let playByPlay = (~game: Game.t, ~swept: array<card>, trail: array<Session.played>): array<
  Render.line,
> => {
  let moves =
    trail->Array.mapWithIndex((step: Session.played, i) =>
      Render.concat([
        [Render.plain(`${Int.toString(i + 1)->String.padStart(4, " ")}. `)],
        Render.action(~game, step.action),
      ])
    )
  // Indented under the numbers when there are any to line up with, and flush when the
  // board was already finishable and the sweep is the only thing that happened.
  let sweepRow = Render.concat([
    [Render.plain(Array.length(moves) == 0 ? "finish " : "      finish ")],
    Render.cardSpans(swept),
  ])
  Array.length(swept) == 0 ? moves : moves->Array.concat([sweepRow])
}

// The board a change leaves behind, as this driver prints it — and *whether* it prints
// one. A move that landed carries the win line with it, since that's the moment
// a victory becomes news; `print` and a fresh deal show the board as it stands; and a
// command that moved nothing shows none at all, because the board above it is still
// the board.
let boardBlock = (s: Session.t, change: Session.change): array<Render.line> =>
  switch change {
  | Session.Shown | Session.Dealt => Session.boardLines(s)
  | Session.Settled(_) | Session.Swept(_) | Session.Restored | Session.Played(_) =>
    Session.hasWon(s) ? Array.concat(Session.boardLines(s), winLines(s)) : Session.boardLines(s)
  | Session.Unchanged | Session.Blocked(_) | Session.Rejected(_) => []
  }

// One command's whole answer, as a transcript prints it: what the session had to say,
// the play-by-play if it played a line, then the board it left behind. Blocks that have
// nothing in them are left out rather than printed as a gap.
let transcript = (s: Session.t, outcome: Session.outcome): string =>
  [
    outcome.reply,
    switch outcome.change {
    | Session.Played({trail, swept}) => playByPlay(~game=s.game, ~swept, trail)
    | _ => []
    },
    boardBlock(s, outcome.change),
  ]
  ->Array.filter(block => Array.length(block) > 0)
  ->Array.map(Render.toAnsi)
  ->Array.join("\n\n")

// What "deal a game first" points at. It used to differ by verb — a plain `move`
// suggested a demo board, a `moverun` FreeCell — but FreeCell is the only game
// there is, so every board verb is answered with the same one. Asked before the command
// runs, so this is said ahead of any complaint about the arguments.
let dealFirstHint = "freecell"

// Interpret one already-parsed command against the current session, returning the
// updated session and the text to show. Pure: no I/O — the caller prints the text and
// carries the session forward. Unknown or malformed lines answer with guidance rather
// than failing, so a scrolling session never dead-ends.
//
// The board verbs are forwarded to `Session.step` and only *painted* here. What's
// answered here is what a terminal answers for itself: its own help, its own
// scrollback, its own flags, and the deal that opens a session in the first place.
//
// `~newSeed` is where a *fresh* deal's number comes from: `deal`/`new` names no board, so
// something has to invent one, and inventing is not the interpreter's to do. The default
// keeps a driver (and every test) deterministic; `Cli.res` overrides it with a random one,
// which is the same split the web app draws — `Main.randomSeed` lives in the impure view
// layer, not in `core`'s deal path.
//
// `~clock` is the other impurity a session needs, and it's here for the same reason:
// `Timing` stamps a win with a real moment, and `core` doesn't invent one.
let stepCommand = (
  ~options: Options.t,
  ~newSeed: unit => int=() => Game.freecellSeed,
  ~clock: unit => float=stoppedClock,
  session: option<Session.t>,
  command: Command.t,
): (option<Session.t>, string) => {
  // Every board verb funnels through here so the "deal a game first" answer is
  // written once rather than once per verb. The driver's flags are pushed into the
  // session on the way in: they're the loop's to carry (a `set` before any `deal` has
  // nowhere else to live), and the session's to consult.
  let onBoard = run =>
    switch session {
    | Some(s) => run(Session.withOptions(s, options))
    | None => (session, `Deal a game first (try \`deal ${dealFirstHint}\`).`)
    }
  let onSession = (s: Session.t) => {
    let (s', outcome) = Session.step(~clock, s, command)
    (Some(s'), transcript(s', outcome))
  }
  switch command {
  | Command.Blank => (session, "") // blank line: nothing to do
  | Command.Help => (session, help())
  | Command.Games => (session, gamesList())
  // The panel's scrollback verb. A scrolling transcript has no screen to
  // wipe, so the CLI takes it as a well-formed no-op rather than an unknown verb —
  // the grammar is shared even where the effect isn't.
  | Command.Clear => (session, "")
  // Leaving a session is the *loop's* business, not the interpreter's: `consider`
  // below intercepts this before it ever reaches here, and both drivers act on the
  // `Ended` it returns. A line that arrives here anyway (a caller stepping a parsed
  // command straight in) changes nothing, which is the only sound answer an
  // interpreter with no loop to stop can give.
  | Command.Quit => (session, "")
  // The driver's flags are the *loop's* state too, for exactly the reason quitting is:
  // `~options` here is one call's value, so a change made through it couldn't outlive the
  // command that made it. `consider` answers both before they reach here; a caller
  // stepping one in directly can still read them, but setting one changes nothing.
  | Command.Settings => (session, Command.describeSettings(options))
  | Command.Set(_) => (session, "")
  | Command.Unknown({verb}) => (session, Command.describeUnknown(verb))
  // A prefix that fit more than one verb: text-level, like an
  // unknown verb, so it's answered before any question about a board.
  | Command.Ambiguous({verb, matches}) => (session, Command.describeAmbiguous(~verb, ~matches))
  // Every shape of `deal` — bare, numbered, named, at a position — reads the same here as
  // it does in the panel, because the reading is `core`'s (see `Command.resolveDeal`).
  // A refusal hands `session` straight back, so a mistyped `deal` doesn't cost you the
  // game you were playing — it just says what it couldn't read. (It used to drop the
  // session, which made a typo the most destructive thing you could enter.)
  | Command.Deal({game, scenario}) =>
    switch Session.deal(~clock, ~newSeed, ~options, game, scenario) {
    | (Some(s), outcome) => (Some(s), transcript(s, outcome))
    | (None, outcome) => (session, Render.toAnsi(outcome.reply))
    }
  // A malformed *board* verb is answered "deal a game first" when there's no game, since
  // that's the more useful complaint — but a malformed `set` is about the driver's own
  // flags, which exist whether or not a board does, so it says what it couldn't read.
  | Command.Usage({verb: "set", message}) => (session, message)
  | Command.Usage({message}) => onBoard(_ => (session, message))
  // Everything left needs a board, and every one of them is `core`'s to run.
  | _ => onBoard(onSession)
  }
}

// The same, from raw text: parse the line, then run it. The line-based entry point
// most callers (and every test) want.
let step = (
  ~options: Options.t,
  ~newSeed: unit => int=() => Game.freecellSeed,
  ~clock: unit => float=stoppedClock,
  session: option<Session.t>,
  line: string,
): (option<Session.t>, string) =>
  stepCommand(~options, ~newSeed, ~clock, session, Command.parse(line))

// The prompt, in one place: written *before* the read in an interactive session and
// *behind* the line in a batch transcript. Same string either way — that's what makes
// the two shapes of `cli play` print the same thing, so a session on screen and a
// piped transcript of the same commands are indistinguishable (and `examples/*.txt`
// stays readable as a session log).
let prompt = "pip> "

// What a line asks the driver to *do*, decided once for both of them. The two loops
// differ only in when they learn the answer — a terminal a line at a time, a pipe all
// at once — so everything that decides anything lives here, on the pure side, and the
// loops are left holding nothing but I/O.
type outcome =
  | Skipped // a blank line or a `#` comment: neither echoed nor run
  // Everything that ran: the driver's state after it (the session *and* the flags, since
  // `set` changes those) and the text to show. Both come back on every line, changed or
  // not, so a loop adopts the pair rather than deciding which half moved.
  | Ran({session: option<Session.t>, options: Options.t, output: string})
  // `clear`: wipe the screen, if this driver has one. Nothing else changes — which is why
  // it carries no state. A batch fold has no screen and treats it as a well-formed line
  // that prints nothing, exactly as it always did.
  | Cleared
  | Ended // `quit`/`exit`: the session is over

// Decide one line. `#` comments and blanks are dropped *before* parsing, because a
// comment isn't part of the grammar at all (`# note` would otherwise read as an
// unknown verb) — which is what lets a piped script annotate itself, and what lets a
// whole such script be pasted into a live prompt and simply play.
let consider = (
  ~options: Options.t,
  ~newSeed: unit => int=() => Game.freecellSeed,
  ~clock: unit => float=stoppedClock,
  session: option<Session.t>,
  line: string,
): outcome => {
  let trimmed = String.trim(line)
  if trimmed == "" || String.startsWith(trimmed, "#") {
    Skipped
  } else {
    switch Command.parse(line) {
    | Command.Quit => Ended
    | Command.Clear => Cleared
    | Command.Settings => Ran({session, options, output: Command.describeSettings(options)})
    // The one command that changes the *driver* rather than the board. Handed back as
    // part of the state so the loop carries it into the next line — which is what makes
    // a setting stick for the rest of the session.
    | Command.Set({setting, on}) =>
      Ran({
        session,
        options: Options.apply(options, ~setting, ~on),
        output: Command.describeSet(~setting, ~on),
      })
    | command =>
      let (next, output) = stepCommand(~options, ~newSeed, ~clock, session, command)
      Ran({session: next, options, output})
    }
  }
}

// Fold a whole script of command lines into a single transcript: each non-blank,
// non-comment line is echoed behind the prompt, followed by its output. This is what
// tests assert against — the reducer loop exercised end-to-end with no terminal — and
// what a piped `cli play` prints.
//
// `quit` ends the transcript where it appears, the way `exit` ends a shell script:
// it's echoed (a transcript should say why it stopped) and the rest of the input is
// left unread.
let run = (
  ~options: Options.t=Options.default,
  ~newSeed: unit => int=() => Game.freecellSeed,
  ~clock: unit => float=stoppedClock,
  lines: array<string>,
): string => {
  let session = ref(None)
  // `~options` is where the fold *starts*; a `set` line moves it from there.
  let flags = ref(options)
  let out = []
  let ended = ref(false)
  lines->Array.forEach(line =>
    if !ended.contents {
      switch consider(~options=flags.contents, ~newSeed, ~clock, session.contents, line) {
      | Skipped => ()
      | Ended =>
        out->Array.push(prompt ++ String.trim(line))
        ended := true
      // Nothing to wipe in a transcript, so the line is echoed and says nothing — the
      // shape `clear` has always had here.
      | Cleared => out->Array.push(prompt ++ String.trim(line))
      | Ran({session: next, options: flags', output}) =>
        session := next
        flags := flags'
        out->Array.push(prompt ++ String.trim(line))
        if output != "" {
          out->Array.push(output)
        }
      }
    }
  )
  out->Array.join("\n\n")
}
