# `cli` — a headless reducer driver for the card games

A terminal front-end over the same `core` "brain" the web app dispatches into.
It draws a game's board with box-drawing characters, and — via `play` — lets you
deal a game and dispatch moves into the pure `Reducer.reduce`, printing the
resulting board (or a typed rejection) after each command.

## Commands

```
cli show <game>   Draw a game's opening layout (one-shot)
cli list          List the available games
cli play [game]   Drive the reducer: read commands from stdin, print boards
cli               Greeting + usage
```

Run it through the `cli` mise task (which builds first, then forwards everything
after `--` to the built script):

```
mise run cli -- list
mise run cli -- show stacking
```

## `play`: batch mode, not a live REPL

`play` is **batch-oriented**, not an interactive prompt-and-response REPL. It
reads *all* of stdin to EOF, runs the whole script through the pure `Repl`
interpreter, and prints the entire transcript at once. There is no per-command
prompt: nothing is echoed until the input stream closes.

That means the two ways to use it are:

**Pipe a script** (the primary mode) — a file or a `printf`:

```
mise run cli -- play < packages/cli/examples/stacking-run.txt

printf 'deal stacking\nmove AS 1\nprint\n' | mise run cli -- play
```

**Type then Ctrl-D** — you can run `mise run cli -- play`, type commands, and
press Ctrl-D to end input; the whole transcript then prints in one go. Because
nothing echoes back as you type, this is really just batch mode with a keyboard
as the source, not a live REPL. (A true line-at-a-time interactive mode would be
a future enhancement — the interpreter itself is already pure and per-line, so
only the stdin plumbing in `Cli.res` would need to change.)

### The command language

Fed to `play` on stdin, one per line:

```
deal <game>          start (or restart) a game
move <card> <pile>   move a card onto pile <index>   (e.g. move AS 0)
move <card> table    move a card loose onto the table (free games only)
print                re-print the current board
games                list the available games
help                 show the command surface
```

- **Cards** are named by a compact identity: a rank (`A 2-9 T J Q K`, or the
  two-digit `10`) followed by a suit letter (`S H D C`) — `AS`, `TH`/`10H`,
  `KD`. Case-insensitive. See `CardText.res`.
- **Piles** are addressed by index (`0`, `1`, …); the table by the word `table`.
- **Comments**: a line whose first non-space character is `#` is skipped
  entirely (not echoed, not run), so a piped script can document itself. Blank
  lines are skipped too.
- Illegal moves are **rejected with a reason** (wrong rank/colour, no loose
  drops in a piles-only game, no such pile, card not in play) rather than
  silently ignored — that's the whole point of the reducer returning a typed
  `moveError`.

## Examples

Ready-to-pipe scripts live in [`examples/`](./examples):

| File | Shows |
| --- | --- |
| [`stacking-run.txt`](./examples/stacking-run.txt) | Building a full Ace→King run onto a fanned tableau pile. |
| [`stacking-rejected.txt`](./examples/stacking-rejected.txt) | A move refused by the stacking rule, with its reason. |
| [`foundations.txt`](./examples/foundations.txt) | Two pile rules on one board — a same-suit foundation and an alternating-colour tableau. |
| [`four-fans.txt`](./examples/four-fans.txt) | A piles-only game refusing a loose drop onto the table. |

Each file is self-documenting (leading `#` comments explain what it does), so
reading one is the fastest way to learn the command language:

```
mise run cli -- play < packages/cli/examples/foundations.txt
```
