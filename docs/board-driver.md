# The board and its driver

`TableScene.make` takes fifteen arguments and publishes a record back. That is a
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
value      ~initial ~newDeal ~winShare ~skipFlights ~skipDealFlyIn
           settled before the board is built, and true for its whole life

live ref   ~options ~tiltEnabled
           read at the moment of use, so a menu toggle lands without a rebuild

channel    ~onHistory ~onDeal          board → driver, after every change
           ~loadHistory ~currentDeal   driver → board, asked at the moment of use
           ~onceUncovered              board → driver → board: a thunk handed over,
                                       run now or when the board is next in view
           ~publish ~persist           the two records that cross whole
```

A value that could change while the board is up must not be a value. A channel
that could be a value should be one.

## Why the preferences are refs

`~options` (the shared `Options.t` both front ends read) and `~tiltEnabled` (the
web app's own presentation flag) are `ref`s rather than values, read live at each
post-move step and wherever a card is laid out.

The alternative is rebuilding the board when a preference flips, and a rebuild
throws the game away. Auto-collect turned on mid-game has to take effect on the
very next move, not on the next deal. `Main` owns both refs because they belong
to the board rather than to any one screen; the Settings screen holds the mirror
its switches render from and writes the refs through on every flip (see
`MenuSettingsScreen.liveEnv`).

`tiltEnabled`'s companion is `controls.relayout`: a tilt change has nothing to
wait for, so the driver asks the board to re-lay the resting cards in place.
`docs/card-tilt.md` § The preference has that half.

The rule the refs imply: **a preference the board consults belongs in a ref, a
preference only the CSS consults does not.** "Display content around notch" has
no ref here for exactly that reason — it reaches the page as a document-root
attribute and the board never reads it.

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

## Why the deal is handed back to be played

The opening fly-in is the one flight that is only worth making in front of someone,
and whether anyone is looking is a fact about the chrome, not the cards. The board
can't ask it — the menu is the driver's — and it can't be a value either: the same
scene mounts many times, and only one of those mounts happens under an open menu.

So the board builds the pass paused, every card parked at the off-stage origin, and
hands the driver a thunk that plays it (`~onceUncovered`). The driver runs it on the
spot for every mount but one: the Games list's segment swapping the board of the
family being played (`Main.swapBoard`), which is the one activation that keeps the
menu up. That mount's thunk is held (`heldDeal`) and run by whatever closes the menu
— on the model's open-to-closed transition rather than in any one message, so a new
way of closing the menu can't leave a board with its cards off-stage. `onActivate`
drops the thunk before anything else, since a board torn down with its deal waiting
has nothing left to play.

The handover is made by every opening build, flights or none, because the driver
has a second use for the moment: it is when a board dealt behind the menu becomes
the player's (§ Which opens touch storage, below). A resumed board or a reduced-motion
one has nothing to play, and still has to be able to say it has been seen.

The board keeps its own guard for the same case from the other side: the held flights
live in a mount-scope ref that a re-deal or a teardown cancels and empties, and the
thunk plays *that ref*, so a stale release the driver still holds plays nothing. It
has to be the ref rather than the array the flights were built from, because playing a
cancelled Web Animation restarts it.

## Who resolves the deal number

This is the seam's most-asked question, and the answer is split deliberately.

The board reports what it *knows* — `Some(n)` for a board it just dealt from `n`,
`None` for anything else. `None` is not "no deal number"; it is "not mine to
say". The driver then fills the gap from what only it can see:

| the board is showing | `~onDeal` reports | the driver resolves it to |
|---|---|---|
| a deal it laid out (open, New Game, `deal <n>`, a Restart of one of those) | `Some(n)` | `n`, and saves it if this open saves |
| a resumed history | `None` | `SavedGame.loadSeed` — the number stored beside that save, by the session that wrote it or by the adoption that took it over |
| a Restart of a resumed history | `None` | the same, and the number is unchanged by the restart — the board replayed is the one the heading already named |
| a `?state=` scenario | `None` | `Scenario.seedForName`, when the scenario has *proved* a line to itself |
| a `#g=` shared game | `None` | nothing — a real position with no deal behind it |

The last row is why both Share buttons can go dark: a shared game has no number
to name, and a button pointing at a board nobody is looking at is worse than no
button. The `?state=` row is the same rule from the other side — only
`almost-won` descends from a deal it can prove (264), so every other posed board
offers nothing rather than naming a deal it didn't come from.

The two Restart rows are the same rule applied to what a board *opened on* rather
than to how the player got there, and they are why a Restart can't simply rebuild
from the game the scene was mounted with. A resumed board wears a placeholder deal
the driver invented while the save was being read; the opening it actually
descends from is the first state of the restored history, and for a shared game
that is the only opening there is, since landing the link clears the seed
(`SavedGame.clearSeed`). `TableScene`'s `opening` type is that distinction.

