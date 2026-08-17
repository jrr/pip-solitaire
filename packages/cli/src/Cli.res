// A tiny CLI over the modelled games (#62), now also a *reducer driver* (#84): it
// can deal a game and dispatch moves into the same `core` reducer the web app uses,
// printing the resulting board — a headless, scriptable way to exercise the rules end
// to end. Still a conventional scrolling CLI, not a TUI.
//
//   cli show <game>   Draw a game's opening layout (one-shot; see Render)
//   cli list          List the available games
//   cli play [game]   Play: a live prompt on a terminal, a script when piped
//   cli               Greeting + usage
//
// `play` is **one verb with two shapes**, chosen by what stdin *is* rather than by a
// second subcommand — the way `node`, `python` and `sqlite3` all decide it:
//
//   cli play                              a terminal → a real prompt, line at a time
//   cli play < examples/foundations.txt    a file     → batch: fold it, print it
//   printf 'deal stacking\nprint\n' | cli play        a pipe → the same batch fold
//
// It reads as one mode rather than two because the two print the *same* transcript:
// `Repl.prompt` is written before the read on a terminal and behind the line in a
// batch fold, and the interactive loop doesn't echo (your own typing is the echo), so
// the screen ends up matching a piped transcript of the same commands line for line.
// Which is what keeps `examples/*.txt` readable as session logs — and means one of
// them can be pasted straight into a live prompt and simply play.
//
// Sniffing stdin is a *default*, so there's an explicit way out, as there is for every
// tool that does this (`sqlite3 -batch`, `psql -f`): `--script` pins the batch shape
// whatever stdin turns out to be. A caller that must not depend on context — CI, a
// scheduled job, an agent shell that inherits a terminal — should pass it rather than
// risk `cli play` sitting at a prompt nobody is going to type into.
//
// An optional `[game]` argument deals that game first in either shape, so
// `cli play stacking` opens straight onto the board. It's the `deal` argument, so a deal
// number works too (`cli play 12345`) — see `Command.resolveDeal`. More in
// packages/cli/README.md and examples/.

@val @scope("process") external argv: array<string> = "argv"

// --- Node bindings ------------------------------------------------------------
type stream
@val @scope("process") external stdin: stream = "stdin"
@val @scope("process") external stdout: stream = "stdout"
// Node leaves this *undefined* rather than false on a redirected stream, hence the
// nullable: `Some(true)` is a terminal, anything else isn't.
@get external isTTY: stream => Nullable.t<bool> = "isTTY"

// Read all of stdin to EOF, synchronously. fd 0 is standard input; an empty or
// unreadable stream (e.g. no pipe attached) yields "" rather than throwing, so
// `play` with no input simply prints nothing.
@module("node:fs") external readFileSync: (int, string) => string = "readFileSync"
let readStdin = (): string =>
  try readFileSync(0, "utf8") catch {
  | _ => ""
  }

// Node's line reader, for the interactive shape. `prompt` is the string it writes
// before each read — `Repl.prompt`, the very one the batch transcript echoes behind.
type readline
type readlineOptions = {input: stream, output: stream, prompt: string}
@module("node:readline") external createInterface: readlineOptions => readline = "createInterface"
@send external writePrompt: readline => unit = "prompt"
// The event name is fixed in the binding rather than passed at the call site: there
// are exactly two events worth listening for, and this way neither can be misspelled.
@send external onLine: (readline, @as("line") _, string => unit) => unit = "on"
@send external onClose: (readline, @as("close") _, unit => unit) => unit = "on"
@send external close: readline => unit = "close"

// Wipe the terminal: the visible screen (`2J`), the scrollback behind it (`3J` — what
// makes this the panel's `clear` rather than a screenful of blank lines), and the cursor
// home (`H`). Built from the escape character rather than written as a literal so the
// bytes are unambiguous.
let escape = String.fromCharCode(27)
let clearScreen = () => Console.log(`${escape}[2J${escape}[3J${escape}[H`)

// Where a fresh `deal`/`new` gets its deal number. `Math.random` belongs out here at the
// impure edge, not in the interpreter — the same line the web app draws with
// `Main.randomSeed`, and the reason `Repl`'s own default is deterministic: a test folds a
// script and gets the same board every time, while a real session gets a new one.
let randomSeed = () => (Math.random() *. 1_000_000.)->Float.toInt

let usage = () => {
  let ids = Game.all->Array.map(g => g.id)->Array.join(", ")
  `Usage:
  cli show <game>   Show a game's opening layout
  cli list          List the available games
  cli play [game|n] Play: a prompt on a terminal, a script when piped
                    (--script forces the piped shape)

Games: ${ids}`
}

let listGames = () => Game.all->Array.map(g => `  ${g.id}  —  ${g.name}`)->Array.join("\n")

