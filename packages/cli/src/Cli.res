// A tiny CLI over the modelled games (#62), now also a *reducer driver* (#84):
// it can deal a game and dispatch moves into the same `core` reducer the web app
// uses, printing the resulting board — a headless, scriptable way to exercise the
// rules end to end. Still a conventional scrolling CLI, not a TUI.
//
//   cli show <game>   Draw a game's opening layout (one-shot; see Render)
//   cli list          List the available games
//   cli play [game]   Drive the reducer: read commands from stdin, print boards
//   cli               Greeting + usage
//
// `play` reads newline-separated commands from stdin and runs them through the
// pure `Repl` interpreter (deal / move / print / …), so it works both piped
//   printf 'deal stacking\nmove AS 0\nprint\n' | cli play
// and interactively (type commands, then Ctrl-D). An optional [game] argument
// deals that game first, so `cli play stacking` opens straight onto the board.

@val @scope("process") external argv: array<string> = "argv"

// Read all of stdin to EOF, synchronously. fd 0 is standard input; an empty or
// unreadable stream (e.g. no pipe attached) yields "" rather than throwing, so
// `play` with no input simply prints nothing.
@module("node:fs") external readFileSync: (int, string) => string = "readFileSync"
let readStdin = (): string =>
  try readFileSync(0, "utf8") catch {
  | _ => ""
  }

let usage = () => {
  let ids = Game.all->Array.map(g => g.id)->Array.join(", ")
  `Usage:
  cli show <game>   Show a game's opening layout
  cli list          List the available games
  cli play [game]   Drive the reducer from stdin (deal / move / print)

Games: ${ids}`
}

let listGames = () => Game.all->Array.map(g => `  ${g.id}  —  ${g.name}`)->Array.join("\n")

let showGame = id =>
  switch Game.all->Array.find(g => g.id == id) {
  | Some(game) => Render.board(game)
  | None => `Unknown game: ${id}\n\n${usage()}`
  }

// Drive the reducer from stdin: split the input into command lines and fold them
// through `Repl.run`. An optional starting game is dealt first, as if the user
// had typed `deal <game>` before their own commands.
let play = (start: option<string>) => {
  let commandLines = readStdin()->String.split("\n")
  let lines = switch start {
  | Some(id) => Array.concat([`deal ${id}`], commandLines)
  | None => commandLines
  }
  Repl.run(lines)
}

// argv[0] is node, argv[1] the script; the arguments proper start at 2.
let output = switch argv {
| [_, _] => `${Core.greeting()}\n\n${usage()}`
| [_, _, "list"] => listGames()
| [_, _, "show", id] => showGame(id)
| [_, _, "play"] => play(None)
| [_, _, "play", id] => play(Some(id))
| _ => usage()
}

Console.log(output)
