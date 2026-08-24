// The menu's **main screen** (#109/#191), lifted out of `Menu` into its own pure
// component (#307). What the pane shows when the menu opens; `Menu` puts the About
// footer under it.
//
// Top to bottom:
//   - the **title** ("Pip", moved here from the retired Home scene) beside the ✕;
//   - a **"game"** section (#156, #98): **New** (re-deals a fresh seed), **Restart**
//     (re-deals the *same* seed to replay the current deal) and **Share Seed** (#98,
//     hands over a `?seed=` link to the deal on the table). New moved here from the
//     top bar; it and Restart call the scene's re-deal hooks and close the menu so
//     the board is visible again. On a scene with no game (a demo) those two are
//     wired to no-op hooks. Share Seed is the odd one of the three: it *keeps* the
//     menu open, because the line under the buttons reporting where the link went is
//     the only confirmation there is, and it's the only one that ever renders
//     *disabled* — on a board with no seed to name;
//   - a **"Games"** section — SceneSwitcher's primary game row(s), spliced in as the
//     `games` node: FreeCell (the game) as a top-level row (#135);
//   - --- the space between top and bottom grows here (`menu-section--bottom`) ---
//   - a single **Settings** button (`onOpenSettings`) low in the menu, just above the
//     About footer — it takes over the pane with the Settings screen (#191).
//
// The screen renders as a fragment (header + sections, no wrapper), so the panel's
// flex column still sees the sections directly and `--bottom`'s `margin-top: auto`
// keeps pushing the Settings button to the foot.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).
type props = {
  onClose: unit => unit,
  onNewGame: unit => unit,
  onRestart: unit => unit,
  // "Share Seed" (#98): the seed the board reports, and `None` is why the button
  // greys out — a demo scene has no seed, and neither does a game restored from a
  // save written before seeds were kept. The seed is passed rather than a bare bool
  // so the group can *name* it: a share is easier to trust when you can see the
  // number going out.
  shareDealSeed: option<int>,
  // The transient line under the buttons reporting where the link went.
  shareDealStatus: option<string>,
  onShareDeal: unit => unit,
  // SceneSwitcher's own rows: an externally-owned real DOM node (the switcher owns
  // them), spliced with `Html.node` so the diff leaves them be across open/close
  // re-renders.
  games: Html.element,
  onOpenSettings: unit => unit,
}

// The line under the "game" buttons (#98). It reports what became of a share ("Link
// copied to clipboard.") or, on a board with nothing to share, why the button is
// greyed out — and is otherwise *empty*, now that the seed itself rides on the button.
//
// Empty, but always rendered: the slot holds its height (`min-height`, see
// MenuMainScreen.css) so the confirmation appears and clears without shoving the
// sections below it. That reflow is the whole reason the line is unconditional
// rather than a node that comes and goes.
let seedLine = (~seed: option<int>, ~status: option<string>): string =>
  switch (status, seed) {
  | (Some(status), _) => status
  | (None, None) => "No seed for this board."
  | (None, Some(_)) => ""
  }

let make = ({
  onClose,
  onNewGame,
  onRestart,
  shareDealSeed,
  shareDealStatus,
  onShareDeal,
  games,
  onOpenSettings,
}) => <>
  <MenuHeader title="Pip" back=None onTitleTap=None onClose />
  <MenuSection label="game" heading="game">
    <div className="menu-buttons">
      <MenuGameButton label="New" value=None enabled=true onClick=onNewGame />
      <MenuGameButton label="Restart" value=None enabled=true onClick=onRestart />
      // Share Seed (#98). The only one of the three that ever goes `disabled` — the
      // real attribute, so no click is emitted at all, with the handler guard behind
      // it as belt and braces — because a board with no seed has no link to hand out.
      // It carries the seed as its value: the label says what kind of thing goes out,
      // the digits say exactly which, and a player can read the number off (or
      // dictate it) where no link can be delivered at all. A disabled button shows the
      // bare label, there being no number to name.
      <MenuGameButton
        label="Share Seed"
        value={shareDealSeed->Option.map(seed => Int.toString(seed))}
        enabled={shareDealSeed->Option.isSome}
        onClick=onShareDeal
      />
    </div>
    <p className="menu-share-line" ariaLive="polite">
      {Html.string(seedLine(~seed=shareDealSeed, ~status=shareDealStatus))}
    </p>
  </MenuSection>
  <MenuSection label="Games" heading="Games" tag=Nav> {Html.node(games)} </MenuSection>
  <MenuSection modifier="menu-section--bottom">
    <button className="menu-button" onClick={_ => onOpenSettings()} type_="button">
      {Html.string("Settings")}
    </button>
  </MenuSection>
</>
