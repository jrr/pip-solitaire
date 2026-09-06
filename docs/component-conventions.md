# Two component conventions

A sketch of a possible future, not a decision. #330 chose child Elm composition
for the Settings screen and ruled hooks out; #406 shipped it. This page asks what
the app would look like if the two kinds of component it already has were filed
in two directories, with hooks allowed in one of them.

## The line the app already draws

The web app has two kinds of component today, and one directory for both.

**Rendered once, node handed over.** `Html.create` renders a vnode into a
throwaway host and lifts the real DOM node out. The caller owns that node from
then on: `TableScene` builds each of the 52 card faces this way and moves them
by writing `style`, the win panel and the Finish button are raised and torn down
whole, and `CardRaster` and the icon generator serialize the same vnodes through
`StaticRender`. Nothing ever renders into that host again, so a `useState` there
holds state no re-render can read and a `useEffect` cleanup never runs. These
components must be pure `props => vnode` functions, and that is not negotiable:
card motion is Web Animations on live nodes, and a node rebuilt rather than
patched restarts every animation on it.

**Mounted, Preact owns the lifetime.** Everything in `Main.view` is in the tree
`Html.mount` diffs: the top bar, the menu pane and its three screens and every
row in them, the About footer, the seed dialog, the debug console's shell. Preact
already re-renders all of it on every model change and keeps each component's
position stable across those renders, which is exactly the condition hooks need.

The boundary between the two is a single splice. `Main.view` places the scene
container with `Html.node(switcher.scene)`, and a spliced subtree is outside the
diff entirely. A re-render of the chrome, from whatever cause, stops at that
host. So "the cards never re-render" is a fact about the tree's shape, not a
discipline anyone has to keep, and nothing a menu component does with local
state can reach a card.

Because `src/components/` holds both kinds, its entry condition has to be the
stricter one for everything in it: no hooks, ever. The rule is right for the
first kind and merely cautious for the second.

## The split

| | `components/` | `chrome/` |
|---|---|---|
| **Lifetime** | rendered once by `Html.create`; the caller owns the node | mounted by `Html.mount`; Preact owns the node |
| **State** | none; pure `props => vnode` | hooks allowed; the Elm loop still above it |
| **Reachable from** | anywhere, including the board and the build scripts | `Main.view` only |
| **Tested by** | `Html.create(C.make(props))`, synchronous | mount into a host, click, await a tick |
| **Today's members** | `cards/*`, `WinOverlay`, the menu rows, `MenuHeader`, `MenuSection`, `VersionBadge` | `Menu` and its three screens, `TopBar`, `AboutFooter`, `RefreshControl`, `SeedDialog`, the console shell |

`chrome` is the word `Main.res` already uses for this layer, and the filing
principle in `CLAUDE.md` still holds: the directory says who owns the DOM. The
menu rows stay in `components/` because they are pure and a screen on either side
could place one; the screens move because they are the things that would hold
state.

Two rules make the split checkable rather than a matter of remembering.

**Dependency direction.** `chrome/` may import `components/`; nothing in
`components/`, `cards/` or `scenes/` may import `chrome/`. A pure component
placed inside a hook-bearing one is fine. A hook-bearing component placed under
`create` is the silent failure the whole arrangement exists to prevent. The
compiled `.res.mjs` files carry plain `import` lines, so this is a grep, and a
grep can be a unit test or a `mise` task that CI runs.

**Placement.** A `chrome/` component is placed as a vnode, never called as a
function. `Menu.res` today does `MenuSettingsScreen.make(settings)`, which
inlines the screen's render into `Menu`'s own. Preact attaches hooks to the
nearest component *vnode*, so a hook in a screen placed that way would land on
`Menu`'s hook list, and that list would change shape when the screen switched
from Settings to Debug. Preact does not check for that; it would reuse the wrong
slot. ReScript 12's JSX spreads a record, so the fix is `<MenuSettingsScreen
{...settings} />`, or `Html.jsx(MenuSettingsScreen.make, settings)` where JSX
is awkward. The same placement gives each screen a mount and an unmount per
visit, which is what a per-visit state reset wants anyway.

## How the chrome would use it

**Settings without a mirror.** The cost #330 and #406 both name is that the
screen's model mirrors values whose real home is elsewhere: the `options` ref,
the tilt ref, a document-root attribute, storage. With hooks the mirror can go.
Each setting becomes a small subscribable store that *is* the home; the screen
reads it through one hook that subscribes on mount and unsubscribes on unmount;
the switch is a view of the real value and the tap writes the store; the store's
setter does the persist and the publish. `MenuSettingsScreen.liveEnv` is already
the write-through, so the stores' setters are that function split four ways.

```rescript
// platform/Setting.res: one value, one home, watchers told on change
type t<'a> = {mutable value: 'a, mutable watchers: array<'a => unit>, onChange: 'a => unit}
let set = (s, v) => {
  s.value = v
  s.onChange(v)
  s.watchers->Array.forEach(w => w(v))
}

