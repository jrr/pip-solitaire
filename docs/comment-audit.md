# Comment audit

An audit of the repo's code comments, proposing candidates for two cleanups:
essays that have outgrown a code margin and want to be documents, and history
prose that describes a previous state without warning anyone away from anything.

Counts are over `.res`, `.resi`, `.mjs` and `.css` under `packages/`, excluding
`node_modules` and generated `.res.mjs` output. A comment line is any line whose
first non-space characters are `//`, `/*` or `*`. Line numbers are against
`99f28fa`.

| | |
|---|---|
| Comment lines | 11,944 of 35,127 (34%) |
| Unbroken comment blocks of 20+ lines | 97 |
| Issue-number references in comments | 1,228 |
| Files where comment outnumbers code | 32 |

## Four dispositions, not two

The brief asked for two buckets. A third is worth naming, because it's where the
audit could most easily do damage.

The test for deletion is sharp: *history earns its place only as a warning sign
in front of a path not taken*. A lot of the historical prose here does sit in
front of a real path — but it's written backwards, as *what we changed* rather
than *what not to do*. Deleting those loses a live constraint; keeping them
as-is keeps the changelog. They want rewriting, not removing.

- **Move to docs** — a self-contained explanation of a mechanism or format,
  longer than the code it annotates, or told in more than one file.
- **Delete** — describes a previous state and warns of nothing. Includes prose
  that is now simply false.
- **Rewrite as a rule** — a genuine warning sign, currently phrased as history.
  Keep the constraint, drop the narrative.
- **Keep** — already a warning sign, already forward-facing. Listed so the pass
  doesn't over-correct.

## Category 1 — essays that want to be documents

Eight candidates, ordered by how strongly the material argues for a document.
In every case the proposal is the same shape: the *mechanism* moves to `docs/`,
and what stays at the call site is the local fact plus one pointer.

### `docs/save-and-share.md` — the persistence pipeline, told in four files

`GameState` → JSON → `deflate-raw` → base64url → `#g=` is one pipeline, and each
of its four modules opens with an essay about its own segment plus enough of its
neighbours' to make sense. Together ~160 comment lines describing a single wire
format that has no document anywhere. It's also the material most likely to be
wanted *away* from the code — the thing you'd reread before changing a format
that's already out in shared links and on every player's device.

Absorbs:
- `core/src/SaveState.res:1-60` — the JSON shape, the version-1 policy, the
  additive-field rule for `stats`/`autoplays`/`timing`/`game`
- `web-app/src/platform/ShareLink.res:1-51` — why the fragment and not the query
  string; the two link kinds
- `web-app/src/platform/Compression.res:1-29` — `deflate-raw` over gzip,
  base64url over base64, the size arithmetic
- `web-app/src/platform/SavedGame.res` — the storage-key notes that assume the above

**Keep in code:** `SaveState.res:28-35`. "The version deliberately stays at 1"
is a constraint on the next edit, not background — it belongs where someone is
about to bump it.

### `docs/animation-timing.md` — one flight model, four tunings, derived once

`TableScene` carries the full C/P → Δ derivation for the staggered card flight —
`Δ = T / (n − 1 + C)`, `t = C·Δ`, and the proof that the last card lands exactly
at T — then re-explains the model three more times for the finish sweep, the
console move, and autoplay. Roughly 90 comment lines for four pairs of numbers.

A document can carry the derivation once and put the four tunings in a table
with their intent. The code keeps the knobs and their one-line feel, which is
the part you actually read when adjusting them.

Absorbs:
- `web-app/src/scenes/TableScene.res:329-346` — the deal knobs and the derivation
- `…:350-357, 359-367, 369-378` — the finish, console and autoplay restatements
- `…:380-385, 387-399, 403-411` — the z-base rule and `flightTiming`/`flyCards`

### `docs/css-layers.md` — an 88%-comment stylesheet

`styles/index.css` is 60 lines: 53 of prose, 7 of CSS. The prose is good and the
rules have teeth — but it's architecture documentation in a file whose job is
four `@import`s. It's already summarised in `CLAUDE.md`, so the same three rules
are maintained in two places. Move the essay; leave the layer declaration, the
imports, and a two-line pointer.

