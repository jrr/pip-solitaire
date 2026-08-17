# `cli` — a headless reducer driver for the card games

A terminal front-end over the same `core` "brain" the web app dispatches into.
It draws a game's board with box-drawing characters, and — via `play` — lets you
deal a game and dispatch moves into the pure `Reducer.reduce`, printing the
resulting board (or a typed rejection) after each command.

## Commands

```
cli show <game>   Draw a game's opening layout (one-shot)
cli list          List the available games
cli play [game]   Play: a live prompt on a terminal, a script when piped
cli               Greeting + usage
```

Run it through the `cli` mise task (which builds first, then forwards everything
after `--` to the built script):

```
mise run cli -- list
mise run cli -- show stacking
```

## `play`: one verb, two shapes

`play` decides what it is from **what stdin is**, rather than from a second
subcommand — the way `node`, `python` and `sqlite3` all do it:

**A terminal → a live REPL.** A `pip> ` prompt, one line at a time, each board
printed as you play it. `quit` (or `exit`, or Ctrl-D) leaves.

```
mise run cli -- play
mise run cli -- play stacking     # deals that game first, straight onto the board
```

**A pipe or a file → batch.** Reads all of stdin to EOF, folds the whole script
through the pure `Repl` interpreter, and prints the transcript at once.

```
mise run cli -- play < packages/cli/examples/stacking-run.txt

printf 'deal stacking\nmove AS 1\nprint\n' | mise run cli -- play
```

The two shapes print the **same transcript**: `Repl.prompt` is written *before*
the read on a terminal and *behind* the line in a batch fold, and the live loop
doesn't echo (your own typing is the echo), so a session on screen matches a piped
transcript of the same commands line for line. That's what keeps the files in
`examples/` readable as session logs — and it means one of them can be pasted
straight into a live prompt and simply play.

### `--script`: pinning the batch shape

Sniffing stdin is a *default*, so there's an explicit way out, as there is for
every tool that does this (`sqlite3 -batch`, `psql -f`):

```
mise run cli -- play --script < some-script.txt
```

`--script` forces the batch shape whatever stdin turns out to be. **Pass it from
anything that mustn't depend on context** — CI, a scheduled job, an agent shell
that inherits a terminal — or a bare `cli play` there will sit at a prompt nobody
is going to type into.

### Where the code lives

The *grammar* isn't the CLI's own: it lives in `core` (`Command.res`) and is
shared with the web app's debug console (#273), which types the same commands at
the same reducer. `Repl` is the half that needs a session — the game in play, the
history to undo over, the board to print — and the transcripts in `examples/` are
the regression net for both.

Both shapes run over one pure decision, `Repl.consider` ("what does this line
ask for?"), so the interactive loop in `Cli.res` is nothing but readline
plumbing. That split is deliberate: a real terminal can't be faked in vitest
without a pty, so the shape the test suite can't reach is the shape that decides
nothing.

### The command language

Typed at the prompt, or fed to `play` on stdin, one per line — `help` prints the
same listing:

```
deal <game> [scenario]   start (or restart) a game, optionally at a named position
move <card> <pile>       move a card onto pile <index>   (e.g. move AS 0)
move <card> table        move a card loose onto the table (free games only)
moverun <card>… <pile>   supermove an ordered run, cards bottom-first
home <card>              send a card to its foundation, if one will take it
movecol <from> <to>      reorder cascade columns: pull <from>, drop it at <to>
finish                   sweep every card home to win, when the board is drainable
undo / redo              step back and forth over the accepted moves
print                    re-print the current board
games                    list the available games
help                     show the command surface
quit / exit              end an interactive session (Ctrl-D does it too)
```

- **Cards** are named by a compact identity: a rank (`A 2-9 T J Q K`, or the
  two-digit `10`) followed by a suit letter (`S H D C`) — `AS`, `TH`/`10H`,
  `KD`. Case-insensitive. See `core`'s `CardText.res`.
- **Piles** are addressed by index (`0`, `1`, …); the table by the word `table`.
- **Comments**: a line whose first non-space character is `#` is skipped
  entirely (not echoed, not run), so a piped script can document itself. Blank
  lines are skipped too. Both hold at a live prompt as well, which is why a whole
  example file can be pasted into one.
- **`quit` in a script** ends the transcript where it appears and leaves the rest
  of the input unread, the way `exit` ends a shell script.
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