let showGame = id =>
  switch Game.all->Array.find(g => g.id == id) {
  | Some(game) => Render.board(~color=true, game)
  | None => `Unknown game: ${id}\n\n${usage()}`
  }

// --- The batch shape ----------------------------------------------------------
// Drive the reducer from a redirected stdin: split the input into command lines and
// fold them through `Repl.run`. An optional starting game is dealt first, as if the
// user had typed `deal <game>` before their own commands.
let script = (start: option<string>): string => {
  let commandLines = readStdin()->String.split("\n")
  let lines = switch start {
  | Some(id) => Array.concat([`deal ${id}`], commandLines)
  | None => commandLines
  }
  Repl.run(~newSeed=randomSeed, lines)
}

// --- The interactive shape ----------------------------------------------------
// A live prompt over the same interpreter the fold above uses. This is the *only*
// impure part of the driver: `Repl.consider` decides what every line means and this
// reads lines and prints what it's told, which is deliberate — a real terminal can't
// be faked in vitest without a pty, so the branch the test suite can't reach is kept
// down to plumbing with no decisions in it.
let interactive = (start: option<string>): unit => {
  let session = ref(None)
  // The driver's flags, carried across lines so a `set` sticks for the session. The batch
  // fold keeps its own for the length of a script; here it's the length of the sitting.
  let flags = ref(Options.default)
  let rl = createInterface({input: stdin, output: stdout, prompt: Repl.prompt})
  // Whether the session is still going. `quit` clears it, which both suppresses the
  // next prompt and tells the close handler the newline below isn't wanted.
  let alive = ref(true)

  // One command's output, spaced the way the batch fold spaces its entries — a blank
  // line between each — so the two shapes print the same transcript. Only the *trailing*
  // separator is written: accepting a line leaves the reader on a fresh line and a blank
  // one below it, which is already the gap the fold puts between an echoed command and
  // its output. A command with nothing to say (`clear` here) prints nothing at all for
  // the same reason — the separator it needs is on screen before we're asked.
  let show = (output: string) =>
    if output != "" {
      Console.log(output ++ "\n")
    }

  let play = (line: string): unit =>
    switch Repl.consider(~options=flags.contents, ~newSeed=randomSeed, session.contents, line) {
    | Repl.Skipped => ()
    | Repl.Ended =>
      alive := false
      close(rl)
    // `clear` finally means something: an interactive session *has* a screen, which is
    // what the panel's version wipes. Both halves go, the visible screen and the
    // scrollback above it, because the panel's `clear` empties its whole ring rather
    // than just the lines on show. Reachable only here — a redirected stdin takes the
    // batch fold, which has no screen to write escapes at.
    | Repl.Cleared => clearScreen()
    | Repl.Ran({session: next, options: flags', output}) =>
      session := next
      flags := flags'
      show(output)
    }

  // A prompt that says nothing about how to get help or get out is a prompt you have
  // to read the source of.
  Console.log(`${Core.greeting()}\n\nType "help" for the commands, "quit" to leave.`)

  // An opening `[game]` is dealt as if it had been typed — echoed behind the prompt,
  // precisely because it *wasn't*: the transcript should show the deal that put this
  // board on screen.
  start->Option.forEach(id => {
    Console.log(`${Repl.prompt}deal ${id}`)
    play(`deal ${id}`)
  })

  rl->onLine(line => {
    play(line)
    if alive.contents {
      writePrompt(rl)
    }
  })
  // Ctrl-D closes the reader with the cursor still after the prompt, so leave the
  // shell a clean line to come back to. A `quit` has already ended its own line.
  rl->onClose(() =>
    if alive.contents {
      Console.log("")
    }
  )
  writePrompt(rl)
}

// Which shape `play` takes. A terminal gets the prompt; a pipe, a file, or a stream
// that isn't there at all gets the batch fold — and `--script` pins the fold for a
// caller that would rather not depend on the answer.
let interactiveStdin = (): bool => isTTY(stdin)->Nullable.toOption->Option.getOr(false)

let play = (~forceScript: bool, start: option<string>): unit =>
  if !forceScript && interactiveStdin() {
    interactive(start)
  } else {
    Console.log(script(start))
  }

// argv[0] is node, argv[1] the script; the arguments proper start at 2. The `--script`
// forms come before the bare `[game]` one, or the flag would be read as a game id.
switch argv {
| [_, _] => Console.log(`${Core.greeting()}\n\n${usage()}`)
| [_, _, "list"] => Console.log(listGames())
| [_, _, "show", id] => Console.log(showGame(id))
| [_, _, "play"] => play(~forceScript=false, None)
| [_, _, "play", "--script"] => play(~forceScript=true, None)
| [_, _, "play", id] => play(~forceScript=false, Some(id))
| [_, _, "play", "--script", id] | [_, _, "play", id, "--script"] =>
  play(~forceScript=true, Some(id))
| _ => Console.log(usage())
}