// runtime/Hooks.res
let useSetting = (s: Setting.t<'a>) => {
  let (v, setV) = useState(() => s.value)
  useEffect(() => Setting.subscribe(s, next => setV(_ => next)), [s])
  v
}

// chrome/MenuSettingsScreen.res
let autoCollect = Hooks.useSetting(settings.autoCollect)
<MenuToggleRow
  label="Auto-collect"
  on=autoCollect
  onToggle={() => Setting.set(settings.autoCollect, !autoCollect)}
/>
```

`Main` still owns the refs and the live board, because they belong to the board
rather than to a screen, and wires each store's `onChange` to them the way
`liveEnv` does now. Three writers that come from outside the screen fall out
correctly: the startup first-tap motion resume writes the motion store and any
mounted switch follows; the debug console's `set autoCollect on` writes the
auto-collect store; the next launch reads storage into the store once. This is
the case a plain `useState` per switch gets wrong, and the reason the hook is
`useSetting` and not `useState`.

**Transient state leaves the driver's model.** Several fields in `Main`'s model
exist only because a chrome component has nothing else to hold them in, and
several `update` branches exist only to clear them when the menu closes:
`seedInput`, `refreshBusy`, `shareStatus`, `shareDealStatus`, and the ten-tap
counter inside `settings.hidden`. Each is per-visit state with a natural home in
the component that shows it, and each "reset on close" branch is replaced by the
component unmounting. What stays in the model is what the driver actually
coordinates: whether the menu is open and on which screen, the console's state,
the active scene, `canUndo`, the deal number, the update flag, the refresh mode.

**The scenes keep the Elm loop.** `RasterScene` and `MotionScene` run their own
`Html.mount` and are mount-side in the same sense, but they live in `scenes/`
and own live DOM; nothing here changes them. Hooks are for the chrome.

## Testing on each side

`components/` tests do not change: `Html.create`, synchronous, the shape every
row test has now.

`chrome/` tests need a mounted root. A `TestDom.mount` that renders a vnode into
a host and returns it is a few lines. The other difference is timing: a hook
state update re-renders in a microtask, because Preact defers through a resolved
promise, so a test that clicks and then reads must `await` one tick or wrap the
click in `act` from `preact/test-utils`. The browser suite is unchanged, and
`settings-reach.spec.mjs` becomes the main guard on the write-through, since the
unit tests no longer hold an effect they can inspect.

## Pros

- **The rule matches the mechanism.** "Pure under `create`, stateful under
  `mount`" is what the runtime actually requires; the directory says which is
  which, and a grep enforces the one crossing that fails silently.
- **No mirror.** A setting has one home, and a seventh switch is a store and a
  row: nothing in `Main`, nothing in a `msg` type, no `update` branch.
- **`Main` shrinks to the driver.** The transient fields and their reset
  branches go, and the model reads as the list of things the board and the
  chrome have to agree on.
- **Standard Preact.** A component with local state is written the way every
  Preact and React tutorial writes one, which is what a newcomer expects and what
  an agent reaches for first.
- **Lifecycle for free.** Mount on entry, unmount on exit, subscription cleanup
  in the effect. `freshVisit` and its six call sites are the unmount.

## Cons

- **Two regimes.** The ROADMAP's "Component state" row has to say where the line
  is, and the honest line is "hooks for state whose home is outside the model or
  local to one mount; the Elm loop for anything the driver coordinates". Every
  future field is a judgement call against that sentence.
- **Hook rules are unchecked.** Call order and no-conditionals are conventions
  ReScript cannot see, and a violation fails quietly. The placement rule above
  is the sharpest edge, and it needs the dependency grep beside it.
- **Pure `update` tests go away for the chrome.** #406's tests hold the effect
  and inspect which kinds of reach it used. Store tests can check that `set`
  calls `onChange`, but what a click *does* is now asserted through a mounted
  tree, asynchronously.
- **Rendering has two origins.** `Html.mount` skips a render when the model is
  physically unchanged; a hook update renders regardless, from inside Preact. The
  optimization still holds for the driver's renders, but it no longer describes
  all of them.
- **A component that grows state moves.** Modules are flat, so a move touches no
  import, but it is a filing change each time rather than an edit in place.
- **Bundle and dependencies.** `preact/hooks` is part of the installed package
  and costs roughly a kilobyte and a half gzipped; `preact/test-utils` would be a
  dev dependency if `act` is preferred over a manual tick.

## What it would take, in order

1. `runtime/Hooks.res` (externals for `useState`, `useEffect`, `useRef`) and
   `TestDom.mount` with a tick helper.
2. The `chrome/` directory, the moves, and the dependency check as a test.
3. The placement fix in `Menu.res` and `Main.view`.
4. Settings as the worked example again: `Setting` stores, `useSetting`, delete
   the screen's `model` and `update`, keep `settings-reach.spec.mjs`.
5. `CLAUDE.md` § Where things live, `docs/rendering.md` § `create` renders once,
   and the ROADMAP row.

Each step is small and the first three are useful on their own. The fourth is
where the decision is actually made.
