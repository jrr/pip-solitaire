// A tiny CLI over the modelled games (#62): print a chosen game's opening
// layout to stdout as box-drawn cards. This is a conventional scrolling CLI,
// not a TUI — it renders once and exits.
//
//   cli show <game>   Draw a game's opening layout (see Render)
//   cli list          List the available games
//   cli               Greeting + usage

@val @scope("process") external argv: array<string> = "argv"

let usage = () => {
  let ids = Game.all->Array.map(g => g.id)->Array.join(", ")
  `Usage:
  cli show <game>   Show a game's opening layout
  cli list          List the available games

Games: ${ids}`
}

let listGames = () => Game.all->Array.map(g => `  ${g.id}  —  ${g.name}`)->Array.join("\n")

let showGame = id =>
  switch Game.all->Array.find(g => g.id == id) {
  | Some(game) => Render.board(game)
  | None => `Unknown game: ${id}\n\n${usage()}`
  }

// argv[0] is node, argv[1] the script; the arguments proper start at 2.
let output = switch argv {
| [_, _] => `${Core.greeting()}\n\n${usage()}`
| [_, _, "list"] => listGames()
| [_, _, "show", id] => showGame(id)
| _ => usage()
}

Console.log(output)