Absorbs:
- `web-app/src/styles/index.css:1-53` — in full
- `CLAUDE.md` § Styling — collapses to a link

**Delete rather than move:** `index.css:4-14`. "This started as a single
2,036-line `<style>` block inside index.html" is the origin story, not the rule.

### `docs/solver.md` — benchmark numbers with no date on them

`Solver.res` opens with a measured claim — 1,000 deals solved, ~160 ms average,
~54 moves to a finishable board, ~13 s worst case — followed by the heuristic
weights and why the two mobility terms earned their keep. That's a benchmark
record. In a comment it has no date, no method, and no way to record a second
run beside the first; in a doc it gets all three.

Absorbs:
- `core/src/Solver.res:1-17` — the contract ("good enough, not optimal") and the soak results
- `…:19-50, 273-310` — the heuristic terms and the deferred-optimisation note
- `core/src/Position.res:1-29, 33-37` — why the packing exists and what it mirrors

### `docs/command-grammar.md` — a user-facing grammar documented only in source

`Command.res` is 886 lines with 305 of comment, much of it reference material a
*player* would want: the three ways to say where a card goes, what `move 8H 9S`
means, why malformed input parses to `Usage` rather than failing. Two front ends
type these commands and neither has a written grammar. `packages/cli/README.md`
already exists and is the natural home.

Absorbs:
- `core/src/Command.res:1-40` — the two-front-end rationale and the parse/resolve split
- `…:44-70, 205-224` — the three `where` shapes and the source-pile mirror
- `cli/src/Repl.res:1-52` and `web-app/src/debug/DebugConsole.res:1-50` — the
  per-front-end command surfaces

### `docs/rendering.md` — the preserve-mode build, currently in three places

The ReScript-JSX-onto-Preact story is told in `Html.res`, summarised again in
`CLAUDE.md`, and referenced from `StaticRender`, `Html_test`, and
`scripts/lib/load-jsx-module.mjs`. The build-configuration warning — the same
three esbuild settings duplicated across `vite.config.js` (twice),
`vitest.config.js`, and the loader, with nothing checking they agree — is the
most load-bearing paragraph in the repo and deserves a page rather than a
paragraph inside a type definition file.

Absorbs:
- `web-app/src/runtime/Html.res:1-34` — preserve mode, the swap, the esbuild warning
- `…:242-266` — the multi-root serialization note
- `CLAUDE.md` § Rendering — collapses to a link

**Keep in code:** `Html.res:18-30` — "get either wrong and preserve mode either
silently stops preserving or emits JSX no bundler can parse" is exactly the
warning sign, sitting on exactly the two `external`s it guards. Also `:71-77`,
the three reasons `JsxDOM.domProps` doesn't fit.

### `docs/board-geometry.md` — 68% comment, and the maths is the point

`TableLayout.res` is 168 comment lines to 78 of code. It's the one module whose
comments are almost entirely *derivations* — the 5:7 design box, the concentric
corner radii, `card + 2·inset`, the width/height fits, the minimum stage width
the console dock consults. Diagrams would serve this better than prose.

Absorbs:
- `web-app/src/scenes/TableLayout.res:1-23` — the extraction rationale and the seam
- `…:40-90, 128-142, 161-178` — the footprints and the two fits
- `web-app/src/scenes/TableScene.res:85-97` — the scale/safe-area reading

### `docs/card-tilt.md` — small, but genuinely intricate

The deterministic hash tilt — why it's a hash and not `Math.random`, the prime
choice, and the transition-delay trick that stops the whole board swinging to
its landing angles in unison at the start of a finish sweep — is ~60 lines over
five blocks. Lowest priority of the eight, but a self-contained piece of design
reasoning that reads better whole.

Absorbs:
- `web-app/src/scenes/TableScene.res:435-452, 460-467` — what the determinism buys
- `…:488-503, 504-515, 527-531` — the hash, the custom property, the sweep's delay/duration

## Category 2A — stale prose that is now simply wrong

Start here. Each describes the codebase as it is *not*, and a reader who trusts
them is misled about the current architecture. All in `core`, all cheap.

### `core/src/Reducer.res:6-9`

```
// Deliberately still *no view changes*: nothing dispatches yet. This is the
// transition function plus its tests, so the later drivers (the view cutover and
// the CLI) have something to dispatch into. The view keeps its own mutable refs
// for now.
```

