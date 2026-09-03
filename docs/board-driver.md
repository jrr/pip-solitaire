# The board and its driver

`TableScene.make` takes fourteen arguments and publishes a record back. That is a
wide seam for one call site, and the width is not accidental: the board owns the
cards and the driver owns everything a card can't answer. This page is the
contract between them — what each side may know, why an argument is the shape it
is, and what a new one has to decide.

Two files, and the split is the load-bearing part:

| | owns |
|---|---|
| `scenes/TableScene.res` | the cards. The zones, the drag, the layout, the history, the session. Everything that is true of the board *now*. |
| `Main.res` | everything a board can't see: storage, the URL, the menu's preferences, which game is on the table, whether a share link is coming. |

The board is torn down and rebuilt on every re-deal. The driver is not — it is
module-level, built once at startup, and outlives every board it drives. Almost
every awkwardness below follows from that one asymmetry.

## Three kinds of argument

Everything crossing the seam is one of these, and which one it is decides the
shape:

```
value      ~initial ~newDeal ~winShare ~skipDealAnimation
           settled before the board is built, and true for its whole life

live ref   ~options ~tiltEnabled ~victoryAnimation
           read at the moment of use, so a menu toggle lands without a rebuild

channel    ~onHistory ~onDeal          board → driver, after every change
           ~loadHistory ~currentDeal   driver → board, asked at the moment of use
           ~publish ~persist           the two records that cross whole
```

A value that could change while the board is up must not be a value. A channel
that could be a value should be one.

## Why the preferences are refs

`~options` (the shared `Options.t` both front ends read), `~tiltEnabled` (the web
app's own presentation flag) and `~victoryAnimation` (the hidden victory-cascade
flag) are `ref`s rather than values, read live at each post-move step, wherever a
card is laid out, and at the moment a game is won.

The alternative is rebuilding the board when a preference flips, and a rebuild
throws the game away. Auto-collect turned on mid-game has to take effect on the
very next move, not on the next deal. `Main` owns all three refs, the menu's
switches write them, and the model keeps a mirror only so the switch itself
renders in the right position.

`tiltEnabled`'s companion is `controls.relayout`: a tilt change has nothing to
wait for, so the driver asks the board to re-lay the resting cards in place.
`docs/card-tilt.md` § The preference has that half. `victoryAnimation` needs no
companion for the opposite reason: it decides what the *next* victory does, and
there is never a victory on the table to redecorate.

The rule the refs imply: **a preference the board consults belongs in a ref, a
preference only the CSS consults does not.** `notchDisplayEnabled` is a plain
value for exactly that reason — it reaches the page as a document-root attribute
and the board never reads it.

## Why the reverse channels are refs *in the driver*

`Main` holds a cluster of module-level refs — `reportHistory`, `reportDeal`,
`closeMenu`, `reportScene` — each initialised to a stand-in and filled with a
real dispatcher just after mount. They exist for one ordering fact:

**The first board mounts during module init, before `Html.mount` has returned a
`dispatch`.** `SceneSwitcher.render` activates the initial scene as it is built,
that scene is the FreeCell board, and the board reports its opening `canUndo` and
its deal number immediately. There is no loop yet to dispatch them into.

So each channel has a pre-mount default, and two of them have to *remember* what
they were told:

| ref | pre-mount default | what would break without it |
|---|---|---|
| `reportHistory` | stash into `initialCanUndo` | a resumed game opens with Undo wrongly disabled |
| `reportDeal` | stash into `initialDealSeed` | Share opens dark on every load, lighting only after a New Game |
| `closeMenu` | do nothing | nothing — the menu isn't open yet |
| `reportScene` | do nothing | nothing — `init` reads `switcher.active` directly |

`init` then reads the stashed values into the model. The two that drop their
opening report can afford to because the answer is available elsewhere; the two
that stash cannot.

`liveDealSeed` is a third shape again: a mirror kept beside the dispatched copy,
because the win overlay's Share button is built by the *board*, outside the loop,
and asks at the moment of the press. Every report goes through `publishDeal` so
the model's copy and the mirror can't drift into a Share button that offers a
different deal than the menu's.

## Why the read-backs are thunks

`~loadHistory` and `~currentDeal` are `unit => …` rather than values, and both
for the same reason with different consequences.

