# `cli` — a headless reducer driver for the card games

A terminal front-end over the same `core` "brain" the web app dispatches into.
It draws a game's board with box-drawing characters, and — via `play` — lets you
deal a game and dispatch moves into the pure `Reducer.reduce`, printing the
resulting board (or a typed rejection) after each command.

The board is drawn in the same two role-grouped rows the web app lays out: free
cells and foundations across the top, tableau columns below, each column headed by
the name a typed move can address it by (`T3`, `C1`, `F2`).

The box-drawn board isn't this package's own any more: `core`'s `Render` draws it,
because the web app's debug console prints the same one. What's left here is the
terminal end of it — stdin, stdout, and asking for ANSI colour.

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

Neither the *grammar* nor the *board drawing* is the CLI's own: `Command.res` and
`Render.res` both live in `core`, shared with the web app's debug console (#273),
which types the same commands at the same reducer and prints the same board.
`Repl` is the half that needs a session — the game in play, the history to undo
over, the board to print — and the transcripts in `examples/` are the regression
net for both.

Colour is the one thing the two ask for differently: `Render` writes it as ANSI
escapes, which a terminal paints and a browser panel would show as garbage, so
it's off by default and this driver passes `~color=true`.

Both shapes run over one pure decision, `Repl.consider` ("what does this line
ask for?"), so the interactive loop in `Cli.res` is nothing but readline
plumbing. That split is deliberate: a real terminal can't be faked in vitest
without a pty, so the shape the test suite can't reach is the shape that decides
nothing.

### The command language

Typed at the prompt, or fed to `play` on stdin, one per line — `help` prints the
same listing:

```
deal <n>                 deal FreeCell game number <n>  (e.g. deal 12345)
deal <game> [position]   deal a named game, at a named position if given
new                      deal a fresh game
redeal / restart         play the current deal again from the start (same board)
move <card> <where>      move a card   (e.g. move AS T3, mv 2H 3C, m AS 0)
move <card> table        move a card loose onto the table (free games only)
moverun <card>… <where>  supermove an ordered run, cards bottom-first
home <card>              send a card to its foundation, if one will take it
movecol <from> <to>      reorder cascade columns: pull <from>, drop it at <to>
finish                   sweep every card home to win, when the board is drainable
undo / redo              step back and forth over the accepted moves
set                      show the driver settings
set <setting> on|off     change one (autocollect, reorder)
clear                    wipe the screen (a live prompt only)
print                    re-print the current board
games                    list the available games
help                     show the command surface
quit / exit              end an interactive session (Ctrl-D does it too)
```

- **`deal` reads the same here as in the web app's debug console**, because the
  reading is `core`'s (`Command.resolveDeal`): a number is a deal number, a word is
  a game id, a second word is one of that game's named positions (`games` lists the
  games; a refusal lists the positions). Only the *acting* differs — a terminal
  opens a session, the panel rebuilds the board on screen.
- **`deal freecell` is `deal 1`**: a game id names that game's canonical board, so
  it's the same deal in both front ends. `new` is the one that invents a board.
- **`redeal`** is the menu's Restart button as a verb: the same deal from its
  opening layout, with a clean history. From a posed position it goes to the
  game's real deal, not back to the pose — exactly what the button does.
- **The board names its deal**: a dealt FreeCell board prints `FreeCell — deal
  #12345`, so the number you'd need to open it again (here or in the browser) is
  on screen rather than only in what you typed. A posed position names only a
  deal it has been *proved* to descend from, and a fixed-layout demo names none.
- **`set` changes the driver's flags** (`Options`) for the rest of the session —
  `set autocollect off`, `set reorder on`. It's shared with the web console,
  where it's the only way to reach the column-reorder house rule at all: that one
  has no switch in the menu.
- **`clear`** wipes the terminal at a live prompt. In a piped script there's no
  screen, so it's a well-formed line that prints nothing — the shape it has
  always had.
- **Cards** are named by a compact identity: a rank (`A 2-9 T J Q K`, or the
  two-digit `10`) followed by a suit letter (`S H D C`) — `AS`, `TH`/`10H`,
  `KD`. Case-insensitive. See `core`'s `CardText.res`.
- **`move` has three shorthands and three destinations.** The verb is `move`, `mv`
  or `m` — it's the line you type most — and where it sends the card can be said
  any of these ways:
  - **a slot name**, the label printed above the column: `T1`…`T8` for the tableau
    columns, `C1`…`C4` for the free cells, `F1`…`F4` for the foundations. Letter
    first on purpose: a card is rank-then-suit, so a digit-first `3C` would be both
    the Three of Clubs and a free cell in the one place both can appear.
  - **the card to land on** — `mv 2H 3C` puts the Two of Hearts on the Three of
    Clubs, wherever that is. It has to be the card *showing* at the top of exactly
    one pile: a buried card, a card that isn't in play, or (on a board that could
    show one card twice) an ambiguous match is refused rather than guessed at.
  - **a pile index** (`0`, `1`, …), the absolute position in the model — what the
    reducer itself speaks, and unchanged.

  The same three work for `moverun`'s destination. The table is the word `table`.
- **The board says its own slot names**: each column is drawn under its label, so
  the move you can see is the move you can type.
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