The saved deal number is the one fact the history doesn't carry, which is why
`SavedGame.saveSeed` exists at all; `docs/save-and-share.md` § Storage has the
storage half.

## What `~publish` hands back

One record, `controls`, handed over once as the scene mounts — not a callback per
action. A scene swap therefore replaces the whole surface at once: there is no
list of hooks for a new action to be missing from, and no way for the chrome to
be left driving a board that has been torn down.

**Every field is mount-scoped, not build-scoped.** The four that genuinely
belong to a build — `undo`, `runCommand`, `autoplay`, `relayout` — dispatch
through mount-scope refs that each `buildBoard` repoints at its own. So the record the
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

`autoplay` answers with a pair, and it is the one field that exists because of *where*
its caller stands. What it adds over a typed line is whether the solver found a line
(`autoplayed.playing`). A caller covering the board — the menu's Debug screen, whose
panel is the width of a phone — has to know: a line found is played out on the board
behind it and is something to get out of the way of, while a refusal moves nothing at
all, which makes the reply the only thing there will ever be to show.

**And it is the one field that answers by callback**, because it is the one verb whose
answer does not arrive in the same breath as the press: the search runs on a worker
thread, so the call returns at once and `~onAnswer` fires seconds later, or never if the
board moves on first. That is why `runCommand` forwards `Command.Autoplay` here rather
than running it — the verb has no reply to return by the time it would have to — and why
the Debug screen can write "Thinking…" and actually be seen writing it. `Thinker`'s
header has the thread, the cancel and what may cross the boundary.

## Which opens touch storage

Saving is not a property of the URL but of the board, and the question it turns on
is whether the board on the table is the player's own. A **plain open of a
re-dealable game** — no `?state=`, no `?seed=`, no `#g=` — is theirs the moment it
deals: nobody addressed it, so what came up is simply the game they are playing.
An addressed board is one they were *sent*, and it writes nothing on sight. It
opens what it was addressed to and leaves the saved game alone, neither resumed
nor overwritten, which is what keeps the screenshot report's shots
side-effect-free.

**A plain deal made behind the menu is nobody's until the menu goes.** The
segment's swap is the one mount that happens under the open menu, and a fresh deal
there is a board the player hasn't met. It reports its number and lays its cards out
like any other, but `saving()` answers no (`unseen`) until the held release runs
(`reveal`), which then writes the number and the history its opening build would have
written. Cycle on before that and it was never there: nothing was saved, and the next
mount of that scene deals afresh — rather than resuming, at rest, a board the player
only ever saw the menu over. `unseen` is one mount's fact, cleared as the next
publishes, and any deal the player makes for themselves clears it too, since a New
Deal under the menu closes it in the same breath.

**An addressed board is adopted the moment the player changes it** — a move
played, or a board dealt from it (New Deal, Enter seed, Restart). From then on it
saves like any other: it persists after every change, and a later mount of that
scene resumes it. The two halves are reported separately, so adoption is wired to
both — `~onHistory` with something to undo is a board that has been played,
`~onDeal` past this mount's opening build is a board the player dealt for
themselves — and `~publish` is what says a mount's opening build is still to come.

`adopted` is one ref per *scene*, not per mount, and that is the whole point: every
scene change tears the board down and builds it again, so a board that hadn't
saved had nothing to come back to but the deal its link named. The three storage
decisions ask one thunk between them, `saving()`, because two of its three answers
land after the scene was built.

Adoption also writes the one thing a history can't carry. The number it takes is
whatever the app would share for that board at that moment (`liveDealSeed`) — the
link's seed, or a scenario's proved deal — and it *clears* the key when there is
none, so a posed board is never handed the last game's seed to answer with. That
is a shared game's arrival in miniature.

What it changes on the next launch: a bare relaunch resumes a link's board once
the player has played it, where it used to go back to whatever was saved before
the link landed. That is the same rule as everywhere else here — the game you
played is the game you come back to — and the board it used to resume is one the
player had already left.

Which *game* a launch comes up on is a separate question with its own rule: only a
plain open may open on the game the player was last on, since a bare `?seed=` is a
link to the default game's deal and a remembered game would answer it with a
different board. `Main` spells that condition once (`plainUrl`) and both readers
take it from there, so they cannot drift apart; `docs/save-and-share.md` § Storage
has the keys.

A `#g=` link is the one addressed open that takes storage over without being
played, and it splits the two halves apart: it doesn't resume (the link already
says which board), but once the shared game lands it takes over. That gate is
asked twice at two different times, because inflating the blob is asynchronous —
at build time a scene knows only that *some* link is coming (`sharePending`), and
only later does one of them turn out to be the game it named (`sharedOpen`).

The consequence to hold onto: **the placeholder board a shared open wears while
the blob inflates must never be written to storage unasked.** It is scaffolding.
Writing it would clobber the player's own game with a board nobody chose, and a
link that fails to decode would take a save down with it. Adoption is the only
thing that may promote it, and it takes a move to do so.

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