**A scene can mount more than once.** The switcher re-mounts on a scene change,
so a value read when the scene was *built* is a snapshot of storage as it stood
at page load. Re-opening a board from that snapshot silently rewinds the game to
where it was when the page loaded — and if the player resumed a finished game
that session, brings the victory overlay back with it. Reading at mount time
resumes whatever is saved *now*.

`~currentDeal` is asked at the moment the console prints a board, for the same
class of reason: the number can't come from `game.seed`, because a posed position
sits on a game whose own seed didn't produce it and a resumed game's number lives
in the driver's storage.

## Who resolves the deal number

This is the seam's most-asked question, and the answer is split deliberately.

The board reports what it *knows* — `Some(n)` for a board it just dealt from `n`,
`None` for anything else. `None` is not "no deal number"; it is "not mine to
say". The driver then fills the gap from what only it can see:

| the board is showing | `~onDeal` reports | the driver resolves it to |
|---|---|---|
| a fresh deal (open, New Game, Restart) | `Some(n)` | `n`, and saves it if this open saves |
| a resumed history | `None` | `SavedGame.loadSeed` — the number the last session stored |
| a `?state=` scenario | `None` | `Scenario.seedForName`, when the scenario has *proved* a line to itself |
| a `#g=` shared game | `None` | nothing — a real position with no deal behind it |

That last row is why both Share buttons can go dark: a shared game has no number
to name, and a button pointing at a board nobody is looking at is worse than no
button. The `?state=` row is the same rule from the other side — only
`almost-won` descends from a deal it can prove (264), so every other posed board
offers nothing rather than naming a deal it didn't come from.

The saved deal number is the one fact the history doesn't carry, which is why
`SavedGame.saveSeed` exists at all; `docs/save-and-share.md` § Storage has the
storage half.

## What `~publish` hands back

One record, `controls`, handed over once as the scene mounts — not a callback per
action. A scene swap therefore replaces the whole surface at once: there is no
list of hooks for a new action to be missing from, and no way for the chrome to
be left driving a board that has been torn down.

**Every field is mount-scoped, not build-scoped.** The three that genuinely
belong to a build — `undo`, `runCommand`, `relayout` — dispatch through
mount-scope refs that each `buildBoard` repoints at its own. So the record the
chrome took at mount goes on driving whatever is actually on the table, and a
stale closure over a torn-down build isn't something a caller can hold even by
accident.

Two fields are `option`, and they are the two a board can genuinely lack:
`newGame` and `loadDeal` both open a board the caller names, which only a
*re-dealable* game has. **Ask `game.deal->Option.isSome`, never `id ==
"freecell"`** — a second seeded game answers yes on the day it lands, with no
edit anywhere.

`winShare` is a *pair* rather than two props for a related reason: offering a
button that then has no deal to share is the one failure a share button can't
afford, so the record makes it a type error rather than a convention two call
sites keep.

## Which opens touch storage

Save-and-resume attaches to one case only: a **plain open of a re-dealable
game** — no `?state=`, no `?seed=`, no `#g=`. An addressed board opens what it
was addressed to and leaves any saved game strictly alone, neither resumed nor
overwritten, which is what keeps the screenshot report's shots side-effect-free.

A `#g=` link is the one addressed open that *does* write, and it splits the two
halves apart: it doesn't resume (the link already says which board), but once the
shared game lands it takes over. That gate is asked twice at two different times,
because inflating the blob is asynchronous — at build time a scene knows only
that *some* link is coming (`sharePending`), and only later does one of them turn
out to be the game it named (`sharedOpen`). The `~persist` sink is wired for any
scene the link might name, and the gate inside it settles which one it did.

The consequence to hold onto: **the placeholder board a shared open wears while
the blob inflates must never be written to storage.** It is scaffolding. Writing
it would clobber the player's own game with a board nobody asked for, and a link
that fails to decode would take a save down with it.

## Before you add an argument

1. **Which of the three kinds is it?** A preference the board consults live is a
   ref. Anything settled before the build is a value. Don't make a value a
   channel because it might change one day.
2. **Can the board answer it?** If the answer lives in storage, in the URL, or in
   the menu, the board must report what it knows and let the driver resolve the
   rest — the deal-number table above is the shape.
3. **Does it need to survive a re-deal?** Then it belongs on `controls`, through
   a mount-scope ref, not in a build's closure.
4. **Is it read before `dispatch` exists?** Everything the initial mount reports
   is. Give it a pre-mount default, and decide whether that default has to
   remember.
5. **Does it write to storage?** Then say which of the four opens it applies to,
   and check the shared-link placeholder case.
