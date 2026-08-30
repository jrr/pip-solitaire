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
mise run cli -- show freecell
```

## `play`: one verb, two shapes

`play` decides what it is from **what stdin is**, rather than from a second
subcommand — the way `node`, `python` and `sqlite3` all do it:

**A terminal → a live REPL.** A `pip> ` prompt, one line at a time, each board
printed as you play it. `quit` (or `exit`, or Ctrl-D) leaves.

```
mise run cli -- play
mise run cli -- play freecell     # deals that game first, straight onto the board
```

**A pipe or a file → batch.** Reads all of stdin to EOF, folds the whole script
through the pure `Repl` interpreter, and prints the transcript at once.

```
mise run cli -- play < some-script.txt

printf 'deal freecell sendhome\nmove C1 F1\nprint\n' | mise run cli -- play
```

The two shapes print the **same transcript**: `Repl.prompt` is written *before*
the read on a terminal and *behind* the line in a batch fold, and the live loop
doesn't echo (your own typing is the echo), so a session on screen matches a piped
transcript of the same commands line for line. That's what keeps a script file
readable as a session log — and it means one can be pasted straight into a live
prompt and simply play.

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
which types the same commands at the same reducer and prints the same board — see
[`docs/command-grammar.md`](../../docs/command-grammar.md). `Repl` is the half
that needs a session — the game in play, the history to undo over, the board to
print.

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
move <what> <where>      move a card   (e.g. move AS T3, mv 2H 3C, m C1 F1)
moverun <what> <where>   supermove an ordered run: its cards bottom-first, or
                         the column it's showing in (moverun T6 T2)
home <card>              send a card to its foundation, if one will take it
movecol <from> <to>      reorder cascade columns: pull <from>, drop it at <to>
finish                   sweep every card home to win, when the board is drainable
autoplay                 let the solver play the rest of the game (and finish it)
undo / redo              step back and forth over the accepted moves
set                      show the driver settings
set <setting> on|off     change one (autocollect, reorder)
clear                    wipe the screen (a live prompt only)
print                    re-print the current board
games                    list the available games
help                     show the command surface
quit / exit              end an interactive session (Ctrl-D does it too)
```

**How to say a move**, in short — the full grammar, and the reasoning behind it,
is [`docs/command-grammar.md`](../../docs/command-grammar.md):

- **Cards** are named by a compact identity: a rank (`A 2-9 T J Q K`, or the
  two-digit `10`) followed by a suit letter (`S H D C`) — `AS`, `TH`/`10H`, `KD`.
  Case-insensitive.
- **Columns** are named by the label the board prints over them: `T1`…`T8` for
  the tableau, `C1`…`C4` for the free cells, `F1`…`F4` for the foundations. The
  move you can see is the move you can type.
- **Either half of a move takes a card, a label or a pile index.** `move 8H T3`
  names the card; `move C1 F1` means "whatever is showing in the first free cell";
  `mv 2H 3C` lands the Two of Hearts on the Three of Clubs wherever that is;
  `moverun T6 T2` lifts the whole run showing on T6. Anything ambiguous — a buried
  card, an empty cell — is refused by name rather than guessed at.
- **Any verb may be shortened to an unambiguous prefix.** `p` prints, `u` undoes,
  `de 12345` deals. `h` is refused, because it could be `help` or `home`.

A few things that are the terminal's own:

- **`clear`** wipes the screen at a live prompt. In a piped script there's no
  screen, so it's a well-formed line that prints nothing.
- **Comments**: a line whose first non-space character is `#` is skipped entirely
  (not echoed, not run), so a piped script can document itself. Blank lines are
  skipped too. Both hold at a live prompt as well, which is why a whole script
  file can be pasted into one.
- **`quit` in a script** ends the transcript where it appears and leaves the rest
  of the input unread, the way `exit` ends a shell script.

And two things worth knowing at the prompt:

- **The board names its deal**: a dealt FreeCell board prints `FreeCell — deal
  #12345`, so the number you'd need to open it again (here or in the browser) is
  on screen rather than only in what you typed. A posed position names only a
  deal it has been *proved* to descend from, and stays quiet otherwise.
- **`autoplay` hands the game to the solver** ([`docs/solver.md`](../../docs/solver.md)):
  it thinks the deal through, plays its line here a move at a time, and then runs
  `finish`, so a solvable board ends on the win line. Every move it plays is an
  ordinary undoable step, so you can undo back into the game and take it over.
- Illegal moves are **rejected with a reason** (wrong rank/colour, a full free
  cell, no such pile, a buried card) rather than silently ignored — that's the
  whole point of the reducer returning a typed `moveError`.