False in every clause. `TableScene.res:1251` defines `dispatch`;
`Session.dispatch` is the single path both front ends take; the view's mutable
refs went with the `GameState` cutover. This is the header of the module that
*is* the architecture, telling a reader the architecture doesn't exist yet.

### `core/src/Rules.res:2-9`

Claims "the game state is still view-owned for now" and that "the later M1
migration relocates it into a reducer". The migration happened — `GameState.t`
lives in `core` and the reducer exists.

**Rewrite as a rule:** keep `:9-12` (the hover highlight and the drop decision
call the same `accepts`, so they can't disagree), drop the roadmap framing.

### `core/src/Reducer.res:32-33`

```
// `Deal`/`Undo` will grow this variant when their steps land.
```

They didn't. The variant is `Move` / `MoveRun` / `MoveColumn`; undo lives in
`History` and `Session`, deliberately. A prediction that turned out otherwise
reads as a design intention still pending.

### `core/src/Card.res:7-9` and `core/src/Command.res:17-18`

"The fuller, ordering-aware card model is still its own future game-track item"
and "(#148's TUI is the third caller waiting on this.)" — roadmap items pinned
into source. Both are true statements about a backlog rather than about the
code, and neither warns anyone away from anything. `ROADMAP.md` is where a
reader would look for either.

## Category 2B — the "it replaced N things" genre

The largest single cluster, and the most repetitive. Six refactors are each
narrated at every site they touched, so the same story is told three to eight
times. The pattern is always: *this used to be N separate things; nothing
type-checked the list; now it's one value.*

Almost none of it passes the test. The current shape isn't surprising — a single
typed record instead of eleven refs is the obvious design — so there's no path
to warn anyone off. The prose is arguing the case for a change already merged.

| Story | Told in | Sites | Proposal |
|---|---|---|---|
| **The eleven hooks** → one `controls` record | `Main.res:181-188, 861-863` · `TableScene.res:236-241, 549-550, 2360-2362` · `TableScene_test.res:266` | 6 | Keep one clause on the `controls` type. Delete the rest, including the list of eleven hook names. |
| **The old hand-rolled runtime** (#309) | `Html.res:10-16, 62-68, 178, 200-215, 249` · `StaticRender.res:10-14` · `Html_test.res:15` · `DebugConsole.res:37-44` · `WebDom.res:32` · `Scene.res` | 10 | Delete the comparisons. Where a current fact hangs off one, state the fact directly. |
| **Four components used to draw this box** (#335) | `MenuRow.res:5-8` · `MenuRow_test.res:4` · `MenuDisclosure.res:61` · `MenuDisclosure_test.res:85` · `MenuMainScreen_test.res:6, 16` · `MenuHeader_test.res:77` · `SceneSwitcher_test.res:110` | 8 | Delete all eight. `MenuRow`'s job is legible from its callers. |
| **The size story** (#201) | `RefreshControl.res:11-19` · `AboutFooter.res:6-25` · `RefreshControl_test.res:3-15, 38` · `AboutFooter_test.res:3, 38` · `WinOverlay_test.res:13` | 7 | Rewrite as a rule — see below. This one *is* a warning sign. |
| **The command loop existed three times** | `Session.res:4-14` | 1 | Delete the enumeration; keep the line saying a front end can't opt out of stats and timing. |
| **Scene-switcher lineage** | `SceneSwitcher.res:4, 14-24` · `Scene.res:13` · `TopBar.res:5` · `Menu.res:14-25` · `MenuDebugScreen.res:2, 12, 20` | 8 | Delete. "X no longer lives here; it moved to Y" is what `git log` answers best. |

### The #201 size story, rewritten forwards

`RefreshControl.res:11-19` explains that the control used to carry a transient
status line under the button, which grew and shrank it and reflowed everything
below. That history is doing real work: a status line under a button is exactly
the obvious thing the next person would add, and the comment is the sign saying
don't. But it's written as a change log, so the constraint is buried in the
middle.

Now:

> This control **used to carry** a transient status line *under* the button
> ("Checking…", "Up to date") that appeared and disappeared, growing and
> shrinking it — a visible reflow of everything below. The status line is gone: …

Instead:

> This control must stay size-stable in every state — the About footer reflows
> everything below it if the height changes. So a busy check shows a spinner on
> the button's own line rather than a status line beneath it. `RefreshControl_test`
> pins the row count.

Same knowledge, a third of the length, facing the reader who is about to break
it. `AboutFooter.res:6-25` and the four test-file restatements can then all go —
the rule lives in one place and the tests already enforce it.

## Category 2C — issue numbers as provenance

1,228 references, doing two different jobs. A minority point at a live question
— a deferred decision, a constraint whose reasoning is genuinely in the thread.
The large majority are provenance: *this line arrived in #217*. That's what
`git blame` is for, and it answers more precisely, because it can't drift.

This is the biggest mechanical win available and also the most a matter of
taste, so it's worth treating as a separate decision rather than folding it into
the passes above.

| File | Refs | Comment lines |
|---|---|---|
| `web-app/src/scenes/TableScene.res` | 186 | 1,286 |
| `web-app/src/Main.res` | 134 | 737 |
| `core/src/Reducer.res` | 47 | 268 |
| `core/src/Core_test.res` | 46 | 367 |
| `core/src/Game.res` | 34 | 198 |
| `web-app/src/scenes/TableScene.css` | 33 | 30 |
| `core/src/Session.res` | 32 | 280 |

A rule that would hold the line: an issue number stays only when a reader needs
to open the thread to act correctly — an unresolved trade-off, a decision
deliberately deferred. Everywhere else the sentence should stand on its own,
because a comment that needs a closed issue to be understood is a comment that
isn't finished.

## Guardrail — what the pass must not touch

These describe previous states, or read like background, and every one earns it.
Listed because a keyword sweep for "used to" and "no longer" would catch several.

| Location | The path it warns off |
|---|---|
| `Html.res:18-30` | Plain `let` bindings instead of `@module` externals — preserve mode silently stops preserving. |
| `Html.res:71-77` | Reaching for `JsxDOM.domProps` instead of the hand-written props record. |
| `TableScene.res:73-78` | Reading `ResizeObserver` as a bare identifier — a `ReferenceError` in jsdom instead of a skipped feature. |
| `TableScene.res:114-118` | Assuming a cancelled animation fires `onfinish`; it doesn't, which is what stops a stale win overlay. |
| `TableScene.res:421-433` | Using `dblclick` for send-home — mobile Safari never fires it. |
| `TableScene.res:582-588` | Reading the saved game at build time rather than mount time — silently rewinds a resumed game to page load. |
| `SaveState.res:28-35` | Bumping the format version for an additive field — drops every saved game and every share link already sent. |
| `Compression.res:1-29` + the Blob note | Choosing gzip over `deflate-raw`; routing bytes through `Blob.stream()`, which jsdom lacks. |
| `ShareLink.res:15-34` | Putting the payload in the query string — an ~8 KB server limit, and the board in the access logs. |
| `index.css:29-48` | Adding an unlayered stylesheet, or relying on a source-order tie inside a layer. |
| `Main.res:117-125` | Building the share URL on the press — loses `navigator.share`'s transient activation behind the compression `await`. |

## A sequence that keeps each step reviewable

1. **The five stale comments** (2A). A few dozen lines, no judgment calls, and it
   stops `core`'s headline modules describing an architecture that isn't there.
   Worth doing alone so it isn't buried in a larger diff.
2. **`docs/save-and-share.md`**. The strongest doc candidate and a self-contained
   one — four files, one pipeline, no code changes. It also establishes what a
   `docs/` page looks like here.
3. **The "it replaced N things" sweep** (2B, minus #201). Roughly 33 sites across
   20 files. Mechanical once the first few set the pattern, and the biggest
   single reduction.
4. **The #201 rewrite.** One rule in one place, five restatements deleted. Small,
   but it's the template for any other history that turns out to be a warning sign.
5. **The remaining seven docs**, one per change, in the order above. Each is
   independent, and each leaves the code with a local fact and a pointer.
6. **Decide on issue numbers** (2C). Last, because it's a policy call rather than
   a cleanup and it touches nearly every file — and cheapest once the passes
   above have removed the comments carrying the densest clusters.
